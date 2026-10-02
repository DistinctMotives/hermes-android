import 'package:flutter/material.dart';

import '../services/config_backup.dart';
import '../services/config_backup_service.dart';

/// Result of the export sheet: the passphrase the user chose.
class ExportPassphraseChoice {
  final String passphrase;

  const ExportPassphraseChoice(this.passphrase);
}

/// Result of the import sheet: the passphrase plus how to apply the backup.
class ImportChoice {
  final String passphrase;
  final ConfigImportMode mode;

  const ImportChoice({required this.passphrase, required this.mode});
}

/// Asks for a passphrase to protect an export, requiring confirmation so a
/// typo cannot lock the user out of their own backup.
class ExportPassphraseSheet extends StatefulWidget {
  const ExportPassphraseSheet({super.key});

  @override
  State<ExportPassphraseSheet> createState() => _ExportPassphraseSheetState();
}

class _ExportPassphraseSheetState extends State<ExportPassphraseSheet> {
  final TextEditingController _passphrase = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  String? _error;
  bool _obscure = true;

  @override
  void dispose() {
    _passphrase.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _passphrase.text;
    if (value.trim().isEmpty) {
      setState(() => _error = 'Enter a passphrase.');
      return;
    }
    if (value.length < 8) {
      setState(() => _error = 'Use at least 8 characters.');
      return;
    }
    if (value != _confirm.text) {
      setState(() => _error = 'The two passphrases do not match.');
      return;
    }
    Navigator.of(context).pop(ExportPassphraseChoice(value));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Protect this backup',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'The file contains your API keys and dashboard password, so it is '
            'encrypted. Without this passphrase the backup cannot be restored.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('export_passphrase_field'),
            controller: _passphrase,
            obscureText: _obscure,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Passphrase',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
                tooltip: _obscure ? 'Show passphrase' : 'Hide passphrase',
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('export_passphrase_confirm_field'),
            controller: _confirm,
            obscureText: _obscure,
            decoration: const InputDecoration(
              labelText: 'Confirm passphrase',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const Spacer(),
              FilledButton.icon(
                key: const Key('export_confirm_button'),
                onPressed: _submit,
                icon: const Icon(Icons.lock),
                label: const Text('Export'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Asks for the passphrase of a backup file and how it should be applied.
class ImportOptionsSheet extends StatefulWidget {
  const ImportOptionsSheet({super.key});

  @override
  State<ImportOptionsSheet> createState() => _ImportOptionsSheetState();
}

class _ImportOptionsSheetState extends State<ImportOptionsSheet> {
  final TextEditingController _passphrase = TextEditingController();
  ConfigImportMode _mode = ConfigImportMode.merge;
  String? _error;
  bool _obscure = true;

  @override
  void dispose() {
    _passphrase.dispose();
    super.dispose();
  }

  void _submit() {
    if (_passphrase.text.trim().isEmpty) {
      setState(() => _error = 'Enter the passphrase for this backup.');
      return;
    }
    Navigator.of(
      context,
    ).pop(ImportChoice(passphrase: _passphrase.text, mode: _mode));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Restore configuration',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('import_passphrase_field'),
            controller: _passphrase,
            obscureText: _obscure,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Passphrase',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
                tooltip: _obscure ? 'Show passphrase' : 'Hide passphrase',
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          RadioGroup<ConfigImportMode>(
            groupValue: _mode,
            onChanged: (value) => setState(() => _mode = value!),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                RadioListTile<ConfigImportMode>(
                  key: Key('import_mode_merge'),
                  value: ConfigImportMode.merge,
                  title: Text('Merge'),
                  subtitle: Text(
                    'Add and update connections from the backup, keep the '
                    'rest.',
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
                RadioListTile<ConfigImportMode>(
                  key: Key('import_mode_replace'),
                  value: ConfigImportMode.replace,
                  title: Text('Replace'),
                  subtitle: Text(
                    'Delete connections that are not in the backup.',
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const Spacer(),
              FilledButton.icon(
                key: const Key('import_confirm_button'),
                onPressed: _submit,
                icon: const Icon(Icons.restore),
                label: const Text('Restore'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Settings card that exports the current configuration to an encrypted file
/// and restores it on another device.
class ConfigBackupCard extends StatefulWidget {
  /// Produces the encrypted backup file contents. Injected so the card can be
  /// tested without touching the platform file system.
  final Future<String> Function(String passphrase) onExport;

  /// Hands the encrypted contents to the platform (share sheet, file save).
  /// Returns a short description of where it went, or null if the user
  /// cancelled.
  final Future<String?> Function(String contents) onDeliverExport;

  /// Reads a backup file chosen by the user. Returns null if cancelled.
  final Future<String?> Function() onPickBackupFile;

  /// Applies a decrypted backup.
  final Future<ConfigImportResult> Function(
    String contents,
    String passphrase,
    ConfigImportMode mode,
  )
  onImport;

  const ConfigBackupCard({
    required this.onExport,
    required this.onDeliverExport,
    required this.onPickBackupFile,
    required this.onImport,
    super.key,
  });

  @override
  State<ConfigBackupCard> createState() => _ConfigBackupCardState();
}

class _ConfigBackupCardState extends State<ConfigBackupCard> {
  bool _busy = false;
  String? _status;
  String? _error;

  Future<void> _runExport() async {
    final choice = await showModalBottomSheet<ExportPassphraseChoice>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const ExportPassphraseSheet(),
    );
    if (choice == null || !mounted) return;

    setState(() {
      _busy = true;
      _status = null;
      _error = null;
    });
    try {
      final contents = await widget.onExport(choice.passphrase);
      final destination = await widget.onDeliverExport(contents);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = destination == null ? null : 'Backup exported — $destination';
      });
    } on ConfigBackupException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'The backup could not be exported.';
      });
    }
  }

  Future<void> _runImport() async {
    final contents = await widget.onPickBackupFile();
    if (contents == null || !mounted) return;

    final choice = await showModalBottomSheet<ImportChoice>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const ImportOptionsSheet(),
    );
    if (choice == null || !mounted) return;

    setState(() {
      _busy = true;
      _status = null;
      _error = null;
    });
    try {
      final result = await widget.onImport(
        contents,
        choice.passphrase,
        choice.mode,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = result.summary;
      });
    } on ConfigBackupException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'The backup could not be restored.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.settings_backup_restore,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Backup & restore',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Save your connections and settings to an encrypted file, then '
              'restore them after reinstalling or on another device.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('config_export_button'),
                      onPressed: _runExport,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Export'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('config_import_button'),
                      onPressed: _runImport,
                      icon: const Icon(Icons.download),
                      label: const Text('Import'),
                    ),
                  ),
                ],
              ),
            if (_status != null) ...[
              const SizedBox(height: 12),
              Text(
                _status!,
                key: const Key('config_backup_status'),
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: const Key('config_backup_error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
