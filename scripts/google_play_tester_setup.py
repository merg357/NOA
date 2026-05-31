#!/usr/bin/env python3
"""
google_play_tester_setup.py

Creates managed Google Workspace tester accounts, keeps them in a Google Group,
and registers that group on a Google Play testing track.

Important Google Play API detail:
The Android Publisher API edits.testers resource supports Google Groups only.
Individual email tester lists can be managed in the Play Console UI, but are
not supported by the API. This script therefore uses a Google Group as the
bridge between managed tester accounts and Play Console testing access.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import secrets
import string
import sys
from pathlib import Path

try:
    from dotenv import load_dotenv

    env_path = Path(__file__).resolve().parent.parent / ".env"
    if env_path.exists():
        load_dotenv(env_path)
except ImportError:
    pass

try:
    from google.oauth2 import service_account
    from googleapiclient.discovery import build
    from googleapiclient.errors import HttpError
except ImportError:
    service_account = None
    build = None
    HttpError = Exception


WORKSPACE_SCOPES = [
    "https://www.googleapis.com/auth/admin.directory.user",
    "https://www.googleapis.com/auth/admin.directory.group",
    "https://www.googleapis.com/auth/admin.directory.group.member",
]
PLAY_SCOPES = ["https://www.googleapis.com/auth/androidpublisher"]
VALID_TRACKS = {"internal", "alpha", "beta"}
EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def env_bool(name: str, default: bool = False) -> bool:
    raw = os.environ.get(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create Workspace tester accounts, add them to a Google Group, and register the group on Google Play."
    )
    parser.add_argument("--count", type=int, default=None, help="Tester account count. Use at least 12; 15 is safer.")
    parser.add_argument("--domain", default=None, help="Workspace domain for tester accounts.")
    parser.add_argument("--admin-email", default=None, help="Workspace admin to impersonate.")
    parser.add_argument("--package", default=None, help="Android package name in Play Console.")
    parser.add_argument("--track", default=None, help="Play track. Use alpha/beta for closed testing; internal does not satisfy production-access testing.")
    parser.add_argument("--group-email", default=None, help="Google Group email to register in Play Console.")
    parser.add_argument("--ou-path", default=None, help="Workspace OU for tester accounts, e.g. /Testers.")
    parser.add_argument("--service-account-json", default=None, help="Path to GCP service account JSON key.")
    parser.add_argument("--skip-workspace", action="store_true", help="Do not create users or group members; only register group in Play.")
    parser.add_argument("--skip-play-console", action="store_true", help="Only create Workspace users/group; do not update Play.")
    parser.add_argument("--delete", action="store_true", help="Delete tester users. The Google Group is kept by default.")
    parser.add_argument("--delete-group", action="store_true", help="When used with --delete, also delete the tester Google Group.")
    parser.add_argument("--doctor", action="store_true", help="Validate local config and API access without making persistent changes.")
    parser.add_argument("--dry-run", action="store_true", help="Preview actions without API writes.")
    parser.add_argument("--output-passwords", default=None, help="Write generated passwords JSON to this path.")
    return parser.parse_args()


def load_config(args: argparse.Namespace) -> dict:
    domain = args.domain or os.environ.get("TESTER_DOMAIN", "")
    count = args.count or int(os.environ.get("TESTER_COUNT", "15"))
    group_email = args.group_email or os.environ.get("TESTER_GROUP_EMAIL", "")
    if not group_email and domain:
        group_email = f"play-testers@{domain}"

    cfg = {
        "sa_json": args.service_account_json or os.environ.get("GOOGLE_SERVICE_ACCOUNT_JSON", ""),
        "admin_email": args.admin_email or os.environ.get("GOOGLE_ADMIN_EMAIL", ""),
        "domain": domain,
        "count": count,
        "package": args.package or os.environ.get("PLAY_PACKAGE_NAME", "xyz.brilliant.noaflutter"),
        "track": args.track or os.environ.get("PLAY_TRACK", "alpha"),
        "group_email": group_email,
        "ou_path": args.ou_path or os.environ.get("TESTER_OU_PATH", "/Testers"),
        "create_group": env_bool("TESTER_CREATE_GROUP", True),
    }

    missing = []
    credentials_missing = []
    if not cfg["sa_json"]:
        credentials_missing.append("GOOGLE_SERVICE_ACCOUNT_JSON")
    if not args.skip_workspace and not cfg["admin_email"]:
        credentials_missing.append("GOOGLE_ADMIN_EMAIL")
    if not args.skip_workspace and not cfg["domain"]:
        missing.append("TESTER_DOMAIN")
    if cfg["group_email"] and not EMAIL_RE.match(cfg["group_email"]):
        missing.append("TESTER_GROUP_EMAIL must be an email address")
    elif not cfg["group_email"]:
        missing.append("TESTER_GROUP_EMAIL")
    if not args.skip_play_console and not cfg["package"]:
        missing.append("PLAY_PACKAGE_NAME")
    if cfg["track"] not in VALID_TRACKS:
        missing.append("PLAY_TRACK must be one of: internal, alpha, beta")

    if cfg["count"] < 12:
        print("WARNING: Google Play production-access testing requires at least 12 opted-in testers for 14 days.")
    if cfg["track"] == "internal":
        print("WARNING: Internal testing is useful for QA but does not satisfy the 12-tester/14-day production-access requirement.")

    if args.doctor:
        return cfg

    if credentials_missing and not args.dry_run:
        missing.extend(credentials_missing)

    if missing:
        print("ERROR: Missing/invalid configuration:")
        for item in missing:
            print(f"  - {item}")
        sys.exit(1)
    return cfg


def tester_emails(domain: str, count: int) -> list[str]:
    return [f"tester{i:02d}@{domain}" for i in range(1, count + 1)]


def random_password(length: int = 24) -> str:
    alphabet = string.ascii_letters + string.digits + "!@#$%^&*()-_=+"
    return "".join(secrets.choice(alphabet) for _ in range(length))


def parse_http_error(exc: HttpError) -> tuple[int, str, str]:
    status = getattr(exc.resp, "status", 0) or 0
    try:
        details = json.loads(exc.content.decode())
        error = details.get("error", {})
        reason = (error.get("errors") or [{}])[0].get("reason", "")
        message = error.get("message", str(exc))
        return status, reason, message
    except Exception:
        return status, "", str(exc)


def workspace_service(sa_json_path: str, admin_email: str):
    if service_account is None or build is None:
        raise RuntimeError(
            "Required Google packages are missing. Run: "
            "pip install google-auth google-auth-httplib2 google-api-python-client python-dotenv"
        )
    creds = service_account.Credentials.from_service_account_file(
        sa_json_path, scopes=WORKSPACE_SCOPES
    ).with_subject(admin_email)
    return build("admin", "directory_v1", credentials=creds, cache_discovery=False)


def play_service(sa_json_path: str):
    if service_account is None or build is None:
        raise RuntimeError(
            "Required Google packages are missing. Run: "
            "pip install google-auth google-auth-httplib2 google-api-python-client python-dotenv"
        )
    creds = service_account.Credentials.from_service_account_file(
        sa_json_path, scopes=PLAY_SCOPES
    )
    return build("androidpublisher", "v3", credentials=creds, cache_discovery=False)


def load_service_account_summary(sa_json_path: str) -> dict:
    path = Path(sa_json_path)
    data = json.loads(path.read_text())
    return {
        "path": str(path),
        "exists": path.exists(),
        "mode": oct(path.stat().st_mode & 0o777),
        "type": data.get("type", ""),
        "project_id": data.get("project_id", ""),
        "client_email": data.get("client_email", ""),
        "has_private_key": bool(data.get("private_key")),
    }


def doctor(args: argparse.Namespace, cfg: dict) -> int:
    print("\nGoogle Play Tester Setup Doctor")
    print("=" * 60)

    ok = True
    def line(label: str, ready: bool, detail: str = "") -> None:
        nonlocal ok
        mark = "OK" if ready else "MISSING"
        print(f"  {label:24s} {mark:8s} {detail}")
        ok = ok and ready

    sa_path = Path(cfg["sa_json"]) if cfg["sa_json"] else None
    line("service account", bool(sa_path and sa_path.exists()), cfg["sa_json"] or "GOOGLE_SERVICE_ACCOUNT_JSON is empty")
    if sa_path and sa_path.exists():
        try:
            summary = load_service_account_summary(str(sa_path))
            line("service account type", summary["type"] == "service_account", summary["type"] or "<empty>")
            line("service account key", summary["has_private_key"], "private key present" if summary["has_private_key"] else "private key missing")
            print(f"  {'project':24s} {'INFO':8s} {summary['project_id']}")
            print(f"  {'client email':24s} {'INFO':8s} {summary['client_email']}")
            print(f"  {'file mode':24s} {'INFO':8s} {summary['mode']}")
        except Exception as exc:
            line("service account json", False, str(exc))

    line("package", bool(cfg["package"]), cfg["package"] or "PLAY_PACKAGE_NAME is empty")
    line("track", cfg["track"] in VALID_TRACKS, cfg["track"] or "PLAY_TRACK is empty")
    line("tester group", bool(cfg["group_email"] and EMAIL_RE.match(cfg["group_email"])), cfg["group_email"] or "TESTER_GROUP_EMAIL is empty")

    workspace_ready = bool(cfg["admin_email"] and cfg["domain"] and cfg["group_email"])
    print("\nWorkspace automation")
    line("admin email", bool(cfg["admin_email"]), "configured" if cfg["admin_email"] else "GOOGLE_ADMIN_EMAIL is empty")
    line("tester domain", bool(cfg["domain"]), cfg["domain"] or "TESTER_DOMAIN is empty")
    line("tester count", cfg["count"] >= 12, str(cfg["count"]))
    if not workspace_ready:
        print("  INFO                    Workspace account creation is not runnable yet.")
        print("  INFO                    Use --skip-workspace after creating a Google Group manually, or set the Workspace admin/domain values.")

    if not args.skip_play_console and sa_path and sa_path.exists() and cfg["package"] and build is not None:
        print("\nPlay API access")
        try:
            svc = play_service(str(sa_path))
            edit_id = open_edit(svc, cfg["package"])
            try:
                if cfg["track"] in VALID_TRACKS:
                    try:
                        current = (
                            svc.edits()
                            .testers()
                            .get(packageName=cfg["package"], editId=edit_id, track=cfg["track"])
                            .execute()
                        )
                        groups = current.get("googleGroups", []) or []
                        print(f"  {'current groups':24s} {'INFO':8s} {len(groups)} configured on {cfg['track']}")
                    except HttpError as exc:
                        _, _, message = parse_http_error(exc)
                        print(f"  {'current groups':24s} {'WARN':8s} could not read testers: {message}")
                svc.edits().delete(packageName=cfg["package"], editId=edit_id).execute()
                print(f"  {'play edit probe':24s} {'OK':8s} edit opened and deleted")
            except Exception:
                try:
                    svc.edits().delete(packageName=cfg["package"], editId=edit_id).execute()
                except Exception:
                    pass
                raise
        except Exception as exc:
            ok = False
            print(f"  {'play api access':24s} {'FAILED':8s} {exc}")
    elif build is None:
        ok = False
        print("\nPlay API access")
        print("  google packages          MISSING  install google-auth google-auth-httplib2 google-api-python-client python-dotenv")

    print("\nNext command")
    if workspace_ready and ok:
        print("  .venv/bin/python scripts/google_play_tester_setup.py --output-passwords /root/jarvis-tester-passwords.json")
    elif cfg["group_email"] and ok:
        print("  .venv/bin/python scripts/google_play_tester_setup.py --skip-workspace")
    else:
        print("  Fill GOOGLE_ADMIN_EMAIL + TESTER_DOMAIN + TESTER_GROUP_EMAIL, or create a Google Group and set TESTER_GROUP_EMAIL.")

    return 0 if ok else 1


def ensure_group(svc, group_email: str, dry_run: bool) -> None:
    if dry_run:
        print(f"  [DRY-RUN] Ensure Google Group exists: {group_email}")
        return
    try:
        svc.groups().get(groupKey=group_email).execute()
        print(f"  ↩ Group exists: {group_email}")
    except HttpError as exc:
        status, reason, message = parse_http_error(exc)
        if status != 404:
            raise RuntimeError(f"Could not read group {group_email}: {message}") from exc
        body = {
            "email": group_email,
            "name": "Google Play Testers",
            "description": "Managed tester group for Google Play closed/internal testing.",
        }
        svc.groups().insert(body=body).execute()
        print(f"  ✓ Created group: {group_email}")


def create_workspace_user(svc, email: str, ou_path: str, dry_run: bool) -> dict:
    username = email.split("@", 1)[0]
    suffix = username.replace("tester", "").zfill(2)
    password = random_password()
    body = {
        "primaryEmail": email,
        "name": {"givenName": "Tester", "familyName": suffix},
        "password": password,
        "changePasswordAtNextLogin": False,
        "orgUnitPath": ou_path,
    }

    if dry_run:
        print(f"  [DRY-RUN] Create user: {email}")
        return {"email": email, "password": password, "status": "dry-run"}

    try:
        svc.users().insert(body=body).execute()
        print(f"  ✓ Created user: {email}")
        return {"email": email, "password": password, "status": "created"}
    except HttpError as exc:
        _, reason, message = parse_http_error(exc)
        if reason == "duplicate" or "Entity already exists" in message:
            print(f"  ↩ User exists: {email}")
            return {"email": email, "password": "(existing unchanged)", "status": "exists"}
        print(f"  ✗ User failed: {email}: {message}")
        return {"email": email, "password": "", "status": f"error: {message}"}


def add_group_member(svc, group_email: str, member_email: str, dry_run: bool) -> None:
    if dry_run:
        print(f"  [DRY-RUN] Add {member_email} to {group_email}")
        return
    try:
        svc.members().insert(
            groupKey=group_email,
            body={"email": member_email, "role": "MEMBER"},
        ).execute()
        print(f"  ✓ Added member: {member_email}")
    except HttpError as exc:
        _, reason, message = parse_http_error(exc)
        if reason == "duplicate" or "Member already exists" in message:
            print(f"  ↩ Member exists: {member_email}")
            return
        raise RuntimeError(f"Could not add {member_email} to {group_email}: {message}") from exc


def delete_workspace_user(svc, email: str, dry_run: bool) -> None:
    if dry_run:
        print(f"  [DRY-RUN] Delete user: {email}")
        return
    try:
        svc.users().delete(userKey=email).execute()
        print(f"  ✓ Deleted user: {email}")
    except HttpError as exc:
        status, _, message = parse_http_error(exc)
        if status == 404:
            print(f"  ↩ User already absent: {email}")
            return
        print(f"  ✗ Delete failed: {email}: {message}")


def delete_group(svc, group_email: str, dry_run: bool) -> None:
    if dry_run:
        print(f"  [DRY-RUN] Delete group: {group_email}")
        return
    try:
        svc.groups().delete(groupKey=group_email).execute()
        print(f"  ✓ Deleted group: {group_email}")
    except HttpError as exc:
        status, _, message = parse_http_error(exc)
        if status == 404:
            print(f"  ↩ Group already absent: {group_email}")
            return
        print(f"  ✗ Group delete failed: {message}")


def open_edit(svc, package_name: str) -> str:
    edit = svc.edits().insert(packageName=package_name, body={}).execute()
    return edit["id"]


def add_play_tester_group(svc, package_name: str, track: str, group_email: str, dry_run: bool) -> None:
    if dry_run:
        print(f"  [DRY-RUN] Register Google Group on Play track: {group_email} -> {package_name}/{track}")
        return

    edit_id = open_edit(svc, package_name)
    try:
        current = (
            svc.edits()
            .testers()
            .get(packageName=package_name, editId=edit_id, track=track)
            .execute()
        )
    except HttpError:
        current = {}

    groups = set(current.get("googleGroups", []) or [])
    groups.add(group_email)
    body = {"googleGroups": sorted(groups)}
    svc.edits().testers().update(
        packageName=package_name,
        editId=edit_id,
        track=track,
        body=body,
    ).execute()
    svc.edits().commit(packageName=package_name, editId=edit_id).execute()
    print(f"  ✓ Registered tester group on {package_name}/{track}: {group_email}")


def write_passwords(path: str, rows: list[dict]) -> None:
    output = Path(path)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(rows, indent=2) + "\n")
    output.chmod(0o600)
    print(f"  Passwords saved: {output} (0600)")


def main() -> None:
    args = parse_args()
    cfg = load_config(args)
    if args.doctor:
        sys.exit(doctor(args, cfg))

    emails = tester_emails(cfg["domain"] or "example.com", cfg["count"])

    print("\nGoogle Play Tester Setup")
    print("=" * 60)
    print(f"  Domain:  {cfg['domain'] or '(dry-run placeholder)'}")
    print(f"  Count:   {cfg['count']}")
    print(f"  Group:   {cfg['group_email']}")
    print(f"  Package: {cfg['package']}")
    print(f"  Track:   {cfg['track']}")
    print(f"  Dry-run: {args.dry_run}")
    print("=" * 60)

    created_rows: list[dict] = []

    if not args.skip_workspace:
        print("\nWorkspace users + group")
        ws = None if args.dry_run else workspace_service(cfg["sa_json"], cfg["admin_email"])
        if args.delete:
            for email in emails:
                delete_workspace_user(ws, email, args.dry_run)
            if args.delete_group:
                delete_group(ws, cfg["group_email"], args.dry_run)
        else:
            if cfg["create_group"]:
                ensure_group(ws, cfg["group_email"], args.dry_run)
            for email in emails:
                row = create_workspace_user(ws, email, cfg["ou_path"], args.dry_run)
                created_rows.append(row)
                if row["status"] in {"created", "exists", "dry-run"}:
                    add_group_member(ws, cfg["group_email"], email, args.dry_run)

    if not args.skip_play_console and not args.delete:
        print("\nGoogle Play tester group")
        play = None if args.dry_run else play_service(cfg["sa_json"])
        add_play_tester_group(play, cfg["package"], cfg["track"], cfg["group_email"], args.dry_run)

    if created_rows and args.output_passwords:
        write_passwords(args.output_passwords, [row for row in created_rows if row["status"] in {"created", "dry-run"}])
    elif created_rows:
        created = [row for row in created_rows if row["status"] == "created"]
        if created:
            print("\nGenerated passwords. Save these now or rerun with --output-passwords.")
            for row in created:
                print(f"  {row['email']:40s} {row['password']}")

    print("\nDone.")


if __name__ == "__main__":
    main()
