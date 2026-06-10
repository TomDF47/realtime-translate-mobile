import '../diagnostics/privacy_safe_diagnostics.dart';
import '../storage/local_meeting_repository.dart';

enum OpenAiCredentialAvailability { missing, configured }

enum LiveCredentialProvider { openAi, gemini }

class OpenAiCredentialStatus {
  const OpenAiCredentialStatus({
    required this.availability,
    required this.configuredAt,
  });

  const OpenAiCredentialStatus.missing()
    : availability = OpenAiCredentialAvailability.missing,
      configuredAt = null;

  final OpenAiCredentialAvailability availability;
  final DateTime? configuredAt;

  bool get isConfigured =>
      availability == OpenAiCredentialAvailability.configured;

  String displayLabelForProvider(LiveCredentialProvider provider) {
    final providerLabel = switch (provider) {
      LiveCredentialProvider.openAi => 'OpenAI',
      LiveCredentialProvider.gemini => 'Gemini',
    };
    return switch (availability) {
      OpenAiCredentialAvailability.configured =>
        '$providerLabel credential stored on this device',
      OpenAiCredentialAvailability.missing => '$providerLabel setup required',
    };
  }

  String get displayLabel =>
      displayLabelForProvider(LiveCredentialProvider.openAi);
}

class OpenAiCredentialStore {
  OpenAiCredentialStore({
    required this.repository,
    this.diagnostics = const PrivacySafeDiagnostics(),
    this.provider = LiveCredentialProvider.openAi,
  });

  OpenAiCredentialStore.gemini({
    required LocalMeetingRepository repository,
    PrivacySafeDiagnostics diagnostics = const PrivacySafeDiagnostics(),
  }) : this(
         repository: repository,
         diagnostics: diagnostics,
         provider: LiveCredentialProvider.gemini,
       );

  static const apiKeyStorageKey = 'openai_user_provided_api_key';
  static const configuredAtStorageKey =
      'openai_user_provided_api_key_configured_at';
  static const geminiApiKeyStorageKey = 'gemini_user_provided_api_key';
  static const geminiConfiguredAtStorageKey =
      'gemini_user_provided_api_key_configured_at';

  final LocalMeetingRepository repository;
  final PrivacySafeDiagnostics diagnostics;
  final LiveCredentialProvider provider;

  String get _apiKeyStorageKey {
    return switch (provider) {
      LiveCredentialProvider.openAi => apiKeyStorageKey,
      LiveCredentialProvider.gemini => geminiApiKeyStorageKey,
    };
  }

  String get _configuredAtStorageKey {
    return switch (provider) {
      LiveCredentialProvider.openAi => configuredAtStorageKey,
      LiveCredentialProvider.gemini => geminiConfiguredAtStorageKey,
    };
  }

  String get _diagnosticPrefix {
    return switch (provider) {
      LiveCredentialProvider.openAi => 'openai',
      LiveCredentialProvider.gemini => 'gemini',
    };
  }

  Future<OpenAiCredentialStatus> loadStatus() async {
    final material = await repository.loadCredentialSessionMaterial();
    final credential = material[_apiKeyStorageKey]?.trim();
    if (credential == null || credential.isEmpty) {
      _recordStatus(const OpenAiCredentialStatus.missing());
      return const OpenAiCredentialStatus.missing();
    }

    final status = OpenAiCredentialStatus(
      availability: OpenAiCredentialAvailability.configured,
      configuredAt: DateTime.tryParse(material[_configuredAtStorageKey] ?? ''),
    );
    _recordStatus(status);
    return status;
  }

  Future<void> saveUserProvidedCredential(
    String credential, {
    DateTime? configuredAt,
  }) async {
    final trimmed = credential.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(
        credential,
        'credential',
        'Credential must not be empty.',
      );
    }

    final savedAt = configuredAt ?? DateTime.now().toUtc();
    await repository.saveCredentialSessionMaterial(
      key: _apiKeyStorageKey,
      value: trimmed,
    );
    await repository.saveCredentialSessionMaterial(
      key: _configuredAtStorageKey,
      value: savedAt.toIso8601String(),
    );
    diagnostics.info(
      '$_diagnosticPrefix.credential_saved',
      fields: {
        'credentialStatus': OpenAiCredentialAvailability.configured.name,
        'storageArea': 'credentialSessionMaterial',
        'result': 'success',
      },
    );
  }

  Future<String?> readCredentialForNetworkUse() async {
    final material = await repository.loadCredentialSessionMaterial();
    final credential = material[_apiKeyStorageKey]?.trim();
    if (credential == null || credential.isEmpty) {
      diagnostics.info(
        '$_diagnosticPrefix.credential_read',
        fields: {
          'credentialStatus': OpenAiCredentialAvailability.missing.name,
          'operation': 'networkCredentialRead',
          'result': 'missing',
        },
      );
      return null;
    }

    diagnostics.info(
      '$_diagnosticPrefix.credential_read',
      fields: {
        'credentialStatus': OpenAiCredentialAvailability.configured.name,
        'operation': 'networkCredentialRead',
        'result': 'configured',
      },
    );
    return credential;
  }

  Future<void> clearCredential() async {
    await repository.deleteCredentialSessionMaterialKeys({
      _apiKeyStorageKey,
      _configuredAtStorageKey,
    });
    diagnostics.info(
      '$_diagnosticPrefix.credential_removed',
      fields: {
        'credentialStatus': OpenAiCredentialAvailability.missing.name,
        'storageArea': 'credentialSessionMaterial',
        'result': 'success',
      },
    );
  }

  void _recordStatus(OpenAiCredentialStatus status) {
    diagnostics.info(
      '$_diagnosticPrefix.credential_status',
      fields: {
        'credentialStatus': status.availability.name,
        'configured': status.isConfigured,
        'storageArea': 'credentialSessionMaterial',
      },
    );
  }
}
