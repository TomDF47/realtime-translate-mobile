import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/export/local_meeting_exporter.dart';
import 'src/language/language_support.dart';
import 'src/mock/mock_live_translate_data.dart';
import 'src/openai/openai_ai_chat.dart';
import 'src/openai/openai_configuration.dart';
import 'src/openai/openai_credential_store.dart';
import 'src/openai/openai_meeting_summary.dart';
import 'src/openai/openai_realtime_resilience.dart';
import 'src/openai/openai_realtime_translation.dart';
import 'src/session/live_session_controller.dart';
import 'src/session/microphone_capture.dart';
import 'src/session/microphone_permission.dart';
import 'src/session/realtime_translation_coordinator.dart';
import 'src/session/realtime_transcript_committer.dart';
import 'src/session/translated_audio_playback.dart';
import 'src/storage/encrypted_local_store.dart';
import 'src/storage/local_meeting_repository.dart';
import 'src/storage/local_storage_models.dart';
import 'src/theme/live_translate_theme.dart';
import 'src/ui/live_translate_components.dart';
import 'src/ui/live_translate_models.dart';

const _debugE2eHarnessEnabled =
    kDebugMode && bool.fromEnvironment('LIVE_TRANSLATE_DEBUG_E2E');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LiveTranslateApp());
}

class LiveTranslateApp extends StatelessWidget {
  const LiveTranslateApp({
    super.key,
    this.permissionGateway,
    this.meetingRepository,
    this.aiChatGateway,
    this.meetingSummaryGateway,
    this.microphoneCaptureGateway,
    this.translatedAudioPlaybackGateway,
    this.realtimeTranslationGateway,
  });

  final MicrophonePermissionGateway? permissionGateway;
  final LocalMeetingRepository? meetingRepository;
  final AiChatGateway? aiChatGateway;
  final MeetingSummaryGateway? meetingSummaryGateway;
  final MicrophoneCaptureGateway? microphoneCaptureGateway;
  final TranslatedAudioPlaybackGateway? translatedAudioPlaybackGateway;
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
        aiChatGateway: aiChatGateway,
        meetingSummaryGateway: meetingSummaryGateway,
        microphoneCaptureGateway: microphoneCaptureGateway,
        translatedAudioPlaybackGateway: translatedAudioPlaybackGateway,
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
    this.aiChatGateway,
    this.meetingSummaryGateway,
    this.microphoneCaptureGateway,
    this.translatedAudioPlaybackGateway,
    this.realtimeTranslationGateway,
  });

  final MicrophonePermissionGateway? permissionGateway;
  final LocalMeetingRepository? meetingRepository;
  final AiChatGateway? aiChatGateway;
  final MeetingSummaryGateway? meetingSummaryGateway;
  final MicrophoneCaptureGateway? microphoneCaptureGateway;
  final TranslatedAudioPlaybackGateway? translatedAudioPlaybackGateway;
  final RealtimeTranslationGateway? realtimeTranslationGateway;

  @override
  State<LiveTranslateHome> createState() => _LiveTranslateHomeState();
}

class _LiveTranslateHomeState extends State<LiveTranslateHome>
    with WidgetsBindingObserver {
  late final LiveSessionController _sessionController;
  late final LocalMeetingRepository _meetingRepository;
  late final OpenAiCredentialStore _openAiCredentialStore;
  late final AiChatGateway _aiChatGateway;
  late final MeetingSummaryGateway _meetingSummaryGateway;
  late final LiveRealtimeTranslationCoordinator _realtimeCoordinator;
  _AppSurface _surface = _AppSurface.setup;
  List<StoredMeeting> _storedMeetings = const [];
  final Set<String> _deletedMeetingIds = <String>{};
  OpenAiCredentialStatus _openAiCredentialStatus =
      const OpenAiCredentialStatus.missing();
  String? _activeMeetingId;
  String? _debugRealtimeProofStatus;
  TranslationLanguage _selectedSourceLanguage =
      LanguageSupport.autoDetectSource;
  TranslationLanguage _selectedTargetLanguage =
      LanguageSupport.realtimeTargetLanguages.first;
  bool _translateTextEnabled = true;
  bool _readAloudEnabled = true;
  Duration _recordingElapsed = Duration.zero;
  DateTime? _recordingStartedAt;
  Timer? _recordingTicker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionController = LiveSessionController(
      permissionGateway:
          widget.permissionGateway ??
          MethodChannelMicrophonePermissionGateway(),
    );
    _sessionController.addListener(_handleSessionStateChanged);
    _meetingRepository =
        widget.meetingRepository ??
        LocalMeetingRepository(store: FlutterSecureEncryptedLocalStore());
    _openAiCredentialStore = OpenAiCredentialStore(
      repository: _meetingRepository,
    );
    _aiChatGateway = widget.aiChatGateway ?? OpenAiResponsesAiChatGateway();
    _meetingSummaryGateway =
        widget.meetingSummaryGateway ?? OpenAiResponsesMeetingSummaryGateway();
    _realtimeCoordinator = LiveRealtimeTranslationCoordinator(
      sessionController: _sessionController,
      credentialStore: _openAiCredentialStore,
      captureGateway:
          widget.microphoneCaptureGateway ??
          MethodChannelMicrophoneCaptureGateway(),
      playbackGateway:
          widget.translatedAudioPlaybackGateway ??
          MethodChannelTranslatedAudioPlaybackGateway(),
      realtimeGateway:
          widget.realtimeTranslationGateway ??
          OpenAiRealtimeTranslationGateway(),
      onTranscriptCommitted: _scheduleTranscriptRefresh,
    );
    unawaited(_loadStoredMeetings());
    unawaited(_loadOpenAiCredentialStatus());
  }

  @override
  void dispose() {
    _recordingTicker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _realtimeCoordinator.dispose();
    _sessionController.removeListener(_handleSessionStateChanged);
    _sessionController.dispose();
    super.dispose();
  }

  void _handleSessionStateChanged() {
    if (!mounted) {
      return;
    }

    _syncRecordingTimer();
    setState(() {});
  }

  void _syncRecordingTimer() {
    final shouldRun = _sessionController.state.isMicrophoneCaptureOpen;
    if (shouldRun && _recordingStartedAt == null) {
      _recordingStartedAt = DateTime.now();
      _recordingTicker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() => _refreshRecordingElapsed());
        }
      });
      return;
    }

    if (!shouldRun) {
      if (_recordingStartedAt != null) {
        _refreshRecordingElapsed();
        _recordingStartedAt = null;
      }
      _cancelRecordingTicker();
    }
  }

  void _refreshRecordingElapsed() {
    final startedAt = _recordingStartedAt;
    if (startedAt == null) {
      return;
    }

    _recordingElapsed += DateTime.now().difference(startedAt);
    _recordingStartedAt = DateTime.now();
  }

  void _resetRecordingTimer() {
    _cancelRecordingTicker();
    _recordingStartedAt = null;
    _recordingElapsed = Duration.zero;
  }

  void _cancelRecordingTicker() {
    _recordingTicker?.cancel();
    _recordingTicker = null;
  }

  String _recordingElapsedLabel() {
    final elapsed = _recordingStartedAt == null
        ? _recordingElapsed
        : _recordingElapsed + DateTime.now().difference(_recordingStartedAt!);
    final totalSeconds = elapsed.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }

    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
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
    _resetRecordingTimer();
    _selectedSourceLanguage = LanguageSupport.autoDetectSource;
    _selectedTargetLanguage = LanguageSupport.languageByCode('en');
    final meetingId = 'meeting-${DateTime.now().microsecondsSinceEpoch}';
    _activeMeetingId = meetingId;
    setState(() => _surface = _AppSurface.listening);
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
      if (_shouldKeepRecoveryMeetingVisible(_sessionController.state)) {
        setState(() => _surface = _AppSurface.listening);
        return;
      }
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

  bool _shouldKeepRecoveryMeetingVisible(LiveSessionState state) {
    return switch (state.phase) {
      LiveSessionPhase.reconnecting ||
      LiveSessionPhase.offline ||
      LiveSessionPhase.error => true,
      _ => false,
    };
  }

  Future<bool> _startRealtimeForSession(
    LiveSessionViewData _, {
    String? meetingId,
  }) async {
    _realtimeCoordinator.setRuntimeOutputOptions(
      translationOutputEnabled: _translateTextEnabled,
      readAloudOutputEnabled: _readAloudEnabled,
    );
    const sourceLanguageCode = 'auto';
    final targetLanguageCode = _selectedTargetLanguage.code;
    final result = await _realtimeCoordinator.start(
      config: _realtimeConfigForTarget(targetLanguageCode),
      transcriptCommitTarget: meetingId == null
          ? null
          : LiveRealtimeTranscriptCommitTarget(
              repository: _meetingRepository,
              meetingId: meetingId,
              sourceLanguageCode: sourceLanguageCode,
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

    setState(() {
      _storedMeetings = _deletedMeetingIds.isEmpty
          ? snapshot.meetings
          : [
              for (final meeting in snapshot.meetings)
                if (!_deletedMeetingIds.contains(meeting.id)) meeting,
            ];
    });
  }

  bool _transcriptRefreshScheduled = false;
  bool _transcriptRefreshDirty = false;

  void _scheduleTranscriptRefresh() {
    if (_activeMeetingId == null || !mounted) {
      return;
    }

    if (_transcriptRefreshScheduled) {
      _transcriptRefreshDirty = true;
      return;
    }

    _transcriptRefreshScheduled = true;
    unawaited(_refreshTranscriptsAfterCommit());
  }

  Future<void> _refreshTranscriptsAfterCommit() async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    try {
      while (mounted && _activeMeetingId != null) {
        _transcriptRefreshDirty = false;
        await _loadStoredMeetings();
        if (!_transcriptRefreshDirty) {
          break;
        }
        await Future<void>.delayed(Duration.zero);
      }
    } finally {
      _transcriptRefreshScheduled = false;
      if (_transcriptRefreshDirty && _activeMeetingId != null && mounted) {
        _transcriptRefreshDirty = false;
        _scheduleTranscriptRefresh();
      }
    }
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
            ? 'Live read-aloud meeting'
            : 'Live translation meeting',
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

  OpenAiRealtimeTranslationConfig _realtimeConfigForTarget(
    String targetLanguageCode,
  ) {
    return OpenAiRealtimeTranslationConfig(
      sourceLanguageCode: 'auto',
      targetLanguageCode: targetLanguageCode,
      profile: _profileForLiveInterpretation(targetLanguageCode),
      translationOutputEnabled: _translateTextEnabled,
      readAloudOutputEnabled: _readAloudEnabled,
    );
  }

  OpenAiRealtimeTranslationProfile _profileForLiveInterpretation(
    String targetLanguageCode,
  ) {
    try {
      final target = LanguageSupport.languageByCode(targetLanguageCode);
      if (target.supportsRealtimeTarget) {
        return OpenAiRealtimeTranslationProfile.dedicatedTranslation;
      }
    } on ArgumentError {
      return OpenAiRealtimeTranslationProfile.dedicatedTranslation;
    }

    return OpenAiRealtimeTranslationProfile.dedicatedTranslation;
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
    final selectedSession = _applyLiveControls(base);
    if (meeting == null) {
      return selectedSession;
    }

    return _applyLiveControls(
      _sessionFromStoredMeeting(meeting: meeting, base: base),
    );
  }

  LiveSessionViewData _applyLiveControls(LiveSessionViewData base) {
    final source = _selectorForLanguage(
      LanguageSupport.autoDetectSource,
      fallback: base.fromLanguage,
      isTarget: false,
    );
    final target = _selectorForLanguage(
      _selectedTargetLanguage,
      fallback: base.toLanguage,
      isTarget: true,
    );
    return base.copyWith(
      routeLabel:
          '${_routeEndpointLabel(_languageLabel(source))} -> '
          '${_routeEndpointLabel(_languageLabel(target))}',
      elapsedLabel: _recordingElapsedLabel(),
      fromLanguage: source,
      toLanguage: target,
      features: _featuresForSession(base),
      bottomControls: _bottomControlsForSession(base),
      statusLabel: _liveStatusLabel(base.mode),
      statusAccent: _liveStatusAccent(base.mode),
    );
  }

  String? _liveStatusLabel(LiveSessionMode fallbackMode) {
    return switch (_sessionController.state.phase) {
      LiveSessionPhase.requestingMicrophonePermission => 'Mic permission',
      LiveSessionPhase.connecting => 'Connecting',
      LiveSessionPhase.reconnecting => 'Reconnecting',
      LiveSessionPhase.offline => 'Offline',
      LiveSessionPhase.error => 'Needs attention',
      LiveSessionPhase.listening => 'Listening',
      LiveSessionPhase.speaking => 'Speaking',
      LiveSessionPhase.readAloudPaused => fallbackMode.statusLabel,
      _ => fallbackMode.statusLabel,
    };
  }

  LiveAccent? _liveStatusAccent(LiveSessionMode fallbackMode) {
    return switch (_sessionController.state.phase) {
      LiveSessionPhase.requestingMicrophonePermission ||
      LiveSessionPhase.connecting ||
      LiveSessionPhase.reconnecting => LiveAccent.amber,
      LiveSessionPhase.offline || LiveSessionPhase.error => LiveAccent.red,
      LiveSessionPhase.listening => LiveAccent.teal,
      LiveSessionPhase.speaking ||
      LiveSessionPhase.readAloudPaused => LiveAccent.amber,
      _ => fallbackMode.accent,
    };
  }

  LanguageSelectorData _selectorForLanguage(
    TranslationLanguage language, {
    required LanguageSelectorData fallback,
    required bool isTarget,
  }) {
    return LanguageSelectorData(
      eyebrow: isTarget ? 'To' : 'From',
      primaryLabel: language.name,
      secondaryLabel: language.code == 'auto'
          ? fallback.secondaryLabel
          : language.regionLabel,
      icon: fallback.icon,
      accent: fallback.accent,
    );
  }

  List<FeatureChipData> _featuresForSession(LiveSessionViewData base) {
    return [
      for (final feature in base.features)
        if (feature.label == 'Translate Text')
          FeatureChipData(
            label: feature.label,
            icon: feature.icon,
            accent: feature.accent,
            isEnabled: _translateTextEnabled,
          )
        else if (feature.label == 'Read Aloud')
          FeatureChipData(
            label: feature.label,
            icon: feature.icon,
            accent: feature.accent,
            isEnabled: _readAloudEnabled,
          )
        else
          feature,
    ];
  }

  List<BottomControlActionData> _bottomControlsForSession(
    LiveSessionViewData base,
  ) {
    return [
      for (final control in base.bottomControls)
        if (control.label == 'Pause Read Aloud' && !_readAloudEnabled)
          const BottomControlActionData(
            label: 'Resume Read Aloud',
            icon: Icons.play_arrow_rounded,
            accent: LiveAccent.amber,
            semanticLabel: 'Resume read aloud',
          )
        else if (control.label == 'Switch Direction')
          BottomControlActionData(
            label: control.label,
            icon: control.icon,
            accent: control.accent,
            semanticLabel:
                'Switch translation direction disabled in live translation',
            isEnabled: false,
          )
        else
          control,
    ];
  }

  Future<void> _appendContinuationToMeeting({
    required StoredMeeting meeting,
    required LiveSessionViewData session,
  }) async {
    final sourceEntries = session.transcriptEntries;
    final now = _nextActivityTimestamp(meeting.updatedAt);
    if (sourceEntries.isEmpty) {
      await _meetingRepository.touchMeeting(
        meetingId: meeting.id,
        updatedAt: now,
      );
      await _loadStoredMeetings();
      return;
    }

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

  DateTime _nextActivityTimestamp(DateTime previous) {
    final now = DateTime.now().toUtc();
    return now.isAfter(previous)
        ? now
        : previous.add(const Duration(microseconds: 1));
  }

  Future<void> _continueMeeting(StoredMeeting meeting) async {
    final nextSurface = _surfaceForMeeting(meeting);
    final session = _baseSessionForSurface(nextSurface);
    _activeMeetingId = meeting.id;
    _selectedSourceLanguage = LanguageSupport.autoDetectSource;
    _selectedTargetLanguage = _languageFromStoredLabel(
      meeting.targetLanguageLabel,
      fallback: _selectedTargetLanguage,
    );
    _resetRecordingTimer();
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

  TranslationLanguage _languageFromStoredLabel(
    String label, {
    required TranslationLanguage fallback,
  }) {
    final normalized = label.toLowerCase();
    for (final language in LanguageSupport.languages) {
      if (normalized.contains(language.name.toLowerCase())) {
        return language;
      }
    }

    return fallback;
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
    _selectedSourceLanguage = LanguageSupport.autoDetectSource;
    setState(() => _surface = _AppSurface.listening);
  }

  void _openSpeakingPaused() {
    unawaited(_openSpeakingPausedAfterPermission());
  }

  Future<void> _openSpeakingPausedAfterPermission() async {
    final amberTarget = LanguageSupport.languageByCode('ja');
    final shouldUpdateTarget = _selectedTargetLanguage.code != amberTarget.code;
    if (shouldUpdateTarget) {
      _selectedTargetLanguage = amberTarget;
      await _persistActiveRouteAndRestart();
      if (!mounted) {
        return;
      }
    }

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
    _selectedSourceLanguage = LanguageSupport.autoDetectSource;
    setState(() => _surface = _AppSurface.speakingPaused);
  }

  void _openSetup() {
    unawaited(_realtimeCoordinator.stop());
    _activeMeetingId = null;
    _resetRecordingTimer();
    setState(() => _surface = _AppSurface.setup);
  }

  void _handleBottomAction(BottomControlActionData action) {
    if (action.label == 'Stop Listening') {
      _openSetup();
      return;
    }

    if (action.label == 'Switch Direction') {
      return;
    }

    if (action.label == 'Pause Read Aloud') {
      _setReadAloudEnabled(false);
      return;
    }

    if (action.label == 'Resume Read Aloud') {
      _setReadAloudEnabled(true);
      _openListening();
    }
  }

  void _toggleFeature(String label) {
    if (label == 'Translate Text') {
      _setTranslateTextEnabled(!_translateTextEnabled);
    } else if (label == 'Read Aloud') {
      _setReadAloudEnabled(!_readAloudEnabled);
    }
  }

  void _setTranslateTextEnabled(bool enabled) {
    if (_translateTextEnabled == enabled) {
      return;
    }

    setState(() => _translateTextEnabled = enabled);
    _realtimeCoordinator.setRuntimeOutputOptions(
      translationOutputEnabled: _translateTextEnabled,
      readAloudOutputEnabled: _readAloudEnabled,
    );
    unawaited(_restartRealtimeIfActive());
  }

  void _setReadAloudEnabled(bool enabled) {
    if (_readAloudEnabled == enabled) {
      return;
    }

    setState(() => _readAloudEnabled = enabled);
    _realtimeCoordinator.setRuntimeOutputOptions(
      translationOutputEnabled: _translateTextEnabled,
      readAloudOutputEnabled: _readAloudEnabled,
    );
    if (enabled) {
      unawaited(_restartRealtimeIfActive());
    } else {
      unawaited(_realtimeCoordinator.pauseReadAloudOutput());
      _sessionController.enterSpeakingPaused();
      setState(() => _surface = _AppSurface.speakingPaused);
    }
  }

  Future<void> _selectLanguage(
    TranslationLanguage language, {
    required bool isTarget,
  }) async {
    if (!isTarget) {
      return;
    }

    setState(() {
      _selectedTargetLanguage = language;
    });
    await _persistActiveRouteAndRestart();
  }

  Future<void> _persistActiveRouteAndRestart() async {
    final activeMeeting = _activeMeeting;
    if (activeMeeting != null) {
      await _meetingRepository.upsertMeeting(
        activeMeeting.copyWith(
          sourceLanguageLabel: _languageLabel(
            _selectorForLanguage(
              LanguageSupport.autoDetectSource,
              fallback: MockLiveTranslateData.listeningSession.fromLanguage,
              isTarget: false,
            ),
          ),
          targetLanguageLabel: _languageLabel(
            _selectorForLanguage(
              _selectedTargetLanguage,
              fallback: MockLiveTranslateData.listeningSession.toLanguage,
              isTarget: true,
            ),
          ),
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      await _loadStoredMeetings();
    }
    await _restartRealtimeIfActive();
  }

  Future<void> _restartRealtimeIfActive() async {
    final meetingId = _activeMeetingId;
    if (meetingId == null) {
      return;
    }

    await _startRealtimeForSelectedRoute(meetingId: meetingId);
  }

  Future<void> _startRealtimeForSelectedRoute({
    required String meetingId,
  }) async {
    final targetLanguageCode = _selectedTargetLanguage.code;
    _realtimeCoordinator.setRuntimeOutputOptions(
      translationOutputEnabled: _translateTextEnabled,
      readAloudOutputEnabled: _readAloudEnabled,
    );
    await _realtimeCoordinator.start(
      config: OpenAiRealtimeTranslationConfig(
        sourceLanguageCode: 'auto',
        targetLanguageCode: targetLanguageCode,
        profile: _profileForLiveInterpretation(targetLanguageCode),
        translationOutputEnabled: _translateTextEnabled,
        readAloudOutputEnabled: _readAloudEnabled,
      ),
      transcriptCommitTarget: LiveRealtimeTranscriptCommitTarget(
        repository: _meetingRepository,
        meetingId: meetingId,
        sourceLanguageCode: 'auto',
        targetLanguageCode: targetLanguageCode,
        now: DateTime.now,
      ),
    );
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
        onOpenGeneratedExports: () {
          Navigator.of(context).pop();
          _showGeneratedExportsSheet();
        },
        onResumeAmberMeeting: () async {
          await _openSpeakingPausedAfterPermission();
          if (context.mounted) {
            Navigator.of(context).pop();
          }
        },
      ),
    );
  }

  void _showMeetingHistory() {
    var visibleMeetings = List<StoredMeeting>.of(_storedMeetings);
    String? statusLabel;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return _MeetingHistorySheet(
              meetings: visibleMeetings,
              statusLabel: statusLabel,
              onOpenAllMeetingsAssistant: () {
                Navigator.of(context).pop();
                _showAssistantSheet(AiChatScope.allMeetings);
              },
              onOpenMeeting: (meeting) {
                Navigator.of(context).pop();
                unawaited(_continueMeeting(meeting));
              },
              onDeleteMeeting: (meeting) async {
                void markMeetingDeleted() {
                  if (!context.mounted) {
                    return;
                  }
                  setSheetState(() {
                    visibleMeetings = [
                      for (final item in visibleMeetings)
                        if (item.id != meeting.id) item,
                    ];
                    statusLabel = 'Meeting deleted.';
                  });
                }

                await _deleteMeetingFromHistory(
                  meeting,
                  onDeleteStarted: markMeetingDeleted,
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _deleteMeetingFromHistory(
    StoredMeeting meeting, {
    VoidCallback? onDeleteStarted,
  }) async {
    final wasActiveMeeting = _activeMeetingId == meeting.id;
    _deletedMeetingIds.add(meeting.id);
    Future<void>? activeTeardownFuture;
    if (wasActiveMeeting) {
      _activeMeetingId = null;
      _transcriptRefreshDirty = false;
      _resetRecordingTimer();
      activeTeardownFuture = _realtimeCoordinator.discardActiveSession();
    }
    if (mounted) {
      setState(() {
        _storedMeetings = [
          for (final item in _storedMeetings)
            if (item.id != meeting.id) item,
        ];
        if (wasActiveMeeting) {
          _surface = _AppSurface.setup;
        }
      });
    }
    onDeleteStarted?.call();

    final deleteMeetingFuture = _meetingRepository.deleteMeeting(meeting.id);
    if (wasActiveMeeting) {
      await Future.wait<void>([activeTeardownFuture!, deleteMeetingFuture]);
    } else {
      await deleteMeetingFuture;
    }

    if (!mounted) {
      return;
    }

    await _loadStoredMeetings();
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Meeting deleted.')));
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
        meeting: _activeMeeting,
        onGenerateExport: _queueGeneratedExport,
        onOpenGeneratedExports: _showGeneratedExportsSheet,
      ),
    );
  }

  void _queueGeneratedExport(ExportType type) {
    final meeting = _activeMeeting;
    if (meeting == null) {
      _showExportSnackBar('Start or select a meeting before generating.');
      return;
    }

    _showExportSnackBar('Generating export in the background.');
    unawaited(_generateExportInBackground(meetingId: meeting.id, type: type));
  }

  Future<void> _generateExportInBackground({
    required String meetingId,
    required ExportType type,
  }) async {
    try {
      var meeting = await _loadMeetingById(meetingId);
      if (meeting == null) {
        _showExportSnackBar('Meeting is no longer available.');
        return;
      }

      if (type != ExportType.transcript && !_hasFreshStoredSummary(meeting)) {
        final credential = await _openAiCredentialStore
            .readCredentialForNetworkUse();
        if (credential == null) {
          _showExportSnackBar(
            'OpenAI setup is required before generating this export.',
          );
          return;
        }

        final summary = await _meetingSummaryGateway.generate(
          request: MeetingSummaryRequest(meeting: meeting),
          credential: credential,
        );
        final updatedMeeting = await _meetingRepository.saveMeetingSummary(
          meetingId: meeting.id,
          summaryMetadata: summary.toMetadata(),
          updatedAt: summary.generatedAt,
        );
        if (updatedMeeting != null) {
          meeting = updatedMeeting;
        }
      }

      final document = LocalMeetingExportComposer.compose(
        meeting: meeting,
        type: type,
        recipients: const [],
      );
      final now = DateTime.now().toUtc();
      final generatedExport = StoredGeneratedExport(
        id: 'export-${now.microsecondsSinceEpoch}',
        meetingId: meeting.id,
        type: type.name,
        subject: document.subject,
        body: document.body,
        createdAt: now,
        transcriptEntryCount: meeting.transcriptEntries.length,
      );
      final updatedMeeting = await _meetingRepository.saveGeneratedExport(
        meetingId: meeting.id,
        generatedExport: generatedExport,
        updatedAt: now,
      );
      if (updatedMeeting != null && _activeMeetingId == meeting.id) {
        _activeMeetingId = meeting.id;
      }
      await _loadStoredMeetings();
      _showGeneratedExportReady(generatedExport);
    } on SummaryExportUnavailableException {
      _showExportSnackBar(
        'Generate a summary before exporting this selection.',
      );
    } on MeetingSummaryCredentialException {
      _showExportSnackBar(
        'OpenAI rejected the stored credential. Update OpenAI setup.',
      );
    } on MeetingSummaryNetworkException {
      _showExportSnackBar(
        'Could not reach OpenAI from this device. Try again when online.',
      );
    } on MeetingSummaryMalformedResponseException {
      _showExportSnackBar('OpenAI returned an unreadable summary. Try again.');
    } on MeetingSummaryRequestException {
      _showExportSnackBar(
        'OpenAI could not generate the summary for this meeting.',
      );
    } catch (_) {
      _showExportSnackBar('Could not generate the export on this device.');
    }
  }

  Future<StoredMeeting?> _loadMeetingById(String meetingId) async {
    final snapshot = await _meetingRepository.loadSnapshot();
    return _meetingById(snapshot.meetings, meetingId);
  }

  void _showGeneratedExportReady(StoredGeneratedExport generatedExport) {
    _showExportSnackBar(
      'Generated export is ready.',
      actionLabel: 'Open',
      onAction: () => _showGeneratedExportDetail(generatedExport),
    );
  }

  void _showExportSnackBar(
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        action: actionLabel == null || onAction == null
            ? null
            : SnackBarAction(label: actionLabel, onPressed: onAction),
      ),
    );
  }

  void _jumpToLive() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Jumped to latest transcript.')),
    );
  }

  List<_GeneratedExportListItem> _generatedExportItems() {
    final items = <_GeneratedExportListItem>[
      for (final meeting in _storedMeetings)
        for (final generatedExport in meeting.generatedExports)
          _GeneratedExportListItem(
            meetingTitle: meeting.title,
            generatedExport: generatedExport,
          ),
    ];
    items.sort(
      (a, b) =>
          b.generatedExport.createdAt.compareTo(a.generatedExport.createdAt),
    );
    return items;
  }

  void _showGeneratedExportsSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _GeneratedExportsSheet(
        items: _generatedExportItems(),
        onOpenExport: (item) {
          Navigator.of(context).pop();
          _showGeneratedExportDetail(item.generatedExport);
        },
      ),
    );
  }

  void _showGeneratedExportDetail(StoredGeneratedExport generatedExport) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _GeneratedExportDetailSheet(
        generatedExport: generatedExport,
        onCopy: () async {
          await Clipboard.setData(ClipboardData(text: generatedExport.body));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Generated export copied.')),
            );
          }
        },
      ),
    );
  }

  void _showLanguageOptionsSheet({required bool isTarget}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _LanguageOptionsSheet(
        isTarget: isTarget,
        selectedLanguage: isTarget
            ? _selectedTargetLanguage
            : _selectedSourceLanguage,
        onSelected: (language) async {
          await _selectLanguage(language, isTarget: isTarget);
          if (context.mounted) {
            Navigator.of(context).pop();
          }
        },
      ),
    );
  }

  Future<void> _runDebugRealtimeProof() async {
    if (!_debugE2eHarnessEnabled) {
      return;
    }

    final meetingId = _activeMeetingId;
    if (meetingId == null) {
      setState(() => _debugRealtimeProofStatus = 'Debug realtime proof failed');
      return;
    }

    final beforeSnapshot = await _meetingRepository.loadSnapshot();
    final beforeRealtimeRows = _realtimeRowCount(beforeSnapshot, meetingId);
    if (!mounted) {
      return;
    }

    setState(() => _debugRealtimeProofStatus = 'Debug realtime proof running');
    try {
      final result = await _realtimeCoordinator
          .debugInjectGeneratedSpeechStyleReconnectProof();
      final afterSnapshot = await _meetingRepository.loadSnapshot();
      final afterRealtimeRows = _realtimeRowCount(afterSnapshot, meetingId);
      if (!mounted) {
        return;
      }

      final newRealtimeRows = afterRealtimeRows - beforeRealtimeRows;
      final passed =
          newRealtimeRows == 1 &&
          result.playbackChunkCount == 1 &&
          result.simulatedReconnectCount == 1;
      setState(() {
        _debugRealtimeProofStatus = passed
            ? 'Debug realtime proof passed: 1 realtime row, 1 audio chunk'
            : 'Debug realtime proof failed';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _debugRealtimeProofStatus = 'Debug realtime proof failed');
    }
  }

  int _realtimeRowCount(LocalStorageSnapshot snapshot, String meetingId) {
    for (final meeting in snapshot.meetings) {
      if (meeting.id == meetingId) {
        return meeting.transcriptEntries
            .where((entry) => entry.id.contains('-realtime-'))
            .length;
      }
    }

    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final sessionState = _sessionController.state;
    if (_activeMeetingId == null &&
        (sessionState.phase ==
                LiveSessionPhase.requestingMicrophonePermission ||
            sessionState.phase == LiveSessionPhase.connecting)) {
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
        sessionState: sessionState,
        onOpenMenu: _showMeetingMenu,
        onOpenAssistant: () => _showAssistantSheet(AiChatScope.thisMeeting),
        onOpenSourceLanguageOptions: null,
        onOpenTargetLanguageOptions: () =>
            _showLanguageOptionsSheet(isTarget: true),
        onDirectionSwitch: null,
        onRetryLiveSession: _openListening,
        onBottomAction: _handleBottomAction,
        onFeatureToggle: _toggleFeature,
        onQueuePrimaryAction: () => _setReadAloudEnabled(true),
        onQueueSecondaryAction: _skipQueuedReadAloudToLive,
        onJumpToLive: _jumpToLive,
        debugHarness: _debugE2eHarnessEnabled
            ? DebugRealtimeProofPanel(
                status: _debugRealtimeProofStatus,
                onRun: _runDebugRealtimeProof,
              )
            : null,
      ),
      _AppSurface.speakingPaused => LiveSessionScreen(
        session: _sessionForSurface(_AppSurface.speakingPaused),
        sessionState: sessionState,
        onOpenMenu: _showMeetingMenu,
        onOpenAssistant: () => _showAssistantSheet(AiChatScope.thisMeeting),
        onOpenSourceLanguageOptions: null,
        onOpenTargetLanguageOptions: () =>
            _showLanguageOptionsSheet(isTarget: true),
        onDirectionSwitch: null,
        onRetryLiveSession: _openSpeakingPaused,
        onBottomAction: _handleBottomAction,
        onFeatureToggle: _toggleFeature,
        onQueuePrimaryAction: () => _setReadAloudEnabled(true),
        onQueueSecondaryAction: _skipQueuedReadAloudToLive,
        onJumpToLive: _jumpToLive,
        debugHarness: _debugE2eHarnessEnabled
            ? DebugRealtimeProofPanel(
                status: _debugRealtimeProofStatus,
                onRun: _runDebugRealtimeProof,
              )
            : null,
      ),
    };
  }

  void _skipQueuedReadAloudToLive() {
    if (!_readAloudEnabled) {
      setState(() => _readAloudEnabled = true);
    }
    _realtimeCoordinator.setRuntimeOutputOptions(
      translationOutputEnabled: _translateTextEnabled,
      readAloudOutputEnabled: true,
    );
    unawaited(_restartRealtimeIfActive());
    _sessionController.resumeListening();
    setState(() => _surface = _AppSurface.listening);
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
                    child: FooterBranding(),
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
        const XenovisLogo(),
        const SizedBox(height: AppSpacing.xl),
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
    required this.sessionState,
    required this.onOpenMenu,
    required this.onOpenAssistant,
    required this.onOpenSourceLanguageOptions,
    required this.onOpenTargetLanguageOptions,
    required this.onDirectionSwitch,
    required this.onRetryLiveSession,
    required this.onBottomAction,
    required this.onFeatureToggle,
    required this.onQueuePrimaryAction,
    required this.onQueueSecondaryAction,
    required this.onJumpToLive,
    this.debugHarness,
  });

  final LiveSessionViewData session;
  final LiveSessionState sessionState;
  final VoidCallback onOpenMenu;
  final VoidCallback onOpenAssistant;
  final VoidCallback? onOpenSourceLanguageOptions;
  final VoidCallback onOpenTargetLanguageOptions;
  final VoidCallback? onDirectionSwitch;
  final VoidCallback onRetryLiveSession;
  final ValueChanged<BottomControlActionData> onBottomAction;
  final ValueChanged<String> onFeatureToggle;
  final VoidCallback onQueuePrimaryAction;
  final VoidCallback onQueueSecondaryAction;
  final VoidCallback onJumpToLive;
  final Widget? debugHarness;

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
          if (_RealtimeRecoveryBanner.shouldShow(sessionState)) ...[
            const SizedBox(height: AppSpacing.xs),
            _RealtimeRecoveryBanner(
              state: sessionState,
              onRetry: onRetryLiveSession,
              onBack: () => onBottomAction(session.bottomControls.first),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          _LanguageRouteRow(
            session: session,
            onDirectionSwitch: onDirectionSwitch,
            onOpenSourceLanguageOptions: onOpenSourceLanguageOptions,
            onOpenTargetLanguageOptions: onOpenTargetLanguageOptions,
          ),
          const SizedBox(height: AppSpacing.xs),
          _FeatureRow(features: session.features, onToggle: onFeatureToggle),
          if (debugHarness != null) ...[
            const SizedBox(height: AppSpacing.xs),
            debugHarness!,
          ],
          if (session.queueBanner != null) ...[
            const SizedBox(height: AppSpacing.xs),
            QueueBanner(
              data: session.queueBanner!,
              onPrimaryPressed: onQueuePrimaryAction,
              onSecondaryPressed: onQueueSecondaryAction,
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
                      onPressed: onJumpToLive,
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

class _RealtimeRecoveryBanner extends StatelessWidget {
  const _RealtimeRecoveryBanner({
    required this.state,
    required this.onRetry,
    required this.onBack,
  });

  final LiveSessionState state;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  static bool shouldShow(LiveSessionState state) {
    return switch (state.phase) {
      LiveSessionPhase.reconnecting ||
      LiveSessionPhase.offline ||
      LiveSessionPhase.error => true,
      _ => false,
    };
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final accent = state.phase == LiveSessionPhase.error
        ? LiveAccent.red
        : LiveAccent.amber;
    final accentColor = AppColors.forAccent(accent);

    return Semantics(
      container: true,
      liveRegion: true,
      label: _title,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(color: accentColor.withValues(alpha: 0.72)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_icon, color: accentColor),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    _title,
                    style: AppTextStyles.label(
                      textTheme,
                    ).copyWith(color: accentColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              state.notice ?? _fallbackNotice,
              style: AppTextStyles.body(textTheme),
            ),
            if (_retryDetail != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                _retryDetail!,
                style: AppTextStyles.compact(
                  textTheme,
                ).copyWith(color: AppColors.textSecondary),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                if (_showRetryAction)
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry live session'),
                  ),
                OutlinedButton.icon(
                  onPressed: onBack,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Back to start'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData get _icon {
    return switch (state.phase) {
      LiveSessionPhase.reconnecting => Icons.sync_rounded,
      LiveSessionPhase.offline => Icons.wifi_off_rounded,
      LiveSessionPhase.error => Icons.error_outline_rounded,
      _ => Icons.info_outline_rounded,
    };
  }

  String get _title {
    return switch (state.phase) {
      LiveSessionPhase.reconnecting => 'Reconnecting to OpenAI',
      LiveSessionPhase.offline => 'Live translation paused',
      LiveSessionPhase.error =>
        state.realtimeRecoveryAction ==
                OpenAiRealtimeRecoveryAction.unsupportedLanguage
            ? 'Language not supported'
            : state.realtimeFailureKind == OpenAiRealtimeFailureKind.rateLimited
            ? 'OpenAI rate limit reached'
            : state.realtimeFailureKind ==
                  OpenAiRealtimeFailureKind.transientOpenAiError
            ? 'OpenAI temporarily unavailable'
            : 'Live translation stopped',
      _ => 'Live translation needs attention',
    };
  }

  String get _fallbackNotice {
    return switch (state.phase) {
      LiveSessionPhase.reconnecting =>
        'Connection interrupted. Reconnecting to OpenAI shortly.',
      LiveSessionPhase.offline =>
        'Network connection appears offline. Live translation is paused.',
      LiveSessionPhase.error =>
        state.realtimeRecoveryAction ==
                OpenAiRealtimeRecoveryAction.unsupportedLanguage
            ? 'This target language is not available for realtime output. Choose another target language.'
            : state.realtimeFailureKind == OpenAiRealtimeFailureKind.rateLimited
            ? 'OpenAI rate limits persisted after retries. Restart when quota is available.'
            : state.realtimeFailureKind ==
                  OpenAiRealtimeFailureKind.transientOpenAiError
            ? 'OpenAI realtime remained unavailable after retries. Restart when ready.'
            : 'OpenAI realtime session stopped. Restart the meeting when ready.',
      _ => 'Live translation needs attention.',
    };
  }

  String? get _retryDetail {
    if (state.phase == LiveSessionPhase.reconnecting) {
      final seconds = state.realtimeReconnectDelay.inMilliseconds / 1000;
      return 'Retry attempt ${state.realtimeRetryAttempt}; next retry in ${seconds.toStringAsFixed(1)}s.';
    }

    if (state.phase == LiveSessionPhase.offline &&
        state.realtimeRetryAttempt > 0) {
      return 'Retries exhausted after ${state.realtimeRetryAttempt} attempts.';
    }

    return null;
  }

  bool get _showRetryAction {
    if (state.phase == LiveSessionPhase.reconnecting) {
      return false;
    }

    if (state.realtimeRecoveryAction ==
        OpenAiRealtimeRecoveryAction.unsupportedLanguage) {
      return false;
    }

    return true;
  }
}

class DebugRealtimeProofPanel extends StatelessWidget {
  const DebugRealtimeProofPanel({
    super.key,
    required this.status,
    required this.onRun,
  });

  final String? status;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Debug realtime proof panel',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                status ?? 'Debug realtime proof idle',
                style: AppTextStyles.compact(Theme.of(context).textTheme),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: onRun,
              icon: const Icon(Icons.science_rounded, size: 16),
              label: const Text('Run debug realtime proof'),
            ),
          ],
        ),
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
  final VoidCallback? onDirectionSwitch;
  final VoidCallback? onOpenSourceLanguageOptions;
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
  const _FeatureRow({required this.features, required this.onToggle});

  final List<FeatureChipData> features;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var index = 0; index < features.length; index++) ...[
          Expanded(
            child: FeatureChip(
              data: features[index],
              onTap: features[index].isPassive
                  ? null
                  : () => onToggle(features[index].label),
            ),
          ),
          if (index < features.length - 1) const SizedBox(width: AppSpacing.xs),
        ],
      ],
    );
  }
}

class _LanguageOptionsSheet extends StatelessWidget {
  const _LanguageOptionsSheet({
    required this.isTarget,
    required this.selectedLanguage,
    required this.onSelected,
  });

  final bool isTarget;
  final TranslationLanguage selectedLanguage;
  final Future<void> Function(TranslationLanguage language) onSelected;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final languages = isTarget
        ? LanguageSupport.targetLanguages
        : LanguageSupport.sourceLanguages;

    return _SheetFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SheetHandle(),
          Text(
            isTarget ? 'Target languages' : 'Source languages',
            style: AppTextStyles.title(textTheme),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            isTarget
                ? 'All app target languages are listed. Realtime-supported targets are marked separately from direct OpenAI fallback targets.'
                : 'Source speech can use auto-detect or a known local language preference.',
            style: AppTextStyles.body(textTheme),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final language in languages)
            _LanguageOptionRow(
              language: language,
              statusLabel: isTarget
                  ? language.supportsRealtimeTarget
                        ? 'Realtime output'
                        : 'Direct OpenAI fallback target'
                  : 'Source input',
              isSelected: language.code == selectedLanguage.code,
              onTap: () => onSelected(language),
            ),
          if (isTarget) ...[
            const SizedBox(height: AppSpacing.sm),
            const Divider(color: AppColors.border),
            const SizedBox(height: AppSpacing.sm),
            Text('Fallback route', style: AppTextStyles.label(textTheme)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Broader targets are selectable, but the app still labels them '
              'against the realtime translation constraints before starting.',
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
  const _LanguageOptionRow({
    required this.language,
    required this.statusLabel,
    required this.isSelected,
    required this.onTap,
  });

  final TranslationLanguage language;
  final String statusLabel;
  final bool isSelected;
  final Future<void> Function() onTap;

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
      trailing: isSelected
          ? const Icon(Icons.check_circle_rounded, color: AppColors.teal)
          : const Icon(Icons.chevron_right_rounded),
      onTap: () async {
        await onTap();
      },
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
    final activeMeetingId = widget.activeMeeting?.id;
    final activeMeeting = activeMeetingId == null
        ? null
        : _meetingById(snapshot.meetings, activeMeetingId);
    final context = AiChatContextBuilder.fromSnapshot(
      scope: widget.scope,
      snapshot: snapshot,
      activeMeeting: activeMeeting ?? widget.activeMeeting,
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

  void _recordFeedback(bool helpful) {
    setState(() {
      _statusLabel = helpful
          ? 'Feedback saved for this answer.'
          : 'Feedback saved. The answer can be regenerated.';
      _errorLabel = null;
    });
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
                    onPressed: () => _recordFeedback(true),
                    icon: const Icon(Icons.thumb_up_alt_outlined),
                  ),
                  IconButton(
                    tooltip: 'Not helpful',
                    onPressed: () => _recordFeedback(false),
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

StoredMeeting? _meetingById(List<StoredMeeting> meetings, String meetingId) {
  for (final meeting in meetings) {
    if (meeting.id == meetingId) {
      return meeting;
    }
  }

  return null;
}

bool _hasFreshStoredSummary(StoredMeeting meeting) {
  final summary = meeting.summaryMetadata;
  return summary.isUsable &&
      summary.modelIntent == OpenAiConfiguration.summaryModel &&
      summary.transcriptEntryCount == meeting.transcriptEntries.length;
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
    required this.onOpenGeneratedExports,
    required this.onResumeAmberMeeting,
  });

  final VoidCallback onOpenHistory;
  final VoidCallback onExport;
  final VoidCallback onOpenGeneratedExports;
  final Future<void> Function() onResumeAmberMeeting;

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
            label: 'Generate export',
            onTap: onExport,
          ),
          _SheetAction(
            icon: Icons.folder_copy_outlined,
            label: 'Open generated exports',
            onTap: onOpenGeneratedExports,
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
    this.statusLabel,
  });

  final List<StoredMeeting> meetings;
  final String? statusLabel;
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
          if (statusLabel != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              statusLabel!,
              style: AppTextStyles.compact(Theme.of(context).textTheme),
            ),
          ],
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
    return Semantics(
      button: true,
      label: 'Open ${meeting.title}',
      child: ListTile(
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
      ),
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
    required this.meeting,
    required this.onGenerateExport,
    required this.onOpenGeneratedExports,
  });

  final StoredMeeting? meeting;
  final ValueChanged<ExportType> onGenerateExport;
  final VoidCallback onOpenGeneratedExports;

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  ExportType _selectedType = ExportType.transcript;
  String? _errorLabel;

  bool get _summaryRequired => _selectedType != ExportType.transcript;

  void _generateExport() {
    if (widget.meeting == null) {
      setState(() => _errorLabel = 'Start or select a meeting first.');
      return;
    }

    widget.onGenerateExport(_selectedType);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final meeting = widget.meeting;

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
                  'Generate export',
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.title(textTheme),
                ),
              ),
              IconButton(
                tooltip: 'Close export',
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
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onOpenGeneratedExports();
              },
              icon: const Icon(Icons.folder_copy_outlined),
              label: const Text('Open generated exports'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          ExportTypeSelector(
            selected: _selectedType,
            onChanged: (type) {
              setState(() {
                _selectedType = type;
                _errorLabel = null;
              });
            },
          ),
          if (_summaryRequired) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              meeting != null && _hasFreshStoredSummary(meeting)
                  ? 'A GPT-5.5 summary is stored locally for this transcript.'
                  : 'Summary is generated by a direct OpenAI request from this device, then stored locally for review.',
              style: AppTextStyles.compact(textTheme),
            ),
          ],
          if (_errorLabel != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              _errorLabel!,
              style: AppTextStyles.compact(
                textTheme,
              ).copyWith(color: AppColors.red),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          const PrivacyNote(
            label:
                'Generated exports stay encrypted on this device. Plain text is shown only in the in-app export view and when you press Copy.',
            icon: Icons.lock_outline_rounded,
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _generateExport,
              icon: const Icon(Icons.add_to_photos_outlined),
              label: const Text('Generate export'),
            ),
          ),
        ],
      ),
    );
  }
}

class _GeneratedExportListItem {
  const _GeneratedExportListItem({
    required this.meetingTitle,
    required this.generatedExport,
  });

  final String meetingTitle;
  final StoredGeneratedExport generatedExport;
}

class _GeneratedExportsSheet extends StatelessWidget {
  const _GeneratedExportsSheet({
    required this.items,
    required this.onOpenExport,
  });

  final List<_GeneratedExportListItem> items;
  final ValueChanged<_GeneratedExportListItem> onOpenExport;

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
              const Icon(Icons.folder_copy_outlined, color: AppColors.teal),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Generated exports',
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.title(textTheme),
                ),
              ),
              IconButton(
                tooltip: 'Close generated exports',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (items.isEmpty)
            Text(
              'No generated exports yet.',
              style: AppTextStyles.body(textTheme),
            )
          else
            for (final item in items)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  backgroundColor: AppColors.surfacePressed,
                  foregroundColor: AppColors.teal,
                  child: Icon(Icons.description_outlined),
                ),
                title: Text(
                  item.generatedExport.subject,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.label(textTheme),
                ),
                subtitle: Text(
                  '${item.meetingTitle} - '
                  '${_exportTypeLabel(item.generatedExport.type)} - '
                  '${_timeLabel(item.generatedExport.createdAt)}',
                  style: AppTextStyles.compact(textTheme),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => onOpenExport(item),
              ),
          const SizedBox(height: AppSpacing.sm),
          const PrivacyNote(
            label:
                'Generated export bodies are stored only in encrypted local app storage.',
            icon: Icons.lock_outline_rounded,
          ),
        ],
      ),
    );
  }
}

class _GeneratedExportDetailSheet extends StatelessWidget {
  const _GeneratedExportDetailSheet({
    required this.generatedExport,
    required this.onCopy,
  });

  final StoredGeneratedExport generatedExport;
  final Future<void> Function() onCopy;

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
              const Icon(Icons.description_outlined, color: AppColors.teal),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  generatedExport.subject,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.title(textTheme),
                ),
              ),
              IconButton(
                tooltip: 'Close generated export',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          Text(
            '${_exportTypeLabel(generatedExport.type)} generated '
            '${_timeLabel(generatedExport.createdAt)}',
            style: AppTextStyles.compact(textTheme),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 360),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(AppRadii.card),
              border: Border.all(color: AppColors.border),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                generatedExport.body,
                style: AppTextStyles.body(textTheme),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const PrivacyNote(
            label:
                'This is the only in-app plaintext view. Use Copy only when you are ready to place the export on the clipboard.',
            icon: Icons.lock_outline_rounded,
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onCopy,
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy generated export'),
            ),
          ),
        ],
      ),
    );
  }
}

String _exportTypeLabel(String value) {
  return switch (value) {
    'summary' => 'Summary',
    'both' => 'Both',
    _ => 'Transcript',
  };
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
  final FutureOr<void> Function() onTap;

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
      onTap: () async {
        await onTap();
      },
    );
  }
}
