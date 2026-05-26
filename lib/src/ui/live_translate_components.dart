import 'package:flutter/material.dart';

import '../theme/live_translate_theme.dart';
import 'live_translate_models.dart';

class LiveTranslateShell extends StatelessWidget {
  const LiveTranslateShell({
    super.key,
    required this.child,
    this.fixedBottomControls,
    this.screenPadding = const EdgeInsets.fromLTRB(
      AppSpacing.screen,
      AppSpacing.xxl,
      AppSpacing.screen,
      AppSpacing.lg,
    ),
  });

  final Widget child;
  final Widget? fixedBottomControls;
  final EdgeInsets screenPadding;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(padding: screenPadding, child: child),
            ),
            if (fixedBottomControls != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: fixedBottomControls!,
              ),
          ],
        ),
      ),
    );
  }
}

class LiveTranslateHeader extends StatelessWidget {
  const LiveTranslateHeader({
    super.key,
    required this.onOpenMenu,
    required this.onOpenAssistant,
  });

  final VoidCallback onOpenMenu;
  final VoidCallback onOpenAssistant;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Open menu',
          onPressed: onOpenMenu,
          icon: const Icon(Icons.menu_rounded),
        ),
        Expanded(
          child: Text(
            'Live Translate',
            textAlign: TextAlign.center,
            style: AppTextStyles.title(Theme.of(context).textTheme),
          ),
        ),
        IconButton(
          tooltip: 'Open AI chat',
          onPressed: onOpenAssistant,
          icon: const Icon(Icons.chat_bubble_outline_rounded),
        ),
      ],
    );
  }
}

class WaveLogo extends StatelessWidget {
  const WaveLogo({super.key, this.size = 72, this.accent = LiveAccent.teal});

  final double size;
  final LiveAccent accent;

  @override
  Widget build(BuildContext context) {
    final accentColor = AppColors.forAccent(accent);

    return Semantics(
      label: 'Live Translate audio wave logo',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: accentColor.withValues(alpha: 0.14),
          border: Border.all(color: accentColor.withValues(alpha: 0.55)),
        ),
        child: Icon(
          Icons.graphic_eq_rounded,
          color: accentColor,
          size: size * 0.58,
        ),
      ),
    );
  }
}

class XenovisLogo extends StatelessWidget {
  const XenovisLogo({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      label: 'Xenovis logo',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.teal, AppColors.blue],
              ),
              boxShadow: AppElevation.raised(AppColors.background),
            ),
            child: const Center(
              child: Text(
                'X',
                style: TextStyle(
                  color: AppColors.background,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'XENOVIS',
            style: AppTextStyles.title(
              textTheme,
            ).copyWith(letterSpacing: 0, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class AudioWavePanel extends StatelessWidget {
  const AudioWavePanel({super.key, this.accent = LiveAccent.teal});

  final LiveAccent accent;

  @override
  Widget build(BuildContext context) {
    final accentColor = AppColors.forAccent(accent);

    return Semantics(
      label: 'Teal audio wave illustration',
      child: Container(
        height: 96,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.card),
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              accentColor.withValues(alpha: 0.04),
              accentColor.withValues(alpha: 0.22),
              AppColors.blue.withValues(alpha: 0.08),
            ],
          ),
          border: Border.all(color: AppColors.border),
        ),
        child: Center(
          child: Icon(
            Icons.multitrack_audio_rounded,
            color: accentColor,
            size: 64,
          ),
        ),
      ),
    );
  }
}

class LocalSetupActionButton extends StatelessWidget {
  const LocalSetupActionButton({
    super.key,
    required this.action,
    required this.onPressed,
  });

  final LocalSetupActionData action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = action.isPrimary
        ? AppColors.teal
        : AppColors.surface;
    final foregroundColor = action.isPrimary
        ? AppColors.background
        : AppColors.textPrimary;

    return Semantics(
      button: true,
      container: true,
      excludeSemantics: true,
      label: action.semanticLabel,
      onTap: onPressed,
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: 18,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.card),
              side: BorderSide(
                color: action.isPrimary ? AppColors.teal : AppColors.border,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(action.icon, size: 26),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  action.label,
                  style: AppTextStyles.title(
                    Theme.of(context).textTheme,
                  ).copyWith(color: foregroundColor),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 28),
            ],
          ),
        ),
      ),
    );
  }
}

class PrivacyNote extends StatelessWidget {
  const PrivacyNote({
    super.key,
    required this.label,
    this.icon = Icons.lock_outline_rounded,
  });

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Privacy note',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.teal),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              label,
              style: AppTextStyles.body(Theme.of(context).textTheme),
            ),
          ),
        ],
      ),
    );
  }
}

class FooterBranding extends StatelessWidget {
  const FooterBranding({super.key});

  static const label = 'Copyright by Xenovis Pty Ltd';

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      textAlign: TextAlign.center,
      style: AppTextStyles.compact(Theme.of(context).textTheme),
    );
  }
}

class SessionStatusCard extends StatelessWidget {
  const SessionStatusCard({super.key, required this.session});

  final LiveSessionViewData session;

  @override
  Widget build(BuildContext context) {
    final accentColor = AppColors.forSessionMode(session.mode);

    return _Surface(
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.graphic_eq_rounded, color: accentColor),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  session.routeLabel,
                  style: AppTextStyles.label(Theme.of(context).textTheme),
                ),
              ),
              StatusPill(
                label: session.statusLabel ?? session.mode.statusLabel,
                accent: session.statusAccent ?? session.mode.accent,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.schedule_rounded,
                size: 18,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                session.elapsedLabel,
                style: AppTextStyles.body(Theme.of(context).textTheme),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.accent});

  final String label;
  final LiveAccent accent;

  @override
  Widget build(BuildContext context) {
    final accentColor = AppColors.forAccent(accent);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadii.chip),
      ),
      child: Text(
        label,
        style: AppTextStyles.compact(
          Theme.of(context).textTheme,
        ).copyWith(color: accentColor, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class LanguageSelectorCard extends StatelessWidget {
  const LanguageSelectorCard({super.key, required this.data, this.onTap});

  final LanguageSelectorData data;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accentColor = AppColors.forAccent(data.accent);
    final label =
        '${data.eyebrow} language selector: ${data.primaryLabel} ${data.secondaryLabel}'
            .trim();
    final card = _Surface(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  data.eyebrow,
                  style: AppTextStyles.compact(Theme.of(context).textTheme),
                ),
              ),
              CircleAvatar(
                backgroundColor: accentColor.withValues(alpha: 0.18),
                foregroundColor: accentColor,
                child: Icon(data.icon),
              ),
              if (onTap != null) const Icon(Icons.keyboard_arrow_down_rounded),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            data.primaryLabel,
            style: AppTextStyles.label(Theme.of(context).textTheme),
          ),
          Text(
            data.secondaryLabel,
            style: AppTextStyles.label(Theme.of(context).textTheme),
          ),
        ],
      ),
    );

    return Semantics(
      container: true,
      button: onTap != null,
      label: label,
      onTap: onTap,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.card),
        onTap: onTap,
        child: card,
      ),
    );
  }
}

class DirectionSwitchButton extends StatelessWidget {
  const DirectionSwitchButton({
    super.key,
    this.onPressed,
    this.accent = LiveAccent.teal,
  });

  final VoidCallback? onPressed;
  final LiveAccent accent;

  @override
  Widget build(BuildContext context) {
    final accentColor = AppColors.forAccent(accent);

    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: 'Switch translation direction',
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: accentColor,
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.card),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.md,
          ),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.swap_horiz_rounded),
            SizedBox(height: AppSpacing.xxs),
            Text('Switch'),
          ],
        ),
      ),
    );
  }
}

class FeatureChip extends StatelessWidget {
  const FeatureChip({super.key, required this.data, this.onTap});

  final FeatureChipData data;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accentColor = AppColors.forAccent(data.accent);
    final stateLabel = data.isPassive
        ? 'active'
        : data.isEnabled
        ? 'on'
        : 'off';

    return Semantics(
      container: true,
      button: onTap != null,
      label: '${data.label} $stateLabel',
      onTap: onTap,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.chip),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 38),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.xxs,
          ),
          decoration: BoxDecoration(
            color: data.isEnabled || data.isPassive
                ? accentColor.withValues(alpha: 0.14)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.chip),
            border: Border.all(
              color: data.isEnabled || data.isPassive
                  ? accentColor
                  : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(data.icon, size: 16, color: accentColor),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  data.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.compact(Theme.of(context).textTheme)
                      .copyWith(
                        color: data.isPassive
                            ? accentColor
                            : AppColors.textPrimary,
                        fontSize: 11,
                      ),
                ),
              ),
              if (!data.isPassive) ...[
                const SizedBox(width: AppSpacing.xxs),
                Icon(
                  data.isEnabled
                      ? Icons.toggle_on_rounded
                      : Icons.toggle_off_rounded,
                  size: 24,
                  color: data.isEnabled ? accentColor : AppColors.textTertiary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class TranscriptCard extends StatelessWidget {
  const TranscriptCard({super.key, required this.entry});

  final TranscriptEntryData entry;

  @override
  Widget build(BuildContext context) {
    final accentColor = AppColors.forAccent(entry.accent);
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      container: true,
      label: 'Transcript ${entry.languageCode} at ${entry.timestamp}',
      child: _Surface(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.xxs,
          AppSpacing.sm,
          AppSpacing.xxs,
        ),
        borderColor: accentColor.withValues(alpha: 0.82),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: accentColor.withValues(alpha: 0.12),
              foregroundColor: accentColor,
              child: Text(
                entry.languageCode,
                style: AppTextStyles.compact(textTheme),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (entry.speakerLabel != null) ...[
                        Text(
                          entry.speakerLabel!,
                          style: AppTextStyles.compact(
                            textTheme,
                          ).copyWith(color: accentColor),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                      ],
                      const Spacer(),
                      Text(
                        entry.timestamp,
                        style: AppTextStyles.compact(textTheme),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'Original',
                    style: AppTextStyles.compact(
                      textTheme,
                    ).copyWith(color: AppColors.textSecondary),
                  ),
                  Text(
                    entry.originalText.isEmpty
                        ? 'Original speech pending'
                        : entry.originalText,
                    style: AppTextStyles.compact(textTheme).copyWith(
                      color: entry.originalText.isEmpty
                          ? AppColors.textTertiary
                          : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'Translation',
                    style: AppTextStyles.compact(
                      textTheme,
                    ).copyWith(color: AppColors.textSecondary),
                  ),
                  Text(
                    entry.translatedText.isEmpty
                        ? 'Translation pending'
                        : entry.translatedText,
                    style: AppTextStyles.label(textTheme).copyWith(
                      fontSize: 15,
                      color: entry.translatedText.isEmpty
                          ? AppColors.textTertiary
                          : AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Icon(
              _playbackIcon(entry.playbackState),
              color: accentColor,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  IconData _playbackIcon(TranscriptPlaybackState state) {
    return switch (state) {
      TranscriptPlaybackState.none => Icons.more_horiz_rounded,
      TranscriptPlaybackState.playable => Icons.volume_up_rounded,
      TranscriptPlaybackState.speaking => Icons.graphic_eq_rounded,
    };
  }
}

class TranscriptList extends StatelessWidget {
  const TranscriptList({
    super.key,
    required this.entries,
    this.bottomPadding = AppSpacing.bottomControlsHeight,
  });

  final List<TranscriptEntryData> entries;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return ListView(
        padding: EdgeInsets.only(bottom: bottomPadding),
        children: const [_EmptyTranscriptState()],
      );
    }

    return ListView.separated(
      padding: EdgeInsets.only(bottom: bottomPadding),
      itemBuilder: (context, index) => TranscriptCard(entry: entries[index]),
      separatorBuilder: (context, index) =>
          const SizedBox(height: AppSpacing.xs),
      itemCount: entries.length,
    );
  }
}

class _EmptyTranscriptState extends StatelessWidget {
  const _EmptyTranscriptState();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      container: true,
      label: 'Transcript waiting for speech',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xl,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            const Icon(Icons.graphic_eq_rounded, color: AppColors.textTertiary),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Waiting for speech',
              textAlign: TextAlign.center,
              style: AppTextStyles.label(textTheme),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Live transcript lines will appear here.',
              textAlign: TextAlign.center,
              style: AppTextStyles.compact(textTheme),
            ),
          ],
        ),
      ),
    );
  }
}

class QueueBanner extends StatelessWidget {
  const QueueBanner({
    super.key,
    required this.data,
    required this.onPrimaryPressed,
    required this.onSecondaryPressed,
  });

  final QueueBannerData data;
  final VoidCallback onPrimaryPressed;
  final VoidCallback onSecondaryPressed;

  @override
  Widget build(BuildContext context) {
    final accentColor = AppColors.forAccent(data.accent);

    return _Surface(
      borderColor: accentColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.pause_circle_outline_rounded, color: accentColor),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.title,
                      style: AppTextStyles.label(Theme.of(context).textTheme),
                    ),
                    Text(
                      data.detail,
                      style: AppTextStyles.compact(Theme.of(context).textTheme),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xxs,
            children: [
              TextButton(
                onPressed: onPrimaryPressed,
                child: Text(data.primaryActionLabel),
              ),
              TextButton(
                onPressed: onSecondaryPressed,
                child: Text(data.secondaryActionLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class JumpToLiveChip extends StatelessWidget {
  const JumpToLiveChip({
    super.key,
    required this.onPressed,
    this.accent = LiveAccent.teal,
  });

  final VoidCallback onPressed;
  final LiveAccent accent;

  @override
  Widget build(BuildContext context) {
    final accentColor = AppColors.forAccent(accent);

    return ActionChip(
      avatar: Icon(Icons.arrow_downward_rounded, color: accentColor, size: 18),
      label: const Text('Jump to Live'),
      labelStyle: AppTextStyles.label(
        Theme.of(context).textTheme,
      ).copyWith(color: accentColor, fontSize: 14),
      backgroundColor: accentColor.withValues(alpha: 0.12),
      side: BorderSide(color: accentColor.withValues(alpha: 0.55)),
      onPressed: onPressed,
    );
  }
}

class BottomControlBar extends StatelessWidget {
  const BottomControlBar({
    super.key,
    required this.actions,
    required this.onPressed,
  });

  final List<BottomControlActionData> actions;
  final ValueChanged<BottomControlActionData> onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(top: BorderSide(color: AppColors.border)),
        boxShadow: AppElevation.raised(AppColors.background),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final action in actions)
            _BottomControlButton(
              action: action,
              onPressed: () => onPressed(action),
            ),
        ],
      ),
    );
  }
}

class _BottomControlButton extends StatelessWidget {
  const _BottomControlButton({required this.action, required this.onPressed});

  final BottomControlActionData action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final accentColor = AppColors.forAccent(action.accent);
    final isNeutral = action.accent == LiveAccent.neutral;

    return Semantics(
      button: action.isEnabled,
      enabled: action.isEnabled,
      container: true,
      excludeSemantics: true,
      label: action.semanticLabel,
      onTap: action.isEnabled ? onPressed : null,
      child: SizedBox(
        width: 104,
        child: InkWell(
          onTap: action.isEnabled ? onPressed : null,
          borderRadius: BorderRadius.circular(AppRadii.card),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: action.isEnabled
                        ? (isNeutral ? AppColors.surfacePressed : accentColor)
                        : AppColors.surface,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    action.icon,
                    color: !action.isEnabled
                        ? AppColors.textTertiary
                        : isNeutral
                        ? AppColors.textPrimary
                        : AppColors.background,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  action.label,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.compact(Theme.of(context).textTheme),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PromptActionChip extends StatelessWidget {
  const PromptActionChip({
    super.key,
    required this.prompt,
    required this.onPressed,
  });

  final PromptChipData prompt;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: prompt.icon == null ? null : Icon(prompt.icon, size: 18),
      label: Text(prompt.label),
      onPressed: onPressed,
      backgroundColor: AppColors.surface,
      side: const BorderSide(color: AppColors.border),
    );
  }
}

class AiChatScopePill extends StatelessWidget {
  const AiChatScopePill({super.key, required this.scope});

  final AiChatScope scope;

  @override
  Widget build(BuildContext context) {
    return StatusPill(label: scope.label, accent: LiveAccent.teal);
  }
}

class ExportTypeSelector extends StatelessWidget {
  const ExportTypeSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final ExportType selected;
  final ValueChanged<ExportType> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ExportType>(
      segments: [
        for (final type in ExportType.values)
          ButtonSegment(value: type, label: Text(type.label)),
      ],
      selected: {selected},
      onSelectionChanged: (selection) => onChanged(selection.single),
    );
  }
}

class _Surface extends StatelessWidget {
  const _Surface({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.borderColor = AppColors.border,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: borderColor),
      ),
      child: child,
    );
  }
}
