import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/chat_model_override_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('restores a model override for the same connection and chat', () async {
    final store = await ChatModelOverrideStore.open();
    await store.save(
      connectionIdentity:
          'https://gateway.example|/api|https://desktop.example',
      sessionId: 'chat-1',
      provider: 'custom',
      model: 'hermes-model',
      reasoningEffort: 'high',
    );

    final restored = store.read(
      connectionIdentity:
          'https://gateway.example|/api|https://desktop.example',
      sessionId: 'chat-1',
    );

    expect(restored?.provider, 'custom');
    expect(restored?.model, 'hermes-model');
    expect(restored?.reasoningEffort, 'high');
  });

  test('keeps older model overrides valid without an effort value', () async {
    final store = await ChatModelOverrideStore.open();
    await store.save(
      connectionIdentity: 'connection-a',
      sessionId: 'chat-legacy',
      provider: 'custom',
      model: 'model-a',
    );

    final restored = store.read(
      connectionIdentity: 'connection-a',
      sessionId: 'chat-legacy',
    );

    expect(restored?.model, 'model-a');
    expect(restored?.reasoningEffort, isNull);
  });

  test('does not leak an override into another chat', () async {
    final store = await ChatModelOverrideStore.open();
    await store.save(
      connectionIdentity: 'connection-a',
      sessionId: 'chat-1',
      provider: 'custom',
      model: 'model-a',
    );

    expect(
      store.read(connectionIdentity: 'connection-a', sessionId: 'chat-2'),
      isNull,
    );
  });

  test('does not leak an override into another connection', () async {
    final store = await ChatModelOverrideStore.open();
    await store.save(
      connectionIdentity: 'connection-a',
      sessionId: 'shared-chat-id',
      provider: 'custom',
      model: 'model-a',
    );

    expect(
      store.read(
        connectionIdentity: 'connection-b',
        sessionId: 'shared-chat-id',
      ),
      isNull,
    );
  });
}
