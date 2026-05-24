import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_translate_mobile/src/openai/openai_configuration.dart';
import 'package:realtime_translate_mobile/src/openai/openai_credential_store.dart';
import 'package:realtime_translate_mobile/src/storage/encrypted_local_store.dart';
import 'package:realtime_translate_mobile/src/storage/local_meeting_repository.dart';

void main() {
  test('keeps OpenAI model defaults explicit', () {
    expect(OpenAiConfiguration.realtimeModel, 'gpt-realtime-2');
    expect(
      OpenAiConfiguration.translationFallbackModel,
      'gpt-realtime-translate',
    );
    expect(OpenAiConfiguration.summaryModel, 'gpt-5.5');
    expect(OpenAiConfiguration.summaryReasoningEffort, 'xhigh');
    expect(
      OpenAiConfiguration.realtimeCallsEndpoint,
      'https://api.openai.com/v1/realtime/calls',
    );
  });

  test('stores credential material in encrypted local storage only', () async {
    final repository = LocalMeetingRepository(
      store: MemoryEncryptedLocalStore(),
    );
    final store = OpenAiCredentialStore(repository: repository);
    final configuredAt = DateTime.utc(2026, 5, 24, 4);

    expect((await store.loadStatus()).isConfigured, isFalse);

    await store.saveUserProvidedCredential(
      'placeholder-local-openai-credential',
      configuredAt: configuredAt,
    );

    final status = await store.loadStatus();
    final snapshot = await repository.loadSnapshot();

    expect(repository.isEncryptedAtRest, isTrue);
    expect(status.isConfigured, isTrue);
    expect(status.configuredAt, configuredAt);
    expect(
      status.displayLabel,
      isNot(contains('placeholder-local-openai-credential')),
    );
    expect(
      await store.readCredentialForNetworkUse(),
      'placeholder-local-openai-credential',
    );
    expect(
      snapshot.credentialSessionMaterial,
      containsPair(
        OpenAiCredentialStore.apiKeyStorageKey,
        'placeholder-local-openai-credential',
      ),
    );
  });

  test('clears saved credential material without deleting meetings', () async {
    final repository = LocalMeetingRepository(
      store: MemoryEncryptedLocalStore(),
    );
    final store = OpenAiCredentialStore(repository: repository);

    await store.saveUserProvidedCredential(
      'placeholder-local-openai-credential',
    );
    await repository.saveSensitivePreference(key: 'retentionDays', value: '30');

    await store.clearCredential();

    final snapshot = await repository.loadSnapshot();
    expect((await store.loadStatus()).isConfigured, isFalse);
    expect(await store.readCredentialForNetworkUse(), isNull);
    expect(snapshot.credentialSessionMaterial, isEmpty);
    expect(snapshot.sensitivePreferences, containsPair('retentionDays', '30'));
  });
}
