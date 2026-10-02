import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/widgets/chat_context_header.dart';

Future<void> _pump(
  WidgetTester tester, {
  String? projectName,
  String model = 'gpt-5.6-sol',
  String reasoning = 'high',
  String connection = 'Miniserver',
  ChatConnectionStatus status = ChatConnectionStatus.connected,
  Size size = const Size(400, 800),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: hermesTheme(Brightness.dark),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Chat'),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: ChatContextHeader(
                projectName: projectName,
                model: model,
                reasoningEffort: reasoning,
                connectionLabel: connection,
                connectionStatus: status,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows project, model, reasoning and connection', (tester) async {
    await _pump(tester, projectName: 'Hermes Android');

    expect(find.text('Hermes Android'), findsOneWidget);
    expect(find.text('gpt-5.6-sol'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
    expect(find.text('Miniserver'), findsOneWidget);
    expect(find.bySemanticsLabel('Miniserver connected'), findsOneWidget);
  });

  testWidgets('labels a chat without a known project as Unassigned', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Unassigned'), findsOneWidget);
  });

  testWidgets('exposes offline state accessibly', (tester) async {
    await _pump(tester, status: ChatConnectionStatus.offline);

    expect(find.bySemanticsLabel('Miniserver offline'), findsOneWidget);
  });

  testWidgets('survives narrow width and large text', (tester) async {
    await _pump(
      tester,
      projectName: 'A very long Project name that must not overflow',
      model: 'a-very-long-provider/a-very-long-model-name',
      size: const Size(320, 640),
      textScale: 1.8,
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(ChatContextHeader), findsOneWidget);
  });
}
