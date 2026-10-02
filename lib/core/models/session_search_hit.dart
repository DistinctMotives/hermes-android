import '../models/session.dart';

/// One session returned by the dashboard's full-text search endpoint.
///
/// The endpoint answers with the matching session plus the message excerpt
/// that produced the hit, so the UI can show *why* a chat matched instead of
/// only its title.
class SessionSearchHit {
  /// The matching session, shaped like every other session in the list.
  final Session session;

  /// Message excerpt around the match, as returned by SQLite FTS5.
  ///
  /// Empty when the match came from a session id rather than message content.
  final String snippet;

  /// Role of the message that matched (`user`, `assistant`, ...), when known.
  final String? role;

  const SessionSearchHit({required this.session, this.snippet = '', this.role});

  /// Builds a hit from one `/api/sessions/search` result entry.
  ///
  /// The endpoint returns session fields alongside the match metadata, so the
  /// same map feeds both [Session.fromJson] and the excerpt fields. Missing
  /// keys fall back to the defaults [Session.fromJson] already applies —
  /// search results are rendered in the same list as unfiltered sessions and
  /// must never crash the list on a sparse row.
  factory SessionSearchHit.fromJson(Map<String, dynamic> json) {
    final started = json['session_started'] ?? json['started_at'] ?? 0;
    return SessionSearchHit(
      session: Session.fromJson({
        ...json,
        'started_at': started,
        // The search endpoint identifies the conversation with `session_id`;
        // the session list model expects `id`.
        'id': json['id'] ?? json['session_id'] ?? '',
      }),
      snippet: (json['snippet'] as String?)?.trim() ?? '',
      role: (json['role'] as String?)?.trim().isEmpty == false
          ? (json['role'] as String).trim()
          : null,
    );
  }
}
