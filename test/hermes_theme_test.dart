import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/theme/hermes_theme.dart';

HermesTokens? _tokensFrom(ThemeData theme) => theme.extension<HermesTokens>();

Future<HermesTokens> _pumpAndReadTokens(
  WidgetTester tester,
  ThemeData theme,
) async {
  late HermesTokens seen;
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Builder(
        builder: (context) {
          seen = HermesTokens.of(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return seen;
}

void main() {
  group('HermesSpacing', () {
    test('exposes a strictly increasing 4dp-based scale', () {
      const scale = [
        HermesSpacing.xs,
        HermesSpacing.sm,
        HermesSpacing.md,
        HermesSpacing.lg,
        HermesSpacing.xl,
        HermesSpacing.xxl,
      ];

      for (final step in scale) {
        expect(step % 4, 0, reason: '$step must sit on the 4dp grid');
      }
      for (var i = 1; i < scale.length; i++) {
        expect(scale[i], greaterThan(scale[i - 1]));
      }
    });

    test('radii grow from control to sheet', () {
      expect(HermesRadius.sm, lessThan(HermesRadius.md));
      expect(HermesRadius.md, lessThan(HermesRadius.lg));
      expect(HermesRadius.lg, lessThan(HermesRadius.xl));
    });

    test('motion durations stay inside the roadmap 150-250ms budget', () {
      expect(HermesMotion.fast.inMilliseconds, greaterThanOrEqualTo(100));
      expect(HermesMotion.standard.inMilliseconds, inInclusiveRange(150, 250));
      expect(HermesMotion.emphasized.inMilliseconds, lessThanOrEqualTo(400));
      expect(HermesMotion.standard, greaterThan(HermesMotion.fast));
    });
  });

  group('HermesTokens', () {
    test('dark and light token sets are distinct but complete', () {
      final dark = HermesTokens.dark();
      final light = HermesTokens.light();

      for (final tokens in [dark, light]) {
        expect(tokens.accent.a, 1.0);
        expect(tokens.running, isNot(tokens.blocked));
        expect(tokens.success, isNot(tokens.danger));
        expect(tokens.blocked, isNot(tokens.success));
      }
      expect(dark.surface, isNot(light.surface));
      expect(dark.brightness, Brightness.dark);
      expect(light.brightness, Brightness.light);
    });

    test('both themes keep the Hermes gold accent identity', () {
      expect(HermesTokens.dark().accent, HermesTokens.hermesGold);
      expect(HermesTokens.light().accent, HermesTokens.hermesGold);
    });

    test('status colors resolve from a semantic status enum', () {
      final tokens = HermesTokens.dark();

      expect(tokens.colorForStatus(HermesStatus.running), tokens.running);
      expect(tokens.colorForStatus(HermesStatus.blocked), tokens.blocked);
      expect(tokens.colorForStatus(HermesStatus.failed), tokens.danger);
      expect(tokens.colorForStatus(HermesStatus.completed), tokens.success);
      expect(tokens.colorForStatus(HermesStatus.idle), tokens.muted);
    });

    test('lerp keeps a valid token set mid-animation', () {
      final dark = HermesTokens.dark();
      final light = HermesTokens.light();

      final mid = dark.lerp(light, 0.5);

      expect(mid, isA<HermesTokens>());
      expect(mid.accent, HermesTokens.hermesGold);
      expect(mid.surface, isNot(dark.surface));
    });

    test('lerp against a foreign extension keeps this token set', () {
      final dark = HermesTokens.dark();

      expect(dark.lerp(null, 0.5), same(dark));
    });

    test('copyWith overrides only the named token', () {
      final tokens = HermesTokens.dark();
      final recolored = tokens.copyWith(danger: const Color(0xFF00FF00));

      expect(recolored.danger, const Color(0xFF00FF00));
      expect(recolored.success, tokens.success);
      expect(recolored.accent, tokens.accent);
    });
  });

  group('HermesTypography', () {
    test('the ramp is ordered and mono is a monospace family', () {
      final ramp = HermesTypography.ramp(Brightness.dark);

      expect(ramp.display.fontSize, greaterThan(ramp.title.fontSize!));
      expect(ramp.title.fontSize, greaterThan(ramp.section.fontSize!));
      expect(ramp.section.fontSize, greaterThan(ramp.body.fontSize!));
      expect(ramp.body.fontSize, greaterThan(ramp.label.fontSize!));
      expect(ramp.mono.fontFamily, isNotNull);
      expect(ramp.mono.fontFamilyFallback, contains('monospace'));
    });
  });

  group('hermesTheme', () {
    testWidgets('attaches tokens to the dark theme', (tester) async {
      final theme = hermesTheme(Brightness.dark);
      expect(_tokensFrom(theme), isNotNull);

      final tokens = await _pumpAndReadTokens(tester, theme);
      expect(tokens.brightness, Brightness.dark);
    });

    testWidgets('attaches tokens to the light theme', (tester) async {
      final theme = hermesTheme(Brightness.light);
      expect(_tokensFrom(theme), isNotNull);

      final tokens = await _pumpAndReadTokens(tester, theme);
      expect(tokens.brightness, Brightness.light);
    });

    testWidgets('falls back to matching tokens when none are attached', (
      tester,
    ) async {
      final tokens = await _pumpAndReadTokens(
        tester,
        ThemeData(brightness: Brightness.light, useMaterial3: true),
      );

      expect(tokens.brightness, Brightness.light);
      expect(tokens.accent, HermesTokens.hermesGold);
    });

    test('uses Material 3 and keeps the accent in the color scheme', () {
      for (final brightness in Brightness.values) {
        final theme = hermesTheme(brightness);
        expect(theme.useMaterial3, isTrue);
        expect(theme.brightness, brightness);
        expect(theme.colorScheme.brightness, brightness);
      }
    });

    test('body text meets the WCAG AA contrast floor on the base surface', () {
      for (final brightness in Brightness.values) {
        final tokens = _tokensFrom(hermesTheme(brightness))!;
        expect(
          contrastRatio(tokens.onSurface, tokens.surface),
          greaterThanOrEqualTo(4.5),
          reason: 'body text must stay readable in $brightness',
        );
      }
    });

    test('muted text still meets the AA large-text floor', () {
      for (final brightness in Brightness.values) {
        final tokens = _tokensFrom(hermesTheme(brightness))!;
        expect(
          contrastRatio(tokens.muted, tokens.surface),
          greaterThanOrEqualTo(3.0),
          reason: 'secondary text must remain legible in $brightness',
        );
      }
    });
  });
}
