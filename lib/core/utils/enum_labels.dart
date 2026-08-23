/// Etiquetas localizadas para enums compartidos (modo de aprobación, riesgo).
///
/// Los enums conservan su `.label` en español como fallback y para no romper
/// nada; la UI usa estos helpers para respetar el idioma. Reutilizables en
/// permisos, chat (aprobaciones) y runs.
library;

import '../../l10n/app_localizations.dart';
import '../services/approval_policy.dart';
import '../services/command_risk.dart';

String approvalModeLabel(Strings s, ApprovalMode m) => switch (m) {
      ApprovalMode.globalDefault => s.modeGlobalDefault,
      ApprovalMode.yolo => s.modeYolo,
      ApprovalMode.interactive => s.modeInteractive,
      ApprovalMode.conservative => s.modeConservative,
      ApprovalMode.readOnly => s.modeReadOnly,
    };

String commandRiskLabel(Strings s, CommandRisk r) => switch (r) {
      CommandRisk.low => s.riskLow,
      CommandRisk.medium => s.riskMedium,
      CommandRisk.high => s.riskHigh,
    };
