import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';
import 'package:hermes_android/core/widgets/hermes_shell.dart';

Future<void> _pumpShell(
  WidgetTester tester, {
  HermesDestination initial = HermesDestination.home,
  ValueChanged<HermesDestination>? onDestinationChanged,
  Map<HermesDestination, int> badges = const {},
  Widget? floatingActionButton,
  Size size = const Size(360, 720),
  double textScale = 1.0,
  Brightness brightness = Brightness.dark,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: hermesTheme(brightness),
      home: Builder(
        builder: (context) => MediaQuery(
          // Keep the real view metrics; only override the text scale, so the
          // shell still sees the width the test configured.
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: HermesShell(
            initialDestination: initial,
            badges: badges,
            onDestinationChanged: onDestinationChanged,
            floatingActionButton: floatingActionButton,
            builder: (context, destination) =>
                Center(child: Text('pane:${destination.name}')),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('HermesDestination', () {
    test('declares the five validated top-level destinations in order', () {
      expect(HermesDestination.values, [
        HermesDestination.home,
        HermesDestination.chats,
        HermesDestination.projects,
        HermesDestination.activity,
        HermesDestination.more,
      ]);
    });

    test('each destination carries a label and distinct icons', () {
      final labels = <String>{};
      final icons = <IconData>{};
      for (final destination in HermesDestination.values) {
        expect(destination.label, isNotEmpty);
        labels.add(destination.label);
        icons.add(destination.icon);
        expect(destination.selectedIcon, isNotNull);
      }
      expect(labels, hasLength(HermesDestination.values.length));
      expect(icons, hasLength(HermesDestination.values.length));
    });
  });

  group('HermesShell', () {
    testWidgets('shows the initial destination pane', (tester) async {
      await _pumpShell(tester);

      expect(find.text('pane:home'), findsOneWidget);
      expect(find.text('pane:projects'), findsNothing);
    });

    testWidgets('builds destination panes lazily', (tester) async {
      final built = <HermesDestination>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: hermesTheme(Brightness.dark),
          home: HermesShell(
            builder: (context, destination) {
              built.add(destination);
              return Text('pane:${destination.name}');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(built.toSet(), {HermesDestination.home});

      await tester.tap(find.text(HermesDestination.chats.label));
      await tester.pumpAndSettle();

      expect(built.toSet(), {HermesDestination.home, HermesDestination.chats});
      expect(built, isNot(contains(HermesDestination.projects)));
    });

    testWidgets('opens on any requested destination', (tester) async {
      await _pumpShell(tester, initial: HermesDestination.activity);

      expect(find.text('pane:activity'), findsOneWidget);
    });

    testWidgets('switches panes when a destination is tapped', (tester) async {
      await _pumpShell(tester);

      await tester.tap(find.text('Projects'));
      await tester.pumpAndSettle();

      expect(find.text('pane:projects'), findsOneWidget);
      expect(find.text('pane:home'), findsNothing);
    });

    testWidgets('reports every destination change exactly once', (
      tester,
    ) async {
      final changes = <HermesDestination>[];
      await _pumpShell(tester, onDestinationChanged: changes.add);

      await tester.tap(find.text('Activity'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();

      expect(changes, [HermesDestination.activity, HermesDestination.more]);
    });

    testWidgets('re-tapping the current destination does not re-notify', (
      tester,
    ) async {
      final changes = <HermesDestination>[];
      await _pumpShell(tester, onDestinationChanged: changes.add);

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();

      expect(changes, isEmpty);
      expect(find.text('pane:home'), findsOneWidget);
    });

    testWidgets('shows an attention badge and hides zero counts', (
      tester,
    ) async {
      await _pumpShell(
        tester,
        badges: const {
          HermesDestination.activity: 3,
          HermesDestination.projects: 0,
        },
      );

      expect(find.text('3'), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('caps an oversized badge instead of breaking the layout', (
      tester,
    ) async {
      await _pumpShell(tester, badges: const {HermesDestination.activity: 250});

      expect(find.text('99+'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('every destination is reachable and renders its pane', (
      tester,
    ) async {
      await _pumpShell(tester);

      for (final destination in HermesDestination.values) {
        await tester.tap(find.text(destination.label));
        await tester.pumpAndSettle();
        expect(find.text('pane:${destination.name}'), findsOneWidget);
      }
    });

    testWidgets('uses a bottom bar on a phone width', (tester) async {
      await _pumpShell(tester, size: const Size(360, 720));

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('uses a side rail on a tablet width', (tester) async {
      await _pumpShell(tester, size: const Size(900, 700));

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('the rail keeps navigation working', (tester) async {
      await _pumpShell(tester, size: const Size(900, 700));

      await tester.tap(find.text('Activity'));
      await tester.pumpAndSettle();

      expect(find.text('pane:activity'), findsOneWidget);
    });

    testWidgets('survives a large text scale on a narrow phone', (
      tester,
    ) async {
      await _pumpShell(tester, size: const Size(320, 640), textScale: 1.8);

      expect(tester.takeException(), isNull);
      expect(find.text('pane:home'), findsOneWidget);
    });

    testWidgets('renders in the light theme', (tester) async {
      await _pumpShell(tester, brightness: Brightness.light);

      expect(tester.takeException(), isNull);
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('destination labels are exposed to screen readers', (
      tester,
    ) async {
      await _pumpShell(tester);

      for (final destination in HermesDestination.values) {
        expect(
          find.bySemanticsLabel(RegExp(destination.label)),
          findsWidgets,
          reason: '${destination.label} must be reachable by screen reader',
        );
      }
    });

    testWidgets('a floating action button never covers the navigation bar', (
      tester,
    ) async {
      // The shell owns the bottom bar, so it must own the FAB too: one placed
      // by an outer Scaffold sits over the last destination and swallows its
      // taps.
      await _pumpShell(
        tester,
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {},
          label: const Text('New'),
        ),
      );

      await tester.tap(find.text(HermesDestination.more.label));
      await tester.pumpAndSettle();

      expect(find.text('pane:more'), findsOneWidget);
    });

    testWidgets('a floating action button is drawn when supplied', (
      tester,
    ) async {
      await _pumpShell(
        tester,
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {},
          label: const Text('New'),
        ),
      );

      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('no floating action button is drawn by default', (
      tester,
    ) async {
      await _pumpShell(tester);

      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('the rail also accepts a floating action button', (
      tester,
    ) async {
      await _pumpShell(
        tester,
        size: const Size(900, 700),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {},
          label: const Text('New'),
        ),
      );

      expect(find.byType(FloatingActionButton), findsOneWidget);
      await tester.tap(find.text(HermesDestination.more.label));
      await tester.pumpAndSettle();
      expect(find.text('pane:more'), findsOneWidget);
    });
  });
}
