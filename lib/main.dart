import 'dart:async';

import 'package:flutter/material.dart';

import 'src/export/local_meeting_exporter.dart';
import 'src/language/language_support.dart';
import 'src/mock/mock_live_translate_data.dart';
import 'src/openai/openai_ai_chat.dart';
import 'src/openai/openai_configuration.dart';
import 'src/openai/openai_credential_store.dart';
import 'src/openai/openai_meeting_summary.dart';
import 'src/openai/openai_realtime_translation.dart';
import 'src/session/live_session_controller.dart';
import 'src/session/microphone_capture.dart';
import 'src/session/microphone_permission.dart';
import 'src/session/realtime_translation_coordinator.dart';
import 'src/session/realtime_transcript_committer.dart';
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
    this.nativeShareGateway,
    this.aiChatGateway,
    this.meetingSummaryGateway,
    this.microphoneCaptureGateway,
    this.realtimeTranslationGateway,
  });

  final MicrophonePermissionGateway? permissionGateway;
  final LocalMeetingRepository? meetingRepository;
  final NativeShareGateway? nativeShareGateway;
  final AiChatGateway? aiChatGateway;
  final MeetingSummaryGateway? meetingSummaryGateway;
  final MicrophoneCaptureGateway? microphoneCaptureGateway;
  final RealtimeTranslationGateway? realtimeTranslationGateway;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Live Translate',
      debugShowCheckedModeBanner: false,
      theme: LiveTranslateTheme.dark(),
      home: LiveTranslateHome(
        permissionGateway: permissionGateway,
        meetingRepository: meetingRepository,
        nativeShareGateway: nativeShareGateway,
        aiChatGateway: aiChatGateway,
        meetingSummaryGateway: meetingSummaryGateway,
        microphoneCaptureGateway: microphoneCaptureGateway,
        realtimeTranslationGateway: realtimeTranslationGateway,
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
    this.nativeShareGateway,
    this.aiChatGateway,
    this.meetingSummaryGateway,
    this.microphoneCaptureGateway,
    this.realtimeTranslationGateway,
  });

  final MicrophonePermissionGateway? permissionGateway;
  final LocalMeetingRepository? meetingRepository;
  final NativeShareGateway? nativeShareGateway;
  final AiChatGateway? aiChatGateway;
  final MeetingSummaryGateway? meetingSummaryGateway;
  final MicrophoneCaptureGateway? microphoneCaptureGateway;
  final RealtimeTranslationGateway? realtimeTranslationGateway;

  @override
  State<LiveTranslateHome> createState() => _LiveTranslateHomeState();
}

class _LiveTranslateHomeState extends State<LiveTranslateHome>
    with WidgetsBindingObserver {
  late final LiveSessionController _sessionController;
  late final LocalMeetingRepository _meetingRepository;
  late final OpenAiCredentialStore _openAiCredentialStore;
  late final NativeShareGateway _nativeShareGateway;
  late final AiChatGateway _aiChatGateway;
  late final MeetingSummaryGateway _meetingSummaryGateway;
  late final LiveRealtimeTranslationCoordinator _realtimeCoordinator;
  _AppSurface _surface = _AppSurface.setup;
  List<StoredMeeting> _storedMeetings = const [];
  OpenAiCredentialStatus _openAiCredentialStatus =
      const OpenAiCredentialStatus.missing();
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
    _openAiCredentialStore = OpenAiCredentialStore(
      repository: _meetingRepository,
    );
    _nativeShareGateway =
        widget.nativeShareGateway ?? const MethodChannelNativeShareGateway();
    _aiChatGateway = widget.aiChatGateway ?? OpenAiResponsesAiChatGateway();
    _meetingSummaryGateway =
        widget.meetingSummaryGateway ?? OpenAiResponsesMeetingSummaryGateway();
    _realtimeCoordinator = LiveRealtimeTranslationCoordinator(
      sessionController: _sessionController,
      credentialStore: _openAiCredentialStore,
      captureGateway:
          widget.microphoneCaptureGateway ??
          MethodChannelMicrophoneCaptureGateway(),
      realtimeGateway:
          widget.realtimeTranslationGateway ??
          OpenAiRealtimeTranslationGateway(),
    );
    unawaited(_loadStoredMeetings());
    unawaited(_loadOpenAiCredentialStatus());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _realtimeCoordinator.dispose();
    _sessionController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _realtimeCoordinator.handleAppLifecycleState(state);
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
    final meetingId = 'meeting-${DateTime.now().microsecondsSinceEpoch}';
    _activeMeetingId = meetingId;
    await _persistMeetingFromSession(MockLiveTranslateData.listeningSession);
    if (!mounted) {
      return;
    }

    final started = await _startRealtimeForSession(
      MockLiveTranslateData.listeningSession,
      meetingId: meetingId,
    );
    if (!mounted) {
      return;
    }

    if (started) {
      setState(() => _surface = _AppSurface.listening);
    } else {
      await _meetingRepository.deleteMeeting(meetingId);
      if (_activeMeetingId == meetingId) {
        _activeMeetingId = null;
      }
      await _loadStoredMeetings();
      if (!mounted) {
        return;
      }
      setState(() {});
    }
  }

  Future<bool> _startRealtimeForSession(
    LiveSessionViewData session, {
    String? meetingId,
  }) async {
    final targetLanguageCode = _languageCodeForSelector(session.toLanguage);
    final result = await _realtimeCoordinator.start(
      config: _realtimeConfigForSession(
        session,
        targetLanguageCode: targetLanguageCode,
      ),
      transcriptCommitTarget: meetingId == null
          ? null
          : LiveRealtimeTranscriptCommitTarget(
              repository: _meetingRepository,
              meetingId: meetingId,
              sourceLanguageCode: 'auto',
              targetLanguageCode: targetLanguageCode,
              now: DateTime.now,
            ),
    );
    if (!mounted) {
      return false;
    }

    _openAiCredentialStatus = await _openAiCredentialStore.loadStatus();
    if (!mounted) {
      return false;
    }

    if (result == LiveRealtimeStartResult.started) {
      return true;
    }

    if (result == LiveRealtimeStartResult.missingCredential) {
      setState(() => _surface = _AppSurface.setup);
      return false;
    }

    setState(() {});
    return false;
  }

  Future<void> _loadStoredMeetings() async {
    final snapshot = await _meetingRepository.loadSnapshot();
    if (!mounted) {
      return;
    }

    setState(() => _storedMeetings = snapshot.meetings);
  }

  Future<void> _loadOpenAiCredentialStatus() async {
    final status = await _openAiCredentialStore.loadStatus();
    if (!mounted) {
      return;
    }

    setState(() => _openAiCredentialStatus = status);
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

  Future<bool> _ensureLiveSessionReady(LiveSessionViewData session) async {
    if (_sessionController.state.microphonePermission.isGranted &&
        _realtimeCoordinator.isStreaming) {
      return true;
    }

    return _startRealtimeForSession(session, meetingId: _activeMeetingId);
  }

  OpenAiRealtimeTranslationConfig _realtimeConfigForSession(
    LiveSessionViewData session, {
    required String targetLanguageCode,
  }) {
    return OpenAiRealtimeTranslationConfig(
      sourceLanguageCode: 'auto',
      targetLanguageCode: targetLanguageCode,
      profile: OpenAiRealtimeTranslationProfile.dedicatedTranslation,
    );
  }

  String _languageCodeForSelector(LanguageSelectorData data) {
    final primary = data.primaryLabel.toLowerCase();
    for (final language in LanguageSupport.languages) {
      if (language.name.toLowerCase() == primary) {
        return language.code;
      }
    }

    return 'en';
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
    _activeMeetingId = meeting.id;
    final isReady = await _ensureLiveSessionReady(
      nextSurface == _AppSurface.speakingPaused
          ? MockLiveTranslateData.listeningSession
          : session,
    );
    if (!isReady) {
      if (_activeMeetingId == meeting.id) {
        _activeMeetingId = null;
      }
      if (mounted) {
        setState(() {});
      }
      return;
    }
    if (!mounted) {
      return;
    }

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
    final isReady = await _ensureLiveSessionReady(
      MockLiveTranslateData.listeningSession,
    );
    if (!isReady || !mounted) {
      return;
    }

    _sessionController.resumeListening();
    setState(() => _surface = _AppSurface.listening);
  }

  void _openSpeakingPaused() {
    unawaited(_openSpeakingPausedAfterPermission());
  }

  Future<void> _openSpeakingPausedAfterPermission() async {
    if (!_sessionController.state.microphonePermission.isGranted ||
        !_realtimeCoordinator.isStreaming) {
      final isReady = await _ensureLiveSessionReady(
        MockLiveTranslateData.listeningSession,
      );
      if (!isReady || !mounted) {
        return;
      }
    }

    _sessionController.enterSpeakingPaused();
    setState(() => _surface = _AppSurface.speakingPaused);
  }

  void _openSetup() {
    unawaited(_realtimeCoordinator.stop());
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
      builder: (context) => _AssistantSheet(
        scope: scope,
        repository: _meetingRepository,
        credentialStore: _openAiCredentialStore,
        aiChatGateway: _aiChatGateway,
        activeMeeting: _activeMeeting,
      ),
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
        onOpenAllMeetingsAssistant: () {
          Navigator.of(context).pop();
          _showAssistantSheet(AiChatScope.allMeetings);
        },
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

  void _showOpenAiSetupSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _OpenAiSetupSheet(
        credentialStore: _openAiCredentialStore,
        initialStatus: _openAiCredentialStatus,
        onCredentialChanged: _loadOpenAiCredentialStatus,
      ),
    );
  }

  void _showExportSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ExportSheet(
        repository: _meetingRepository,
        credentialStore: _openAiCredentialStore,
        nativeShareGateway: _nativeShareGateway,
        meetingSummaryGateway: _meetingSummaryGateway,
        meeting: _activeMeeting,
        onMeetingUpdated: (meeting) async {
          _activeMeetingId = meeting.id;
          await _loadStoredMeetings();
        },
      ),
    );
  }

  void _showLanguageOptionsSheet({required bool isTarget}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _LanguageOptionsSheet(isTarget: isTarget),
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

    if (sessionState.phase == LiveSessionPhase.credentialInvalid) {
      return _OpenAiCredentialRequiredScreen(
        status: _openAiCredentialStatus,
        notice: sessionState.notice,
        onOpenSetup: _showOpenAiSetupSheet,
        onBack: _openSetup,
      );
    }

    return switch (_surface) {
      _AppSurface.setup => LocalSetupScreen(
        onStartMeeting: _startMeeting,
        onOpenMeetingHistory: _showMeetingHistory,
        onOpenOpenAiSetup: _showOpenAiSetupSheet,
      ),
      _AppSurface.listening => LiveSessionScreen(
        session: _sessionForSurface(_AppSurface.listening),
        onOpenMenu: _showMeetingMenu,
        onOpenAssistant: () => _showAssistantSheet(AiChatScope.thisMeeting),
        onOpenSourceLanguageOptions: () =>
            _showLanguageOptionsSheet(isTarget: false),
        onOpenTargetLanguageOptions: () =>
            _showLanguageOptionsSheet(isTarget: true),
        onDirectionSwitch: _openSpeakingPaused,
        onBottomAction: _handleBottomAction,
      ),
      _AppSurface.speakingPaused => LiveSessionScreen(
        session: _sessionForSurface(_AppSurface.speakingPaused),
        onOpenMenu: _showMeetingMenu,
        onOpenAssistant: () => _showAssistantSheet(AiChatScope.thisMeeting),
        onOpenSourceLanguageOptions: () =>
            _showLanguageOptionsSheet(isTarget: false),
        onOpenTargetLanguageOptions: () =>
            _showLanguageOptionsSheet(isTarget: true),
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
    this.onOpenOpenAiSetup,
  });

  static const _privacyLabel =
      'Transcripts are stored on device only. Your conversations stay private.';

  final VoidCallback? onStartMeeting;
  final VoidCallback? onOpenMeetingHistory;
  final VoidCallback? onOpenOpenAiSetup;

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
                    onOpenOpenAiSetup: onOpenOpenAiSetup ?? () {},
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
    required this.onOpenOpenAiSetup,
  });

  final VoidCallback onStartMeeting;
  final VoidCallback onOpenMeetingHistory;
  final VoidCallback onOpenOpenAiSetup;

  @override
  Widget build(BuildContext context) {
    final actions = MockLiveTranslateData.localSetupActions;

    return Column(
      children: [
        for (var index = 0; index < actions.length; index++) ...[
          LocalSetupActionButton(
            action: actions[index],
            onPressed: switch (index) {
              0 => onStartMeeting,
              1 => onOpenMeetingHistory,
              _ => onOpenOpenAiSetup,
            },
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

class _OpenAiCredentialRequiredScreen extends StatelessWidget {
  const _OpenAiCredentialRequiredScreen({
    required this.status,
    required this.notice,
    required this.onOpenSetup,
    required this.onBack,
  });

  final OpenAiCredentialStatus status;
  final String? notice;
  final VoidCallback onOpenSetup;
  final VoidCallback onBack;

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
                  const WaveLogo(accent: LiveAccent.amber),
                  const SizedBox(height: AppSpacing.xxl),
                  Text(
                    'OpenAI setup required',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.display(
                      textTheme,
                    ).copyWith(fontSize: 36),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    notice ?? status.displayLabel,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body(textTheme).copyWith(fontSize: 18),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _PermissionActionButton(
                    label: 'Open OpenAI setup',
                    icon: Icons.key_rounded,
                    onPressed: onOpenSetup,
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
                        'Your OpenAI credential is stored only in encrypted local device storage and is never bundled with the app.',
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
    required this.onOpenSourceLanguageOptions,
    required this.onOpenTargetLanguageOptions,
    required this.onDirectionSwitch,
    required this.onBottomAction,
  });

  final LiveSessionViewData session;
  final VoidCallback onOpenMenu;
  final VoidCallback onOpenAssistant;
  final VoidCallback onOpenSourceLanguageOptions;
  final VoidCallback onOpenTargetLanguageOptions;
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
          const SizedBox(height: AppSpacing.xs),
          SessionStatusCard(session: session),
          const SizedBox(height: AppSpacing.xs),
          _LanguageRouteRow(
            session: session,
            onDirectionSwitch: onDirectionSwitch,
            onOpenSourceLanguageOptions: onOpenSourceLanguageOptions,
            onOpenTargetLanguageOptions: onOpenTargetLanguageOptions,
          ),
          const SizedBox(height: AppSpacing.xs),
          _FeatureRow(features: session.features),
          if (session.queueBanner != null) ...[
            const SizedBox(height: AppSpacing.xs),
            QueueBanner(
              data: session.queueBanner!,
              onPrimaryPressed: onDirectionSwitch,
              onSecondaryPressed: onDirectionSwitch,
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
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
    required this.onOpenSourceLanguageOptions,
    required this.onOpenTargetLanguageOptions,
  });

  final LiveSessionViewData session;
  final VoidCallback onDirectionSwitch;
  final VoidCallback onOpenSourceLanguageOptions;
  final VoidCallback onOpenTargetLanguageOptions;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: LanguageSelectorCard(
            data: session.fromLanguage,
            onTap: onOpenSourceLanguageOptions,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        DirectionSwitchButton(
          accent: session.mode.accent,
          onPressed: onDirectionSwitch,
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: LanguageSelectorCard(
            data: session.toLanguage,
            onTap: onOpenTargetLanguageOptions,
          ),
        ),
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

class _LanguageOptionsSheet extends StatelessWidget {
  const _LanguageOptionsSheet({required this.isTarget});

  final bool isTarget;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final languages = isTarget
        ? LanguageSupport.realtimeTargetLanguages
        : LanguageSupport.sourceLanguages;

    return _SheetFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SheetHandle(),
          Text(
            isTarget ? 'Realtime target languages' : 'Source languages',
            style: AppTextStyles.title(textTheme),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            isTarget
                ? 'Default target choices stay inside the conservative realtime output table.'
                : 'Source speech can use auto-detect or a known local language preference.',
            style: AppTextStyles.body(textTheme),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final language in languages)
            _LanguageOptionRow(
              language: language,
              statusLabel: isTarget ? 'Realtime output' : 'Source input',
            ),
          if (isTarget) ...[
            const SizedBox(height: AppSpacing.sm),
            const Divider(color: AppColors.border),
            const SizedBox(height: AppSpacing.sm),
            Text('Fallback route', style: AppTextStyles.label(textTheme)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Japanese and other broader targets use a direct OpenAI fallback '
              'route once credentials are configured.',
              style: AppTextStyles.compact(textTheme),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          PrivacyNote(
            label:
                'Fallback keeps meeting content on device except for user-approved direct OpenAI requests.',
            icon: Icons.lock_outline,
          ),
        ],
      ),
    );
  }
}

class _LanguageOptionRow extends StatelessWidget {
  const _LanguageOptionRow({required this.language, required this.statusLabel});

  final TranslationLanguage language;
  final String statusLabel;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const CircleAvatar(
        backgroundColor: AppColors.surfacePressed,
        foregroundColor: AppColors.teal,
        child: Icon(Icons.language_rounded),
      ),
      title: Text(
        language.displayLabel,
        style: AppTextStyles.label(Theme.of(context).textTheme),
      ),
      subtitle: Text(
        statusLabel,
        style: AppTextStyles.compact(Theme.of(context).textTheme),
      ),
    );
  }
}

class _AssistantSheet extends StatefulWidget {
  const _AssistantSheet({
    required this.scope,
    required this.repository,
    required this.credentialStore,
    required this.aiChatGateway,
    required this.activeMeeting,
  });

  final AiChatScope scope;
  final LocalMeetingRepository repository;
  final OpenAiCredentialStore credentialStore;
  final AiChatGateway aiChatGateway;
  final StoredMeeting? activeMeeting;

  @override
  State<_AssistantSheet> createState() => _AssistantSheetState();
}

class _AssistantSheetState extends State<_AssistantSheet> {
  final TextEditingController _promptController = TextEditingController();
  AiChatContext? _context;
  bool _isLoadingContext = true;
  bool _isSending = false;
  String? _statusLabel;
  String? _errorLabel;
  final List<_ChatBubbleData> _bubbles = [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadContext());
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _loadContext() async {
    final snapshot = await widget.repository.loadSnapshot();
    final context = AiChatContextBuilder.fromSnapshot(
      scope: widget.scope,
      snapshot: snapshot,
      activeMeeting: widget.activeMeeting,
    );
    if (!mounted) {
      return;
    }

    setState(() {
      _context = context;
      _isLoadingContext = false;
      _statusLabel = context.hasTranscriptContext
          ? 'Ready to answer from ${context.transcriptEntryCount} local transcript lines.'
          : 'No local transcript lines are available for this scope yet.';
    });
  }

  void _usePrompt(PromptChipData prompt) {
    setState(() {
      _promptController.text = prompt.label;
      _promptController.selection = TextSelection.collapsed(
        offset: prompt.label.length,
      );
      _errorLabel = null;
    });
  }

  Future<void> _sendPrompt() async {
    final prompt = _promptController.text.trim();
    final context = _context;
    if (prompt.isEmpty) {
      setState(() => _errorLabel = 'Enter a question before sending.');
      return;
    }

    if (_isLoadingContext || context == null) {
      setState(() => _errorLabel = 'Local meeting context is still loading.');
      return;
    }

    if (!context.hasTranscriptContext) {
      setState(
        () => _errorLabel =
            'No local transcript lines are available for this scope yet.',
      );
      return;
    }

    final credential = await widget.credentialStore
        .readCredentialForNetworkUse();
    if (credential == null) {
      setState(
        () => _errorLabel = 'OpenAI setup is required before AI chat can run.',
      );
      return;
    }

    setState(() {
      _isSending = true;
      _errorLabel = null;
      _statusLabel = 'Sending direct OpenAI request from this phone.';
      _bubbles.add(
        _ChatBubbleData(
          label: prompt,
          timestamp: _timeLabel(DateTime.now()),
          isUser: true,
        ),
      );
      _promptController.clear();
    });

    try {
      final answer = await widget.aiChatGateway.ask(
        request: AiChatRequest(prompt: prompt, context: context),
        credential: credential,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _bubbles.add(
          _ChatBubbleData(
            label: answer.text,
            timestamp: _timeLabel(answer.generatedAt),
          ),
        );
        _statusLabel = 'Answer generated from ${context.scope.label}.';
      });
    } on AiChatCredentialException {
      if (mounted) {
        setState(
          () => _errorLabel =
              'OpenAI rejected the saved credential. Update OpenAI setup and try again.',
        );
      }
    } on AiChatNetworkException {
      if (mounted) {
        setState(
          () => _errorLabel =
              'Could not reach OpenAI from this phone. Check connectivity and try again.',
        );
      }
    } on AiChatException {
      if (mounted) {
        setState(
          () => _errorLabel =
              'AI chat could not complete. Try again after checking OpenAI setup.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return _SheetFrame(
      child: SingleChildScrollView(
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
            AiChatScopePill(scope: widget.scope),
            const SizedBox(height: AppSpacing.sm),
            Text(
              widget.scope == AiChatScope.thisMeeting
                  ? 'I answer from this local meeting transcript.'
                  : 'I answer across local meeting history.',
              style: AppTextStyles.body(textTheme),
            ),
            if (_statusLabel != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_statusLabel!, style: AppTextStyles.compact(textTheme)),
            ],
            const SizedBox(height: AppSpacing.md),
            if (_bubbles.isEmpty)
              Text(
                'Ask a question to use only the selected local transcript context.',
                style: AppTextStyles.compact(textTheme),
              )
            else
              for (final bubble in _bubbles) ...[
                Align(
                  alignment: bubble.isUser
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: _ChatBubble(
                    label: bubble.label,
                    timestamp: bubble.timestamp,
                    isUser: bubble.isUser,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
            if (_bubbles.isNotEmpty && !_bubbles.last.isUser)
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
                  PromptActionChip(
                    prompt: prompt,
                    onPressed: () => _usePrompt(prompt),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _promptController,
              enabled: !_isSending,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendPrompt(),
              decoration: InputDecoration(
                hintText: widget.scope.inputPlaceholder,
                suffixIcon: IconButton.filled(
                  tooltip: 'Send AI chat prompt',
                  onPressed: _isSending ? null : _sendPrompt,
                  icon: _isSending
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.arrow_upward_rounded),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.card),
                ),
              ),
            ),
            if (_errorLabel != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                _errorLabel!,
                style: AppTextStyles.compact(
                  textTheme,
                ).copyWith(color: AppColors.red),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            PrivacyNote(
              label: widget.scope.privacyLabel,
              icon: Icons.lock_outline,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBubbleData {
  const _ChatBubbleData({
    required this.label,
    required this.timestamp,
    this.isUser = false,
  });

  final String label;
  final String timestamp;
  final bool isUser;
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
    required this.onOpenAllMeetingsAssistant,
    required this.onOpenMeeting,
    required this.onDeleteMeeting,
  });

  final List<StoredMeeting> meetings;
  final VoidCallback onOpenAllMeetingsAssistant;
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
          _SheetAction(
            icon: Icons.auto_awesome_rounded,
            label: 'Ask across meetings',
            onTap: onOpenAllMeetingsAssistant,
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

class _OpenAiSetupSheet extends StatefulWidget {
  const _OpenAiSetupSheet({
    required this.credentialStore,
    required this.initialStatus,
    required this.onCredentialChanged,
  });

  final OpenAiCredentialStore credentialStore;
  final OpenAiCredentialStatus initialStatus;
  final Future<void> Function() onCredentialChanged;

  @override
  State<_OpenAiSetupSheet> createState() => _OpenAiSetupSheetState();
}

class _OpenAiSetupSheetState extends State<_OpenAiSetupSheet> {
  late OpenAiCredentialStatus _status = widget.initialStatus;
  final TextEditingController _credentialController = TextEditingController();
  bool _isSaving = false;
  String? _errorLabel;

  @override
  void dispose() {
    _credentialController.dispose();
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    final status = await widget.credentialStore.loadStatus();
    if (!mounted) {
      return;
    }

    setState(() => _status = status);
    await widget.onCredentialChanged();
  }

  Future<void> _saveCredential() async {
    final credential = _credentialController.text.trim();
    if (credential.isEmpty) {
      setState(() => _errorLabel = 'Enter a credential before saving.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorLabel = null;
    });

    try {
      await widget.credentialStore.saveUserProvidedCredential(credential);
      _credentialController.clear();
      await _refreshStatus();
    } on ArgumentError {
      if (mounted) {
        setState(() => _errorLabel = 'Enter a credential before saving.');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _clearCredential() async {
    setState(() {
      _isSaving = true;
      _errorLabel = null;
    });

    await widget.credentialStore.clearCredential();
    await _refreshStatus();

    if (mounted) {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final configuredAt = _status.configuredAt;

    return _SheetFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SheetHandle(),
          Row(
            children: [
              const Icon(Icons.key_rounded, color: AppColors.teal),
              const SizedBox(width: AppSpacing.sm),
              Text('OpenAI setup', style: AppTextStyles.title(textTheme)),
              const Spacer(),
              IconButton(
                tooltip: 'Close OpenAI setup',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          StatusPill(
            label: _status.displayLabel,
            accent: _status.isConfigured ? LiveAccent.teal : LiveAccent.amber,
          ),
          if (configuredAt != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Configured ${_timeLabel(configuredAt)}',
              style: AppTextStyles.compact(textTheme),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Text(
            'Realtime: ${OpenAiConfiguration.realtimeModel}  |  Fallback: '
            '${OpenAiConfiguration.translationFallbackModel}',
            style: AppTextStyles.compact(textTheme),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _credentialController,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            autofillHints: const [AutofillHints.password],
            onChanged: (_) => setState(() => _errorLabel = null),
            decoration: InputDecoration(
              labelText: 'OpenAI API key',
              helperText: 'Stored encrypted on this device only.',
              errorText: _errorLabel,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.card),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isSaving ? null : _saveCredential,
              icon: const Icon(Icons.lock_rounded),
              label: Text(
                _status.isConfigured
                    ? 'Replace encrypted credential'
                    : 'Save encrypted credential',
              ),
            ),
          ),
          if (_status.isConfigured) ...[
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isSaving ? null : _clearCredential,
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Remove credential from this device'),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          const PrivacyNote(
            label:
                'The app never displays a saved credential. It is read back only for a direct OpenAI request initiated from this phone.',
            icon: Icons.lock_outline_rounded,
          ),
        ],
      ),
    );
  }
}

class _ExportSheet extends StatefulWidget {
  const _ExportSheet({
    required this.repository,
    required this.credentialStore,
    required this.nativeShareGateway,
    required this.meetingSummaryGateway,
    required this.meeting,
    required this.onMeetingUpdated,
  });

  final LocalMeetingRepository repository;
  final OpenAiCredentialStore credentialStore;
  final NativeShareGateway nativeShareGateway;
  final MeetingSummaryGateway meetingSummaryGateway;
  final StoredMeeting? meeting;
  final Future<void> Function(StoredMeeting meeting) onMeetingUpdated;

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  ExportType _selectedType = ExportType.transcript;
  final TextEditingController _recipientController = TextEditingController();
  StoredMeeting? _meeting;
  Map<String, bool> _recipients = const {};
  bool _isLoadingRecipients = true;
  bool _isGeneratingSummary = false;
  bool _isSharing = false;
  String? _statusLabel;
  String? _errorLabel;

  @override
  void initState() {
    super.initState();
    _meeting = widget.meeting;
    unawaited(_loadRecipientPreferences());
  }

  @override
  void dispose() {
    _recipientController.dispose();
    super.dispose();
  }

  List<String> get _selectedRecipients {
    return [
      for (final entry in _recipients.entries)
        if (entry.value) entry.key,
    ];
  }

  bool get _summaryRequired => _selectedType != ExportType.transcript;

  bool get _isBusy => _isGeneratingSummary || _isSharing;

  bool get _canOpenShareSheet {
    return !_isLoadingRecipients &&
        !_isBusy &&
        _meeting != null &&
        _selectedRecipients.isNotEmpty;
  }

  Future<void> _loadRecipientPreferences() async {
    final snapshot = await widget.repository.loadSnapshot();
    final preferences = snapshot.recipientPreferences;
    final remembered = preferences.rememberedRecipients.isEmpty
        ? const ['recipient@example.com', 'assistant@example.com']
        : preferences.rememberedRecipients;
    final selected = preferences.lastSelectedRecipients.toSet();
    final defaultSelected = preferences.lastSelectedRecipients.isEmpty;

    if (!mounted) {
      return;
    }

    setState(() {
      _recipients = {
        for (var index = 0; index < remembered.length; index++)
          remembered[index]: defaultSelected
              ? index == 0
              : selected.contains(remembered[index]),
      };
      _isLoadingRecipients = false;
    });
  }

  void _addRecipient() {
    final value = _recipientController.text.trim();
    if (value.isEmpty) {
      setState(() => _errorLabel = 'Enter an email address to add.');
      return;
    }

    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) {
      setState(() => _errorLabel = 'Enter a valid email address.');
      return;
    }

    setState(() {
      _recipients = {..._recipients, value: true};
      _recipientController.clear();
      _errorLabel = null;
      _statusLabel = null;
    });
  }

  void _removeRecipient(String recipient) {
    setState(() {
      _recipients = {
        for (final entry in _recipients.entries)
          if (entry.key != recipient) entry.key: entry.value,
      };
      _statusLabel = null;
    });
  }

  Future<void> _saveRecipientPreferences() {
    return widget.repository.saveRecipientPreferences(
      RecipientPreferences(
        rememberedRecipients: _recipients.keys.toList(growable: false),
        lastSelectedRecipients: _selectedRecipients,
      ),
    );
  }

  Future<void> _openShareSheet() async {
    var meeting = _meeting;
    if (meeting == null) {
      setState(
        () => _errorLabel = 'Start or select a meeting before exporting.',
      );
      return;
    }

    final selectedRecipients = _selectedRecipients;
    if (selectedRecipients.isEmpty) {
      setState(
        () => _errorLabel = 'Select at least one recipient before exporting.',
      );
      return;
    }

    final needsSummary = _summaryRequired && !_hasFreshSummary(meeting);
    setState(() {
      _isGeneratingSummary = needsSummary;
      _isSharing = !_isGeneratingSummary;
      _errorLabel = null;
      _statusLabel = null;
    });

    try {
      await _saveRecipientPreferences();
      if (_summaryRequired && !_hasFreshSummary(meeting)) {
        final credential = await widget.credentialStore
            .readCredentialForNetworkUse();
        if (credential == null) {
          if (mounted) {
            setState(
              () => _errorLabel =
                  'OpenAI setup is required before generating a summary.',
            );
          }
          return;
        }

        final summary = await widget.meetingSummaryGateway.generate(
          request: MeetingSummaryRequest(meeting: meeting),
          credential: credential,
        );
        final updatedMeeting = await widget.repository.saveMeetingSummary(
          meetingId: meeting.id,
          summaryMetadata: summary.toMetadata(),
          updatedAt: summary.generatedAt,
        );
        if (updatedMeeting != null) {
          meeting = updatedMeeting;
          await widget.onMeetingUpdated(updatedMeeting);
          if (!mounted) {
            return;
          }

          setState(() {
            _meeting = updatedMeeting;
            _isGeneratingSummary = false;
            _isSharing = true;
            _statusLabel = 'Summary generated and stored on this device.';
          });
        }
      }

      final document = LocalMeetingExportComposer.compose(
        meeting: meeting,
        type: _selectedType,
        recipients: selectedRecipients,
      );
      final result = await widget.nativeShareGateway.shareMeetingExport(
        document,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _statusLabel = switch (result) {
          NativeShareResult.launched =>
            'Share sheet opened. Review the export before sending.',
          NativeShareResult.unavailable =>
            'No local share target is available on this device.',
        };
      });
    } on SummaryExportUnavailableException {
      if (mounted) {
        setState(
          () => _errorLabel =
              'Generate a summary before exporting this selection.',
        );
      }
    } on MeetingSummaryCredentialException {
      if (mounted) {
        setState(
          () => _errorLabel =
              'OpenAI rejected the stored credential. Update OpenAI setup and try again.',
        );
      }
    } on MeetingSummaryNetworkException {
      if (mounted) {
        setState(
          () => _errorLabel =
              'Could not reach OpenAI from this device. Try again when online.',
        );
      }
    } on MeetingSummaryMalformedResponseException {
      if (mounted) {
        setState(
          () => _errorLabel =
              'OpenAI returned an unreadable summary. Try again before exporting.',
        );
      }
    } on MeetingSummaryRequestException {
      if (mounted) {
        setState(
          () => _errorLabel =
              'OpenAI could not generate the summary for this meeting.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorLabel =
              'Could not open the local share sheet on this device.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingSummary = false;
          _isSharing = false;
        });
      }
    }
  }

  bool _hasFreshSummary(StoredMeeting meeting) {
    final summary = meeting.summaryMetadata;
    return summary.isUsable &&
        summary.modelIntent == OpenAiConfiguration.summaryModel &&
        summary.transcriptEntryCount == meeting.transcriptEntries.length;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final meeting = _meeting;

    return _SheetFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SheetHandle(),
          Row(
            children: [
              const Icon(Icons.ios_share_rounded, color: AppColors.teal),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Email export',
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.title(textTheme),
                ),
              ),
              IconButton(
                tooltip: 'Close email export',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          if (meeting == null)
            Text(
              'Start or select a meeting before exporting.',
              style: AppTextStyles.body(textTheme),
            )
          else
            Text(meeting.title, style: AppTextStyles.compact(textTheme)),
          const SizedBox(height: AppSpacing.sm),
          ExportTypeSelector(
            selected: _selectedType,
            onChanged: (type) {
              setState(() {
                _selectedType = type;
                _errorLabel = null;
                _statusLabel = null;
              });
            },
          ),
          if (_summaryRequired) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              meeting != null && _hasFreshSummary(meeting)
                  ? 'A GPT-5.5 summary is stored locally for this transcript.'
                  : 'Summary is generated by a direct OpenAI request from this device, then stored locally for review.',
              style: AppTextStyles.compact(textTheme),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Text('Recipients', style: AppTextStyles.label(textTheme)),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: _recipientController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'Add recipient',
              errorText: _errorLabel != null && _errorLabel!.contains('email')
                  ? _errorLabel
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.card),
              ),
            ),
            onSubmitted: (_) => _addRecipient(),
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton.filled(
              tooltip: 'Add recipient',
              onPressed: _addRecipient,
              icon: const Icon(Icons.add_rounded),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_isLoadingRecipients)
            Text(
              'Loading recipients...',
              style: AppTextStyles.compact(textTheme),
            )
          else if (_recipients.isEmpty)
            Text(
              'No remembered recipients yet.',
              style: AppTextStyles.compact(textTheme),
            )
          else
            for (final recipient in _recipients.keys)
              Row(
                children: [
                  Checkbox(
                    value: _recipients[recipient],
                    onChanged: (value) {
                      setState(() {
                        _recipients = {
                          ..._recipients,
                          recipient: value ?? false,
                        };
                        _statusLabel = null;
                      });
                    },
                  ),
                  Expanded(
                    child: Text(
                      recipient,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body(textTheme),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove $recipient',
                    onPressed: () => _removeRecipient(recipient),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
          if (_errorLabel != null && !_errorLabel!.contains('email')) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              _errorLabel!,
              style: AppTextStyles.compact(
                textTheme,
              ).copyWith(color: AppColors.red),
            ),
          ],
          if (_statusLabel != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              _statusLabel!,
              style: AppTextStyles.compact(
                textTheme,
              ).copyWith(color: AppColors.teal),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          PrivacyNote(
            label:
                'Exports are prepared locally and handed to the device mail or share sheet. Review before sending.',
            icon: Icons.lock_outline_rounded,
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _canOpenShareSheet ? _openShareSheet : null,
              icon: const Icon(Icons.ios_share_rounded),
              label: Text(
                _isGeneratingSummary
                    ? 'Generating summary'
                    : _isSharing
                    ? 'Opening share sheet'
                    : 'Open share sheet',
              ),
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
