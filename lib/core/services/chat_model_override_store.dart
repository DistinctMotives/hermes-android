import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ChatModelOverride {
  final String provider;
  final String model;
  final String? reasoningEffort;

  const ChatModelOverride({
    required this.provider,
    required this.model,
    this.reasoningEffort,
  });
}

/// Persists a model override independently for each connection and chat.
///
/// The encoded namespace avoids leaking gateway URLs into preference keys while
/// still preventing identical session IDs from colliding across connections.
class ChatModelOverrideStore {
  static const _prefix = 'chat_model_override';

  final SharedPreferences _preferences;

  ChatModelOverrideStore(this._preferences);

  static Future<ChatModelOverrideStore> open() async {
    return ChatModelOverrideStore(await SharedPreferences.getInstance());
  }

  ChatModelOverride? read({
    required String connectionIdentity,
    required String sessionId,
  }) {
    final provider = _preferences.getString(
      _key(connectionIdentity, sessionId, 'provider'),
    );
    final model = _preferences.getString(
      _key(connectionIdentity, sessionId, 'model'),
    );
    final reasoningEffort = _preferences.getString(
      _key(connectionIdentity, sessionId, 'reasoning_effort'),
    );
    if (provider == null ||
        provider.trim().isEmpty ||
        model == null ||
        model.trim().isEmpty) {
      return null;
    }
    return ChatModelOverride(
      provider: provider.trim(),
      model: model.trim(),
      reasoningEffort: reasoningEffort?.trim().isEmpty == false
          ? reasoningEffort!.trim()
          : null,
    );
  }

  Future<void> save({
    required String connectionIdentity,
    required String sessionId,
    required String provider,
    required String model,
    String? reasoningEffort,
  }) async {
    final normalizedProvider = provider.trim();
    final normalizedModel = model.trim();
    if (normalizedProvider.isEmpty || normalizedModel.isEmpty) {
      throw ArgumentError('Provider and model are required');
    }
    await _preferences.setString(
      _key(connectionIdentity, sessionId, 'provider'),
      normalizedProvider,
    );
    await _preferences.setString(
      _key(connectionIdentity, sessionId, 'model'),
      normalizedModel,
    );
    final normalizedEffort = reasoningEffort?.trim().toLowerCase() ?? '';
    final effortKey = _key(connectionIdentity, sessionId, 'reasoning_effort');
    if (normalizedEffort.isEmpty) {
      await _preferences.remove(effortKey);
    } else {
      await _preferences.setString(effortKey, normalizedEffort);
    }
  }

  String _key(String connectionIdentity, String sessionId, String field) {
    final namespace = base64Url
        .encode(utf8.encode('$connectionIdentity\u0000$sessionId'))
        .replaceAll('=', '');
    return '$_prefix.$namespace.$field';
  }
}
