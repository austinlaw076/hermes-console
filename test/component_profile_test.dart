import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/theme/app_theme.dart';
import 'package:hermes_android/core/theme/component_profile.dart';

void main() {
  group('ComponentProfiles v1 catalog', () {
    test('contains the four exact stable ids', () {
      expect(
        ComponentProfiles.values.map((profile) => profile.id),
        orderedEquals(['minimal', 'soft', 'terminal', 'glass-lite']),
      );
      expect(ComponentProfiles.ids, {
        'minimal',
        'soft',
        'terminal',
        'glass-lite',
      });
      expect(ComponentProfiles.byId('unknown'), ComponentProfiles.minimal);
    });

    test('minimal tokens preserve the calm baseline contract', () {
      final profile = ComponentProfiles.minimal;
      expect(
        [
          profile.shape.chipRadius,
          profile.shape.fieldRadius,
          profile.shape.cardRadius,
          profile.shape.groupRadius,
          profile.shape.buttonRadius,
        ],
        [9, 12, 14, 16, 12],
      );
      expect(profile.elevation.resting, 0);
      expect(profile.motion.pressDurationMs, 140);
      expect(profile.motion.stateDurationMs, 170);
      expect(profile.motion.curve, ComponentMotionCurve.easeOutCubic);
    });

    test(
      'soft, terminal and glass-lite keep their distinct bounded identities',
      () {
        expect(ComponentProfiles.soft.shape.buttonRadius, 16);
        expect(ComponentProfiles.soft.elevation.resting, 2);
        expect(ComponentProfiles.soft.motion.pressedTranslateY, 1);

        expect(ComponentProfiles.terminal.shape.buttonRadius, 6);
        expect(
          ComponentProfiles.terminal.density.kind,
          ComponentDensityKind.compact,
        );
        expect(
          ComponentProfiles.terminal.border.outlinesRestingControls,
          isFalse,
        );
        expect(
          ComponentProfiles.terminal.border.usesStaticHighlightEdge,
          isTrue,
        );
        expect(
          ComponentProfiles.terminal.motion.curve,
          ComponentMotionCurve.linear,
        );

        expect(ComponentProfiles.glassLite.shape.buttonRadius, 14);
        expect(
          ComponentProfiles.glassLite.border.usesStaticHighlightEdge,
          isTrue,
        );
        expect(ComponentProfiles.glassLite.effects.usesStaticShadow, isTrue);
        expect(ComponentProfiles.glassLite.effects.allowsOneShotGlow, isTrue);
      },
    );

    test(
      'all shipped profiles satisfy accessibility and performance invariants',
      () {
        for (final profile in ComponentProfiles.values) {
          expect(profile.invariantViolations, isEmpty, reason: profile.id);
          expect(profile.isValid, isTrue, reason: profile.id);
          expect(profile.motion.pressDurationMs, inInclusiveRange(120, 160));
          expect(profile.motion.stateDurationMs, inInclusiveRange(120, 220));
          expect(profile.effects.allowsContinuousGlow, isFalse);
          expect(profile.effects.allowsBackdropFilterInCollections, isFalse);
        }
      },
    );

    test('terminal cambia lenguaje visual sin encajonar cada botón', () {
      final theme = AppTheme.fromId(
        AppTheme.defaultThemeId,
        componentProfile: ComponentProfiles.terminal,
      );
      final states = <WidgetState>{};
      final iconSide = theme.iconButtonTheme.style?.side?.resolve(states);
      final textSide = theme.textButtonTheme.style?.side?.resolve(states);
      final labelStyle = theme.filledButtonTheme.style?.textStyle?.resolve(
        states,
      );

      expect(iconSide?.style, BorderStyle.none);
      expect(textSide?.style, BorderStyle.none);
      expect(labelStyle?.fontFamily, 'monospace');
      expect(
        theme.inputDecorationTheme.enabledBorder,
        isA<UnderlineInputBorder>(),
      );
    });
  });

  group('ComponentProfile interaction invariants', () {
    test(
      'compact visuals never reduce the semantic hit target below 48 dp',
      () {
        for (final profile in ComponentProfiles.values) {
          expect(profile.density.hitTargetFor(18), componentMinimumTapTarget);
          expect(profile.density.hitTargetFor(47.9), componentMinimumTapTarget);
          expect(profile.density.hitTargetFor(64), 64);
        }
      },
    );

    test(
      'reduced motion removes scale, translation, duration and decorative glow',
      () {
        for (final profile in ComponentProfiles.values) {
          final resolved = profile.motion.resolve(reducedMotion: true);
          expect(resolved.pressDurationMs, 0, reason: profile.id);
          expect(resolved.stateDurationMs, 0, reason: profile.id);
          expect(resolved.pressedScale, 1, reason: profile.id);
          expect(resolved.pressedTranslateY, 0, reason: profile.id);
          expect(resolved.decorativeGlow, isFalse, reason: profile.id);
        }
      },
    );

    test('normal motion resolves without changing declared tokens', () {
      final profile = ComponentProfiles.soft;
      final resolved = profile.motion.resolve(reducedMotion: false);
      expect(resolved.pressDurationMs, profile.motion.pressDurationMs);
      expect(resolved.stateDurationMs, profile.motion.stateDurationMs);
      expect(resolved.pressedScale, profile.motion.pressedScale);
      expect(resolved.pressedTranslateY, profile.motion.pressedTranslateY);
      expect(resolved.decorativeGlow, profile.motion.decorativeGlow);
    });

    test('invalid custom token sets report each dangerous invariant', () {
      const invalid = ComponentProfile(
        id: 'invalid',
        shape: ComponentShapeTokens(
          chipRadius: -1,
          fieldRadius: 100,
          cardRadius: 1,
          groupRadius: 1,
          buttonRadius: 1,
        ),
        border: ComponentBorderTokens(
          width: 4,
          emphasizedWidth: 1,
          outlinesRestingControls: false,
          usesStaticHighlightEdge: false,
        ),
        elevation: ComponentElevationTokens(resting: -1, pressed: 0, modal: 9),
        density: ComponentDensityTokens(
          kind: ComponentDensityKind.compact,
          visualPaddingScale: 0.2,
          gapScale: 2,
        ),
        motion: ComponentMotionTokens(
          pressDurationMs: 500,
          stateDurationMs: 500,
          curve: ComponentMotionCurve.linear,
          pressedScale: 0.5,
          pressedTranslateY: 4,
          decorativeGlow: true,
        ),
        effects: ComponentEffectTokens(
          staticTintOpacity: 1,
          usesStaticShadow: true,
          allowsOneShotGlow: true,
          allowsContinuousGlow: true,
          allowsBackdropFilterInCollections: true,
        ),
      );

      expect(invalid.isValid, isFalse);
      expect(
        invalid.invariantViolations,
        containsAll([
          'shape.radii',
          'border.width',
          'elevation',
          'density',
          'motion.pressDuration',
          'motion.stateDuration',
          'motion.pressedScale',
          'motion.pressedTranslateY',
          'effects.staticTintOpacity',
          'effects.continuousGlow',
          'effects.collectionBackdropFilter',
        ]),
      );
    });
  });
}
