enum GatewaySensitivePromptKind { sudo, secret }

/// A request-ID keyed password or secret prompt emitted by Hermes.
///
/// Values entered by the user are intentionally not part of this model so they
/// cannot be retained alongside chat or connection state.
class GatewaySensitivePromptRequest {
  final GatewaySensitivePromptKind kind;
  final String requestId;
  final String title;
  final String description;
  final String fieldLabel;

  const GatewaySensitivePromptRequest({
    required this.kind,
    required this.requestId,
    required this.title,
    required this.description,
    required this.fieldLabel,
  });

  static GatewaySensitivePromptRequest? fromEventData({
    required GatewaySensitivePromptKind kind,
    required Map<String, dynamic> data,
  }) {
    final requestId = data['request_id']?.toString().trim() ?? '';
    if (requestId.isEmpty) return null;

    if (kind == GatewaySensitivePromptKind.sudo) {
      return GatewaySensitivePromptRequest(
        kind: kind,
        requestId: requestId,
        title: 'Administrator password needed',
        description:
            'Hermes needs a sudo password for the pending terminal command.',
        fieldLabel: 'Sudo password',
      );
    }

    final envVar = data['env_var']?.toString().trim() ?? '';
    final prompt = data['prompt']?.toString().trim() ?? '';
    return GatewaySensitivePromptRequest(
      kind: kind,
      requestId: requestId,
      title: envVar.isEmpty ? 'Secret needed' : envVar,
      description: prompt.isEmpty
          ? 'Hermes needs a secret for the pending skill.'
          : prompt,
      fieldLabel: envVar.isEmpty ? 'Secret value' : envVar,
    );
  }
}
