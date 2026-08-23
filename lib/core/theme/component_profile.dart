import 'package:flutter/foundation.dart';

const double componentMinimumTapTarget = 48;

enum ComponentDensityKind { comfortable, compact }

enum ComponentMotionCurve { linear, easeOut, easeOutCubic }

@immutable
final class ComponentShapeTokens {
  final double chipRadius;
  final double fieldRadius;
  final double cardRadius;
  final double groupRadius;
  final double buttonRadius;

  const ComponentShapeTokens({
    required this.chipRadius,
    required this.fieldRadius,
    required this.cardRadius,
    required this.groupRadius,
    required this.buttonRadius,
  });
}

@immutable
final class ComponentBorderTokens {
  final double width;
  final double emphasizedWidth;
  final bool outlinesRestingControls;
  final bool usesStaticHighlightEdge;

  const ComponentBorderTokens({
    required this.width,
    required this.emphasizedWidth,
    required this.outlinesRestingControls,
    required this.usesStaticHighlightEdge,
  });
}

@immutable
final class ComponentElevationTokens {
  final double resting;
  final double pressed;
  final double modal;

  const ComponentElevationTokens({
    required this.resting,
    required this.pressed,
    required this.modal,
  });
}

@immutable
final class ComponentDensityTokens {
  /// Scales visual padding only. Hit targets remain fixed at 48 dp or larger.
  final ComponentDensityKind kind;
  final double visualPaddingScale;
  final double gapScale;

  const ComponentDensityTokens({
    required this.kind,
    required this.visualPaddingScale,
    required this.gapScale,
  });

  double hitTargetFor(double visualSize) =>
      visualSize < componentMinimumTapTarget
      ? componentMinimumTapTarget
      : visualSize;
}

@immutable
final class ComponentEffectTokens {
  final double staticTintOpacity;
  final bool usesStaticShadow;
  final bool allowsOneShotGlow;
  final bool allowsContinuousGlow;
  final bool allowsBackdropFilterInCollections;

  const ComponentEffectTokens({
    required this.staticTintOpacity,
    required this.usesStaticShadow,
    required this.allowsOneShotGlow,
    this.allowsContinuousGlow = false,
    this.allowsBackdropFilterInCollections = false,
  });
}

@immutable
final class ComponentMotionTokens {
  final int pressDurationMs;
  final int stateDurationMs;
  final ComponentMotionCurve curve;
  final double pressedScale;
  final double pressedTranslateY;
  final bool decorativeGlow;

  const ComponentMotionTokens({
    required this.pressDurationMs,
    required this.stateDurationMs,
    required this.curve,
    required this.pressedScale,
    required this.pressedTranslateY,
    required this.decorativeGlow,
  });

  ResolvedComponentMotion resolve({required bool reducedMotion}) =>
      reducedMotion
      ? const ResolvedComponentMotion(
          pressDurationMs: 0,
          stateDurationMs: 0,
          pressedScale: 1,
          pressedTranslateY: 0,
          decorativeGlow: false,
        )
      : ResolvedComponentMotion(
          pressDurationMs: pressDurationMs,
          stateDurationMs: stateDurationMs,
          pressedScale: pressedScale,
          pressedTranslateY: pressedTranslateY,
          decorativeGlow: decorativeGlow,
        );
}

@immutable
final class ResolvedComponentMotion {
  final int pressDurationMs;
  final int stateDurationMs;
  final double pressedScale;
  final double pressedTranslateY;
  final bool decorativeGlow;

  const ResolvedComponentMotion({
    required this.pressDurationMs,
    required this.stateDurationMs,
    required this.pressedScale,
    required this.pressedTranslateY,
    required this.decorativeGlow,
  });
}

@immutable
final class ComponentProfile {
  final String id;
  final ComponentShapeTokens shape;
  final ComponentBorderTokens border;
  final ComponentElevationTokens elevation;
  final ComponentDensityTokens density;
  final ComponentMotionTokens motion;
  final ComponentEffectTokens effects;

  const ComponentProfile({
    required this.id,
    required this.shape,
    required this.border,
    required this.elevation,
    required this.density,
    required this.motion,
    required this.effects,
  });

  List<String> get invariantViolations {
    final failures = <String>[];
    final radii = [
      shape.chipRadius,
      shape.fieldRadius,
      shape.cardRadius,
      shape.groupRadius,
      shape.buttonRadius,
    ];
    if (radii.any((value) => !value.isFinite || value < 0 || value > 32)) {
      failures.add('shape.radii');
    }
    if (!border.width.isFinite ||
        !border.emphasizedWidth.isFinite ||
        border.width < 0 ||
        border.width > 2 ||
        border.emphasizedWidth < border.width ||
        border.emphasizedWidth > 3) {
      failures.add('border.width');
    }
    if ([
      elevation.resting,
      elevation.pressed,
      elevation.modal,
    ].any((value) => !value.isFinite || value < 0 || value > 8)) {
      failures.add('elevation');
    }
    if (!density.visualPaddingScale.isFinite ||
        !density.gapScale.isFinite ||
        density.visualPaddingScale < 0.75 ||
        density.visualPaddingScale > 1.25 ||
        density.gapScale < 0.75 ||
        density.gapScale > 1.25) {
      failures.add('density');
    }
    if (motion.pressDurationMs < 120 || motion.pressDurationMs > 160) {
      failures.add('motion.pressDuration');
    }
    if (motion.stateDurationMs < 120 || motion.stateDurationMs > 220) {
      failures.add('motion.stateDuration');
    }
    if (!motion.pressedScale.isFinite ||
        motion.pressedScale < 0.97 ||
        motion.pressedScale > 1) {
      failures.add('motion.pressedScale');
    }
    if (!motion.pressedTranslateY.isFinite ||
        motion.pressedTranslateY < 0 ||
        motion.pressedTranslateY > 1) {
      failures.add('motion.pressedTranslateY');
    }
    if (!effects.staticTintOpacity.isFinite ||
        effects.staticTintOpacity < 0 ||
        effects.staticTintOpacity > 0.35) {
      failures.add('effects.staticTintOpacity');
    }
    if (effects.allowsContinuousGlow) {
      failures.add('effects.continuousGlow');
    }
    if (effects.allowsBackdropFilterInCollections) {
      failures.add('effects.collectionBackdropFilter');
    }
    return List.unmodifiable(failures);
  }

  bool get isValid => invariantViolations.isEmpty;
}

abstract final class ComponentProfiles {
  static const minimal = ComponentProfile(
    id: 'minimal',
    shape: ComponentShapeTokens(
      chipRadius: 9,
      fieldRadius: 12,
      cardRadius: 14,
      groupRadius: 16,
      buttonRadius: 12,
    ),
    border: ComponentBorderTokens(
      width: 0,
      emphasizedWidth: 1,
      outlinesRestingControls: false,
      usesStaticHighlightEdge: false,
    ),
    elevation: ComponentElevationTokens(resting: 0, pressed: 0, modal: 0),
    density: ComponentDensityTokens(
      kind: ComponentDensityKind.comfortable,
      visualPaddingScale: 1,
      gapScale: 1,
    ),
    motion: ComponentMotionTokens(
      pressDurationMs: 140,
      stateDurationMs: 170,
      curve: ComponentMotionCurve.easeOutCubic,
      pressedScale: 0.99,
      pressedTranslateY: 0,
      decorativeGlow: false,
    ),
    effects: ComponentEffectTokens(
      staticTintOpacity: 0.08,
      usesStaticShadow: false,
      allowsOneShotGlow: false,
    ),
  );

  static const soft = ComponentProfile(
    id: 'soft',
    shape: ComponentShapeTokens(
      chipRadius: 12,
      fieldRadius: 16,
      cardRadius: 18,
      groupRadius: 20,
      buttonRadius: 16,
    ),
    border: ComponentBorderTokens(
      width: 0.5,
      emphasizedWidth: 1,
      outlinesRestingControls: false,
      usesStaticHighlightEdge: true,
    ),
    elevation: ComponentElevationTokens(resting: 2, pressed: 1, modal: 3),
    density: ComponentDensityTokens(
      kind: ComponentDensityKind.comfortable,
      visualPaddingScale: 1.08,
      gapScale: 1.05,
    ),
    motion: ComponentMotionTokens(
      pressDurationMs: 150,
      stateDurationMs: 190,
      curve: ComponentMotionCurve.easeOut,
      pressedScale: 0.98,
      pressedTranslateY: 1,
      decorativeGlow: false,
    ),
    effects: ComponentEffectTokens(
      staticTintOpacity: 0.12,
      usesStaticShadow: true,
      allowsOneShotGlow: false,
    ),
  );

  static const terminal = ComponentProfile(
    id: 'terminal',
    shape: ComponentShapeTokens(
      chipRadius: 6,
      fieldRadius: 8,
      cardRadius: 10,
      groupRadius: 12,
      buttonRadius: 6,
    ),
    border: ComponentBorderTokens(
      width: 0.5,
      emphasizedWidth: 1,
      // Terminal se expresa con densidad, tipografía y líneas de acento. Un
      // marco completo alrededor de cada icono/control convertía la pantalla
      // en una cuadrícula pesada sin aportar jerarquía.
      outlinesRestingControls: false,
      usesStaticHighlightEdge: true,
    ),
    elevation: ComponentElevationTokens(resting: 0, pressed: 0, modal: 0),
    density: ComponentDensityTokens(
      kind: ComponentDensityKind.compact,
      visualPaddingScale: 0.88,
      gapScale: 0.9,
    ),
    motion: ComponentMotionTokens(
      pressDurationMs: 120,
      stateDurationMs: 140,
      curve: ComponentMotionCurve.linear,
      pressedScale: 1,
      pressedTranslateY: 0,
      decorativeGlow: false,
    ),
    effects: ComponentEffectTokens(
      staticTintOpacity: 0.06,
      usesStaticShadow: false,
      allowsOneShotGlow: false,
    ),
  );

  static const glassLite = ComponentProfile(
    id: 'glass-lite',
    shape: ComponentShapeTokens(
      chipRadius: 12,
      fieldRadius: 16,
      cardRadius: 18,
      groupRadius: 20,
      buttonRadius: 14,
    ),
    border: ComponentBorderTokens(
      width: 1,
      emphasizedWidth: 1.5,
      outlinesRestingControls: true,
      usesStaticHighlightEdge: true,
    ),
    elevation: ComponentElevationTokens(resting: 1, pressed: 0, modal: 2),
    density: ComponentDensityTokens(
      kind: ComponentDensityKind.comfortable,
      visualPaddingScale: 1,
      gapScale: 1,
    ),
    motion: ComponentMotionTokens(
      pressDurationMs: 155,
      stateDurationMs: 200,
      curve: ComponentMotionCurve.easeOutCubic,
      pressedScale: 0.99,
      pressedTranslateY: 0,
      decorativeGlow: false,
    ),
    effects: ComponentEffectTokens(
      staticTintOpacity: 0.16,
      usesStaticShadow: true,
      allowsOneShotGlow: true,
    ),
  );

  static const List<ComponentProfile> values = [
    minimal,
    soft,
    terminal,
    glassLite,
  ];

  static const Set<String> ids = {'minimal', 'soft', 'terminal', 'glass-lite'};

  static ComponentProfile byId(String? id) =>
      values.firstWhere((profile) => profile.id == id, orElse: () => minimal);
}
