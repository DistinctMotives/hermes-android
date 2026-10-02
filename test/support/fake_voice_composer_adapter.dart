import 'package:hermes_android/core/services/voice_composer_adapter.dart';

class FakeVoiceComposerAdapter implements VoiceComposerAdapter {
  final bool permissionGranted;
  final bool initializationSucceeds;
  String? finalTranscriptOnStop;

  VoiceStatusCallback? _onStatus;
  VoiceErrorCallback? _onError;
  VoiceResultCallback? _onResult;

  int initializeCount = 0;
  int listenCount = 0;
  int stopCount = 0;
  int cancelCount = 0;
  int disposeCount = 0;

  FakeVoiceComposerAdapter({
    this.permissionGranted = true,
    this.initializationSucceeds = true,
    this.finalTranscriptOnStop,
  });

  @override
  Future<bool> get hasPermission async => permissionGranted;

  @override
  Future<bool> initialize({
    required VoiceStatusCallback onStatus,
    required VoiceErrorCallback onError,
  }) async {
    initializeCount += 1;
    _onStatus = onStatus;
    _onError = onError;
    return initializationSucceeds;
  }

  @override
  Future<void> listen({
    required VoiceResultCallback onResult,
    String? localeId,
  }) async {
    listenCount += 1;
    _onResult = onResult;
    _onStatus?.call('listening');
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
    final transcript = finalTranscriptOnStop;
    if (transcript != null) {
      _onResult?.call(transcript: transcript, isFinal: true);
    }
    _onStatus?.call('done');
  }

  @override
  Future<void> cancel() async {
    cancelCount += 1;
    _onStatus?.call('notListening');
  }

  void emitPartial(String transcript) {
    _onResult?.call(transcript: transcript, isFinal: false);
  }

  void emitFinal(String transcript) {
    _onResult?.call(transcript: transcript, isFinal: true);
  }

  void emitStatus(String status) {
    _onStatus?.call(status);
  }

  void emitError(String message) {
    _onError?.call(message);
  }

  @override
  void dispose() {
    disposeCount += 1;
  }
}
