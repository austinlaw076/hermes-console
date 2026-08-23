// Núcleo visual "reactor" del modo voz Jarvis: anillos concéntricos animados en
// torno a un NÚCLEO ESFÉRICO central (la "esfera Jarvis"), con
// color/velocidad/glow/pulso derivados de la fase (ver [JarvisStateStyle]).
// Flutter puro (CustomPaint), sin dependencias nuevas. El [child] es opcional:
// en el modo voz se deja vacío para mostrar solo la esfera (sin mascota dentro).
//
// Inspirado en el arc-reactor del HUD de Jarvis (eadmin2/jarvis_ai), pero
// reimplementado y atado a los tokens del tema de Hermes. Es presentación pura:
// recibe el estilo ya resuelto y el nivel de micro; no conoce el motor de voz.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'jarvis_state_style.dart';

class JarvisReactorCore extends StatefulWidget {
  /// Estilo visual de la fase actual (color, velocidad de giro, glow, pulso).
  final JarvisStateStyle style;

  /// Nivel de micrófono 0..1 (mueve el pulso cuando `style.reactsToMic`).
  final double micLevel;

  /// Diámetro total del reactor (anillos incluidos).
  final double size;

  /// Contenido central opcional. Si es null, se muestra solo la esfera Jarvis
  /// (el caso del modo voz, sin mascota dentro).
  final Widget? child;

  const JarvisReactorCore({
    super.key,
    required this.style,
    this.child,
    this.micLevel = 0,
    this.size = 220,
  });

  @override
  State<JarvisReactorCore> createState() => _JarvisReactorCoreState();
}

class _JarvisReactorCoreState extends State<JarvisReactorCore>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    // Un único ticker continuo (0..1, 6 s/vuelta); cada anillo escala su giro con
    // `ringSpeed`. Repintamos solo el CustomPaint (RepaintBoundary), no el árbol.
    _c = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Anillos + glow + núcleo esférico (la esfera Jarvis).
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) => CustomPaint(
                  painter: _ReactorPainter(
                    t: reduce ? 0 : _c.value,
                    style: widget.style,
                    micLevel: widget.micLevel.clamp(0.0, 1.0),
                    animate: !reduce,
                  ),
                ),
              ),
            ),
            if (widget.child != null) widget.child!,
          ],
        ),
      ),
    );
  }
}

class _ReactorPainter extends CustomPainter {
  final double t; // 0..1 continuo
  final JarvisStateStyle style;
  final double micLevel;
  final bool animate;

  _ReactorPainter({
    required this.t,
    required this.style,
    required this.micLevel,
    required this.animate,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = math.min(size.width, size.height) / 2;
    final color = style.color;
    final twoPi = 2 * math.pi;
    final baseAngle = t * twoPi;

    // Intensidad del pulso del núcleo: micro en escucha, onda autónoma al hablar,
    // y un latido suave en el resto (cuando la fase tiene pulso).
    final double intensity;
    if (style.reactsToMic) {
      intensity = micLevel;
    } else if (style.reactsToSpeech) {
      intensity = animate ? (0.5 + 0.5 * math.sin(baseAngle * 2)) : 0.5;
    } else {
      intensity = animate ? (0.5 + 0.5 * math.sin(baseAngle)) : 0.5;
    }

    // 1) Halo difuso de fondo.
    if (style.glow > 0) {
      final haloR = maxR * (0.66 + 0.06 * style.pulse * intensity);
      final halo = Paint()
        ..color = color.withValues(alpha: 0.10 + 0.22 * style.glow)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, maxR * 0.18);
      canvas.drawCircle(center, haloR, halo);
    }

    // 2) Anillo exterior con marcas (ticks) que gira a `ringSpeed`.
    final outerR = maxR * 0.94;
    _drawTickRing(
      canvas,
      center,
      outerR,
      ticks: 48,
      angle: baseAngle * style.ringSpeed,
      color: color.withValues(alpha: 0.35 + 0.25 * style.glow),
      tickLen: maxR * 0.05,
      strokeWidth: 1.6,
    );

    // 3) Anillo medio discontinuo girando en sentido contrario, algo más rápido.
    final midR = maxR * 0.80;
    _drawDashedRing(
      canvas,
      center,
      midR,
      dashes: 24,
      angle: -baseAngle * style.ringSpeed * 1.4,
      color: color.withValues(alpha: 0.45 + 0.20 * style.glow),
      strokeWidth: 2.2,
    );

    // 4) Aro del núcleo, que late con la intensidad (mic/habla/latido).
    final coreScale = 1.0 + 0.10 * style.pulse * intensity;
    final coreR = maxR * 0.62 * coreScale;

    // 4a) NÚCLEO ESFÉRICO (la "esfera Jarvis"): relleno con gradiente radial que
    //     late con la intensidad. Es el centro del reactor; sustituye a la antigua
    //     mascota. Brillo más vivo en el centro y desvanecido hacia el borde.
    final sphereR = maxR * 0.46 * coreScale;
    final sphereRect = Rect.fromCircle(center: center, radius: sphereR);
    final sphere = Paint()
      ..shader = RadialGradient(
        colors: [
          Color.lerp(color, Colors.white, 0.55)!
              .withValues(alpha: 0.92 * (0.7 + 0.3 * intensity)),
          color.withValues(alpha: 0.75),
          color.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(sphereRect);
    canvas.drawCircle(center, sphereR, sphere);
    // Pequeño brillo especular descentrado para dar sensación de esfera 3D.
    final highlight = Paint()
      ..color = Colors.white.withValues(alpha: 0.18 + 0.22 * intensity);
    canvas.drawCircle(
      center.translate(-sphereR * 0.28, -sphereR * 0.28),
      sphereR * 0.16,
      highlight,
    );

    final corePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..color = color.withValues(alpha: 0.55 + 0.35 * intensity);
    canvas.drawCircle(center, coreR, corePaint);
  }

  void _drawTickRing(
    Canvas canvas,
    Offset center,
    double radius, {
    required int ticks,
    required double angle,
    required Color color,
    required double tickLen,
    required double strokeWidth,
  }) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < ticks; i++) {
      final a = angle + (i / ticks) * 2 * math.pi;
      final dir = Offset(math.cos(a), math.sin(a));
      // Cada cuarta marca es más larga (lectura tipo dial).
      final len = i % 4 == 0 ? tickLen * 1.8 : tickLen;
      canvas.drawLine(
        center + dir * (radius - len),
        center + dir * radius,
        paint,
      );
    }
  }

  void _drawDashedRing(
    Canvas canvas,
    Offset center,
    double radius, {
    required int dashes,
    required double angle,
    required Color color,
    required double strokeWidth,
  }) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final span = (2 * math.pi / dashes) * 0.55; // arco pintado de cada segmento
    for (var i = 0; i < dashes; i++) {
      final start = angle + (i / dashes) * 2 * math.pi;
      canvas.drawArc(rect, start, span, false, paint);
    }
  }

  @override
  bool shouldRepaint(_ReactorPainter old) =>
      old.t != t ||
      old.micLevel != micLevel ||
      old.style != style ||
      old.animate != animate;
}
