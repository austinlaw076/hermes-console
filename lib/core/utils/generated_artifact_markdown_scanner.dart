import 'package:markdown/markdown.dart' as md;

import '../models/generated_artifact.dart';
import 'generated_artifact_detector.dart';

final class DetectedGeneratedArtifact {
  final GeneratedArtifactDetection detection;
  final String content;

  const DetectedGeneratedArtifact({
    required this.detection,
    required this.content,
  });
}

/// Extrae únicamente fences completos del Markdown terminal. Un fence abierto
/// durante streaming no se promociona y, por tanto, nunca crea versiones
/// intermedias por token.
abstract final class GeneratedArtifactMarkdownScanner {
  static List<DetectedGeneratedArtifact> scan(String markdown) {
    if (markdown.trim().isEmpty || !_allFencesClosed(markdown)) return const [];
    final document = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored);
    final nodes = document.parseLines(markdown.split('\n'));
    final artifacts = <DetectedGeneratedArtifact>[];

    void visit(md.Node node) {
      if (node is md.Element && node.tag == 'pre') {
        final content = node.textContent.trim();
        final language = _languageOf(node);
        final detection = GeneratedArtifactDetector.detect(language, content);
        if (detection != null) {
          artifacts.add(
            DetectedGeneratedArtifact(detection: detection, content: content),
          );
        }
        return;
      }
      if (node is md.Element) {
        for (final child in node.children ?? const <md.Node>[]) {
          visit(child);
        }
      }
    }

    for (final node in nodes) {
      visit(node);
    }
    return List<DetectedGeneratedArtifact>.unmodifiable(artifacts);
  }

  static bool _allFencesClosed(String markdown) {
    String? marker;
    var markerLength = 0;
    for (final line in markdown.split('\n')) {
      final trimmedLeft = line.replaceFirst(RegExp(r'^ {0,3}'), '');
      final match = RegExp(r'^(`{3,}|~{3,})').firstMatch(trimmedLeft);
      if (match == null) continue;
      final run = match.group(1)!;
      if (marker == null) {
        marker = run[0];
        markerLength = run.length;
      } else if (run[0] == marker && run.length >= markerLength) {
        marker = null;
        markerLength = 0;
      }
    }
    return marker == null;
  }

  static String? _languageOf(md.Element pre) {
    for (final child in pre.children ?? const <md.Node>[]) {
      if (child is! md.Element || child.tag != 'code') continue;
      final className = child.attributes['class'];
      if (className != null && className.startsWith('language-')) {
        return className.substring('language-'.length);
      }
    }
    return null;
  }
}
