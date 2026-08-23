import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'hermes_bot_face.dart';

/// Presentation states supported by the Android voice surface.
///
/// This is only a projection of the existing voice controller. It never owns
/// capture, playback, a transcript, or a second conversation state machine.
enum VoiceStageState {
  loading,
  listening,
  transcribing,
  thinking,
  toolCall,
  speaking,
  waiting,
  paused,
  error,
}

@immutable
class VoiceStageLabels {
  final String finishListening;
  final String pause;
  final String resume;
  final String stopAndTalk;
  final String cancel;
  final String retry;
  final String review;
  final String close;

  const VoiceStageLabels({
    required this.finishListening,
    required this.pause,
    required this.resume,
    required this.stopAndTalk,
    required this.cancel,
    required this.retry,
    required this.review,
    required this.close,
  });
}

/// Clean, full-screen voice projection centred on the active Blobatar.
///
/// Only one short causal line is painted: public assistant commentary or a
/// safe activity category selected by the caller. User transcript, final
/// answer, reasoning, technical tool data and logs remain outside this stage.
class VoiceStage extends StatelessWidget {
  final VoiceStageState state;
  final String statusLabel;
  final VoiceStageLabels labels;
  final HermesBlobatarFaceVisual faceVisual;
  final ValueListenable<double>? micLevel;
  final VoidCallback? onFinishListening;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onStopAndTalk;
  final VoidCallback? onCancel;
  final VoidCallback? onRetry;
  final VoidCallback? onReview;
  final VoidCallback? onClose;

  const VoiceStage({
    required this.state,
    required this.statusLabel,
    required this.labels,
    required this.faceVisual,
    this.micLevel,
    this.onFinishListening,
    this.onPause,
    this.onResume,
    this.onStopAndTalk,
    this.onCancel,
    this.onRetry,
    this.onReview,
    this.onClose,
    super.key,
  });

  bool get _isPausable => switch (state) {
    VoiceStageState.listening ||
    VoiceStageState.transcribing ||
    VoiceStageState.thinking ||
    VoiceStageState.toolCall ||
    VoiceStageState.speaking => true,
    _ => false,
  };

  bool get _canStopAndTalk => switch (state) {
    VoiceStageState.thinking ||
    VoiceStageState.toolCall ||
    VoiceStageState.speaking => true,
    _ => false,
  };

  bool get _canCancel => switch (state) {
    VoiceStageState.transcribing ||
    VoiceStageState.thinking ||
    VoiceStageState.toolCall ||
    VoiceStageState.speaking => true,
    _ => false,
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).hermes;
    final accent = resolveVoiceAccentColor(state, colors: colors);
    return Material(
      key: const ValueKey('voice-stage'),
      color: colors.background,
      elevation: 0,
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 520;
            final faceExtent = math.min(
              compact ? 150.0 : 190.0,
              math.max(126.0, constraints.maxWidth * 0.55),
            );
            return Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 20,
                vertical: compact ? 8 : 12,
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Align(
                    alignment: compact
                        ? const Alignment(0, -0.02)
                        : const Alignment(0, -0.1),
                    child: Semantics(
                      key: const ValueKey('voice-stage-signal'),
                      container: true,
                      label: statusLabel,
                      child: Column(
                        key: const ValueKey('voice-stage-core'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ExcludeSemantics(
                            child: _ReactiveVoiceFace(
                              key: const ValueKey('voice-stage-visual'),
                              visual: faceVisual,
                              state: state,
                              size: faceExtent,
                              micLevel: micLevel,
                            ),
                          ),
                          SizedBox(height: compact ? 12 : 18),
                          _VoiceActivityLabel(
                            status: statusLabel,
                            color: accent,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (onClose != null)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: _VoiceAction(
                        actionKey: 'voice-stage-close',
                        icon: Icons.call_end_rounded,
                        label: labels.close,
                        onPressed: onClose!,
                        tone: _VoiceActionTone.destructive,
                        accent: accent,
                      ),
                    ),
                  if (_hasInlineActions)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.surfaceVariant.withValues(
                              alpha: 0.72,
                            ),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(
                              color: colors.divider.withValues(alpha: 0.56),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(7),
                            child: Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 6,
                              runSpacing: 6,
                              children: _buildActions(accent),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  bool get _hasInlineActions =>
      (state == VoiceStageState.listening && onFinishListening != null) ||
      ((state == VoiceStageState.paused || state == VoiceStageState.waiting) &&
          onResume != null) ||
      (state == VoiceStageState.waiting && onReview != null) ||
      (state == VoiceStageState.error && onRetry != null) ||
      (_canStopAndTalk && onStopAndTalk != null) ||
      (_isPausable && onPause != null) ||
      (_canCancel && onCancel != null);

  List<Widget> _buildActions(Color accent) {
    final actions = <Widget>[];
    if (state == VoiceStageState.listening && onFinishListening != null) {
      actions.add(
        _VoiceAction(
          actionKey: 'voice-stage-finish-listening',
          icon: Icons.stop_rounded,
          label: labels.finishListening,
          onPressed: onFinishListening!,
          tone: _VoiceActionTone.primary,
          accent: accent,
        ),
      );
    }
    if (state == VoiceStageState.waiting && onReview != null) {
      actions.add(
        _VoiceAction(
          actionKey: 'voice-stage-review',
          icon: Icons.shield_outlined,
          label: labels.review,
          onPressed: onReview!,
          tone: _VoiceActionTone.primary,
          accent: accent,
        ),
      );
    }
    if ((state == VoiceStageState.paused || state == VoiceStageState.waiting) &&
        onResume != null) {
      actions.add(
        _VoiceAction(
          actionKey: 'voice-stage-resume',
          icon: Icons.play_arrow_rounded,
          label: labels.resume,
          onPressed: onResume!,
          tone: _VoiceActionTone.primary,
          accent: accent,
        ),
      );
    }
    if (state == VoiceStageState.error && onRetry != null) {
      actions.add(
        _VoiceAction(
          actionKey: 'voice-stage-retry',
          icon: Icons.refresh_rounded,
          label: labels.retry,
          onPressed: onRetry!,
          tone: _VoiceActionTone.primary,
          accent: accent,
        ),
      );
    }
    if (_canStopAndTalk && onStopAndTalk != null) {
      actions.add(
        _VoiceAction(
          actionKey: 'voice-stage-stop-and-talk',
          icon: Icons.mic_rounded,
          label: labels.stopAndTalk,
          onPressed: onStopAndTalk!,
          tone: _VoiceActionTone.primary,
          accent: accent,
        ),
      );
    }
    if (_isPausable && onPause != null) {
      actions.add(
        _VoiceAction(
          actionKey: 'voice-stage-pause',
          icon: Icons.pause_rounded,
          label: labels.pause,
          onPressed: onPause!,
          tone: _VoiceActionTone.secondary,
          accent: accent,
        ),
      );
    }
    if (_canCancel && onCancel != null) {
      actions.add(
        _VoiceAction(
          actionKey: 'voice-stage-cancel',
          icon: Icons.stop_circle_outlined,
          label: labels.cancel,
          onPressed: onCancel!,
          tone: _VoiceActionTone.destructive,
          accent: accent,
        ),
      );
    }
    return actions;
  }
}

class _ReactiveVoiceFace extends StatelessWidget {
  final HermesBlobatarFaceVisual visual;
  final VoiceStageState state;
  final double size;
  final ValueListenable<double>? micLevel;

  const _ReactiveVoiceFace({
    required this.visual,
    required this.state,
    required this.size,
    required this.micLevel,
    super.key,
  });

  HermesBotFaceMotionState get _motionState => switch (state) {
    VoiceStageState.listening => HermesBotFaceMotionState.listening,
    VoiceStageState.speaking => HermesBotFaceMotionState.speaking,
    VoiceStageState.loading ||
    VoiceStageState.transcribing ||
    VoiceStageState.thinking ||
    VoiceStageState.toolCall => HermesBotFaceMotionState.thinking,
    _ => HermesBotFaceMotionState.idle,
  };

  @override
  Widget build(BuildContext context) {
    Widget face(double scale) => Transform.scale(
      scale: scale,
      child: HermesBotFace(
        visual: visual,
        size: size,
        animate: true,
        motionState: _motionState,
      ),
    );
    final level = micLevel;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (state != VoiceStageState.listening || level == null || reduceMotion) {
      return face(1);
    }
    return ValueListenableBuilder<double>(
      valueListenable: level,
      builder: (context, value, _) => face(1 + value.clamp(0.0, 1.0) * 0.045),
    );
  }
}

class _VoiceActivityLabel extends StatelessWidget {
  final String status;
  final Color color;

  const _VoiceActivityLabel({required this.status, required this.color});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).hermes;
    return ExcludeSemantics(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 160),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.1),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: Row(
          key: ValueKey(status),
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              key: const ValueKey('voice-stage-accent-dot'),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.42),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 9),
            Flexible(
              child: Text(
                status,
                key: const ValueKey('voice-stage-status'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

@visibleForTesting
Color resolveVoiceAccentColor(
  VoiceStageState state, {
  required HermesThemeColors colors,
}) => switch (state) {
  VoiceStageState.error => colors.error,
  VoiceStageState.paused => colors.textDisabled,
  VoiceStageState.waiting => colors.warning,
  _ => colors.accent,
};

enum _VoiceActionTone { primary, secondary, destructive }

class _VoiceAction extends StatelessWidget {
  final String actionKey;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final _VoiceActionTone tone;
  final Color accent;

  const _VoiceAction({
    required this.actionKey,
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.tone,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).hermes;
    final (background, foreground) = switch (tone) {
      _VoiceActionTone.primary => (accent.withValues(alpha: 0.18), accent),
      _VoiceActionTone.secondary => (colors.surface, colors.textPrimary),
      _VoiceActionTone.destructive => (
        colors.error.withValues(alpha: 0.12),
        colors.error,
      ),
    };
    return Semantics(
      button: true,
      label: label,
      onTap: onPressed,
      excludeSemantics: true,
      child: IconButton(
        key: ValueKey(actionKey),
        tooltip: label,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          minimumSize: const Size.square(48),
          fixedSize: const Size.square(48),
          backgroundColor: background,
          foregroundColor: foreground,
          shape: const CircleBorder(),
        ),
        icon: Icon(icon, size: 22),
      ),
    );
  }
}
