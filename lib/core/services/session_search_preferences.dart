import 'package:shared_preferences/shared_preferences.dart';

/// How the session list search bar resolves a query.
enum SessionSearchMode {
  /// Filter the already-loaded session list on the device. Matches titles,
  /// previews, and model names only — no network call, no message bodies.
  local,

  /// Ask the dashboard's `GET /api/sessions/search` endpoint, which runs an
  /// FTS5 full-text query across stored message content and returns snippets.
  server,

  /// First ask a selected inexpensive model to rewrite a natural-language
  /// question into a focused FTS5 query, then run the same server search.
  ai,
}

extension SessionSearchModeCodec on SessionSearchMode {
  String get storageValue => switch (this) {
    SessionSearchMode.local => 'local',
    SessionSearchMode.server => 'server',
    SessionSearchMode.ai => 'ai',
  };

  static SessionSearchMode fromStorage(String? raw) {
    return switch (raw?.trim()) {
      'server' => SessionSearchMode.server,
      'ai' => SessionSearchMode.ai,
      _ => SessionSearchMode.local,
    };
  }
}

/// Model selected for the inexpensive natural-language query rewrite.
class AiSearchModel {
  final String provider;
  final String model;

  const AiSearchModel({required this.provider, required this.model});

  bool get isRecommended => model.toLowerCase().contains('gpt-oss-20b');

  /// Returns configured provider/model pairs, with the inexpensive GPT-OSS
  /// recommendation first and all other choices sorted predictably.
  static List<AiSearchModel> configuredFromOptions(
    Map<String, dynamic> options,
  ) {
    final choices = <AiSearchModel>[];
    final providers = options['providers'];
    if (providers is List) {
      for (final rawProvider in providers.whereType<Map>()) {
        if (rawProvider['authenticated'] != true) continue;
        final provider = rawProvider['slug']?.toString().trim() ?? '';
        final models = rawProvider['models'];
        if (provider.isEmpty || models is! List) continue;
        for (final rawModel in models) {
          final model = rawModel?.toString().trim() ?? '';
          if (model.isNotEmpty) {
            choices.add(AiSearchModel(provider: provider, model: model));
          }
        }
      }
    }
    choices.sort((a, b) {
      final byRecommendation = (b.isRecommended ? 1 : 0).compareTo(
        a.isRecommended ? 1 : 0,
      );
      if (byRecommendation != 0) return byRecommendation;
      final byProvider = a.provider.compareTo(b.provider);
      return byProvider != 0 ? byProvider : a.model.compareTo(b.model);
    });
    return choices;
  }
}

/// Persists the search mode chosen for each connection.
///
/// Search preferences are stored per connection rather than globally: a user
/// may run an open dashboard on one host and a locked-down gateway with no
/// dashboard on another, and only the former can serve full-text search.
///
/// [SessionSearchMode.local] stays the default so an upgrade never changes
/// search behaviour until the user opts in.
class SessionSearchPreferences {
  static const _prefix = 'session_search';

  final SharedPreferences _preferences;

  SessionSearchPreferences(this._preferences);

  static Future<SessionSearchPreferences> open() async {
    return SessionSearchPreferences(await SharedPreferences.getInstance());
  }

  SessionSearchMode readMode({required String connectionIdentity}) {
    return SessionSearchModeCodec.fromStorage(
      _preferences.getString(_key(connectionIdentity, 'mode')),
    );
  }

  Future<void> saveMode({
    required String connectionIdentity,
    required SessionSearchMode mode,
  }) async {
    await _preferences.setString(
      _key(connectionIdentity, 'mode'),
      mode.storageValue,
    );
  }

  AiSearchModel? readAiModel({required String connectionIdentity}) {
    final provider = _preferences.getString(
      _key(connectionIdentity, 'ai_provider'),
    );
    final model = _preferences.getString(_key(connectionIdentity, 'ai_model'));
    if (provider == null ||
        provider.trim().isEmpty ||
        model == null ||
        model.trim().isEmpty) {
      return null;
    }
    return AiSearchModel(provider: provider.trim(), model: model.trim());
  }

  Future<void> saveAiModel({
    required String connectionIdentity,
    required AiSearchModel selection,
  }) async {
    await Future.wait([
      _preferences.setString(
        _key(connectionIdentity, 'ai_provider'),
        selection.provider.trim(),
      ),
      _preferences.setString(
        _key(connectionIdentity, 'ai_model'),
        selection.model.trim(),
      ),
    ]);
  }

  Future<void> clear({required String connectionIdentity}) async {
    await Future.wait([
      _preferences.remove(_key(connectionIdentity, 'mode')),
      _preferences.remove(_key(connectionIdentity, 'ai_provider')),
      _preferences.remove(_key(connectionIdentity, 'ai_model')),
    ]);
  }

  /// Namespaces keys by connection so identical hosts across profiles cannot
  /// collide, without writing gateway URLs into preference key names.
  static String _key(String connectionIdentity, String field) {
    final namespace = Uri.encodeComponent(connectionIdentity);
    return '$_prefix.$namespace.$field';
  }
}
