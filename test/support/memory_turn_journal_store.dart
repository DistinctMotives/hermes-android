/// An in-memory [GatewayTurnJournalStore] for tests that need a real
/// [GatewayTurnJournal] without touching Android secure storage.
///
/// Deliberately minimal: it holds a value, and can be made to fail so the
/// caller's degradation path is assertable.
library;

import 'package:hermes_android/core/services/gateway_turn_journal.dart';

class MemoryTurnJournalStore implements GatewayTurnJournalStore {
  String? value;
  String? legacyValue;

  /// When true, every operation throws, standing in for a storage backend
  /// that is unavailable on this device.
  bool unavailable = false;

  void _guard() {
    if (unavailable) throw StateError('journal storage unavailable');
  }

  @override
  Future<String?> read() async {
    _guard();
    return value;
  }

  @override
  Future<void> write(String newValue) async {
    _guard();
    value = newValue;
  }

  @override
  Future<void> delete() async {
    _guard();
    value = null;
  }

  @override
  Future<String?> readLegacy() async {
    _guard();
    return legacyValue;
  }

  @override
  Future<void> deleteLegacy() async {
    _guard();
    legacyValue = null;
  }
}
