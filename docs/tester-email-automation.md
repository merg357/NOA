# Google Play Tester Automation

This creates managed Google Workspace tester accounts, adds them to a Google
Group, and registers that group on a Google Play testing track.

## Important Google Play Rules

- For production access on newer personal developer accounts, plan on at least
  12 opted-in closed-test testers for 14 days.
- Use a closed testing track (`alpha` or `beta` in the API) for that production
  access requirement. `internal` is useful for fast QA, but it is not the same
  as a 12-tester closed test.
- The Google Play Developer API tester endpoint supports Google Groups. It does
  not support adding individual tester emails through the API. Individual email
  lists are a Play Console UI feature.
- Create more than the bare minimum. `15` tester accounts is the default here
  so you still have 12 active testers if a few accounts do not opt in correctly.

Official references:

- Google Play testing requirements:
  https://support.google.com/googleplay/android-developer/answer/14151465
- Android Publisher API `edits.testers` resource:
  https://developers.google.com/android-publisher/api-ref/rest/v3/edits.testers

## What The Script Does

`scripts/google_play_tester_setup.py`:

1. Creates `tester01@yourdomain.com` through `testerNN@yourdomain.com`.
2. Creates or reuses `play-testers@yourdomain.com`.
3. Adds the tester users to that Google Group.
4. Registers the Google Group on the selected Play track.
5. Saves generated passwords to a `0600` file when `--output-passwords` is used.

## One-Time Setup

Install dependencies:

```bash
cd /root/jarvis
python3 -m venv .venv
.venv/bin/pip install google-auth google-auth-httplib2 google-api-python-client python-dotenv
```

Create a GCP service account in the project linked to Play Console, then enable:

- Admin SDK API
- Google Play Android Developer API

Enable domain-wide delegation on the service account, then in Google Workspace
Admin Console add the service account Client ID with these scopes:

```text
https://www.googleapis.com/auth/admin.directory.user
https://www.googleapis.com/auth/admin.directory.group
https://www.googleapis.com/auth/admin.directory.group.member
```

In Google Play Console:

1. Go to **Setup → API access**.
2. Link the same GCP project if needed.
3. Grant the service account access.
4. Use **Release manager** or a custom role that can manage edits and testers.

## Environment

Copy `.env.template` to `.env` and fill in:

```ini
GOOGLE_SERVICE_ACCOUNT_JSON=/secure/path/service_account.json
GOOGLE_ADMIN_EMAIL=admin@yourdomain.com
TESTER_DOMAIN=yourdomain.com
TESTER_COUNT=15
TESTER_GROUP_EMAIL=play-testers@yourdomain.com
TESTER_OU_PATH=/Testers
TESTER_CREATE_GROUP=true
PLAY_PACKAGE_NAME=xyz.brilliant.noaflutter
PLAY_TRACK=alpha
```

Store the service account JSON outside the repository.

## Usage

Check the server and API setup:

```bash
cd /root/jarvis
.venv/bin/python scripts/google_play_tester_setup.py --doctor
```

Dry run first:

```bash
cd /root/jarvis
.venv/bin/python scripts/google_play_tester_setup.py --dry-run
```

Create 15 accounts, add them to the group, and register the group on the closed
testing track:

```bash
.venv/bin/python scripts/google_play_tester_setup.py --output-passwords /root/jarvis-tester-passwords.json
```

Create only Workspace users/group:

```bash
.venv/bin/python scripts/google_play_tester_setup.py --skip-play-console
```

Register an existing group on Play only:

```bash
.venv/bin/python scripts/google_play_tester_setup.py --skip-workspace --group-email play-testers@yourdomain.com
```

No-Workspace fallback: prepare an email-list CSV for manual upload in Play
Console. This cannot be uploaded through the Android Publisher API; it is a
Play Console UI feature.

```bash
.venv/bin/python scripts/google_play_email_list_csv.py --input /secure/tester-emails.txt --output /root/jarvis/google-play-testers.csv
```

Use internal testing for quick QA only:

```bash
.venv/bin/python scripts/google_play_tester_setup.py --track internal
```

Cleanup tester accounts:

```bash
.venv/bin/python scripts/google_play_tester_setup.py --delete
```

Cleanup tester accounts and the group:

```bash
.venv/bin/python scripts/google_play_tester_setup.py --delete --delete-group
```

## Tester Onboarding

Each tester must:

1. Sign in on their Android device with one tester account.
2. Open the closed-test opt-in URL from Play Console.
3. Tap **Become a tester**.
4. Install the app from the Play Store test link.
5. Keep the account opted in for the full testing period.

## Operational Recommendation

Use `15` tester accounts for the first run. The actual requirement is at least
`12` testers, but a buffer avoids restarting the 14-day window if a few testers
miss the opt-in or stop participating.

## Current Server Findings

As of the last local doctor run:

- Service account key exists at `/opt/mergify-empire/config/play-service-account.json`.
- Service account client email is `play-publisher@topmergs2012.iam.gserviceaccount.com`.
- Package is `xyz.brilliant.noaflutter`.
- Track is `alpha`.
- Missing Workspace values: `GOOGLE_ADMIN_EMAIL`, `TESTER_DOMAIN`, and
  `TESTER_GROUP_EMAIL`.
- Play API probe returns `403 caller does not have permission`, which means the
  service account still needs access to this app in Play Console, or the package
  name is not under the Play developer account linked to this service account.

To clear the 403, go to Google Play Console -> Setup -> API access, link project
`topmergs2012` if needed, then grant
`play-publisher@topmergs2012.iam.gserviceaccount.com` Release manager access for
`xyz.brilliant.noaflutter`. Re-run `--doctor` after that; it should report the
Play edit probe as OK.
