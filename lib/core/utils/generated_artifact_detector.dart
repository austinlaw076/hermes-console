import '../models/generated_artifact.dart';

/// Port nativo de la detección de artifacts sustanciales de Hermes Desktop.
/// Solo clasifica bloques ya cerrados; no abre previews ni ejecuta contenido.
abstract final class GeneratedArtifactDetector {
  static const int htmlDocumentMinChars = 160;
  static const int htmlFragmentMinChars = 1200;
  static const int svgMinChars = 2000;
  static const int codeMinLines = 48;
  static const int codeMinChars = 3000;

  static final RegExp _htmlDocument = RegExp(
    r'<!doctype\s+html|<html[\s>]|<head[\s>]|<body[\s>]',
    caseSensitive: false,
  );
  static final RegExp _htmlTag = RegExp(
    r'<[a-z][a-z0-9-]*(\s[^>]*)?>',
    caseSensitive: false,
  );
  static final RegExp _validLanguage = RegExp(
    r'^[a-z0-9][a-z0-9+#-]*$',
    caseSensitive: false,
  );
  static final RegExp _codeDeclaration = RegExp(
    r'(?:^|\n)\s*(?:export\s+)?(?:default\s+)?(?:async\s+)?(?:function|class|struct|interface|enum|trait|impl|def|fn)\s+([A-Za-z_$][\w$]*)',
  );
  static final RegExp _filenameComment = RegExp(
    r'^\s*(?://|#|--|<!--|/\*)\s*([\w./-]+\.[a-z0-9]{1,8})\b',
    caseSensitive: false,
  );

  static const Set<String> _htmlLanguages = {'html', 'htm', 'xhtml'};
  static const Set<String> _nonArtifactLanguages = {
    '',
    'console',
    'diff',
    'log',
    'logs',
    'markdown',
    'md',
    'mermaid',
    'output',
    'patch',
    'plain',
    'plaintext',
    'shell-session',
    'stdout',
    'text',
    'txt',
  };
  static const Set<String> _commonCodeLanguages = {
    'bash',
    'c',
    'cpp',
    'css',
    'diff',
    'go',
    'html',
    'java',
    'javascript',
    'js',
    'json',
    'jsx',
    'markdown',
    'md',
    'php',
    'python',
    'py',
    'ruby',
    'rust',
    'rs',
    'sh',
    'sql',
    'swift',
    'tsx',
    'ts',
    'typescript',
    'xml',
    'yaml',
    'yml',
  };

  static const Map<String, String> _extensionByLanguage = {
    'bash': '.sh',
    'c': '.c',
    'cpp': '.cpp',
    'csharp': '.cs',
    'css': '.css',
    'dart': '.dart',
    'go': '.go',
    'htm': '.html',
    'html': '.html',
    'java': '.java',
    'javascript': '.js',
    'js': '.js',
    'json': '.json',
    'jsx': '.jsx',
    'kotlin': '.kt',
    'php': '.php',
    'py': '.py',
    'python': '.py',
    'rb': '.rb',
    'rs': '.rs',
    'ruby': '.rb',
    'rust': '.rs',
    'sh': '.sh',
    'sql': '.sql',
    'svg': '.svg',
    'swift': '.swift',
    'toml': '.toml',
    'ts': '.ts',
    'tsx': '.tsx',
    'typescript': '.ts',
    'xhtml': '.html',
    'xml': '.xml',
    'yaml': '.yaml',
    'yml': '.yaml',
  };

  static GeneratedArtifactDetection? detect(String? language, String? code) {
    final trimmed = code?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final clean = sanitizeLanguage(language ?? '');

    if (_htmlLanguages.contains(clean)) {
      final isDocument = _htmlDocument.hasMatch(trimmed);
      if ((isDocument && trimmed.length >= htmlDocumentMinChars) ||
          (!isDocument &&
              trimmed.length >= htmlFragmentMinChars &&
              _htmlTag.hasMatch(trimmed))) {
        return GeneratedArtifactDetection(
          kind: GeneratedArtifactKind.html,
          language: clean,
          title:
              _titleFromTag(trimmed, 'title') ??
              _titleFromTag(trimmed, 'h1') ??
              'HTML',
        );
      }
      return null;
    }

    if (clean == 'svg') {
      if (trimmed.length >= svgMinChars &&
          RegExp(r'<svg[\s>]', caseSensitive: false).hasMatch(trimmed)) {
        return GeneratedArtifactDetection(
          kind: GeneratedArtifactKind.svg,
          language: clean,
          title: _titleFromTag(trimmed, 'title') ?? 'SVG',
        );
      }
      return null;
    }

    if (_nonArtifactLanguages.contains(clean)) return null;
    if (trimmed.length < codeMinChars && _countLines(trimmed) < codeMinLines) {
      return null;
    }
    if (_isLikelyProse(clean, trimmed)) return null;

    return GeneratedArtifactDetection(
      kind: GeneratedArtifactKind.code,
      language: clean,
      title: _codeTitle(clean, trimmed),
    );
  }

  static String sanitizeLanguage(String value) {
    final trimmed = value.trim();
    final first = trimmed.split(RegExp(r'\s')).firstOrNull ?? '';
    return first.length <= 16 && _validLanguage.hasMatch(first)
        ? first.toLowerCase()
        : '';
  }

  static String slug(GeneratedArtifactDetection detection) {
    final title = detection.title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final compact = title.length > 48 ? title.substring(0, 48) : title;
    return '${detection.kind.name}:${detection.language}:'
        '${compact.isEmpty ? 'untitled' : compact}';
  }

  static String downloadName(GeneratedArtifactDetection detection) {
    var base = detection.title
        .replaceAll(RegExp(r'[^A-Za-z0-9._ -]+'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '-');
    if (base.length > 60) base = base.substring(0, 60);
    if (base.isEmpty) base = 'artifact';
    if (RegExp(r'\.[a-z0-9]{1,8}$', caseSensitive: false).hasMatch(base)) {
      return base;
    }
    final extension = switch (detection.kind) {
      GeneratedArtifactKind.html => '.html',
      GeneratedArtifactKind.svg => '.svg',
      GeneratedArtifactKind.code =>
        _extensionByLanguage[detection.language] ?? '.txt',
    };
    return '$base$extension';
  }

  static int _countLines(String value) => '\n'.allMatches(value).length + 1;

  static String? _titleFromTag(String content, String tag) {
    final match = RegExp(
      '<$tag[^>]*>([\\s\\S]*?)</$tag>',
      caseSensitive: false,
    ).firstMatch(content);
    if (match == null) return null;
    final title = (match.group(1) ?? '')
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (title.isEmpty) return null;
    return title.length > 80 ? title.substring(0, 80) : title;
  }

  static String _codeTitle(String language, String content) {
    final head = content.length > 2000 ? content.substring(0, 2000) : content;
    final filename = _filenameComment.firstMatch(head)?.group(1);
    if (filename != null && filename.isNotEmpty) return filename;
    final declaration = _codeDeclaration.firstMatch(head)?.group(1);
    if (declaration != null && declaration.isNotEmpty) return declaration;
    return language;
  }

  static bool _isLikelyProse(String language, String content) {
    final signals = _signals(content);
    if (signals.codeSignals >= 3) return false;
    if (signals.bulletLines >= 1 &&
        (signals.hasMarkdown || signals.proseLines >= 2)) {
      return true;
    }
    const nonCode = {'', 'text', 'plain', 'plaintext', 'md', 'markdown'};
    if (nonCode.contains(language)) {
      return signals.proseLines >= 3 && signals.codeSignals == 0;
    }
    return !_commonCodeLanguages.contains(language) &&
        signals.proseLines >= 2 &&
        signals.codeSignals <= 1;
  }

  static _CodeSignals _signals(String content) {
    var bulletLines = 0;
    var proseLines = 0;
    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (RegExp(r'^[-*]\s+\S+').hasMatch(trimmed)) bulletLines++;
      if (RegExp(r'''^[A-Za-z0-9"'`*-]''').hasMatch(trimmed)) proseLines++;
    }
    final codePatterns = <RegExp>[
      RegExp(
        r'(^|\s)(const|let|var|function|class|import|export|return|if|for|while|switch)\b',
        caseSensitive: false,
        multiLine: true,
      ),
      RegExp(r'=>|==|===|!=|!==|\{|\}|;|</?[a-z][^>]*>', caseSensitive: false),
      RegExp(
        r'^\s*(#include|SELECT|INSERT|UPDATE|DELETE|CREATE|DROP)\b',
        caseSensitive: false,
        multiLine: true,
      ),
    ];
    final codeSignals = codePatterns.fold<int>(
      0,
      (total, pattern) => total + pattern.allMatches(content).length,
    );
    final hasMarkdown =
        RegExp(r'\*\*[^*]+\*\*').hasMatch(content) ||
        RegExp(r'`[^`\n]+`').hasMatch(content);
    return _CodeSignals(
      bulletLines: bulletLines,
      proseLines: proseLines,
      codeSignals: codeSignals,
      hasMarkdown: hasMarkdown,
    );
  }
}

final class _CodeSignals {
  final int bulletLines;
  final int proseLines;
  final int codeSignals;
  final bool hasMarkdown;

  const _CodeSignals({
    required this.bulletLines,
    required this.proseLines,
    required this.codeSignals,
    required this.hasMarkdown,
  });
}
