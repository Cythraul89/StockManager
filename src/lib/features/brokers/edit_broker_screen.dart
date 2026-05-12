import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/app_database.dart';
import '../stocks/stocks_provider.dart';

class EditBrokerScreen extends ConsumerStatefulWidget {
  const EditBrokerScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<EditBrokerScreen> createState() => _EditBrokerScreenState();
}

class _EditBrokerScreenState extends ConsumerState<EditBrokerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _loaded = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);

    return FutureBuilder(
      future: db.brokersDao.findById(widget.id),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final broker = snapshot.data;
        if (broker == null) {
          return Scaffold(
              appBar: const AppBar(),
              body: const Center(child: Text('Broker not found')));
        }
        if (!_loaded) {
          _nameCtrl.text = broker.name;
          _notesCtrl.text = broker.notes ?? '';
          _loaded = true;
        }

        return Scaffold(
          appBar: AppBar(title: Text('Edit ${broker.name}')),
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
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _notesCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Notes (optional)'),
                  maxLines: 3,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _isSaving
                      ? null
                      : () async {
                          if (!_formKey.currentState!.validate()) return;
                          setState(() => _isSaving = true);
                          final router = GoRouter.of(context);
                          try {
                            await db.brokersDao.upsert(
                              BrokersCompanion(
                                id: drift.Value(broker.id),
                                name: drift.Value(_nameCtrl.text.trim()),
                                notes: drift.Value(
                                    _notesCtrl.text.trim().isEmpty
                                        ? null
                                        : _notesCtrl.text.trim()),
                              ),
                            );
                            if (mounted) router.pop();
                          } finally {
                            if (mounted) setState(() => _isSaving = false);
                          }
                        },
                  child: _isSaving
                      ? const CircularProgressIndicator()
                      : const Text('Save'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error),
                  onPressed: () => _confirmDelete(context, broker.name),
                  child: const Text('Delete broker'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context, String name) async {
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete broker?'),
        content: Text('$name cannot be deleted if it has stocks assigned.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      try {
        await ref.read(databaseProvider).brokersDao.deleteById(widget.id);
        if (mounted) router.pop();
      } catch (e) {
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(
                content: Text('Cannot delete: stocks are assigned to this broker')),
          );
        }
      }
    }
  }
}
