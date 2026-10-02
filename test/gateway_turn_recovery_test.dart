import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/gateway_turn_contract.dart';
import 'package:hermes_android/core/services/gateway_turn_recovery.dart';

const _clientTurnId = '11111111-1111-4111-8111-111111111111';
const _mobileSessionId = '22222222-2222-4222-8222-222222222222';
const _turnId = 'turn-1';
const _digest =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

Map<String, dynamic> _readyFrame({
  int version = 2,
  int promptVersion = 2,
  bool shadowOnly = false,
  bool automaticResubmit = false,
  bool attachments = false,
}) {
  final methods = <String>[
    'session.open',
    'turn.reconcile',
    'turn.interrupt',
    if (attachments) 'attachment.detach@2',
  ];
  final appliesTo = <String>[
    'session.open',
    'prompt.submit@2',
    'turn.reconcile',
    'turn.interrupt',
    if (attachments) 'attachment.detach@2',
  ];
  return <String, dynamic>{
    'jsonrpc': '2.0',
    'method': 'event',
    'params': <String, dynamic>{
      'type': 'gateway.ready',
      'payload': <String, dynamic>{
        'protocol': <String, dynamic>{'name': 'hermes-jsonrpc', 'major': 2},
        'capabilities': <String, dynamic>{
          'turn_recovery': <String, dynamic>{
            'version': version,
            'shadow_only': shadowOnly,
            'methods': methods,
            'prompt_submit_version': promptVersion,
            'applies_to': appliesTo,
            'automatic_resubmit': automaticResubmit,
            'execution_route': 'single_process_in_process',
            'event_retention_seconds': 86400,
            'turn_retention_seconds': 604800,
            'max_event_bytes': 65536,
            'max_turn_bytes': 4194304,
            'terminal_event_reserve_bytes': 1024,
            'max_prompt_bytes': 65536,
            'mobile_session_id_format': 'canonical_lowercase_uuid',
            'client_turn_id_format': 'canonical_lowercase_uuid',
            'reconcile_max_events': 256,
            'reconcile_max_page_bytes': 524288,
            if (attachments) ...<String, dynamic>{
              'max_attachments': 10,
              'max_file_attachment_bytes': 16777216,
              'max_image_attachment_bytes': 26214400,
              'max_pdf_attachment_bytes': 52428800,
              'max_attachment_registry_bytes': 67108864,
            },
          },
        },
      },
    },
  };
}

Map<String, dynamic> _event(
  int seq,
  String type,
  Map<String, dynamic> payload,
) => <String, dynamic>{
  'turn_id': _turnId,
  'seq': seq,
  'message_id': 'message-1',
  'type': type,
  'payload': payload,
};

Map<String, dynamic> _eventPage({
  required int afterSeq,
  required int lastSeq,
  required List<Map<String, dynamic>> events,
  required String status,
}) => <String, dynamic>{
  'mode': 'events',
  'turn_id': _turnId,
  'status': status,
  'earliest_seq': 1,
  'last_seq': lastSeq,
  'events': events,
  'has_more': events.isNotEmpty && events.last['seq'] < lastSeq,
  'next_after_seq': events.isEmpty ? afterSeq : events.last['seq'],
  'automatic_resubmit': false,
};

Map<String, dynamic> _openResult({bool attachments = false}) {
  final ready = _readyFrame(attachments: attachments);
  final payload =
      (ready['params'] as Map<String, dynamic>)['payload']
          as Map<String, dynamic>;
  return <String, dynamic>{
    'runtime_session_id': 'runtime-1',
    'stored_session_id': 'stored-1',
    'mobile_session_id': _mobileSessionId,
    'binding_version': 1,
    'turn_recovery': true,
    'automatic_resubmit': false,
    'capabilities': payload['capabilities'],
  };
}

void main() {
  group('turn recovery v2 capability', () {
    test('accepts the exact core and attachment capability shapes', () {
      final core = GatewayTurnRecoveryCapability.fromGatewayReadyFrame(
        _readyFrame(),
      );
      final attachments = GatewayTurnRecoveryCapability.fromGatewayReadyFrame(
        _readyFrame(attachments: true),
      );

      expect(core.supported, isTrue);
      expect(core.attachmentsSupported, isFalse);
      expect(core.reconcileMaxEvents, 256);
      expect(core.terminalEventReserveBytes, 1024);
      expect(attachments.supported, isTrue);
      expect(attachments.attachmentsSupported, isTrue);
      expect(attachments.maxAttachments, 10);
      expect(attachments.maxFileAttachmentBytes, 16777216);
    });

    test('rejects v1, shadow, automatic resubmit, and method drift', () {
      expect(
        GatewayTurnRecoveryCapability.fromGatewayReadyFrame(
          _readyFrame(version: 1),
        ).failure,
        GatewayTurnCapabilityFailure.unsupportedCapabilityVersion,
      );
      expect(
        GatewayTurnRecoveryCapability.fromGatewayReadyFrame(
          _readyFrame(shadowOnly: true),
        ).failure,
        GatewayTurnCapabilityFailure.unsafeShadowCapability,
      );
      expect(
        GatewayTurnRecoveryCapability.fromGatewayReadyFrame(
          _readyFrame(automaticResubmit: true),
        ).failure,
        GatewayTurnCapabilityFailure.automaticResubmitNotDisabled,
      );
      final drift = _readyFrame();
      final recovery =
          (((drift['params'] as Map)['payload'] as Map)['capabilities']
                  as Map)['turn_recovery']
              as Map<String, dynamic>;
      (recovery['methods'] as List).add('turn.snapshot');
      expect(
        GatewayTurnRecoveryCapability.fromGatewayReadyFrame(drift).supported,
        isFalse,
      );

      final malformedVersion = _readyFrame();
      final malformedRecovery =
          ((((malformedVersion['params'] as Map)['payload']
                      as Map)['capabilities']
                  as Map)['turn_recovery']
              as Map<String, dynamic>);
      malformedRecovery['version'] = '2';
      expect(
        GatewayTurnRecoveryCapability.fromGatewayReadyFrame(
          malformedVersion,
        ).failure,
        GatewayTurnCapabilityFailure.unsupportedCapability,
      );

      final invalidShapeAtNewVersion = _readyFrame(version: 3);
      final invalidShapeRecovery =
          ((((invalidShapeAtNewVersion['params'] as Map)['payload']
                      as Map)['capabilities']
                  as Map)['turn_recovery']
              as Map<String, dynamic>);
      (invalidShapeRecovery['methods'] as List).remove('turn.interrupt');
      expect(
        GatewayTurnRecoveryCapability.fromGatewayReadyFrame(
          invalidShapeAtNewVersion,
        ).failure,
        GatewayTurnCapabilityFailure.unsupportedCapability,
      );
    });
  });

  group('wire contract', () {
    test('requires the canonical session binding and v2 ack safety bit', () {
      final readyCapability =
          GatewayTurnRecoveryCapability.fromGatewayReadyFrame(_readyFrame());
      expect(
        GatewaySessionBinding.fromWire(
          _openResult(),
          readyCapability: readyCapability,
          expectedMobileSessionId: _mobileSessionId,
        ),
        isNotNull,
      );
      final invalidMobile = _openResult()
        ..['mobile_session_id'] = 'mob-not-a-uuid';
      expect(
        GatewaySessionBinding.fromWire(
          invalidMobile,
          readyCapability: readyCapability,
          expectedMobileSessionId: _mobileSessionId,
        ),
        isNull,
      );
      expect(
        GatewayTurnAck.fromWire(<String, dynamic>{
          'accepted': true,
          'client_turn_id': _clientTurnId,
          'turn_id': _turnId,
          'status': 'accepted',
          'last_seq': 0,
          'created': true,
          'automatic_resubmit': false,
        }),
        isNotNull,
      );
    });

    test('treats session.open capability as route authority', () {
      final attachmentReady =
          GatewayTurnRecoveryCapability.fromGatewayReadyFrame(
            _readyFrame(attachments: true),
          );
      final attachmentDowngrade = GatewaySessionBinding.fromWire(
        _openResult(),
        readyCapability: attachmentReady,
        expectedMobileSessionId: _mobileSessionId,
      );
      expect(attachmentDowngrade, isNotNull);
      expect(attachmentDowngrade!.capability.attachmentsSupported, isFalse);

      final coreReady = GatewayTurnRecoveryCapability.fromGatewayReadyFrame(
        _readyFrame(),
      );
      expect(
        GatewaySessionBinding.fromWire(
          _openResult(attachments: true),
          readyCapability: coreReady,
          expectedMobileSessionId: _mobileSessionId,
        ),
        isNull,
      );

      final missingCoreMethod = _openResult();
      final recovery =
          ((missingCoreMethod['capabilities'] as Map)['turn_recovery'] as Map);
      (recovery['methods'] as List).remove('turn.reconcile');
      expect(
        GatewaySessionBinding.fromWire(
          missingCoreMethod,
          readyCapability: coreReady,
          expectedMobileSessionId: _mobileSessionId,
        ),
        isNull,
      );
    });

    test('intersects every ready and open numeric limit conservatively', () {
      final readyCapability =
          GatewayTurnRecoveryCapability.fromGatewayReadyFrame(
            _readyFrame(attachments: true),
          );
      final open = _openResult(attachments: true);
      final openRecovery =
          ((open['capabilities'] as Map)['turn_recovery'] as Map);
      openRecovery['event_retention_seconds'] = 43200;
      openRecovery['turn_retention_seconds'] = 302400;
      openRecovery['max_event_bytes'] = 131072;
      openRecovery['max_turn_bytes'] = 2097152;
      openRecovery['terminal_event_reserve_bytes'] = 512;
      openRecovery['max_prompt_bytes'] = 32768;
      openRecovery['reconcile_max_events'] = 512;
      openRecovery['reconcile_max_page_bytes'] = 262144;
      openRecovery['max_attachments'] = 5;
      openRecovery['max_file_attachment_bytes'] = 8388608;
      openRecovery['max_image_attachment_bytes'] = 52428800;
      openRecovery['max_pdf_attachment_bytes'] = 26214400;
      openRecovery['max_attachment_registry_bytes'] = 33554432;

      final binding = GatewaySessionBinding.fromWire(
        open,
        readyCapability: readyCapability,
        expectedMobileSessionId: _mobileSessionId,
      );
      expect(binding, isNotNull);
      final effective = binding!.capability;
      expect(effective.eventRetentionSeconds, 43200);
      expect(effective.turnRetentionSeconds, 302400);
      expect(effective.maxEventBytes, 65536);
      expect(effective.maxTurnBytes, 2097152);
      expect(effective.terminalEventReserveBytes, 512);
      expect(effective.maxPromptBytes, 32768);
      expect(effective.reconcileMaxEvents, 256);
      expect(effective.reconcileMaxPageBytes, 262144);
      expect(effective.maxAttachments, 5);
      expect(effective.maxFileAttachmentBytes, 8388608);
      expect(effective.maxImageAttachmentBytes, 26214400);
      expect(effective.maxPdfAttachmentBytes, 26214400);
      expect(effective.maxAttachmentRegistryBytes, 33554432);
    });

    test('requires the session.open binding to echo durable authority', () {
      final readyCapability =
          GatewayTurnRecoveryCapability.fromGatewayReadyFrame(_readyFrame());
      expect(
        GatewaySessionBinding.fromWire(
          _openResult(),
          readyCapability: readyCapability,
          expectedMobileSessionId: '33333333-3333-4333-8333-333333333333',
        ),
        isNull,
      );
      expect(
        GatewaySessionBinding.fromWire(
          _openResult(),
          readyCapability: readyCapability,
          expectedMobileSessionId: _mobileSessionId,
          expectedStoredSessionId: 'stored-other',
        ),
        isNull,
      );
      expect(
        GatewaySessionBinding.fromWire(
          _openResult(),
          readyCapability: readyCapability,
          expectedMobileSessionId: _mobileSessionId,
          expectedStoredSessionId: 'stored-1',
          minimumBindingVersion: 2,
        ),
        isNull,
      );
      expect(
        GatewaySessionBinding.fromWire(
          _openResult(),
          readyCapability: readyCapability,
          expectedMobileSessionId: _mobileSessionId,
          expectedStoredSessionId: 'stored-1',
          minimumBindingVersion: 1,
        ),
        isNotNull,
      );
    });

    test('accepts only the server event payload allowlist', () {
      expect(
        GatewayTurnEvent.fromWire(_event(1, 'message.start', {})),
        isNotNull,
      );
      expect(
        GatewayTurnEvent.fromWire(
          _event(2, 'message.delta', <String, dynamic>{'text': 'a'}),
        ),
        isNotNull,
      );
      expect(
        GatewayTurnEvent.fromWire(
          _event(3, 'message.delta', <String, dynamic>{
            'text': 'a',
            'secret': 'must-not-cross',
          }),
        ),
        isNull,
      );
      expect(
        GatewayTurnEvent.fromWire(
          _event(3, 'tool.result', <String, dynamic>{}),
        ),
        isNull,
      );
    });
  });

  group('reconcile reducer', () {
    test('uncertain ACK and disconnect only request reconciliation', () {
      final initial = GatewayTurnRecoveryState.initial(
        clientTurnId: _clientTurnId,
      );
      final submitting = initial.markSubmissionStarted();
      final disconnected = submitting.markDisconnected();

      expect(submitting.requiredAction, GatewayTurnRecoveryAction.reconcile);
      expect(disconnected.requiredAction, GatewayTurnRecoveryAction.reconcile);
      expect(
        GatewayTurnRecoveryAction.values.map((value) => value.name),
        isNot(contains(anyOf('submit', 'resubmit'))),
      );
    });

    test('merges paged replay exactly once and reaches terminal state', () {
      var state = GatewayTurnRecoveryState.initial(
        clientTurnId: _clientTurnId,
      ).markSubmissionStarted();
      final first = GatewayTurnReconcilePage.fromWire(
        _eventPage(
          afterSeq: 0,
          lastSeq: 3,
          events: <Map<String, dynamic>>[
            _event(1, 'message.start', <String, dynamic>{}),
            _event(2, 'turn.status', <String, dynamic>{'status': 'running'}),
          ],
          status: 'completed',
        ),
        expectedAfterSeq: 0,
        expectedClientTurnId: _clientTurnId,
      );
      final second = GatewayTurnReconcilePage.fromWire(
        _eventPage(
          afterSeq: 2,
          lastSeq: 3,
          events: <Map<String, dynamic>>[
            _event(3, 'message.complete', <String, dynamic>{
              'text': 'done',
              'status': 'completed',
            }),
          ],
          status: 'completed',
        ),
        expectedAfterSeq: 2,
        expectedTurnId: _turnId,
        expectedClientTurnId: _clientTurnId,
      );

      expect(first, isNotNull);
      expect(second, isNotNull);
      state = state.applyReconcilePage(first!);
      expect(state.lastSeq, 2);
      expect(state.requiredAction, GatewayTurnRecoveryAction.reconcile);
      state = state.applyReconcilePage(second!);
      expect(state.lastSeq, 3);
      expect(state.status, GatewayRecoveryTurnStatus.completed);
      expect(state.requiredAction, GatewayTurnRecoveryAction.none);
      expect(state.events.map((event) => event.seq), <int>[1, 2, 3]);
      expect(state.applyEvent(state.events.last), same(state));
    });

    test('fails closed on cursor gaps and conflicting duplicates', () {
      final badPage = _eventPage(
        afterSeq: 0,
        lastSeq: 2,
        events: <Map<String, dynamic>>[
          _event(2, 'message.delta', <String, dynamic>{'text': 'gap'}),
        ],
        status: 'running',
      );
      expect(
        GatewayTurnReconcilePage.fromWire(badPage, expectedAfterSeq: 0),
        isNull,
      );

      final event = GatewayTurnEvent.fromWire(
        _event(1, 'message.delta', <String, dynamic>{'text': 'a'}),
      )!;
      final conflict = GatewayTurnEvent.fromWire(
        _event(1, 'message.delta', <String, dynamic>{'text': 'b'}),
      )!;
      final state = GatewayTurnRecoveryState.initial(
        clientTurnId: _clientTurnId,
      ).applyEvent(event).applyEvent(conflict);
      expect(state.failure, GatewayTurnRecoveryFailure.duplicateConflict);
      expect(state.requiredAction, GatewayTurnRecoveryAction.stopFailClosed);
    });

    test('a live sequence gap preserves the cursor and requests reconcile', () {
      final ack = GatewayTurnAck.fromWire(<String, dynamic>{
        'accepted': true,
        'client_turn_id': _clientTurnId,
        'turn_id': _turnId,
        'status': 'accepted',
        'last_seq': 0,
        'created': true,
        'automatic_resubmit': false,
      })!;
      final missingFirst = GatewayTurnEvent.fromWire(
        _event(2, 'message.delta', <String, dynamic>{'text': 'late'}),
      )!;

      final state = GatewayTurnRecoveryState.initial(
        clientTurnId: _clientTurnId,
      ).applyAck(ack).applyEvent(missingFirst);

      expect(state.failure, isNull);
      expect(state.lastSeq, 0);
      expect(state.events, isEmpty);
      expect(state.reconcilePending, isTrue);
      expect(state.requiredAction, GatewayTurnRecoveryAction.reconcile);
    });

    test('message start and complete drive the durable lifecycle', () {
      final ack = GatewayTurnAck.fromWire(<String, dynamic>{
        'accepted': true,
        'client_turn_id': _clientTurnId,
        'turn_id': _turnId,
        'status': 'accepted',
        'last_seq': 0,
        'created': true,
        'automatic_resubmit': false,
      })!;
      var state = GatewayTurnRecoveryState.initial(
        clientTurnId: _clientTurnId,
      ).applyAck(ack);

      state = state.applyEvent(
        GatewayTurnEvent.fromWire(_event(1, 'message.start', const {}))!,
      );
      expect(state.status, GatewayRecoveryTurnStatus.running);
      state = state.applyEvent(
        GatewayTurnEvent.fromWire(
          _event(2, 'message.delta', <String, dynamic>{'text': 'done'}),
        )!,
      );
      expect(state.status, GatewayRecoveryTurnStatus.running);
      state = state.applyEvent(
        GatewayTurnEvent.fromWire(
          _event(3, 'message.complete', <String, dynamic>{
            'text': 'done',
            'status': 'completed',
          }),
        )!,
      );
      expect(state.status, GatewayRecoveryTurnStatus.completed);
      expect(state.isTerminal, isTrue);
      expect(state.requiredAction, GatewayTurnRecoveryAction.none);
    });

    test('terminal state accepts only an exact duplicate event', () {
      final ack = GatewayTurnAck.fromWire(<String, dynamic>{
        'accepted': true,
        'client_turn_id': _clientTurnId,
        'turn_id': _turnId,
        'status': 'accepted',
        'last_seq': 0,
        'created': true,
        'automatic_resubmit': false,
      })!;
      final start = GatewayTurnEvent.fromWire(
        _event(1, 'message.start', const {}),
      )!;
      final complete = GatewayTurnEvent.fromWire(
        _event(2, 'message.complete', <String, dynamic>{
          'text': 'done',
          'status': 'completed',
        }),
      )!;
      final terminal = GatewayTurnRecoveryState.initial(
        clientTurnId: _clientTurnId,
      ).applyAck(ack).applyEvent(start).applyEvent(complete);

      expect(terminal.applyEvent(complete), same(terminal));
      final conflictingDuplicate = GatewayTurnEvent.fromWire(
        _event(2, 'message.complete', <String, dynamic>{
          'text': 'different',
          'status': 'completed',
        }),
      )!;
      expect(
        terminal.applyEvent(conflictingDuplicate).failure,
        GatewayTurnRecoveryFailure.duplicateConflict,
      );
      for (final late in <GatewayTurnEvent>[
        GatewayTurnEvent.fromWire(
          _event(3, 'message.delta', <String, dynamic>{'text': 'late'}),
        )!,
        GatewayTurnEvent.fromWire(
          _event(4, 'message.delta', <String, dynamic>{'text': 'gap'}),
        )!,
        GatewayTurnEvent.fromWire(
          _event(3, 'turn.status', <String, dynamic>{'status': 'completed'}),
        )!,
      ]) {
        final failed = terminal.applyEvent(late);
        expect(failed.failure, GatewayTurnRecoveryFailure.invalidTransition);
        expect(failed.requiredAction, GatewayTurnRecoveryAction.stopFailClosed);
      }
    });

    test('rejects a reconcile cursor beyond the server last sequence', () {
      final impossibleCursor = _eventPage(
        afterSeq: 0,
        lastSeq: 1,
        events: <Map<String, dynamic>>[
          _event(1, 'message.start', <String, dynamic>{}),
          _event(2, 'message.delta', <String, dynamic>{'text': 'beyond'}),
        ],
        status: 'running',
      );

      expect(impossibleCursor['next_after_seq'], 2);
      expect(
        GatewayTurnReconcilePage.fromWire(
          impossibleCursor,
          expectedAfterSeq: 0,
        ),
        isNull,
      );
    });

    test('accepts the exact server-selected terminal snapshot', () {
      final page = GatewayTurnReconcilePage.fromWire(
        <String, dynamic>{
          'mode': 'snapshot',
          'snapshot': <String, dynamic>{
            'turn_id': _turnId,
            'client_turn_id': _clientTurnId,
            'status': 'completed',
            'last_seq': 9,
            'assistant': <String, dynamic>{
              'message_id': 'message-1',
              'text': 'durable result',
              'complete': true,
            },
            'attachment_manifest_digest': _digest,
            'final_message_ref': 42,
          },
          'earliest_seq': 5,
          'last_seq': 9,
          'has_more': false,
          'next_after_seq': 9,
          'automatic_resubmit': false,
        },
        expectedAfterSeq: 0,
        expectedClientTurnId: _clientTurnId,
      );

      expect(page, isNotNull);
      final state = GatewayTurnRecoveryState.initial(
        clientTurnId: _clientTurnId,
      ).markDisconnected().applyReconcilePage(page!);
      expect(state.snapshot?.assistant.text, 'durable result');
      expect(state.status, GatewayRecoveryTurnStatus.completed);
      expect(state.lastSeq, 9);
      expect(state.requiredAction, GatewayTurnRecoveryAction.none);
    });

    test('rejects cross-turn and cross-client reconciliation', () {
      final crossTurn = _eventPage(
        afterSeq: 0,
        lastSeq: 1,
        events: <Map<String, dynamic>>[
          _event(1, 'turn.status', <String, dynamic>{'status': 'accepted'}),
        ],
        status: 'accepted',
      )..['turn_id'] = 'other-turn';
      expect(
        GatewayTurnReconcilePage.fromWire(
          crossTurn,
          expectedAfterSeq: 0,
          expectedTurnId: _turnId,
        ),
        isNull,
      );

      final snapshot = <String, dynamic>{
        'mode': 'snapshot',
        'snapshot': <String, dynamic>{
          'turn_id': _turnId,
          'client_turn_id': '33333333-3333-4333-8333-333333333333',
          'status': 'failed',
          'last_seq': 2,
          'assistant': <String, dynamic>{
            'message_id': 'message-1',
            'text': 'failed',
            'complete': true,
          },
          'attachment_manifest_digest': _digest,
          'final_message_ref': 7,
        },
        'earliest_seq': 2,
        'last_seq': 2,
        'has_more': false,
        'next_after_seq': 2,
        'automatic_resubmit': false,
      };
      expect(
        GatewayTurnReconcilePage.fromWire(
          snapshot,
          expectedAfterSeq: 0,
          expectedClientTurnId: _clientTurnId,
        ),
        isNull,
      );
    });
  });
}
