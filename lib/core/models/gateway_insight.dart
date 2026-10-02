enum GatewayReasoningEventMode { append, replace }

class GatewayReasoningUpdate {
  static const _maxTextLength = 20000;

  final String text;
  final GatewayReasoningEventMode mode;
  final bool verbose;

  const GatewayReasoningUpdate({
    required this.text,
    required this.mode,
    required this.verbose,
  });

  static GatewayReasoningUpdate? fromGatewayEvent(
    String eventType,
    Map<String, dynamic> data,
  ) {
    if (eventType != 'reasoning.delta' && eventType != 'reasoning.available') {
      return null;
    }
    final text = _safeText(data['text']?.toString(), _maxTextLength);
    if (text == null) return null;
    return GatewayReasoningUpdate(
      text: text,
      mode: eventType == 'reasoning.available'
          ? GatewayReasoningEventMode.replace
          : GatewayReasoningEventMode.append,
      verbose: data['verbose'] == true,
    );
  }

  String applyTo(String current) {
    final combined = mode == GatewayReasoningEventMode.replace
        ? text
        : '$current$text';
    if (combined.length <= _maxTextLength) return combined;
    return '${combined.substring(0, _maxTextLength - 1)}…';
  }

  static String? _safeText(String? value, int maxLength) {
    if (value == null) return null;
    final safe = value.replaceAll('\u0000', '');
    if (safe.trim().isEmpty) return null;
    return safe.length <= maxLength
        ? safe
        : '${safe.substring(0, maxLength - 1)}…';
  }
}

class GatewayInterimTransition {
  final String sealedText;
  final bool startsNewMessage;

  const GatewayInterimTransition({
    required this.sealedText,
    required this.startsNewMessage,
  });

  factory GatewayInterimTransition.resolve({
    required String currentText,
    required String interimText,
    required bool alreadyStreamed,
  }) {
    final safeInterim = interimText.replaceAll('\u0000', '');
    var sealed = currentText;
    if (safeInterim.isNotEmpty &&
        currentText != safeInterim &&
        !currentText.endsWith(safeInterim)) {
      if (!alreadyStreamed) {
        sealed = '$currentText$safeInterim';
      } else if (currentText.isEmpty || safeInterim.startsWith(currentText)) {
        sealed = safeInterim;
      }
    }
    return GatewayInterimTransition(
      sealedText: sealed,
      startsNewMessage: sealed.trim().isNotEmpty,
    );
  }
}

enum GatewayNoticeKind { background, review }

class GatewayNotice {
  static const _maxTextLength = 4000;
  static const _maxTaskIdLength = 120;

  final GatewayNoticeKind kind;
  final String text;
  final String? taskId;

  const GatewayNotice({required this.kind, required this.text, this.taskId});

  String get identity => '${kind.name}|${taskId ?? ''}|$text';

  String get title => switch (kind) {
    GatewayNoticeKind.background =>
      taskId == null
          ? 'Background task completed'
          : 'Background task $taskId completed',
    GatewayNoticeKind.review => 'Hermes review',
  };

  static GatewayNotice? fromGatewayEvent(
    String eventType,
    Map<String, dynamic> data,
  ) {
    if (eventType != 'background.complete' && eventType != 'review.summary') {
      return null;
    }
    final text = safeLine(data['text']?.toString(), _maxTextLength);
    if (text == null) return null;
    return GatewayNotice(
      kind: eventType == 'background.complete'
          ? GatewayNoticeKind.background
          : GatewayNoticeKind.review,
      text: text,
      taskId: eventType == 'background.complete'
          ? safeLine(data['task_id']?.toString(), _maxTaskIdLength)
          : null,
    );
  }

  static String? safeLine(String? value, int maxLength) {
    if (value == null) return null;
    final safe = value.replaceAll('\u0000', '').trim();
    if (safe.isEmpty) return null;
    return safe.length <= maxLength
        ? safe
        : '${safe.substring(0, maxLength - 1)}…';
  }
}

enum GatewayNotificationLevel { info, success, warning, error }

class GatewayNotification {
  final String key;
  final String text;
  final GatewayNotificationLevel level;
  final Duration? ttl;

  const GatewayNotification({
    required this.key,
    required this.text,
    required this.level,
    this.ttl,
  });

  static GatewayNotification? fromEventData(Map<String, dynamic> data) {
    final text = GatewayNotice.safeLine(data['text']?.toString(), 1000);
    if (text == null) return null;
    final key =
        GatewayNotice.safeLine((data['key'] ?? data['id'])?.toString(), 120) ??
        'latest';
    final ttlMs = switch (data['ttl_ms']) {
      int value when value > 0 => value,
      num value when value > 0 => value.toInt(),
      _ => null,
    };
    return GatewayNotification(
      key: key,
      text: text,
      level: switch (data['level']?.toString()) {
        'success' => GatewayNotificationLevel.success,
        'warn' => GatewayNotificationLevel.warning,
        'error' => GatewayNotificationLevel.error,
        _ => GatewayNotificationLevel.info,
      },
      ttl: ttlMs == null ? null : Duration(milliseconds: ttlMs),
    );
  }
}

enum GatewaySubagentPhase { requested, running, thinking, tool, completed }

class GatewaySubagentActivity {
  final String id;
  final String goal;
  final String? model;
  final String? detail;
  final GatewaySubagentPhase phase;
  final int? taskIndex;
  final int? taskCount;

  const GatewaySubagentActivity({
    required this.id,
    required this.goal,
    required this.phase,
    this.model,
    this.detail,
    this.taskIndex,
    this.taskCount,
  });

  bool get isComplete => phase == GatewaySubagentPhase.completed;

  GatewaySubagentActivity merge(GatewaySubagentActivity next) {
    return GatewaySubagentActivity(
      id: id,
      goal: next.goal.isEmpty ? goal : next.goal,
      phase: next.phase,
      model: next.model ?? model,
      detail: next.detail ?? detail,
      taskIndex: next.taskIndex ?? taskIndex,
      taskCount: next.taskCount ?? taskCount,
    );
  }

  static GatewaySubagentActivity? fromGatewayEvent(
    String eventType,
    Map<String, dynamic> data,
  ) {
    if (!eventType.startsWith('subagent.')) return null;
    final id =
        GatewayNotice.safeLine(data['subagent_id']?.toString(), 120) ??
        'task-${data['task_index'] ?? 0}';
    final goal =
        GatewayNotice.safeLine(data['goal']?.toString(), 500) ??
        'Delegated task';
    final detail = GatewayNotice.safeLine(
      (data['summary'] ??
              data['text'] ??
              data['tool_preview'] ??
              data['tool_name'])
          ?.toString(),
      1000,
    );
    return GatewaySubagentActivity(
      id: id,
      goal: goal,
      model: GatewayNotice.safeLine(data['model']?.toString(), 120),
      detail: detail,
      taskIndex: (data['task_index'] as num?)?.toInt(),
      taskCount: (data['task_count'] as num?)?.toInt(),
      phase: switch (eventType) {
        'subagent.spawn_requested' => GatewaySubagentPhase.requested,
        'subagent.thinking' => GatewaySubagentPhase.thinking,
        'subagent.tool' => GatewaySubagentPhase.tool,
        'subagent.complete' => GatewaySubagentPhase.completed,
        _ => GatewaySubagentPhase.running,
      },
    );
  }
}
