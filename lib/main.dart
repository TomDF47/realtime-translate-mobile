import 'dart:async';

import 'package:flutter/material.dart';

import 'src/mock/mock_live_translate_data.dart';
import 'src/session/live_session_controller.dart';
import 'src/session/microphone_permission.dart';
import 'src/storage/encrypted_local_store.dart';
import 'src/storage/local_meeting_repository.dart';
import 'src/storage/local_storage_models.dart';
import 'src/theme/live_translate_theme.dart';
import 'src/ui/live_translate_components.dart';
import 'src/ui/live_translate_models.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LiveTranslateApp());
}

class LiveTranslateApp extends StatelessWidget {
  const LiveTranslateApp({
    super.key,
    this.permissionGateway,
    this.meetingRepository,
  });

  final MicrophonePermissionGateway? permissionGateway;
  final LocalMeetingRepository? meetingRepository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Live Translate',
      debugShowCheckedModeBanner: false,
      theme: LiveTranslateTheme.dark(),
      home: LiveTranslateHome(
        permissionGateway: permissionGateway,
        meetingRepository: meetingRepository,
      ),
    );
  }
}

enum _AppSurface { setup, listening, speakingPaused }

String _languageLabel(LanguageSelectorData data) {
  return '${data.primaryLabel} ${data.secondaryLabel}'.trim();
}

StoredMeeting _storedMeetingFromSession({
  required String id,
  required String title,
  required LiveSessionViewData session,
  required DateTime now,
}) {
  return StoredMeeting(
    id: id,
    title: title,
    createdAt: now,
    updatedAt: now,
    sourceLanguageLabel: _languageLabel(session.fromLanguage),
    targetLanguageLabel: _languageLabel(session.toLanguage),
    transcriptEntries: [
      for (var index = 0; index < session.transcriptEntries.length; index++)
        StoredTranscriptEntry(
          id: '$id-entry-$index',
          meetingId: id,
          languageCode: session.transcriptEntries[index].languageCode,
          originalText: session.transcriptEntries[index].originalText,
          translatedText: session.transcriptEntries[index].translatedText,
          timestamp: now.add(Duration(seconds: index)),
          speakerLabel: session.transcriptEntries[index].speakerLabel,
          confidence: null,
          status: 'final',
          playbackState: session.transcriptEntries[index].playbackState.name,
        ),
    ],
    summaryMetadata: const StoredSummaryMetadata.empty(),
  );
}

String _timeLabel(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $period';
}

TranscriptPlaybackState _playbackStateFromName(String value) {
  for (final state in TranscriptPlaybackState.values) {
    if (state.name == value) {
      return state;
    }
  }

  return TranscriptPlaybackState.playable;
}

TranscriptEntryData _transcriptEntryFromStored(StoredTranscriptEntry entry) {
  final accent = switch (entry.languageCode.toUpperCase()) {
    'EN' => LiveAccent.blue,
    'JA' => LiveAccent.amber,
    _ => LiveAccent.teal,
  };

  return TranscriptEntryData(
    languageCode: entry.languageCode,
    originalText: entry.originalText,
    translatedText: entry.translatedText,
    timestamp: _timeLabel(entry.timestamp),
    accent: accent,
    speakerLabel: entry.speakerLabel,
    playbackState: _playbackStateFromName(entry.playbackState),
  );
}

String _routeEndpointLabel(String label) {
  final trimmed = label.trim();
  final qualifierIndex = trimmed.indexOf(' (');
  if (qualifierIndex > 0 && trimmed.endsWith(')')) {
    return trimmed.substring(0, qualifierIndex);
  }

  return trimmed;
}

LanguageSelectorData _languageSelectorFromStoredLabel({
  required String label,
  required LanguageSelectorData fallback,
}) {
  final trimmed = label.trim();
  if (trimmed.isEmpty) {
    return fallback;
  }

  if (trimmed.startsWith('Auto-detect ')) {
    return LanguageSelectorData(
      eyebrow: fallback.eyebrow,
      primaryLabel: 'Auto-detect',
      secondaryLabel: trimmed.replaceFirst('Auto-detect ', ''),
      icon: fallback.icon,
      accent: fallback.accent,
    );
  }

  final qualifierIndex = trimmed.indexOf(' (');
  if (qualifierIndex > 0 && trimmed.endsWith(')')) {
    return LanguageSelectorData(
      eyebrow: fallback.eyebrow,
      primaryLabel: trimmed.substring(0, qualifierIndex),
      secondaryLabel: trimmed.substring(qualifierIndex + 1),
      icon: fallback.icon,
      accent: fallback.accent,
    );
  }

  return LanguageSelectorData(
    eyebrow: fallback.eyebrow,
    primaryLabel: trimmed,
    secondaryLabel: '',
    icon: fallback.icon,
    accent: fallback.accent,
  );
}

LiveSessionViewData _sessionFromStoredMeeting({
  required StoredMeeting meeting,
  required LiveSessionViewData base,
}) {
  return base.copyWith(
    routeLabel:
        '${_routeEndpointLabel(meeting.sourceLanguageLabel)} -> '
        '${_routeEndpointLabel(meeting.targetLanguageLabel)}',
    fromLanguage: _languageSelectorFromStoredLabel(
      label: meeting.sourceLanguageLabel,
      fallback: base.fromLanguage,
    ),
    toLanguage: _languageSelectorFromStoredLabel(
      label: meeting.targetLanguageLabel,
      fallback: base.toLanguage,
    ),
    transcriptEntries: meeting.transcriptEntries.isEmpty
        ? base.transcriptEntries
        : [
            for (final entry in meeting.transcriptEntries)
              _transcriptEntryFromStored(entry),
          ],
  );
}

StoredTranscriptEntry _storedTranscriptEntryFromTranscriptData({
  required String id,
  required String meetingId,
  required TranscriptEntryData entry,
  required DateTime timestamp,
}) {
  return StoredTranscriptEntry(
    id: id,
    meetingId: meetingId,
    languageCode: entry.languageCode,
    originalText: entry.originalText,
    translatedText: entry.translatedText,
    timestamp: timestamp,
    speakerLabel: entry.speakerLabel,
    confidence: null,
    status: 'final',
    playbackState: entry.playbackState.name,
  );
}

class LiveTranslateHome extends StatefulWidget {
  const LiveTranslateHome({
    super.key,
    this.permissionGateway,
    this.meetingRepository,
  });

  final MicrophonePermissionGateway? permissionGateway;
  final LocalMeetingRepository? meetingRepository;

  @override
  State<LiveTranslateHome> createState() => _LiveTranslateHomeState();
}

class _LiveTranslateHomeState extends State<LiveTranslateHome>
    with WidgetsBindingObserver {
  late final LiveSessionController _sessionController;
  late final LocalMeetingRepository _meetingRepository;
  _AppSurface _surface = _AppSurface.setup;
  List<StoredMeeting> _storedMeetings = const [];
  String? _activeMeetingId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionController = LiveSessionController(
      permissionGateway:
          widget.permissionGateway ??
          MethodChannelMicrophonePermissionGateway(),
    );
    _meetingRepository =
        widget.meetingRepository ??
        LocalMeetingRepository(store: FlutterSecureEncryptedLocalStore());
    unawaited(_loadStoredMeetings());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sessionController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _sessionController.handleAppLifecycleState(state);
    if (_sessionController.state.phase == LiveSessionPhase.readAloudPaused ||
        _sessionController.state.phase == LiveSessionPhase.reconnecting) {
      setState(() => _surface = _AppSurface.speakingPaused);
    }
  }

  StoredMeeting? get _activeMeeting {
    final activeMeetingId = _activeMeetingId;
    if (activeMeetingId == null) {
      return null;
    }

    for (final meeting in _storedMeetings) {
      if (meeting.id == activeMeetingId) {
        return meeting;
      }
    }

    return null;
  }

  Future<void> _startMeeting() async {
    _activeMeetingId = null;
    await _sessionController.startMeeting();
    if (!mounted) {
      return;
    }

    final phase = _sessionController.state.phase;
    if (phase == LiveSessionPhase.listening) {
      await _persistMeetingFromSession(MockLiveTranslateData.listeningSession);
      if (!mounted) {
        return;
      }
      setState(() => _surface = _AppSurface.listening);
    } else {
      setState(() {});
    }
  }

  Future<void> _loadStoredMeetings() async {
    final snapshot = await _meetingRepository.loadSnapshot();
    if (!mounted) {
      return;
    }

    setState(() => _storedMeetings = snapshot.meetings);
  }

  Future<void> _persistMeetingFromSession(LiveSessionViewData session) async {
    final now = DateTime.now().toUtc();
    final meetingId =
        _activeMeetingId ?? 'meeting-${now.microsecondsSinceEpoch}';
    _activeMeetingId = meetingId;
    await _meetingRepository.upsertMeeting(
      _storedMeetingFromSession(
        id: meetingId,
        title: session.mode == LiveSessionMode.speaking
            ? 'Read-aloud follow-up'
            : 'Project timeline review',
        session: session,
        now: now,
      ),
    );
    await _meetingRepository.saveRecentLanguageRoute(
      LanguageRoutePreference(
        sourceLanguageLabel: _languageLabel(session.fromLanguage),
        targetLanguageLabel: _languageLabel(session.toLanguage),
        updatedAt: now,
      ),
    );
    await _loadStoredMeetings();
  }

  Future<bool> _ensureMicrophoneReady() async {
    if (_sessionController.state.microphonePermission.isGranted) {
      return true;
    }

    await _sessionController.startMeeting();
    if (!mounted) {
      return false;
    }

    if (_sessionController.state.phase == LiveSessionPhase.listening) {
      return true;
    }

    setState(() {});
    return false;
  }

  _AppSurface _surfaceForMeeting(StoredMeeting meeting) {
    return meeting.targetLanguageLabel.contains('Japanese')
        ? _AppSurface.speakingPaused
        : _AppSurface.listening;
  }

  LiveSessionViewData _baseSessionForSurface(_AppSurface surface) {
    return switch (surface) {
      _AppSurface.speakingPaused => MockLiveTranslateData.speakingPausedSession,
      _ => MockLiveTranslateData.listeningSession,
    };
  }

  LiveSessionViewData _sessionForSurface(_AppSurface surface) {
    final meeting = _activeMeeting;
    final base = _baseSessionForSurface(surface);
    if (meeting == null || _surfaceForMeeting(meeting) != surface) {
      return base;
    }

    return _sessionFromStoredMeeting(meeting: meeting, base: base);
  }

  Future<void> _appendContinuationToMeeting({
    required StoredMeeting meeting,
    required LiveSessionViewData session,
  }) async {
    final sourceEntries = session.transcriptEntries;
    if (sourceEntries.isEmpty) {
      return;
    }

    final now = DateTime.now().toUtc();
    final sourceEntry =
        sourceEntries[meeting.transcriptEntries.length % sourceEntries.length];
    await _meetingRepository.appendTranscriptEntry(
      meetingId: meeting.id,
      updatedAt: now,
      entry: _storedTranscriptEntryFromTranscriptData(
        id: '${meeting.id}-continued-${now.microsecondsSinceEpoch}',
        meetingId: meeting.id,
        entry: sourceEntry,
        timestamp: now,
      ),
    );
    await _loadStoredMeetings();
  }

  Future<void> _continueMeeting(StoredMeeting meeting) async {
    final nextSurface = _surfaceForMeeting(meeting);
    final session = _baseSessionForSurface(nextSurface);
    final isReady = await _ensureMicrophoneReady();
    if (!isReady || !mounted) {
      return;
    }

    _activeMeetingId = meeting.id;
    if (nextSurface == _AppSurface.speakingPaused) {
      _sessionController.enterSpeakingPaused();
    } else {
      _sessionController.resumeListening();
    }

    await _appendContinuationToMeeting(meeting: meeting, session: session);
    if (!mounted) {
      return;
    }

    setState(() => _surface = nextSurface);
  }

  void _openListening() {
    unawaited(_openListeningAfterPermission());
  }

  Future<void> _openListeningAfterPermission() async {
    if (!_sessionController.state.microphonePermission.isGranted) {
      await _startMeeting();
      return;
    }

    _sessionController.resumeListening();
    setState(() => _surface = _AppSurface.listening);
  }

  void _openSpeakingPaused() {
    unawaited(_openSpeakingPausedAfterPermission());
  }

  Future<void> _openSpeakingPausedAfterPermission() async {
    if (!_sessionController.state.microphonePermission.isGranted) {
      await _sessionController.startMeeting();
      if (!mounted) {
        return;
      }
      if (_sessionController.state.phase != LiveSessionPhase.listening) {
        setState(() {});
        return;
      }
    }

    _sessionController.enterSpeakingPaused();
    setState(() => _surface = _AppSurface.speakingPaused);
  }

  void _openSetup() {
    _sessionController.stopMeeting();
    _activeMeetingId = null;
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
        meetings: _storedMeetings,
        onOpenMeeting: (meeting) {
          Navigator.of(context).pop();
          unawaited(_continueMeeting(meeting));
        },
        onDeleteMeeting: (meeting) async {
          Navigator.of(context).pop();
          await _meetingRepository.deleteMeeting(meeting.id);
          await _loadStoredMeetings();
          if (_activeMeetingId == meeting.id && mounted) {
            _openSetup();
          }
        },
      ),
    );
  }

  void _showExportSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ExportSheet(repository: _meetingRepository),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessionState = _sessionController.state;
    if (sessionState.phase == LiveSessionPhase.requestingMicrophonePermission ||
        sessionState.phase == LiveSessionPhase.connecting) {
      return _LifecycleProgressScreen(state: sessionState);
    }

    if (sessionState.phase == LiveSessionPhase.microphoneDenied ||
        sessionState.phase == LiveSessionPhase.microphonePermanentlyDenied) {
      return _MicrophonePermissionScreen(
        state: sessionState,
        onRetry: _startMeeting,
        onBack: _openSetup,
        onOpenSettings: _sessionController.openPermissionSettings,
      );
    }

    return switch (_surface) {
      _AppSurface.setup => LocalSetupScreen(
        onStartMeeting: _startMeeting,
        onOpenMeetingHistory: _showMeetingHistory,
      ),
      _AppSurface.listening => LiveSessionScreen(
        session: _sessionForSurface(_AppSurface.listening),
        onOpenMenu: _showMeetingMenu,
        onOpenAssistant: () => _showAssistantSheet(AiChatScope.thisMeeting),
        onDirectionSwitch: _openSpeakingPaused,
        onBottomAction: _handleBottomAction,
      ),
      _AppSurface.speakingPaused => LiveSessionScreen(
        session: _sessionForSurface(_AppSurface.speakingPaused),
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

class _LifecycleProgressScreen extends StatelessWidget {
  const _LifecycleProgressScreen({required this.state});

  final LiveSessionState state;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final title = state.phase == LiveSessionPhase.requestingMicrophonePermission
        ? 'Requesting microphone access'
        : 'Preparing live session';

    return LiveTranslateShell(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const WaveLogo(),
            const SizedBox(height: AppSpacing.xxl),
            const CircularProgressIndicator(),
            const SizedBox(height: AppSpacing.xl),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.title(textTheme),
            ),
            if (state.notice != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                state.notice!,
                textAlign: TextAlign.center,
                style: AppTextStyles.body(textTheme),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MicrophonePermissionScreen extends StatelessWidget {
  const _MicrophonePermissionScreen({
    required this.state,
    required this.onRetry,
    required this.onBack,
    required this.onOpenSettings,
  });

  final LiveSessionState state;
  final VoidCallback onRetry;
  final VoidCallback onBack;
  final VoidCallback onOpenSettings;

  bool get _requiresSettings {
    return state.phase == LiveSessionPhase.microphonePermanentlyDenied;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return LiveTranslateShell(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  WaveLogo(
                    accent: _requiresSettings
                        ? LiveAccent.amber
                        : LiveAccent.red,
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  Text(
                    'Microphone access needed',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.display(
                      textTheme,
                    ).copyWith(fontSize: 36),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _requiresSettings
                        ? 'Enable microphone access in Android settings before starting live translation.'
                        : 'Live translation starts only after Android grants microphone access.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body(textTheme).copyWith(fontSize: 18),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _PermissionActionButton(
                    label: _requiresSettings
                        ? 'Open app settings'
                        : 'Try microphone permission again',
                    icon: _requiresSettings
                        ? Icons.settings_rounded
                        : Icons.mic_rounded,
                    onPressed: _requiresSettings ? onOpenSettings : onRetry,
                    isPrimary: true,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _PermissionActionButton(
                    label: 'Back to start',
                    icon: Icons.arrow_back_rounded,
                    onPressed: onBack,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const PrivacyNote(
                    label:
                        'No audio is captured before microphone permission is granted.',
                    icon: Icons.lock_outline_rounded,
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

class _PermissionActionButton extends StatelessWidget {
  const _PermissionActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.isPrimary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = isPrimary ? AppColors.teal : AppColors.surface;
    final foregroundColor = isPrimary
        ? AppColors.background
        : AppColors.textPrimary;

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
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
              color: isPrimary ? AppColors.teal : AppColors.border,
            ),
          ),
        ),
      ),
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
    required this.meetings,
    required this.onOpenMeeting,
    required this.onDeleteMeeting,
  });

  final List<StoredMeeting> meetings;
  final ValueChanged<StoredMeeting> onOpenMeeting;
  final Future<void> Function(StoredMeeting meeting) onDeleteMeeting;

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
          if (meetings.isEmpty)
            Text(
              'No saved meetings yet',
              style: AppTextStyles.body(Theme.of(context).textTheme),
            )
          else
            for (final meeting in meetings)
              _MeetingRow(
                meeting: meeting,
                onTap: () => onOpenMeeting(meeting),
                onDelete: () => onDeleteMeeting(meeting),
              ),
        ],
      ),
    );
  }
}

class _MeetingRow extends StatelessWidget {
  const _MeetingRow({
    required this.meeting,
    required this.onTap,
    required this.onDelete,
  });

  final StoredMeeting meeting;
  final VoidCallback onTap;
  final Future<void> Function() onDelete;

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
        meeting.title,
        style: AppTextStyles.label(Theme.of(context).textTheme),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${meeting.sourceLanguageLabel} -> ${meeting.targetLanguageLabel}',
            style: AppTextStyles.compact(Theme.of(context).textTheme),
          ),
          Text(
            'Created ${_timeLabel(meeting.createdAt)} - Last activity '
            '${_timeLabel(meeting.updatedAt)}',
            style: AppTextStyles.compact(Theme.of(context).textTheme),
          ),
          Text(
            '${meeting.transcriptCount} transcript lines - '
            '${meeting.summaryAvailable ? 'Summary ready' : 'No summary yet'}',
            style: AppTextStyles.compact(Theme.of(context).textTheme),
          ),
        ],
      ),
      trailing: IconButton(
        tooltip: 'Delete ${meeting.title}',
        onPressed: onDelete,
        icon: const Icon(Icons.delete_outline_rounded),
      ),
      onTap: onTap,
    );
  }
}

class _ExportSheet extends StatefulWidget {
  const _ExportSheet({required this.repository});

  final LocalMeetingRepository repository;

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
              onPressed: () async {
                await widget.repository.saveRecipientPreferences(
                  RecipientPreferences(
                    rememberedRecipients: _recipients.keys.toList(
                      growable: false,
                    ),
                    lastSelectedRecipients: [
                      for (final entry in _recipients.entries)
                        if (entry.value) entry.key,
                    ],
                  ),
                );
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
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
