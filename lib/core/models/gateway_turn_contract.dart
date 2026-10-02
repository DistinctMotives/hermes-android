enum GatewayRecoveryTurnStatus {
  accepted('accepted'),
  running('running'),
  waitingInput('waiting_input'),
  completed('completed'),
  failed('failed'),
  interrupted('interrupted');

  const GatewayRecoveryTurnStatus(this.wireValue);

  final String wireValue;

  bool get isTerminal =>
      this == completed || this == failed || this == interrupted;

  static GatewayRecoveryTurnStatus? fromWire(Object? value) {
    if (value is! String) return null;
    for (final status in values) {
      if (status.wireValue == value) return status;
    }
    return null;
  }
}

enum GatewayTurnCapabilityFailure {
  none,
  notGatewayReady,
  missingProtocol,
  unsupportedProtocol,
  missingCapability,
  unsupportedCapabilityVersion,
  unsupportedCapability,
  unsafeShadowCapability,
  automaticResubmitNotDisabled,
  invalidRetention,
  invalidLimits,
}

/// Fail-closed parser for the exact server-side turn-recovery v2 capability.
///
/// This is source-only contract code. It does not enable the recovery route;
/// the application coordinator remains a separate, review-gated ChangeSet.
class GatewayTurnRecoveryCapability {
  static const protocolName = 'hermes-jsonrpc';
  static const protocolMajor = 2;
  static const capabilityVersion = 2;
  static const promptSubmitVersion = 2;
  static const executionRoute = 'single_process_in_process';
  static const sessionOpenMethod = 'session.open';
  static const reconcileMethod = 'turn.reconcile';
  static const interruptMethod = 'turn.interrupt';
  static const attachmentDetachMethod = 'attachment.detach@2';

  static const _coreMethods = <String>{
    sessionOpenMethod,
    reconcileMethod,
    interruptMethod,
  };
  static const _coreAppliesTo = <String>{
    sessionOpenMethod,
    'prompt.submit@2',
    reconcileMethod,
    interruptMethod,
  };

  final bool supported;
  final GatewayTurnCapabilityFailure failure;
  final bool attachmentsSupported;
  final int? eventRetentionSeconds;
  final int? turnRetentionSeconds;
  final int? maxEventBytes;
  final int? maxTurnBytes;
  final int? terminalEventReserveBytes;
  final int? maxPromptBytes;
  final int? reconcileMaxEvents;
  final int? reconcileMaxPageBytes;
  final int? maxAttachments;
  final int? maxFileAttachmentBytes;
  final int? maxImageAttachmentBytes;
  final int? maxPdfAttachmentBytes;
  final int? maxAttachmentRegistryBytes;

  const GatewayTurnRecoveryCapability._({
    required this.supported,
    required this.failure,
    this.attachmentsSupported = false,
    this.eventRetentionSeconds,
    this.turnRetentionSeconds,
    this.maxEventBytes,
    this.maxTurnBytes,
    this.terminalEventReserveBytes,
    this.maxPromptBytes,
    this.reconcileMaxEvents,
    this.reconcileMaxPageBytes,
    this.maxAttachments,
    this.maxFileAttachmentBytes,
    this.maxImageAttachmentBytes,
    this.maxPdfAttachmentBytes,
    this.maxAttachmentRegistryBytes,
  });

  const GatewayTurnRecoveryCapability.unsupported(
    GatewayTurnCapabilityFailure failure,
  ) : this._(supported: false, failure: failure);

  static GatewayTurnRecoveryCapability fromGatewayReadyFrame(
    Map<String, dynamic> frame,
  ) {
    if (frame['method'] != 'event') {
      return const GatewayTurnRecoveryCapability.unsupported(
        GatewayTurnCapabilityFailure.notGatewayReady,
      );
    }
    final params = _stringMap(frame['params']);
    if (params == null || params['type'] != 'gateway.ready') {
      return const GatewayTurnRecoveryCapability.unsupported(
        GatewayTurnCapabilityFailure.notGatewayReady,
      );
    }
    final payload = _stringMap(params['payload']);
    final protocol = _stringMap(payload?['protocol']);
    if (protocol == null) {
      return const GatewayTurnRecoveryCapability.unsupported(
        GatewayTurnCapabilityFailure.missingProtocol,
      );
    }
    if (protocol['name'] != protocolName ||
        _exactInt(protocol['major']) != protocolMajor) {
      return const GatewayTurnRecoveryCapability.unsupported(
        GatewayTurnCapabilityFailure.unsupportedProtocol,
      );
    }

    final capabilities = _stringMap(payload?['capabilities']);
    final recovery = _stringMap(capabilities?['turn_recovery']);
    if (recovery == null) {
      return const GatewayTurnRecoveryCapability.unsupported(
        GatewayTurnCapabilityFailure.missingCapability,
      );
    }
    return _fromRecoveryPayload(recovery);
  }

  /// Validates the route-specific capability returned by `session.open`.
  ///
  /// The open result is authoritative for this runtime. It may disable the
  /// optional attachment route advertised by the generic ready frame, but it
  /// may not add that route or weaken any core recovery invariant.
  static GatewayTurnRecoveryCapability fromSessionOpenResult(
    Map<String, dynamic> result, {
    required GatewayTurnRecoveryCapability readyCapability,
  }) {
    if (!readyCapability.supported) {
      return const GatewayTurnRecoveryCapability.unsupported(
        GatewayTurnCapabilityFailure.unsupportedCapability,
      );
    }
    final capabilities = _stringMap(result['capabilities']);
    final recovery = _stringMap(capabilities?['turn_recovery']);
    if (recovery == null) {
      return const GatewayTurnRecoveryCapability.unsupported(
        GatewayTurnCapabilityFailure.missingCapability,
      );
    }
    final openCapability = _fromRecoveryPayload(recovery);
    if (!openCapability.supported ||
        !readyCapability.attachmentsSupported &&
            openCapability.attachmentsSupported) {
      return const GatewayTurnRecoveryCapability.unsupported(
        GatewayTurnCapabilityFailure.unsupportedCapability,
      );
    }
    final attachmentsSupported =
        readyCapability.attachmentsSupported &&
        openCapability.attachmentsSupported;
    return GatewayTurnRecoveryCapability._(
      supported: true,
      failure: GatewayTurnCapabilityFailure.none,
      attachmentsSupported: attachmentsSupported,
      eventRetentionSeconds: _minimumSupported(
        readyCapability.eventRetentionSeconds,
        openCapability.eventRetentionSeconds,
      ),
      turnRetentionSeconds: _minimumSupported(
        readyCapability.turnRetentionSeconds,
        openCapability.turnRetentionSeconds,
      ),
      maxEventBytes: _minimumSupported(
        readyCapability.maxEventBytes,
        openCapability.maxEventBytes,
      ),
      maxTurnBytes: _minimumSupported(
        readyCapability.maxTurnBytes,
        openCapability.maxTurnBytes,
      ),
      terminalEventReserveBytes: _minimumSupported(
        readyCapability.terminalEventReserveBytes,
        openCapability.terminalEventReserveBytes,
      ),
      maxPromptBytes: _minimumSupported(
        readyCapability.maxPromptBytes,
        openCapability.maxPromptBytes,
      ),
      reconcileMaxEvents: _minimumSupported(
        readyCapability.reconcileMaxEvents,
        openCapability.reconcileMaxEvents,
      ),
      reconcileMaxPageBytes: _minimumSupported(
        readyCapability.reconcileMaxPageBytes,
        openCapability.reconcileMaxPageBytes,
      ),
      maxAttachments: attachmentsSupported
          ? _minimumSupported(
              readyCapability.maxAttachments,
              openCapability.maxAttachments,
            )
          : null,
      maxFileAttachmentBytes: attachmentsSupported
          ? _minimumSupported(
              readyCapability.maxFileAttachmentBytes,
              openCapability.maxFileAttachmentBytes,
            )
          : null,
      maxImageAttachmentBytes: attachmentsSupported
          ? _minimumSupported(
              readyCapability.maxImageAttachmentBytes,
              openCapability.maxImageAttachmentBytes,
            )
          : null,
      maxPdfAttachmentBytes: attachmentsSupported
          ? _minimumSupported(
              readyCapability.maxPdfAttachmentBytes,
              openCapability.maxPdfAttachmentBytes,
            )
          : null,
      maxAttachmentRegistryBytes: attachmentsSupported
          ? _minimumSupported(
              readyCapability.maxAttachmentRegistryBytes,
              openCapability.maxAttachmentRegistryBytes,
            )
          : null,
    );
  }

  static GatewayTurnRecoveryCapability _fromRecoveryPayload(
    Map<String, dynamic> recovery,
  ) {
    final advertisedVersion = _positiveInt(recovery['version']);
    final advertisedPromptVersion = _positiveInt(
      recovery['prompt_submit_version'],
    );
    if (advertisedVersion == null || advertisedPromptVersion == null) {
      return const GatewayTurnRecoveryCapability.unsupported(
        GatewayTurnCapabilityFailure.unsupportedCapability,
      );
    }
    if (advertisedVersion != capabilityVersion ||
        advertisedPromptVersion != promptSubmitVersion) {
      final normalized = <String, dynamic>{
        ...recovery,
        'version': capabilityVersion,
        'prompt_submit_version': promptSubmitVersion,
      };
      final shape = _fromRecoveryPayload(normalized);
      return shape.supported
          ? const GatewayTurnRecoveryCapability.unsupported(
              GatewayTurnCapabilityFailure.unsupportedCapabilityVersion,
            )
          : shape;
    }
    if (recovery['execution_route'] != executionRoute ||
        recovery['mobile_session_id_format'] != 'canonical_lowercase_uuid' ||
        recovery['client_turn_id_format'] != 'canonical_lowercase_uuid') {
      return const GatewayTurnRecoveryCapability.unsupported(
        GatewayTurnCapabilityFailure.unsupportedCapability,
      );
    }
    if (recovery['shadow_only'] != false) {
      return const GatewayTurnRecoveryCapability.unsupported(
        GatewayTurnCapabilityFailure.unsafeShadowCapability,
      );
    }
    if (recovery['automatic_resubmit'] != false) {
      return const GatewayTurnRecoveryCapability.unsupported(
        GatewayTurnCapabilityFailure.automaticResubmitNotDisabled,
      );
    }

    final methods = _strictStringSet(recovery['methods']);
    final appliesTo = _strictStringSet(recovery['applies_to']);
    if (methods == null || appliesTo == null) {
      return const GatewayTurnRecoveryCapability.unsupported(
        GatewayTurnCapabilityFailure.unsupportedCapability,
      );
    }
    final attachmentsSupported = methods.contains(attachmentDetachMethod);
    final expectedMethods = <String>{
      ..._coreMethods,
      if (attachmentsSupported) attachmentDetachMethod,
    };
    final expectedAppliesTo = <String>{
      ..._coreAppliesTo,
      if (attachmentsSupported) attachmentDetachMethod,
    };
    if (!_setEquals(methods, expectedMethods) ||
        !_setEquals(appliesTo, expectedAppliesTo)) {
      return const GatewayTurnRecoveryCapability.unsupported(
        GatewayTurnCapabilityFailure.unsupportedCapability,
      );
    }

    final eventRetention = _positiveInt(recovery['event_retention_seconds']);
    final turnRetention = _positiveInt(recovery['turn_retention_seconds']);
    if (eventRetention == null ||
        turnRetention == null ||
        turnRetention < eventRetention) {
      return const GatewayTurnRecoveryCapability.unsupported(
        GatewayTurnCapabilityFailure.invalidRetention,
      );
    }

    final maxEventBytes = _positiveInt(recovery['max_event_bytes']);
    final maxTurnBytes = _positiveInt(recovery['max_turn_bytes']);
    final terminalReserve = _positiveInt(
      recovery['terminal_event_reserve_bytes'],
    );
    final maxPromptBytes = _positiveInt(recovery['max_prompt_bytes']);
    final reconcileMaxEvents = _positiveInt(recovery['reconcile_max_events']);
    final reconcileMaxPageBytes = _positiveInt(
      recovery['reconcile_max_page_bytes'],
    );
    if (maxEventBytes == null ||
        maxTurnBytes == null ||
        terminalReserve == null ||
        terminalReserve > maxEventBytes ||
        maxPromptBytes == null ||
        reconcileMaxEvents == null ||
        reconcileMaxPageBytes == null ||
        reconcileMaxPageBytes < maxEventBytes) {
      return const GatewayTurnRecoveryCapability.unsupported(
        GatewayTurnCapabilityFailure.invalidLimits,
      );
    }
    final maxAttachments = _positiveInt(recovery['max_attachments']);
    final maxFileAttachmentBytes = _positiveInt(
      recovery['max_file_attachment_bytes'],
    );
    final maxImageAttachmentBytes = _positiveInt(
      recovery['max_image_attachment_bytes'],
    );
    final maxPdfAttachmentBytes = _positiveInt(
      recovery['max_pdf_attachment_bytes'],
    );
    final maxAttachmentRegistryBytes = _positiveInt(
      recovery['max_attachment_registry_bytes'],
    );
    if (attachmentsSupported) {
      if (maxAttachments == null ||
          maxFileAttachmentBytes == null ||
          maxImageAttachmentBytes == null ||
          maxPdfAttachmentBytes == null ||
          maxAttachmentRegistryBytes == null) {
        return const GatewayTurnRecoveryCapability.unsupported(
          GatewayTurnCapabilityFailure.invalidLimits,
        );
      }
    }

    return GatewayTurnRecoveryCapability._(
      supported: true,
      failure: GatewayTurnCapabilityFailure.none,
      attachmentsSupported: attachmentsSupported,
      eventRetentionSeconds: eventRetention,
      turnRetentionSeconds: turnRetention,
      maxEventBytes: maxEventBytes,
      maxTurnBytes: maxTurnBytes,
      terminalEventReserveBytes: terminalReserve,
      maxPromptBytes: maxPromptBytes,
      reconcileMaxEvents: reconcileMaxEvents,
      reconcileMaxPageBytes: reconcileMaxPageBytes,
      maxAttachments: attachmentsSupported ? maxAttachments : null,
      maxFileAttachmentBytes: attachmentsSupported
          ? maxFileAttachmentBytes
          : null,
      maxImageAttachmentBytes: attachmentsSupported
          ? maxImageAttachmentBytes
          : null,
      maxPdfAttachmentBytes: attachmentsSupported
          ? maxPdfAttachmentBytes
          : null,
      maxAttachmentRegistryBytes: attachmentsSupported
          ? maxAttachmentRegistryBytes
          : null,
    );
  }
}

class GatewaySessionBinding {
  final String runtimeSessionId;
  final String storedSessionId;
  final String mobileSessionId;
  final int bindingVersion;
  final GatewayTurnRecoveryCapability capability;

  const GatewaySessionBinding({
    required this.runtimeSessionId,
    required this.storedSessionId,
    required this.mobileSessionId,
    required this.bindingVersion,
    required this.capability,
  });

  static GatewaySessionBinding? fromWire(
    Map<String, dynamic> value, {
    required GatewayTurnRecoveryCapability readyCapability,
    required String expectedMobileSessionId,
    String? expectedStoredSessionId,
    int? minimumBindingVersion,
  }) {
    if (value['turn_recovery'] != true ||
        value['automatic_resubmit'] != false) {
      return null;
    }
    final runtimeSessionId = _requiredWireString(value['runtime_session_id']);
    final storedSessionId = _requiredWireString(value['stored_session_id']);
    final mobileSessionId = _canonicalUuid(value['mobile_session_id']);
    final bindingVersion = _positiveInt(value['binding_version']);
    final capability = GatewayTurnRecoveryCapability.fromSessionOpenResult(
      value,
      readyCapability: readyCapability,
    );
    final canonicalExpectedMobileSessionId = _canonicalUuid(
      expectedMobileSessionId,
    );
    final validExpectedStoredSessionId = expectedStoredSessionId == null
        ? null
        : _requiredWireString(expectedStoredSessionId);
    if (runtimeSessionId == null ||
        storedSessionId == null ||
        mobileSessionId == null ||
        canonicalExpectedMobileSessionId == null ||
        mobileSessionId != canonicalExpectedMobileSessionId ||
        expectedStoredSessionId != null &&
            (validExpectedStoredSessionId == null ||
                storedSessionId != validExpectedStoredSessionId) ||
        bindingVersion == null ||
        minimumBindingVersion != null &&
            (minimumBindingVersion <= 0 ||
                bindingVersion < minimumBindingVersion) ||
        !capability.supported) {
      return null;
    }
    return GatewaySessionBinding(
      runtimeSessionId: runtimeSessionId,
      storedSessionId: storedSessionId,
      mobileSessionId: mobileSessionId,
      bindingVersion: bindingVersion,
      capability: capability,
    );
  }
}

int _minimumSupported(int? left, int? right) {
  if (left == null || right == null) {
    throw StateError('Supported recovery capability is incomplete.');
  }
  return left < right ? left : right;
}

class GatewayTurnAck {
  final String clientTurnId;
  final String turnId;
  final GatewayRecoveryTurnStatus status;
  final int lastSeq;
  final bool created;

  const GatewayTurnAck({
    required this.clientTurnId,
    required this.turnId,
    required this.status,
    required this.lastSeq,
    required this.created,
  });

  static GatewayTurnAck? fromWire(Map<String, dynamic> value) {
    if (value['accepted'] != true || value['automatic_resubmit'] != false) {
      return null;
    }
    final clientTurnId = _canonicalUuid(value['client_turn_id']);
    final turnId = _requiredWireString(value['turn_id']);
    final status = GatewayRecoveryTurnStatus.fromWire(value['status']);
    final lastSeq = _nonNegativeInt(value['last_seq']);
    final created = value['created'];
    if (clientTurnId == null ||
        turnId == null ||
        status == null ||
        lastSeq == null ||
        created is! bool) {
      return null;
    }
    return GatewayTurnAck(
      clientTurnId: clientTurnId,
      turnId: turnId,
      status: status,
      lastSeq: lastSeq,
      created: created,
    );
  }
}

class GatewayTurnEvent {
  static const allowedTypes = <String>{
    'message.start',
    'message.delta',
    'message.complete',
    'turn.status',
  };

  final String turnId;
  final int seq;
  final String messageId;
  final String type;
  final Map<String, dynamic> payload;

  const GatewayTurnEvent({
    required this.turnId,
    required this.seq,
    required this.messageId,
    required this.type,
    required this.payload,
  });

  static GatewayTurnEvent? fromWire(Map<String, dynamic> value) {
    final turnId = _requiredWireString(value['turn_id']);
    final messageId = _requiredWireString(value['message_id']);
    final type = _requiredWireString(value['type']);
    final seq = _positiveInt(value['seq']);
    final payload = _stringMap(value['payload']);
    if (turnId == null ||
        messageId == null ||
        type == null ||
        !allowedTypes.contains(type) ||
        seq == null ||
        payload == null ||
        !_validEventPayload(type, payload)) {
      return null;
    }
    return GatewayTurnEvent(
      turnId: turnId,
      seq: seq,
      messageId: messageId,
      type: type,
      payload: Map<String, dynamic>.unmodifiable(payload),
    );
  }

  bool sameWireEvent(GatewayTurnEvent other) {
    return turnId == other.turnId &&
        seq == other.seq &&
        messageId == other.messageId &&
        type == other.type &&
        _deepEquals(payload, other.payload);
  }
}

bool _validEventPayload(String type, Map<String, dynamic> payload) {
  switch (type) {
    case 'message.start':
      return payload.isEmpty;
    case 'message.delta':
      return payload.length == 1 && payload['text'] is String;
    case 'message.complete':
      final status = GatewayRecoveryTurnStatus.fromWire(payload['status']);
      return payload.length == 2 &&
          payload['text'] is String &&
          status?.isTerminal == true;
    case 'turn.status':
      return payload.length == 1 &&
          GatewayRecoveryTurnStatus.fromWire(payload['status']) != null;
  }
  return false;
}

class GatewayTurnSnapshotAssistant {
  final String messageId;
  final String text;
  final bool complete;

  const GatewayTurnSnapshotAssistant({
    required this.messageId,
    required this.text,
    required this.complete,
  });
}

class GatewayTurnPendingInput {
  static const allowedKinds = <String>{'approval', 'clarify', 'secret', 'sudo'};

  final String requestId;
  final String kind;
  final num createdAt;
  final num expiresAt;

  const GatewayTurnPendingInput({
    required this.requestId,
    required this.kind,
    required this.createdAt,
    required this.expiresAt,
  });

  static GatewayTurnPendingInput? fromWire(Object? raw) {
    final value = _stringMap(raw);
    if (value == null) return null;
    final requestId = _requiredWireString(value['request_id']);
    final kind = _requiredWireString(value['kind']);
    final createdAt = value['created_at'];
    final expiresAt = value['expires_at'];
    if (requestId == null ||
        kind == null ||
        !allowedKinds.contains(kind) ||
        createdAt is! num ||
        expiresAt is! num ||
        expiresAt <= createdAt) {
      return null;
    }
    return GatewayTurnPendingInput(
      requestId: requestId,
      kind: kind,
      createdAt: createdAt,
      expiresAt: expiresAt,
    );
  }
}

class GatewayTurnSnapshot {
  final String turnId;
  final String clientTurnId;
  final GatewayRecoveryTurnStatus status;
  final int lastSeq;
  final GatewayTurnSnapshotAssistant assistant;
  final String attachmentManifestDigest;
  final int finalMessageRef;
  final GatewayTurnPendingInput? pendingInput;

  const GatewayTurnSnapshot({
    required this.turnId,
    required this.clientTurnId,
    required this.status,
    required this.lastSeq,
    required this.assistant,
    required this.attachmentManifestDigest,
    required this.finalMessageRef,
    this.pendingInput,
  });

  static GatewayTurnSnapshot? fromWire(Map<String, dynamic> value) {
    final turnId = _requiredWireString(value['turn_id']);
    final clientTurnId = _canonicalUuid(value['client_turn_id']);
    final status = GatewayRecoveryTurnStatus.fromWire(value['status']);
    final lastSeq = _nonNegativeInt(value['last_seq']);
    final assistantRaw = _stringMap(value['assistant']);
    final assistantMessageId = _requiredWireString(assistantRaw?['message_id']);
    final assistantText = assistantRaw?['text'];
    final assistantComplete = assistantRaw?['complete'];
    final digest = _lowerHexDigest(value['attachment_manifest_digest']);
    final finalMessageRef = _positiveInt(value['final_message_ref']);
    final hasPendingInput = value.containsKey('pending_input');
    final pendingInput = hasPendingInput
        ? GatewayTurnPendingInput.fromWire(value['pending_input'])
        : null;
    if (turnId == null ||
        clientTurnId == null ||
        status == null ||
        !status.isTerminal ||
        lastSeq == null ||
        assistantMessageId == null ||
        assistantText is! String ||
        assistantComplete != true ||
        digest == null ||
        finalMessageRef == null ||
        hasPendingInput && pendingInput == null) {
      return null;
    }
    return GatewayTurnSnapshot(
      turnId: turnId,
      clientTurnId: clientTurnId,
      status: status,
      lastSeq: lastSeq,
      assistant: GatewayTurnSnapshotAssistant(
        messageId: assistantMessageId,
        text: assistantText,
        complete: true,
      ),
      attachmentManifestDigest: digest,
      finalMessageRef: finalMessageRef,
      pendingInput: pendingInput,
    );
  }
}

enum GatewayTurnReconcileMode { events, snapshot }

class GatewayTurnReconcilePage {
  final GatewayTurnReconcileMode mode;
  final String turnId;
  final GatewayRecoveryTurnStatus status;
  final int earliestSeq;
  final int lastSeq;
  final int nextAfterSeq;
  final bool hasMore;
  final List<GatewayTurnEvent> events;
  final GatewayTurnSnapshot? snapshot;

  const GatewayTurnReconcilePage._({
    required this.mode,
    required this.turnId,
    required this.status,
    required this.earliestSeq,
    required this.lastSeq,
    required this.nextAfterSeq,
    required this.hasMore,
    required this.events,
    required this.snapshot,
  });

  static GatewayTurnReconcilePage? fromWire(
    Map<String, dynamic> value, {
    required int expectedAfterSeq,
    String? expectedTurnId,
    String? expectedClientTurnId,
  }) {
    if (expectedAfterSeq < 0 || value['automatic_resubmit'] != false) {
      return null;
    }
    final mode = value['mode'];
    final earliestSeq = _positiveInt(value['earliest_seq']);
    final lastSeq = _nonNegativeInt(value['last_seq']);
    final nextAfterSeq = _nonNegativeInt(value['next_after_seq']);
    final hasMore = value['has_more'];
    if (earliestSeq == null ||
        lastSeq == null ||
        nextAfterSeq == null ||
        hasMore is! bool ||
        lastSeq < expectedAfterSeq ||
        nextAfterSeq > lastSeq) {
      return null;
    }

    if (mode == 'snapshot') {
      final snapshotRaw = _stringMap(value['snapshot']);
      final snapshot = snapshotRaw == null
          ? null
          : GatewayTurnSnapshot.fromWire(snapshotRaw);
      if (snapshot == null ||
          hasMore ||
          snapshot.lastSeq != lastSeq ||
          nextAfterSeq != lastSeq ||
          expectedTurnId != null && snapshot.turnId != expectedTurnId ||
          expectedClientTurnId != null &&
              snapshot.clientTurnId != expectedClientTurnId) {
        return null;
      }
      return GatewayTurnReconcilePage._(
        mode: GatewayTurnReconcileMode.snapshot,
        turnId: snapshot.turnId,
        status: snapshot.status,
        earliestSeq: earliestSeq,
        lastSeq: lastSeq,
        nextAfterSeq: nextAfterSeq,
        hasMore: false,
        events: const [],
        snapshot: snapshot,
      );
    }

    if (mode != 'events') return null;
    final turnId = _requiredWireString(value['turn_id']);
    final status = GatewayRecoveryTurnStatus.fromWire(value['status']);
    final rawEvents = value['events'];
    if (turnId == null ||
        status == null ||
        rawEvents is! List ||
        expectedTurnId != null && turnId != expectedTurnId ||
        expectedAfterSeq < earliestSeq - 1) {
      return null;
    }
    final events = <GatewayTurnEvent>[];
    var expectedSeq = expectedAfterSeq + 1;
    for (final rawEvent in rawEvents) {
      final eventMap = _stringMap(rawEvent);
      final event = eventMap == null
          ? null
          : GatewayTurnEvent.fromWire(eventMap);
      if (event == null || event.turnId != turnId || event.seq != expectedSeq) {
        return null;
      }
      events.add(event);
      expectedSeq += 1;
    }
    final appliedCursor = events.isEmpty ? expectedAfterSeq : events.last.seq;
    if (nextAfterSeq != appliedCursor ||
        hasMore != (nextAfterSeq < lastSeq) ||
        events.isEmpty && lastSeq > expectedAfterSeq) {
      return null;
    }
    return GatewayTurnReconcilePage._(
      mode: GatewayTurnReconcileMode.events,
      turnId: turnId,
      status: status,
      earliestSeq: earliestSeq,
      lastSeq: lastSeq,
      nextAfterSeq: nextAfterSeq,
      hasMore: hasMore,
      events: List<GatewayTurnEvent>.unmodifiable(events),
      snapshot: null,
    );
  }
}

Map<String, dynamic>? _stringMap(Object? value) {
  if (value is! Map) return null;
  try {
    return Map<String, dynamic>.from(value);
  } on TypeError {
    return null;
  }
}

Set<String>? _strictStringSet(Object? value) {
  if (value is! List || value.any((item) => item is! String)) return null;
  final strings = value.cast<String>();
  final result = strings.toSet();
  return result.length == strings.length ? result : null;
}

bool _setEquals(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);

int? _exactInt(Object? value) => value is int && value is! bool ? value : null;

int? _positiveInt(Object? value) {
  final parsed = _exactInt(value);
  return parsed != null && parsed > 0 ? parsed : null;
}

int? _nonNegativeInt(Object? value) {
  final parsed = _exactInt(value);
  return parsed != null && parsed >= 0 ? parsed : null;
}

String? _requiredWireString(Object? value) {
  if (value is! String || value.isEmpty || value.trim() != value) return null;
  if (value.length > 256 || value.codeUnits.any((unit) => unit < 32)) {
    return null;
  }
  return value;
}

String? _canonicalUuid(Object? value) {
  final candidate = _requiredWireString(value);
  if (candidate == null ||
      !RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ).hasMatch(candidate) ||
      candidate == '00000000-0000-0000-0000-000000000000') {
    return null;
  }
  return candidate;
}

String? _lowerHexDigest(Object? value) {
  if (value is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    return null;
  }
  return value;
}

bool _deepEquals(Object? left, Object? right) {
  if (identical(left, right)) return true;
  if (left is Map && right is Map) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key) ||
          !_deepEquals(entry.value, right[entry.key])) {
        return false;
      }
    }
    return true;
  }
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index += 1) {
      if (!_deepEquals(left[index], right[index])) return false;
    }
    return true;
  }
  return left == right;
}
