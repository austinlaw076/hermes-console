import 'package:flutter/material.dart';

import '../../companion/render/companion_view.dart';
import '../../companion/state/companion_controller.dart';
import '../../widgets/hermes_spark_mascot.dart';

/// Playground del Companion (006 FASE 2): muestra la mascota **equipada a gran
/// tamaño** y permite disparar cada animación para lucirlas. Reutiliza
/// [CompanionView] (que mapea cada [HermesSparkMood] a su estado de animación),
/// así que funciona igual con el Spark procedural o con un spritesheet
/// importado. No toca voz, runtime ni red.
class CompanionPlaygroundScreen extends StatefulWidget {
  final CompanionController controller;
  const CompanionPlaygroundScreen({required this.controller, super.key});

  @override
  State<CompanionPlaygroundScreen> createState() =>
      _CompanionPlaygroundScreenState();
}

class _CompanionPlaygroundScreenState
    extends State<CompanionPlaygroundScreen> {
  // Animaciones mostrables (etiqueta visible → mood que las dispara).
  static const List<({String label, HermesSparkMood mood})> _moves = [
    (label: 'Reposo', mood: HermesSparkMood.idle),
    (label: 'Correr', mood: HermesSparkMood.thinking),
    (label: 'Esperar', mood: HermesSparkMood.waiting),
    (label: 'Saludar', mood: HermesSparkMood.success),
    (label: 'Saltar', mood: HermesSparkMood.jump),
    (label: 'Fallo', mood: HermesSparkMood.error),
  ];

  HermesSparkMood _mood = HermesSparkMood.idle;

  /// Cambia con cada pulsación para re-disparar animaciones one-shot
  /// (saludar/saltar/fallo) aunque se repita el mismo estado.
  int _replay = 0;

  void _play(HermesSparkMood mood) {
    setState(() {
      _mood = mood;
      _replay++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Animaciones')),
      body: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          return Column(
            children: [
              Expanded(
                child: Center(
                  child: CompanionView(
                    mood: _mood,
                    size: 200,
                    controller: widget.controller,
                    replayToken: _replay,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final m in _moves)
                      ChoiceChip(
                        label: Text(m.label),
                        selected: _mood == m.mood,
                        onSelected: (_) => _play(m.mood),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
