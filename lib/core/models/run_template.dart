// Plantillas de ejecución: esqueletos de instrucción reutilizables para lanzar
// runs del agente sin partir de un campo en blanco. Hay dos orígenes:
//   - Predefinidas (builtin): se construyen localizadas en la capa de UI
//     (`builtinRunTemplates` en run_template_composer.dart), no se persisten.
//   - Propias (custom): las crea el usuario y se persisten en SharedPreferences
//     vía RunTemplateStore.
//
// El modelo es puro (sin dependencia de l10n): los textos los provee quien lo
// construye. El parseo es tolerante a campos desconocidos entre versiones.

/// Una plantilla de ejecución. [prompt] es el texto que se vuelca en el campo
/// de instrucción (editable antes de lanzar) o se lanza directamente.
class RunTemplate {
  final String id;
  final String name;
  final String description;
  final String prompt;

  /// Clave de icono (mapeada a un IconData en la capa de UI, para no acoplar el
  /// modelo a Material). Ver `_templateIcon` en el composer.
  final String iconKey;

  /// true para las plantillas predefinidas (no editables ni borrables).
  final bool builtin;

  const RunTemplate({
    required this.id,
    required this.name,
    this.description = '',
    required this.prompt,
    this.iconKey = 'bolt',
    this.builtin = false,
  });

  /// Una plantilla "lanzable directa" no necesita que el usuario complete nada:
  /// su prompt ya está listo (no termina en separador a rellenar).
  bool get isReadyToLaunch =>
      prompt.trim().isNotEmpty && !prompt.trimRight().endsWith(':');

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'prompt': prompt,
        'icon': iconKey,
      };

  factory RunTemplate.fromJson(Map<String, dynamic> json) => RunTemplate(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        description: (json['description'] ?? '').toString(),
        prompt: (json['prompt'] ?? '').toString(),
        iconKey: (json['icon'] ?? 'bolt').toString(),
        builtin: false,
      );

  RunTemplate copyWith({
    String? name,
    String? description,
    String? prompt,
    String? iconKey,
  }) =>
      RunTemplate(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        prompt: prompt ?? this.prompt,
        iconKey: iconKey ?? this.iconKey,
        builtin: builtin,
      );
}
