import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../models/subagent_activity.dart';
import '../theme/app_theme.dart';
import '../utils/markdown_clipboard.dart';
import 'hermes_premium_ui.dart';

/// Compact projection of Hermes 0.19 delegated work.
///
/// This renders only the bounded reducer fields already delivered by Hermes;
/// it performs no transcript fetch, filesystem access, polling, or narration.
class SubagentActivityCard extends StatefulWidget {
  final List<SubagentActivity> activities;
  final bool Function(SubagentActivity activity)? canInterrupt;
  final bool Function(SubagentActivity activity)? isInterruptPending;
  final bool Function(SubagentActivity activity)? isOpenPending;
  final ValueChanged<SubagentActivity>? onOpenConversation;
  final ValueChanged<SubagentActivity>? onInterrupt;

  const SubagentActivityCard({
    required this.activities,
    this.canInterrupt,
    this.isInterruptPending,
    this.isOpenPending,
    this.onOpenConversation,
    this.onInterrupt,
    super.key,
  });

  @override
  State<SubagentActivityCard> createState() => _SubagentActivityCardState();
}

class _SubagentActivityCardState extends State<SubagentActivityCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).hermes;
    final strings = Strings.of(context);
    final activities = widget.activities;
    final active = activities.where((item) => !item.isTerminal).length;
    final completed = activities.length - active;
    // Scaffold removes the keyboard inset from the MediaQuery inherited by its
    // body. Read the view directly so the cap still reflects the real visible
    // height when expanded activity sits above the composer.
    final viewData = MediaQueryData.fromView(View.of(context));
    final availableHeight = viewData.size.height - viewData.viewInsets.bottom;
    final maxDetailHeight = (availableHeight * 0.32).clamp(88.0, 180.0);
    final rows = _activityRows(activities, colors);

    return HermesInlineActivity(
      title: strings.subagentActivityTitle,
      summary: strings.subagentActivitySummary(active, completed),
      leading: Icon(
        Icons.account_tree_outlined,
        size: 19,
        color: active > 0 ? colors.accent : colors.textSecondary,
      ),
      detail: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxDetailHeight),
        child: SingleChildScrollView(primary: false, child: rows),
      ),
      expanded: _expanded,
      onExpansionChanged: (expanded) => setState(() => _expanded = expanded),
      disclosureLabel: _expanded
          ? strings.chaErrHideDetails
          : strings.chaErrViewDetails,
      semanticLabel: strings.subagentActivityTitle,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
    );
  }

  Widget _activityRows(
    List<SubagentActivity> activities,
    HermesThemeColors colors,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < activities.length; index++) ...[
          if (index > 0)
            Divider(height: 15, color: colors.divider.withValues(alpha: 0.45)),
          _SubagentRow(
            key: ValueKey(activities[index].key),
            activity: activities[index],
            index: index + 1,
            canInterrupt: widget.canInterrupt?.call(activities[index]) ?? false,
            interruptPending:
                widget.isInterruptPending?.call(activities[index]) ?? false,
            openPending: widget.isOpenPending?.call(activities[index]) ?? false,
            onOpenConversation: widget.onOpenConversation,
            onInterrupt: widget.onInterrupt,
          ),
        ],
      ],
    );
  }
}

class _SubagentRow extends StatelessWidget {
  final SubagentActivity activity;
  final int index;
  final bool canInterrupt;
  final bool interruptPending;
  final bool openPending;
  final ValueChanged<SubagentActivity>? onOpenConversation;
  final ValueChanged<SubagentActivity>? onInterrupt;

  const _SubagentRow({
    required this.activity,
    required this.index,
    required this.canInterrupt,
    required this.interruptPending,
    required this.openPending,
    required this.onOpenConversation,
    required this.onInterrupt,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).hermes;
    final strings = Strings.of(context);
    final phase = activity.phase;
    final color = switch (phase) {
      SubagentActivityPhase.failed => colors.error,
      SubagentActivityPhase.requested ||
      SubagentActivityPhase.running ||
      SubagentActivityPhase.thinking ||
      SubagentActivityPhase.tool => colors.accent,
      SubagentActivityPhase.completed ||
      SubagentActivityPhase.cancelled ||
      SubagentActivityPhase.unknown => colors.textSecondary,
    };
    final label = switch (phase) {
      SubagentActivityPhase.requested => strings.subagentActivityRequested,
      SubagentActivityPhase.running => strings.subagentActivityRunning,
      SubagentActivityPhase.thinking => strings.subagentActivityThinking,
      SubagentActivityPhase.tool => strings.subagentActivityTool,
      SubagentActivityPhase.completed => strings.subagentActivityCompleted,
      SubagentActivityPhase.failed => strings.subagentActivityFailed,
      SubagentActivityPhase.cancelled => strings.subagentActivityCancelled,
      SubagentActivityPhase.unknown => strings.subagentActivityUnknown,
    };
    final rawTitle =
        activity.goalPreview ??
        activity.details.activeToolName ??
        strings.subagentActivityItem(index);
    final compactTitle = markdownToCompactText(rawTitle);
    final title = compactTitle.isEmpty
        ? strings.subagentActivityItem(index)
        : compactTitle;
    final rawDetail = activity.resultPreview ?? activity.details.detailPreview;
    final compactDetail = rawDetail == null
        ? ''
        : markdownToCompactText(rawDetail);
    final detail = compactDetail.isEmpty ? null : compactDetail;
    final progress = activity.progress;
    final canOpen =
        activity.canResumeChildTranscript && onOpenConversation != null;
    final showActions = canOpen || canInterrupt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: '$title, $label',
          excludeSemantics: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      style: TextStyle(color: color, fontSize: 12, height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (progress != null) ...[
          const SizedBox(height: 7),
          LinearProgressIndicator(
            value: progress.displayFraction,
            minHeight: 2,
            color: color,
            backgroundColor: colors.divider.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 4),
          Text(
            strings.subagentActivityProgress(
              progress.displayTaskIndex,
              progress.taskCount,
            ),
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
        ],
        if (detail != null) ...[
          const SizedBox(height: 6),
          Text(
            detail,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12,
              height: 1.3,
            ),
          ),
        ],
        if (showActions) ...[
          const SizedBox(height: 7),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Wrap(
              spacing: 4,
              runSpacing: 2,
              children: [
                if (canOpen)
                  TextButton.icon(
                    key: ValueKey('subagent-open-${activity.key.stableId}'),
                    onPressed: openPending
                        ? null
                        : () => onOpenConversation!(activity),
                    icon: openPending
                        ? _PendingActionIndicator(
                            label: strings.subagentActivityOpening,
                            color: colors.accent,
                          )
                        : const Icon(Icons.open_in_new_rounded, size: 15),
                    label: Text(
                      openPending
                          ? strings.subagentActivityOpening
                          : strings.subagentActivityOpenConversation,
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: colors.accent,
                      minimumSize: const Size(48, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                if (canInterrupt)
                  Semantics(
                    button: true,
                    enabled: !interruptPending,
                    label:
                        '${interruptPending ? strings.subagentActivityStopping : strings.subagentActivityStop}: $title',
                    onTap: interruptPending
                        ? null
                        : () => onInterrupt?.call(activity),
                    child: ExcludeSemantics(
                      child: TextButton.icon(
                        key: ValueKey('subagent-stop-${activity.key.stableId}'),
                        onPressed: interruptPending
                            ? null
                            : () => onInterrupt?.call(activity),
                        icon: interruptPending
                            ? _PendingActionIndicator(
                                label: strings.subagentActivityStopping,
                                color: colors.error,
                              )
                            : const Icon(Icons.stop_circle_outlined, size: 15),
                        label: Text(
                          interruptPending
                              ? strings.subagentActivityStopping
                              : strings.subagentActivityStop,
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: colors.error,
                          minimumSize: const Size(48, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 7),
                          textStyle: const TextStyle(fontSize: 12),
                          shape: const StadiumBorder(),
                          overlayColor: colors.error.withValues(alpha: 0.12),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _PendingActionIndicator extends StatelessWidget {
  final String label;
  final Color color;

  const _PendingActionIndicator({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: SizedBox.square(
      dimension: 13,
      child: CircularProgressIndicator(strokeWidth: 1.8, color: color),
    ),
  );
}
