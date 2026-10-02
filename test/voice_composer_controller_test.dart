import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/controllers/voice_composer_controller.dart';

import 'support/fake_voice_composer_adapter.dart';

void main() {
  testWidgets(
    'successive partials replace one selected range and final remains editable',
    (tester) async {
      final editor = TextEditingController.fromValue(
        const TextEditingValue(
          text: 'Alpha old omega',
          selection: TextSelection(baseOffset: 6, extentOffset: 9),
        ),
      );
      final adapter = FakeVoiceComposerAdapter();
      final controller = VoiceComposerController(
        textController: editor,
        adapter: adapter,
      );
      addTearDown(controller.dispose);
      addTearDown(editor.dispose);

      expect(await controller.start(), isTrue);
      adapter.emitPartial('new');
      expect(editor.text, 'Alpha new omega');
      adapter.emitPartial('new words');
      expect(editor.text, 'Alpha new words omega');
      adapter.emitFinal('new words final');
      await tester.pump();

      expect(editor.text, 'Alpha new words final omega');
      expect(editor.selection, const TextSelection.collapsed(offset: 21));
      expect(controller.listening, isFalse);
      expect(adapter.stopCount, 1);

      editor.text = '${editor.text}!';
      expect(editor.text, 'Alpha new words final omega!');
    },
  );

  testWidgets('uses a valid cursor and falls back to the end', (tester) async {
    final cursorEditor = TextEditingController.fromValue(
      const TextEditingValue(
        text: 'abcd',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    final cursorAdapter = FakeVoiceComposerAdapter();
    final cursorController = VoiceComposerController(
      textController: cursorEditor,
      adapter: cursorAdapter,
    );
    addTearDown(cursorController.dispose);
    addTearDown(cursorEditor.dispose);

    await cursorController.start();
    cursorAdapter.emitPartial('XX');
    expect(cursorEditor.text, 'ab XX cd');
    await cursorController.cancel();

    final fallbackEditor = TextEditingController.fromValue(
      const TextEditingValue(
        text: 'prefix',
        selection: TextSelection.collapsed(offset: -1),
      ),
    );
    final fallbackAdapter = FakeVoiceComposerAdapter();
    final fallbackController = VoiceComposerController(
      textController: fallbackEditor,
      adapter: fallbackAdapter,
    );
    addTearDown(fallbackController.dispose);
    addTearDown(fallbackEditor.dispose);

    await fallbackController.start();
    fallbackAdapter.emitPartial(' dictated');
    expect(fallbackEditor.text, 'prefix dictated');
    expect(fallbackEditor.selection, const TextSelection.collapsed(offset: 15));
    await fallbackController.cancel();
  });

  testWidgets('Stop accepts a final-only callback from adapter.stop', (
    tester,
  ) async {
    final editor = TextEditingController.fromValue(
      const TextEditingValue(
        text: 'Draft: ',
        selection: TextSelection.collapsed(offset: 7),
      ),
    );
    final adapter = FakeVoiceComposerAdapter(
      finalTranscriptOnStop: 'final from stop',
    );
    final controller = VoiceComposerController(
      textController: editor,
      adapter: adapter,
    );
    addTearDown(controller.dispose);
    addTearDown(editor.dispose);

    await controller.start();
    await tester.pump(const Duration(seconds: 2));
    expect(controller.elapsed, const Duration(seconds: 2));
    await controller.stop();

    expect(editor.text, 'Draft: final from stop');
    expect(adapter.stopCount, 1);
    expect(controller.listening, isFalse);
    expect(controller.elapsed, Duration.zero);
  });

  testWidgets('Cancel restores exact value and ignores every late callback', (
    tester,
  ) async {
    const snapshot = TextEditingValue(
      text: 'keep this text',
      selection: TextSelection(baseOffset: 5, extentOffset: 9),
      composing: TextRange(start: 0, end: 4),
    );
    final editor = TextEditingController.fromValue(snapshot);
    final adapter = FakeVoiceComposerAdapter();
    final controller = VoiceComposerController(
      textController: editor,
      adapter: adapter,
    );
    addTearDown(controller.dispose);
    addTearDown(editor.dispose);

    await controller.start();
    adapter.emitPartial('changed');
    expect(editor.value, isNot(snapshot));
    await controller.cancel();
    expect(editor.value, snapshot);
    expect(adapter.cancelCount, 1);
    expect(controller.elapsed, Duration.zero);

    adapter.emitPartial('late partial');
    adapter.emitFinal('late final');
    adapter.emitStatus('done');
    adapter.emitError('late error');
    await tester.pump();

    expect(editor.value, snapshot);
    expect(controller.listening, isFalse);
  });

  testWidgets('error and done reset elapsed and reject late results', (
    tester,
  ) async {
    final editor = TextEditingController(text: 'base');
    final adapter = FakeVoiceComposerAdapter();
    final controller = VoiceComposerController(
      textController: editor,
      adapter: adapter,
    );
    addTearDown(controller.dispose);
    addTearDown(editor.dispose);

    await controller.start();
    await tester.pump(const Duration(seconds: 2));
    adapter.emitError('recognizer failed');
    expect(controller.listening, isFalse);
    expect(controller.elapsed, Duration.zero);
    expect(controller.status, 'recognizer failed');
    adapter.emitFinal('must not appear');
    expect(editor.text, 'base');

    editor.selection = const TextSelection.collapsed(offset: 4);
    await controller.start();
    adapter.emitPartial(' kept');
    adapter.emitStatus('done');
    expect(controller.listening, isFalse);
    expect(controller.elapsed, Duration.zero);
    adapter.emitFinal('late replacement');
    expect(editor.text, 'base kept');
  });

  testWidgets('dispose cancels an active timer and platform adapter', (
    tester,
  ) async {
    final editor = TextEditingController(text: 'draft');
    final adapter = FakeVoiceComposerAdapter();
    final controller = VoiceComposerController(
      textController: editor,
      adapter: adapter,
    );
    addTearDown(editor.dispose);

    await controller.start();
    await tester.pump(const Duration(seconds: 1));
    expect(controller.elapsed, const Duration(seconds: 1));
    controller.dispose();

    expect(controller.elapsed, Duration.zero);
    expect(adapter.disposeCount, 1);
    await tester.pump(const Duration(seconds: 3));
  });
}
