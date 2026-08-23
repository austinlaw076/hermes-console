import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/widgets/hermes_bot_face.dart';

typedef _ReferenceCase = ({String seed, String? kind, String fixture});

// Generated with blobatar@2.0.0 under Node from `_layout`, plus the exact
// rendered core path from `blobatar()`. These are source fixtures, not values
// copied from the Dart port.
const _referenceCases = <_ReferenceCase>[
  (
    seed: 'manager',
    kind: null,
    fixture:
        '{"seed":"manager","pin":null,"shape":"boxy","palette":{"head":"#283a49","eye":"#eff6fd"},"body":{"cx":49.330254,"cy":49.781319,"rx":28.746309,"ry":29.259202,"n":3.888831,"rot":-18.021458,"radii":[0.987846,0.909151,0.967478,1.045237,1.030724,0.889101,0.898372],"sides":null,"round":null},"petals":[],"extra":[],"bodyPath":"M76.67 40.89C84.79 65.87 82.93 69.62 58.38 77.61C33.84 85.59 30.12 83.66 21.99 58.67C13.87 33.69 15.73 29.94 40.28 21.96C64.83 13.97 68.54 15.9 76.67 40.89Z","eyes":[{"cx":42.144931,"cy":48.935384,"rx":2.602798,"ry":5.533094,"n":4.40336,"rot":2.692147},{"cx":61.000436,"cy":49.900015,"rx":2.532569,"ry":5.909812,"n":4.40336,"rot":1.668541}]}',
  ),
  (
    seed: '  ÉLODIE 🤖  ',
    kind: null,
    fixture:
        '{"seed":"élodie 🤖","pin":null,"shape":"organic","palette":{"head":"#e483b8","eye":"#160c11"},"body":{"cx":51.034593,"cy":50.742345,"rx":30.878318,"ry":29.944657,"n":2.46126,"rot":0,"radii":[1.136387,1.040085,1.009469,0.84183,1.082144,1.102129,0.993176],"sides":null,"round":null},"petals":[],"extra":[],"bodyPath":"M86.12 50.74C86.27 58.68 78.06 70.18 71.06 75.09C64.05 80 51.34 82.45 44.1 80.21C36.86 77.98 31.48 68.93 27.61 61.68C23.75 54.42 18.29 43.87 20.93 36.68C23.57 29.5 35.26 20.1 43.46 18.57C51.67 17.03 63.05 22.13 70.16 27.49C77.27 32.85 85.97 42.81 86.12 50.74Z","eyes":[{"cx":44.99352,"cy":46.64757,"rx":2.478862,"ry":6.569184,"n":5.190522,"rot":-4.199169},{"cx":60.545413,"cy":45.906301,"rx":2.811688,"ry":7.695832,"n":5.190522,"rot":-4.097383}]}',
  ),
  (
    seed: 'manager',
    kind: 'round',
    fixture:
        '{"seed":"manager","pin":"round","shape":"round","palette":{"head":"#283a49","eye":"#eff6fd"},"body":{"cx":49.330254,"cy":49.781319,"rx":33.425941,"ry":34.022328,"n":2.012807,"rot":0,"radii":[0.987846,0.909151,0.967478,1.045237,1.030724,0.889101,0.898372],"sides":null,"round":null},"petals":[],"extra":[],"bodyPath":"M82.76 49.78C82.76 68.71 67.93 83.8 49.33 83.8C30.73 83.8 15.9 68.71 15.9 49.78C15.9 30.85 30.73 15.76 49.33 15.76C67.93 15.76 82.76 30.85 82.76 49.78Z","eyes":[{"cx":40.975227,"cy":48.797674,"rx":3.026509,"ry":6.43383,"n":4.40336,"rot":2.692147},{"cx":62.900233,"cy":49.919337,"rx":2.944847,"ry":6.871874,"n":4.40336,"rot":1.668541}]}',
  ),
  (
    seed: 'abc123',
    kind: 'organic',
    fixture:
        '{"seed":"abc123","pin":"organic","shape":"organic","palette":{"head":"#50c186","eye":"#08120c"},"body":{"cx":49.879138,"cy":49.735369,"rx":35.151483,"ry":34.844006,"n":1.970835,"rot":0,"radii":[1.099651,1.044946,0.846688,1.013193,1.029968,0.850273,1.031421,1.02801],"sides":null,"round":null},"petals":[],"extra":[],"bodyPath":"M88.53 49.74C88.6 58.25 82.29 70.56 75.85 75.48C69.41 80.4 58.41 79.37 49.88 79.24C41.35 79.11 30.73 79.62 24.7 74.7C18.66 69.78 13 57.39 13.67 49.74C14.35 42.08 22.71 34.78 28.74 28.79C34.78 22.8 42.1 14.53 49.88 13.8C57.66 13.07 68.99 18.42 75.43 24.41C81.87 30.4 88.46 41.22 88.53 49.74Z","eyes":[{"cx":37.562444,"cy":51.857112,"rx":3.309793,"ry":7.983825,"n":3.990749,"rot":-10.368947},{"cx":59.58566,"cy":51.690116,"rx":3.636502,"ry":7.660166,"n":3.990749,"rot":-11.818158}]}',
  ),
  (
    seed: 'manager',
    kind: 'capsule',
    fixture:
        '{"seed":"manager","pin":"capsule","shape":"capsule","palette":{"head":"#283a49","eye":"#eff6fd"},"body":{"cx":49.330254,"cy":49.781319,"rx":34.09446,"ry":23.506563,"n":2.012807,"rot":0,"radii":[0.987846,0.909151,0.967478,1.045237,1.030724,0.889101,0.898372],"sides":null,"round":null},"petals":[{"cx":38.742358,"cy":49.781319,"r":23.506563},{"cx":59.91815,"cy":49.781319,"r":23.506563}],"extra":[],"bodyPath":"M38.74 26.27H59.92V73.29H38.74Z","eyes":[{"cx":40.648549,"cy":49.14248,"rx":3.087039,"ry":6.562507,"n":4.40336,"rot":2.692147},{"cx":63.012055,"cy":49.870956,"rx":3.003744,"ry":7.009312,"n":4.40336,"rot":1.668541}]}',
  ),
  (
    seed: 'manager',
    kind: 'nub',
    fixture:
        '{"seed":"manager","pin":"nub","shape":"nub","palette":{"head":"#283a49","eye":"#eff6fd"},"body":{"cx":49.330254,"cy":49.781319,"rx":29.414828,"ry":29.939649,"n":2.012807,"rot":0,"radii":[0.987846,0.909151,0.967478,1.045237,1.030724,0.889101,0.898372],"sides":null,"round":null},"petals":[{"cx":34.466477,"cy":70.97339,"r":9.846364},{"cx":23.961191,"cy":54.923922,"r":8.463633}],"extra":[],"bodyPath":"M78.75 49.78C78.75 66.44 65.7 79.72 49.33 79.72C32.96 79.72 19.92 66.44 19.92 49.78C19.92 33.12 32.96 19.84 49.33 19.84C65.7 19.84 78.75 33.12 78.75 49.78Z","eyes":[{"cx":41.97783,"cy":48.915712,"rx":2.663328,"ry":5.66177,"n":4.40336,"rot":2.692147},{"cx":61.271836,"cy":49.902775,"rx":2.591466,"ry":6.047249,"n":4.40336,"rot":1.668541}]}',
  ),
  (
    seed: 'manager',
    kind: 'cloud',
    fixture:
        '{"seed":"manager","pin":"cloud","shape":"cloud","palette":{"head":"#283a49","eye":"#eff6fd"},"body":{"cx":49.330254,"cy":49.781319,"rx":26.072234,"ry":26.537416,"n":2.012807,"rot":0,"radii":[0.987846,0.909151,0.967478,1.045237,1.030724,0.889101,0.898372],"sides":null,"round":null},"petals":[{"cx":30.060171,"cy":44.792613,"r":13.229175},{"cx":41.348324,"cy":37.737517,"r":15.180865},{"cx":57.312183,"cy":37.737517,"r":12.196426},{"cx":68.600336,"cy":44.792613,"r":13.617582}],"extra":[],"bodyPath":"M75.09 49.78C75.11 56.03 69.34 64.47 64.11 68.64C58.88 72.82 50.27 75.95 43.72 74.81C37.16 73.67 27.88 67.97 24.78 61.82C21.68 55.67 21.89 43.75 25.12 37.91C28.35 32.07 37.7 27.91 44.17 26.78C50.64 25.65 58.78 27.31 63.93 31.14C69.09 34.98 75.06 43.53 75.09 49.78Z","eyes":[{"cx":42.49737,"cy":49.13327,"rx":2.360677,"ry":5.018387,"n":4.40336,"rot":2.692147},{"cx":59.598874,"cy":49.872249,"rx":2.296981,"ry":5.360062,"n":4.40336,"rot":1.668541}]}',
  ),
  (
    seed: 'manager',
    kind: 'droplet',
    fixture:
        '{"seed":"manager","pin":"droplet","shape":"droplet","palette":{"head":"#283a49","eye":"#eff6fd"},"body":{"cx":49.330254,"cy":55.619551,"rx":26.072234,"ry":26.537416,"n":2,"rot":0,"radii":[0.987846,0.909151,0.967478,1.045237,1.030724,0.889101,0.898372],"sides":null,"round":null},"petals":[],"extra":["M28.63 39.48L46.43 15.83Q49.33 11.98 52.23 15.83L70.03 39.48Z"],"bodyPath":"M75.4 55.62C75.4 70.28 63.73 82.16 49.33 82.16C34.93 82.16 23.26 70.28 23.26 55.62C23.26 40.96 34.93 29.08 49.33 29.08C63.73 29.08 75.4 40.96 75.4 55.62Z","eyes":[{"cx":42.569273,"cy":56.271247,"rx":2.360677,"ry":5.018387,"n":4.40336,"rot":2.692147},{"cx":59.670778,"cy":57.041157,"rx":2.296981,"ry":5.360062,"n":4.40336,"rot":1.668541}]}',
  ),
  (
    seed: 'manager',
    kind: 'hexagon',
    fixture:
        '{"seed":"manager","pin":"hexagon","shape":"hexagon","palette":{"head":"#283a49","eye":"#eff6fd"},"body":{"cx":49.330254,"cy":49.781319,"rx":35.097238,"ry":35.723444,"n":2.012807,"rot":-10.812875,"radii":[0.987846,0.909151,0.967478,1.045237,1.030724,0.889101,0.898372],"sides":6,"round":0.242509},"petals":[],"extra":[],"bodyPath":"M39.53 17.52Q42.75 14.69 46.77 16.12L71.87 25.01Q75.89 26.43 76.69 30.69L81.68 57.27Q82.48 61.52 79.26 64.35L59.14 82.04Q55.91 84.87 51.9 83.45L26.79 74.55Q22.77 73.13 21.97 68.88L16.98 42.3Q16.18 38.04 19.4 35.21L39.53 17.52Z","eyes":[{"cx":40.11942,"cy":48.913744,"rx":3.177835,"ry":6.755522,"n":4.40336,"rot":2.692147},{"cx":63.140676,"cy":49.903051,"rx":3.09209,"ry":7.215468,"n":4.40336,"rot":1.668541}]}',
  ),
  (
    seed: 'manager',
    kind: 'sun',
    fixture:
        '{"seed":"manager","pin":"sun","shape":"sun","palette":{"head":"#283a49","eye":"#eff6fd"},"body":{"cx":49.330254,"cy":49.781319,"rx":23.398159,"ry":23.81563,"n":2.012807,"rot":0,"radii":[0.987846,0.909151,0.967478,1.045237,1.030724,0.889101,0.898372],"sides":null,"round":null},"petals":[{"cx":71.237992,"cy":40.211529,"r":5.784788},{"cx":68.571804,"cy":63.969082,"r":5.784788},{"cx":46.664066,"cy":73.538871,"r":5.784788},{"cx":27.422516,"cy":59.351109,"r":5.784788},{"cx":30.088704,"cy":35.593556,"r":5.784788},{"cx":51.996442,"cy":26.023767,"r":5.784788}],"extra":[],"bodyPath":"M72.73 49.78C72.73 63.03 62.35 73.6 49.33 73.6C36.31 73.6 25.93 63.03 25.93 49.78C25.93 36.53 36.31 25.97 49.33 25.97C62.35 25.97 72.73 36.53 72.73 49.78Z","eyes":[{"cx":43.481735,"cy":49.092768,"rx":2.118557,"ry":4.503681,"n":4.40336,"rot":2.692147},{"cx":58.829239,"cy":49.877932,"rx":2.061393,"ry":4.810312,"n":4.40336,"rot":1.668541}]}',
  ),
  (
    seed: 'manager',
    kind: 'triangle',
    fixture:
        '{"seed":"manager","pin":"triangle","shape":"triangle","palette":{"head":"#283a49","eye":"#eff6fd"},"body":{"cx":49.330254,"cy":49.781319,"rx":38.439832,"ry":39.125677,"n":2.012807,"rot":-4.505365,"radii":[0.987846,0.909151,0.967478,1.045237,1.030724,0.889101,0.898372],"sides":3,"round":0.242509},"petals":[],"extra":[],"bodyPath":"M42.84 18.19Q46.31 10.78 50.88 17.55L79.45 59.85Q84.03 66.62 75.98 67.27L25.7 71.3Q17.65 71.95 21.13 64.53L42.84 18.19Z","eyes":[{"cx":41.674619,"cy":53.41015,"rx":2.425028,"ry":5.155187,"n":4.40336,"rot":2.692147},{"cx":59.242303,"cy":53.733699,"rx":2.359596,"ry":5.506175,"n":4.40336,"rot":1.668541}]}',
  ),
];

void main() {
  group('HermesBlobatarFaceVisual', () {
    test('accepts and round-trips the four official wire forms', () {
      final cases = <String, (String, String?)>{
        'blobatar': ('manager', null),
        'blobatar:locked_seed': ('locked_seed', null),
        'blobatar:abc123:sun': ('abc123', 'sun'),
        'blobatar::cloud': ('manager', 'cloud'),
      };

      for (final entry in cases.entries) {
        final face = HermesBlobatarFaceVisual.tryParse(
          shapeWire: entry.key,
          profileName: 'manager',
        );
        expect(face, isNotNull, reason: entry.key);
        expect(face!.shapeWire, entry.key);
        expect(face.seed, entry.value.$1);
        expect(face.pinnedKind, entry.value.$2);
      }

      expect(
        HermesBlobatarFaceVisual.buildWire(seedPart: 'abc', kind: 'sun'),
        'blobatar:abc:sun',
      );
      expect(HermesBlobatarFaceVisual.buildWire(kind: 'sun'), 'blobatar::sun');
    });

    test('rejects markup, unknown kinds, invalid seeds and extra segments', () {
      for (final wire in <String>[
        '<svg onload=alert(1)>',
        'blobatar:<svg>',
        'blobatar:',
        'blobatar:abc:',
        'blobatar:abc:mystery',
        'blobatar:abc:sun:extra',
        'Blobatar:abc',
        'blobatar:${'a' * 65}',
      ]) {
        expect(
          HermesBlobatarFaceVisual.tryParse(
            shapeWire: wire,
            profileName: 'manager',
          ),
          isNull,
          reason: wire,
        );
      }
    });

    test(
      'is deterministic and falls back safely for an invalid profile name',
      () {
        final first = HermesBlobatarFaceVisual.tryParse(
          shapeWire: 'blobatar',
          profileName: 'inbox-triage',
        )!;
        final again = HermesBlobatarFaceVisual.tryParse(
          shapeWire: 'blobatar',
          profileName: 'inbox-triage',
        )!;
        final fallback = HermesBlobatarFaceVisual.tryParse(
          shapeWire: 'blobatar',
          profileName: '<script>',
        )!;

        expect(first.seed, again.seed);
        expect(first.resolvedKind, again.resolvedKind);
        expect(fallback.seed, 'agent');
        expect(hermesBlobatarKinds, contains(first.resolvedKind));
      },
    );

    test('matches blobatar npm 2.0.0 reference fixtures', () {
      for (final reference in _referenceCases) {
        expect(
          hermesBlobatarV2ReferenceFixture(
            reference.seed,
            pinnedKind: reference.kind,
          ),
          reference.fixture,
          reason: '${reference.seed} / ${reference.kind ?? 'auto'}',
        );
      }
    });

    test('applies NFC before UTF8 Murmur streaming', () {
      expect(
        hermesBlobatarV2ReferenceFixture('  E\u0301LODIE 🤖  '),
        hermesBlobatarV2ReferenceFixture('élodie 🤖'),
      );
    });
  });

  group('HermesClassicFaceVisual', () {
    test('accepts only official shape and color pairs', () {
      for (final shape in hermesClassicFaceShapes) {
        expect(
          HermesClassicFaceVisual.tryParse(shape: shape, colorHex: '#38BDF8'),
          isNotNull,
          reason: shape,
        );
      }
      expect(
        HermesClassicFaceVisual.tryParse(shape: 'cube', colorHex: '#38bdf8'),
        isNull,
      );
      expect(
        HermesClassicFaceVisual.tryParse(shape: 'circle', colorHex: '#123456'),
        isNull,
      );
    });
  });

  testWidgets('renders every controlled face without interpreting SVG', (
    tester,
  ) async {
    final visuals = <HermesBotFaceVisual>[
      for (final kind in hermesBlobatarKinds)
        HermesBlobatarFaceVisual.tryParse(
          shapeWire: 'blobatar::$kind',
          profileName: 'manager',
        )!,
      for (final shape in hermesClassicFaceShapes)
        HermesClassicFaceVisual.tryParse(shape: shape, colorHex: '#38bdf8')!,
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Wrap(
            children: [
              for (final visual in visuals)
                HermesBotFace(
                  visual: visual,
                  size: 56,
                  semanticLabel: 'Identidad visual del bot',
                ),
            ],
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('hermes-controlled-bot-face')),
      findsNWidgets(visuals.length),
    );
    expect(
      find.bySemanticsLabel('Identidad visual del bot'),
      findsNWidgets(visuals.length),
    );
    expect(find.byType(HtmlElementView), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
