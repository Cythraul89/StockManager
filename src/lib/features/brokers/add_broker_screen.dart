import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../stocks/stocks_provider.dart';

class AddBrokerScreen extends ConsumerStatefulWidget {
  const AddBrokerScreen({super.key});

  @override
  ConsumerState<AddBrokerScreen> createState() => _AddBrokerScreenState();
}

class _AddBrokerScreenState extends ConsumerState<AddBrokerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final db = ref.read(databaseProvider);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    // Enforce 10-broker limit
    final count = await db.brokersDao.count();
    if (count >= 10 && mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Maximum of 10 brokers reached')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      const uuid = Uuid();
      await db.brokersDao.upsert(
        BrokersCompanion.insert(
          id: uuid.v4(),
          name: _nameCtrl.text.trim(),
          notes: drift.Value(
              _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim()),
        ),
      );
      if (mounted) router.pop();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Broker')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Broker name'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
              autofocus: true,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _notesCtrl,
              decoration:
                  const InputDecoration(labelText: 'Notes (optional)'),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const CircularProgressIndicator()
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
