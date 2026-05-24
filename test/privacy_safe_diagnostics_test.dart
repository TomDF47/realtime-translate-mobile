import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_translate_mobile/src/diagnostics/privacy_safe_diagnostics.dart';
import 'package:realtime_translate_mobile/src/openai/openai_credential_store.dart';
import 'package:realtime_translate_mobile/src/session/live_session_controller.dart';
import 'package:realtime_translate_mobile/src/session/microphone_permission.dart';
import 'package:realtime_translate_mobile/src/storage/encrypted_local_store.dart';
import 'package:realtime_translate_mobile/src/storage/local_meeting_repository.dart';

void main() {
  test('redacts forbidden fields and omits unapproved detail', () {
    final sink = MemoryPrivacySafeDiagnosticsSink();
    final diagnostics = PrivacySafeDiagnostics(sink: sink);
    final fakeApiKey = 'sk-${List.filled(24, 'a').join()}';
    final fakeSessionToken = 'sess-${List.filled(24, 'b').join()}';

    diagnostics.info(
      'privacy-check ${'leader@example.com'}',
      fields: {
        'nextPhase': 'listening',
        'credentialStatus': 'configured',
        'model': 'gpt-realtime-2',
        'apiKey': fakeApiKey,
        'sessionToken': fakeSessionToken,
        'prompt': 'Summarize the acquisition timeline.',
        'transcriptText': 'Can we meet on Tuesday?',
        'translatedText': 'Secret translated payload',
        'recipientEmails': 'leader@example.com',
        'requestBody': {'raw': 'payload'},
        'developerNote': 'this unapproved note should not be logged',
      },
    );

    final record = sink.records.single;
    final serialized = _serialize(record);

    expect(record.event, 'diagnostic_event');
    expect(record.fields['nextPhase'], 'listening');
    expect(record.fields['credentialStatus'], 'configured');
    expect(record.fields['model'], 'gpt-realtime-2');
    expect(record.fields['apiKey'], PrivacySafeDiagnostics.redacted);
    expect(record.fields['sessionToken'], PrivacySafeDiagnostics.redacted);
    expect(record.fields['prompt'], PrivacySafeDiagnostics.redacted);
    expect(record.fields['transcriptText'], PrivacySafeDiagnostics.redacted);
    expect(record.fields['translatedText'], PrivacySafeDiagnostics.redacted);
    expect(record.fields['recipientEmails'], PrivacySafeDiagnostics.redacted);
    expect(record.fields['requestBody'], PrivacySafeDiagnostics.redacted);
    expect(record.fields['developerNote'], PrivacySafeDiagnostics.omitted);
    expect(serialized, isNot(contains(fakeApiKey)));
    expect(serialized, isNot(contains(fakeSessionToken)));
    expect(serialized, isNot(contains('leader@example.com')));
    expect(serialized, isNot(contains('acquisition timeline')));
    expect(serialized, isNot(contains('Can we meet on Tuesday?')));
    expect(serialized, isNot(contains('Secret translated payload')));
  });

  test('live session diagnostics record state only', () async {
    final sink = MemoryPrivacySafeDiagnosticsSink();
    final controller = LiveSessionController(
      permissionGateway: _FixedPermissionGateway(
        MicrophonePermissionStatus.granted,
      ),
      diagnostics: PrivacySafeDiagnostics(sink: sink),
    );

    await controller.startMeeting();

    expect(
      sink.records.map((record) => record.event),
      everyElement('live_session.state_change'),
    );
    expect(
      sink.records.last.fields,
      containsPair('nextPhase', LiveSessionPhase.listening.name),
    );
    expect(
      sink.records.last.fields,
      containsPair('isRealtimeSessionOpen', 'true'),
    );
    expect(
      _serializeAll(sink.records),
      isNot(contains('Preparing the phone-local live session.')),
    );
    expect(
      _serializeAll(sink.records),
      isNot(contains('Microphone access is required')),
    );
  });

  test(
    'OpenAI credential diagnostics never include credential material',
    () async {
      final sink = MemoryPrivacySafeDiagnosticsSink();
      final repository = LocalMeetingRepository(
        store: MemoryEncryptedLocalStore(),
      );
      final credentialStore = OpenAiCredentialStore(
        repository: repository,
        diagnostics: PrivacySafeDiagnostics(sink: sink),
      );
      const placeholderCredential = 'placeholder-local-openai-credential';

      await credentialStore.saveUserProvidedCredential(placeholderCredential);
      expect(await credentialStore.readCredentialForNetworkUse(), isNotNull);
      await credentialStore.loadStatus();
      await credentialStore.clearCredential();

      final serialized = _serializeAll(sink.records);
      expect(serialized, contains('openai.credential_saved'));
      expect(serialized, contains('openai.credential_read'));
      expect(serialized, contains('openai.credential_status'));
      expect(serialized, contains('openai.credential_removed'));
      expect(serialized, isNot(contains(placeholderCredential)));
      expect(
        sink.records.expand((record) => record.fields.keys),
        isNot(contains('apiKey')),
      );
    },
  );
}

String _serialize(PrivacySafeDiagnosticRecord record) {
  return '${record.event} ${record.severity} ${record.fields}';
}

String _serializeAll(Iterable<PrivacySafeDiagnosticRecord> records) {
  return records.map(_serialize).join('\n');
}

class _FixedPermissionGateway implements MicrophonePermissionGateway {
  _FixedPermissionGateway(this.status);

  final MicrophonePermissionStatus status;

  @override
  Future<MicrophonePermissionStatus> checkStatus() async => status;

  @override
  Future<void> openAppSettings() async {}

  @override
  Future<MicrophonePermissionStatus> request() async => status;
}
