import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/text_size_preference.dart';

/// App-wide text-size control. It stores only the selected display preference;
/// connection, profile, and credential data never enter this namespace.
class TextSizeSettingsCard extends StatefulWidget {
  const TextSizeSettingsCard({
    required this.preferences,
    required this.onChanged,
    super.key,
  });

  final SharedPreferences preferences;
  final ValueChanged<TextSizePreference> onChanged;

  @override
  State<TextSizeSettingsCard> createState() => _TextSizeSettingsCardState();
}

class _TextSizeSettingsCardState extends State<TextSizeSettingsCard> {
  late final TextSizePreferenceStore _store;
  late TextSizePreference _preference;

  @override
  void initState() {
    super.initState();
    _store = TextSizePreferenceStore(widget.preferences);
    _preference = _store.read();
  }

  Future<void> _select(TextSizePreference preference) async {
    if (preference == _preference) {
      Navigator.of(context).pop();
      return;
    }
    await _store.save(preference);
    if (!mounted) return;
    setState(() => _preference = preference);
    widget.onChanged(preference);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _showPicker() {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Text size',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Explicit choices adjust Android accessibility text size; '
                  'System leaves it unchanged.',
                ),
                const SizedBox(height: 8),
                RadioGroup<TextSizePreference>(
                  groupValue: _preference,
                  onChanged: (value) {
                    if (value != null) _select(value);
                  },
                  child: Column(
                    children: [
                      for (final preference in TextSizePreference.values)
                        RadioListTile<TextSizePreference>(
                          value: preference,
                          title: Text(preference.label),
                          subtitle: Text(preference.description),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            label: 'Text size: ${_preference.label}',
            button: true,
            child: ExcludeSemantics(
              child: ListTile(
                leading: const Icon(Icons.format_size),
                title: const Text('Text size'),
                subtitle: Text(
                  '${_preference.label} — ${_preference.description}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showPicker,
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Semantics(
              label: 'Text size preview',
              child: ExcludeSemantics(
                child: Text(
                  'Preview',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              'Hermes keeps Android accessibility text scaling active.',
            ),
          ),
        ],
      ),
    );
  }
}
