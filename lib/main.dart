import 'package:flutter/material.dart';

import 'src/mock/mock_live_translate_data.dart';
import 'src/theme/live_translate_theme.dart';
import 'src/ui/live_translate_components.dart';
import 'src/ui/live_translate_models.dart';

void main() {
  runApp(const LiveTranslateApp());
}

class LiveTranslateApp extends StatelessWidget {
  const LiveTranslateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Live Translate',
      debugShowCheckedModeBanner: false,
      theme: LiveTranslateTheme.dark(),
      home: const LiveTranslateHome(),
    );
  }
}

enum _AppSurface { setup, listening, speakingPaused }

class LiveTranslateHome extends StatefulWidget {
  const LiveTranslateHome({super.key});

  @override
  State<LiveTranslateHome> createState() => _LiveTranslateHomeState();
}

class _LiveTranslateHomeState extends State<LiveTranslateHome> {
  _AppSurface _surface = _AppSurface.setup;

  void _openListening() {
    setState(() => _surface = _AppSurface.listening);
  }

  void _openSpeakingPaused() {
    setState(() => _surface = _AppSurface.speakingPaused);
  }

  void _openSetup() {
    setState(() => _surface = _AppSurface.setup);
  }

  void _handleBottomAction(BottomControlActionData action) {
    if (action.label == 'Stop Listening') {
      _openSetup();
      return;
    }

    if (action.label == 'Switch Direction' ||
        action.label == 'Pause Read Aloud') {
      _openSpeakingPaused();
      return;
    }

    if (action.label == 'Resume Read Aloud') {
      _openListening();
    }
  }

  void _showAssistantSheet(AiChatScope scope) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AssistantSheet(scope: scope),
    );
  }

  void _showMeetingMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _MeetingMenuSheet(
        onOpenHistory: () {
          Navigator.of(context).pop();
          _showMeetingHistory();
        },
        onExport: () {
          Navigator.of(context).pop();
          _showExportSheet();
        },
        onResumeAmberMeeting: () {
          Navigator.of(context).pop();
          _openSpeakingPaused();
        },
      ),
    );
  }

  void _showMeetingHistory() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _MeetingHistorySheet(
        onOpenListening: () {
          Navigator.of(context).pop();
          _openListening();
        },
        onOpenSpeakingPaused: () {
          Navigator.of(context).pop();
          _openSpeakingPaused();
        },
      ),
    );
  }

  void _showExportSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _ExportSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return switch (_surface) {
      _AppSurface.setup => LocalSetupScreen(
        onStartMeeting: _openListening,
        onOpenMeetingHistory: _showMeetingHistory,
      ),
      _AppSurface.listening => LiveSessionScreen(
        session: MockLiveTranslateData.listeningSession,
        onOpenMenu: _showMeetingMenu,
        onOpenAssistant: () => _showAssistantSheet(AiChatScope.thisMeeting),
        onDirectionSwitch: _openSpeakingPaused,
        onBottomAction: _handleBottomAction,
      ),
      _AppSurface.speakingPaused => LiveSessionScreen(
        session: MockLiveTranslateData.speakingPausedSession,
        onOpenMenu: _showMeetingMenu,
        onOpenAssistant: () => _showAssistantSheet(AiChatScope.thisMeeting),
        onDirectionSwitch: _openListening,
        onBottomAction: _handleBottomAction,
      ),
    };
  }
}

class LocalSetupScreen extends StatelessWidget {
  const LocalSetupScreen({
    super.key,
    this.onStartMeeting,
    this.onOpenMeetingHistory,
  });

  static const _privacyLabel =
      'Transcripts are stored on device only. Your conversations stay private.';

  final VoidCallback? onStartMeeting;
  final VoidCallback? onOpenMeetingHistory;

  @override
  Widget build(BuildContext context) {
    return LiveTranslateShell(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const _LocalSetupHero(),
                  _LocalSetupActions(
                    onStartMeeting: onStartMeeting ?? () {},
                    onOpenMeetingHistory: onOpenMeetingHistory ?? () {},
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: AppSpacing.xxl),
                    child: FooterBadgeRow(
                      badges: MockLiveTranslateData.footerBadges,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LocalSetupHero extends StatelessWidget {
  const _LocalSetupHero();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        const SizedBox(height: AppSpacing.xxl),
        const WaveLogo(),
        const SizedBox(height: AppSpacing.xxl),
        Text(
          'Live Translate',
          textAlign: TextAlign.center,
          style: AppTextStyles.display(textTheme),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Live conversation translation for meetings and face-to-face moments',
          textAlign: TextAlign.center,
          style: AppTextStyles.body(textTheme).copyWith(fontSize: 18),
        ),
        const SizedBox(height: 44),
        const AudioWavePanel(),
      ],
    );
  }
}

class _LocalSetupActions extends StatelessWidget {
  const _LocalSetupActions({
    required this.onStartMeeting,
    required this.onOpenMeetingHistory,
  });

  final VoidCallback onStartMeeting;
  final VoidCallback onOpenMeetingHistory;

  @override
  Widget build(BuildContext context) {
    final actions = MockLiveTranslateData.localSetupActions;

    return Column(
      children: [
        for (var index = 0; index < actions.length; index++) ...[
          LocalSetupActionButton(
            action: actions[index],
            onPressed: index == 0 ? onStartMeeting : onOpenMeetingHistory,
          ),
          if (index < actions.length - 1) const SizedBox(height: AppSpacing.sm),
        ],
        const SizedBox(height: AppSpacing.xl),
        const PrivacyNote(label: LocalSetupScreen._privacyLabel),
      ],
    );
  }
}

class LiveSessionScreen extends StatelessWidget {
  const LiveSessionScreen({
    super.key,
    required this.session,
    required this.onOpenMenu,
    required this.onOpenAssistant,
    required this.onDirectionSwitch,
    required this.onBottomAction,
  });

  final LiveSessionViewData session;
  final VoidCallback onOpenMenu;
  final VoidCallback onOpenAssistant;
  final VoidCallback onDirectionSwitch;
  final ValueChanged<BottomControlActionData> onBottomAction;

  @override
  Widget build(BuildContext context) {
    return LiveTranslateShell(
      screenPadding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      fixedBottomControls: BottomControlBar(
        actions: session.bottomControls,
        onPressed: onBottomAction,
      ),
      child: Column(
        children: [
          LiveTranslateHeader(
            onOpenMenu: onOpenMenu,
            onOpenAssistant: onOpenAssistant,
          ),
          const SizedBox(height: AppSpacing.sm),
          SessionStatusCard(session: session),
          const SizedBox(height: AppSpacing.sm),
          _LanguageRouteRow(
            session: session,
            onDirectionSwitch: onDirectionSwitch,
          ),
          const SizedBox(height: AppSpacing.sm),
          _FeatureRow(features: session.features),
          if (session.queueBanner != null) ...[
            const SizedBox(height: AppSpacing.sm),
            QueueBanner(
              data: session.queueBanner!,
              onPrimaryPressed: onDirectionSwitch,
              onSecondaryPressed: onDirectionSwitch,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                TranscriptList(entries: session.transcriptEntries),
                if (!session.isAtLiveEdge)
                  Padding(
                    padding: const EdgeInsets.only(
                      bottom: AppSpacing.bottomControlsHeight - 28,
                    ),
                    child: JumpToLiveChip(
                      accent: session.mode.accent,
                      onPressed: () {},
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguageRouteRow extends StatelessWidget {
  const _LanguageRouteRow({
    required this.session,
    required this.onDirectionSwitch,
  });

  final LiveSessionViewData session;
  final VoidCallback onDirectionSwitch;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: LanguageSelectorCard(data: session.fromLanguage)),
        const SizedBox(width: AppSpacing.xs),
        DirectionSwitchButton(
          accent: session.mode.accent,
          onPressed: onDirectionSwitch,
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(child: LanguageSelectorCard(data: session.toLanguage)),
      ],
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.features});

  final List<FeatureChipData> features;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [for (final feature in features) FeatureChip(data: feature)],
      ),
    );
  }
}

class _AssistantSheet extends StatelessWidget {
  const _AssistantSheet({required this.scope});

  final AiChatScope scope;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return _SheetFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SheetHandle(),
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, color: AppColors.teal),
              const SizedBox(width: AppSpacing.sm),
              Text('AI Chat', style: AppTextStyles.title(textTheme)),
              const Spacer(),
              IconButton(
                tooltip: 'Close AI chat',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          AiChatScopePill(scope: scope),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'I answer from the selected local meeting scope.',
            style: AppTextStyles.body(textTheme),
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerRight,
            child: _ChatBubble(
              label: 'What did they agree about the timeline?',
              timestamp: '10:42 AM',
              isUser: true,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const _ChatBubble(
            label:
                'They agreed to meet on Tuesday at 10 AM (10:37 AM) and review the deliverables and project timeline (10:38 AM).',
            timestamp: '10:42 AM',
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                tooltip: 'Helpful',
                onPressed: () {},
                icon: const Icon(Icons.thumb_up_alt_outlined),
              ),
              IconButton(
                tooltip: 'Not helpful',
                onPressed: () {},
                icon: const Icon(Icons.thumb_down_alt_outlined),
              ),
            ],
          ),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final prompt in MockLiveTranslateData.assistantPrompts)
                PromptActionChip(prompt: prompt, onPressed: () {}),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            decoration: InputDecoration(
              hintText: scope.inputPlaceholder,
              suffixIcon: IconButton.filled(
                tooltip: 'Send AI chat prompt',
                onPressed: () {},
                icon: const Icon(Icons.arrow_upward_rounded),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.card),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          PrivacyNote(label: scope.privacyLabel, icon: Icons.lock_outline),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.label,
    required this.timestamp,
    this.isUser = false,
  });

  final String label;
  final String timestamp;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: isUser ? AppColors.surfacePressed : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTextStyles.body(Theme.of(context).textTheme)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              timestamp,
              style: AppTextStyles.compact(Theme.of(context).textTheme),
            ),
          ],
        ),
      ),
    );
  }
}

class _MeetingMenuSheet extends StatelessWidget {
  const _MeetingMenuSheet({
    required this.onOpenHistory,
    required this.onExport,
    required this.onResumeAmberMeeting,
  });

  final VoidCallback onOpenHistory;
  final VoidCallback onExport;
  final VoidCallback onResumeAmberMeeting;

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _SheetHandle(),
          _SheetAction(
            icon: Icons.history_rounded,
            label: 'Meeting history',
            onTap: onOpenHistory,
          ),
          _SheetAction(
            icon: Icons.ios_share_rounded,
            label: 'Export meeting',
            onTap: onExport,
          ),
          _SheetAction(
            icon: Icons.play_circle_outline_rounded,
            label: 'Resume read-aloud meeting',
            onTap: onResumeAmberMeeting,
          ),
        ],
      ),
    );
  }
}

class _MeetingHistorySheet extends StatelessWidget {
  const _MeetingHistorySheet({
    required this.onOpenListening,
    required this.onOpenSpeakingPaused,
  });

  final VoidCallback onOpenListening;
  final VoidCallback onOpenSpeakingPaused;

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SheetHandle(),
          Text(
            'Meeting history',
            style: AppTextStyles.title(Theme.of(context).textTheme),
          ),
          const SizedBox(height: AppSpacing.sm),
          _MeetingRow(
            title: 'Project timeline review',
            detail: 'Auto-detect Spanish -> English - 5 transcript lines',
            onTap: onOpenListening,
          ),
          _MeetingRow(
            title: 'Read-aloud follow-up',
            detail: 'English -> Japanese - queued audio',
            onTap: onOpenSpeakingPaused,
          ),
        ],
      ),
    );
  }
}

class _MeetingRow extends StatelessWidget {
  const _MeetingRow({
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const CircleAvatar(
        backgroundColor: AppColors.surfacePressed,
        foregroundColor: AppColors.teal,
        child: Icon(Icons.forum_outlined),
      ),
      title: Text(
        title,
        style: AppTextStyles.label(Theme.of(context).textTheme),
      ),
      subtitle: Text(
        detail,
        style: AppTextStyles.compact(Theme.of(context).textTheme),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _ExportSheet extends StatefulWidget {
  const _ExportSheet();

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  ExportType _selectedType = ExportType.transcript;
  final Map<String, bool> _recipients = {
    'recipient@example.com': true,
    'assistant@example.com': false,
  };

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SheetHandle(),
          Text(
            'Email export',
            style: AppTextStyles.title(Theme.of(context).textTheme),
          ),
          const SizedBox(height: AppSpacing.sm),
          ExportTypeSelector(
            selected: _selectedType,
            onChanged: (type) => setState(() => _selectedType = type),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final recipient in _recipients.keys)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _recipients[recipient],
              onChanged: (value) {
                setState(() => _recipients[recipient] = value ?? false);
              },
              title: Text(recipient),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          const SizedBox(height: AppSpacing.sm),
          PrivacyNote(
            label:
                'Exports are prepared locally and handed to the device mail or share sheet.',
            icon: Icons.lock_outline_rounded,
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.ios_share_rounded),
              label: const Text('Open share sheet'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xl),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight - AppSpacing.xl,
              ),
              child: Material(
                color: AppColors.surfaceRaised,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(AppRadii.sheet),
                  ),
                  side: BorderSide(color: AppColors.border),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      AppSpacing.sm,
                      AppSpacing.xl,
                      AppSpacing.xl,
                    ),
                    child: SingleChildScrollView(child: child),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 48,
        height: 5,
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.textSecondary,
          borderRadius: BorderRadius.circular(AppRadii.circle),
        ),
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppColors.teal),
      title: Text(
        label,
        style: AppTextStyles.label(Theme.of(context).textTheme),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
