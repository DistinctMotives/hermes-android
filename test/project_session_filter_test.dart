/// Pure filtering of a project's loaded chats, used by the per-Project search.
///
/// The rule this pins is the one Phase 1 acceptance depends on: filtering is a
/// *view-layer* operation over sessions the server already returned. The
/// gateway stays the source of truth for what belongs to the project; the
/// query only narrows what the user sees. Matching must never crash on a
/// sparse row (the session list feeds the same sparse `Session.fromJson`).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/session.dart';
import 'package:hermes_android/core/utils/project_session_filter.dart';

Session _session({
  String id = 's1',
  String title = 'Ship the Files browser',
  String preview = 'Ran flutter analyze',
  String model = 'claude-opus-5',
}) => Session(
  id: id,
  title: title,
  model: model,
  preview: preview,
  startedAt: 1750000000,
  source: 'cli',
  messageCount: 3,
  isActive: true,
);

void main() {
  group('filterProjectSessions', () {
    test('an empty query returns every session unchanged and in order', () {
      final sessions = [
        _session(id: 'a', title: 'Alpha'),
        _session(id: 'b', title: 'Beta'),
      ];

      final result = filterProjectSessions(sessions, '   ');

      expect(result.map((s) => s.id), ['a', 'b']);
    });

    test('matches the title case-insensitively', () {
      final sessions = [
        _session(id: 'a', title: 'Ship the Files browser'),
        _session(id: 'b', title: 'Review the draft'),
      ];

      final result = filterProjectSessions(sessions, 'sHiP');

      expect(result.map((s) => s.id), ['a']);
    });

    test('matches the preview content', () {
      final sessions = [
        _session(id: 'a', preview: 'Ran flutter analyze'),
        _session(id: 'b', preview: 'Pushed the release tag'),
      ];

      final result = filterProjectSessions(sessions, 'analyze');

      expect(result.map((s) => s.id), ['a']);
    });

    test('matches the session id', () {
      final sessions = [
        _session(id: 'mob-20260829-xyz', title: 'Alpha'),
        _session(id: 'cli-20260828-abc', title: 'Beta'),
      ];

      final result = filterProjectSessions(sessions, '20260829');

      expect(result.map((s) => s.id), ['mob-20260829-xyz']);
    });

    test('matches the model name', () {
      final sessions = [
        _session(id: 'a', model: 'claude-opus-5'),
        _session(id: 'b', model: 'gpt-5.6-sol'),
      ];

      final result = filterProjectSessions(sessions, 'opus');

      expect(result.map((s) => s.id), ['a']);
    });

    test('trims surrounding whitespace before matching', () {
      final sessions = [
        _session(id: 'a', title: 'Ship the Files browser'),
        _session(id: 'b', title: 'Review the draft'),
      ];

      final result = filterProjectSessions(sessions, '  ship  ');

      expect(result.map((s) => s.id), ['a']);
    });

    test('no match yields an empty list, never a crash', () {
      final sessions = [
        _session(id: 'a', title: 'Alpha'),
        _session(id: 'b', title: 'Beta'),
      ];

      final result = filterProjectSessions(sessions, 'zzz-no-such-chat');

      expect(result, isEmpty);
    });

    test('keeps the server order of the matches', () {
      final sessions = [
        _session(id: 'a', title: 'Review the plan'),
        _session(id: 'b', title: 'Review the budget'),
        _session(id: 'c', title: 'Ship the release'),
      ];

      final result = filterProjectSessions(sessions, 'review');

      expect(result.map((s) => s.id), ['a', 'b']);
    });

    test('a sparse row cannot crash the match', () {
      const sparse = Session(
        id: '',
        title: '',
        model: '',
        preview: '',
        startedAt: 0,
        source: '',
        messageCount: 0,
        isActive: true,
      );

      final result = filterProjectSessions([sparse], 'anything');

      expect(result, isEmpty);
    });
  });
}
