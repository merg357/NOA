import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:noa/models/app_mode.dart';
import 'package:noa/models/productivity_model.dart';
import 'package:noa/models/reminder_model.dart';
import 'package:noa/models/note_model.dart';
import 'package:noa/models/memory_fact.dart';
import 'package:noa/services/productivity_service.dart';
import 'package:noa/style.dart';
import 'package:noa/widgets/bottom_nav_bar.dart';
import 'package:noa/widgets/top_title_bar.dart';

class ProductivityPage extends ConsumerStatefulWidget {
  const ProductivityPage({super.key});

  @override
  ConsumerState<ProductivityPage> createState() => _ProductivityPageState();
}

class _ProductivityPageState extends ConsumerState<ProductivityPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _textController = TextEditingController();
  int _currentTab = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this)
      ..addListener(() => setState(() => _currentTab = _tabController.index));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productivity = ref.watch(productivityProvider);
    final mode = ref.watch(appModeProvider);

    return Scaffold(
      backgroundColor: colorDark,
      appBar: topTitleBar(context, 'TASKS', false, true),
      body: Column(
        children: [
          // ── Mode badge ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Row(
              children: [
                Text('Mode: ', style: textStyleLight),
                const SizedBox(width: 4),
                DropdownButton<AppMode>(
                  value: mode,
                  dropdownColor: colorDark,
                  underline: const SizedBox.shrink(),
                  style: textStyleWhite,
                  items: AppMode.values
                      .map((m) => DropdownMenuItem(
                            value: m,
                            child: Text(
                              '${m.icon}  ${m.displayName}',
                              style: textStyleWhite,
                            ),
                          ))
                      .toList(),
                  onChanged: (m) {
                    if (m != null) ref.read(appModeProvider.notifier).setMode(m);
                  },
                ),
                const Spacer(),
                Text(
                  '${productivity.pendingReminders.length} pending',
                  style: textStyleLight,
                ),
              ],
            ),
          ),
          // ── Tab bar ───────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: TabBar(
              controller: _tabController,
              labelColor: colorWhite,
              unselectedLabelColor: colorLight,
              indicator: BoxDecoration(
                color: colorLight,
                borderRadius: BorderRadius.circular(8),
              ),
              tabs: const [
                Tab(text: 'REMINDERS'),
                Tab(text: 'NOTES'),
                Tab(text: 'MEMORY'),
              ],
            ),
          ),
          // ── Tab content ───────────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _RemindersTab(productivity: productivity),
                _NotesTab(productivity: productivity),
                _FactsTab(productivity: productivity),
              ],
            ),
          ),
          // ── Quick-add bar ─────────────────────────────────────────────────
          _QuickAddBar(
            controller: _textController,
            currentTab: _currentTab,
            productivity: productivity,
          ),
        ],
      ),
      bottomNavigationBar: bottomNavBar(context, 2, true),
    );
  }
}

// ── Reminders Tab ──────────────────────────────────────────────────────────

class _RemindersTab extends StatelessWidget {
  final ProductivityService productivity;
  const _RemindersTab({required this.productivity});

  @override
  Widget build(BuildContext context) {
    final reminders = productivity.reminders;
    if (reminders.isEmpty) {
      return const _EmptyState(message: 'No reminders yet.\nType one below.');
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      itemCount: reminders.length,
      itemBuilder: (context, i) =>
          _ReminderTile(reminder: reminders[i], service: productivity),
    );
  }
}

class _ReminderTile extends StatelessWidget {
  final ReminderModel reminder;
  final ProductivityService service;
  const _ReminderTile({required this.reminder, required this.service});

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(reminder.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: colorRed,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => service.deleteReminder(reminder.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: reminder.isDone ? colorLight.withOpacity(0.3) : colorLight,
          borderRadius: BorderRadius.circular(10),
        ),
        child: ListTile(
          leading: GestureDetector(
            onTap: () {
              if (!reminder.isDone) service.completeReminder(reminder.id);
            },
            child: Icon(
              reminder.isDone
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              color: reminder.isDone ? colorDark : colorDark,
            ),
          ),
          title: Text(
            reminder.text,
            style: reminder.isDone
                ? textStyleDark.copyWith(
                    decoration: TextDecoration.lineThrough)
                : textStyleDark,
          ),
          subtitle: reminder.dueAt != null
              ? Text(
                  _formatDate(reminder.dueAt!),
                  style: textStyleLight.copyWith(color: colorDark),
                )
              : null,
        ),
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

// ── Notes Tab ──────────────────────────────────────────────────────────────

class _NotesTab extends StatelessWidget {
  final ProductivityService productivity;
  const _NotesTab({required this.productivity});

  @override
  Widget build(BuildContext context) {
    final notes = productivity.notes;
    if (notes.isEmpty) {
      return const _EmptyState(message: 'No notes yet.\nType one below.');
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      itemCount: notes.length,
      itemBuilder: (context, i) =>
          _NoteTile(note: notes[i], service: productivity),
    );
  }
}

class _NoteTile extends StatelessWidget {
  final NoteModel note;
  final ProductivityService service;
  const _NoteTile({required this.note, required this.service});

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(note.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: colorRed,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => service.deleteNote(note.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: colorLight,
          borderRadius: BorderRadius.circular(10),
        ),
        child: ListTile(
          leading: const Icon(Icons.note, color: colorDark),
          title: Text(note.title, style: textStyleDark),
          subtitle: Text(
            note.body.length > 60 ? note.body.substring(0, 60) + '…' : note.body,
            style: textStyleDark.copyWith(fontWeight: FontWeight.w300),
          ),
        ),
      ),
    );
  }
}

// ── Memory Facts Tab ───────────────────────────────────────────────────────

class _FactsTab extends StatelessWidget {
  final ProductivityService productivity;
  const _FactsTab({required this.productivity});

  @override
  Widget build(BuildContext context) {
    final facts = productivity.facts;
    if (facts.isEmpty) {
      return const _EmptyState(
          message: 'Nothing remembered yet.\nSay "remember that …" below.');
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      itemCount: facts.length,
      itemBuilder: (context, i) =>
          _FactTile(fact: facts[i], service: productivity),
    );
  }
}

class _FactTile extends StatelessWidget {
  final MemoryFact fact;
  final ProductivityService service;
  const _FactTile({required this.fact, required this.service});

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(fact.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: colorRed,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => service.deleteFact(fact.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: colorLight,
          borderRadius: BorderRadius.circular(10),
        ),
        child: ListTile(
          leading: const Icon(Icons.psychology, color: colorDark),
          title: Text(fact.key, style: textStyleDark),
          subtitle: Text(fact.value,
              style: textStyleDark.copyWith(fontWeight: FontWeight.w300)),
        ),
      ),
    );
  }
}

// ── Quick Add Bar ──────────────────────────────────────────────────────────

class _QuickAddBar extends StatelessWidget {
  final TextEditingController controller;
  final int currentTab;
  final ProductivityService productivity;

  const _QuickAddBar({
    required this.controller,
    required this.currentTab,
    required this.productivity,
  });

  String get _placeholder {
    switch (currentTab) {
      case 0:
        return 'Add a reminder…';
      case 1:
        return 'Add a note…';
      case 2:
        return 'Remember that…';
      default:
        return 'Add…';
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                style: textStyleDark,
                decoration: InputDecoration(
                  hintText: _placeholder,
                  hintStyle: textStyleLight,
                  fillColor: colorLight,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                onSubmitted: (_) => _submit(),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _submit,
              child: Container(
                decoration: BoxDecoration(
                  color: colorLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(10),
                child: const Icon(Icons.add, color: colorDark),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final text = controller.text.trim();
    if (text.isEmpty) return;
    controller.clear();
    switch (currentTab) {
      case 0:
        await productivity.addReminder(text);
        break;
      case 1:
        final title = text.split(' ').take(5).join(' ');
        await productivity.addNote(title, text);
        break;
      case 2:
        final parts = text.split(RegExp(r'\s+'));
        final key = parts.take(3).join(' ');
        await productivity.saveFact(key, text);
        break;
    }
  }
}

// ── Empty State ────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: textStyleLight,
      ),
    );
  }
}
