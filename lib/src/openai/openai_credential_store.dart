import '../diagnostics/privacy_safe_diagnostics.dart';
import '../storage/local_meeting_repository.dart';

enum OpenAiCredentialAvailability { missing, configured }

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

  String get displayLabel {
    return switch (availability) {
      OpenAiCredentialAvailability.configured =>
        'OpenAI credential stored on this device',
      OpenAiCredentialAvailability.missing => 'OpenAI setup required',
    };
  }
}

class OpenAiCredentialStore {
  OpenAiCredentialStore({
    required this.repository,
    this.diagnostics = const PrivacySafeDiagnostics(),
  });

  static const apiKeyStorageKey = 'openai_user_provided_api_key';
  static const configuredAtStorageKey =
      'openai_user_provided_api_key_configured_at';

  final LocalMeetingRepository repository;
  final PrivacySafeDiagnostics diagnostics;

  Future<OpenAiCredentialStatus> loadStatus() async {
    final material = await repository.loadCredentialSessionMaterial();
    final credential = material[apiKeyStorageKey]?.trim();
    if (credential == null || credential.isEmpty) {
      _recordStatus(const OpenAiCredentialStatus.missing());
      return const OpenAiCredentialStatus.missing();
    }

    final status = OpenAiCredentialStatus(
      availability: OpenAiCredentialAvailability.configured,
      configuredAt: DateTime.tryParse(material[configuredAtStorageKey] ?? ''),
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
      key: apiKeyStorageKey,
      value: trimmed,
    );
    await repository.saveCredentialSessionMaterial(
      key: configuredAtStorageKey,
      value: savedAt.toIso8601String(),
    );
    diagnostics.info(
      'openai.credential_saved',
      fields: {
        'credentialStatus': OpenAiCredentialAvailability.configured.name,
        'storageArea': 'credentialSessionMaterial',
        'result': 'success',
      },
    );
  }

  Future<String?> readCredentialForNetworkUse() async {
    final material = await repository.loadCredentialSessionMaterial();
    final credential = material[apiKeyStorageKey]?.trim();
    if (credential == null || credential.isEmpty) {
      diagnostics.info(
        'openai.credential_read',
        fields: {
          'credentialStatus': OpenAiCredentialAvailability.missing.name,
          'operation': 'networkCredentialRead',
          'result': 'missing',
        },
      );
      return null;
    }

    diagnostics.info(
      'openai.credential_read',
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
      apiKeyStorageKey,
      configuredAtStorageKey,
    });
    diagnostics.info(
      'openai.credential_removed',
      fields: {
        'credentialStatus': OpenAiCredentialAvailability.missing.name,
        'storageArea': 'credentialSessionMaterial',
        'result': 'success',
      },
    );
  }

  void _recordStatus(OpenAiCredentialStatus status) {
    diagnostics.info(
      'openai.credential_status',
      fields: {
        'credentialStatus': status.availability.name,
        'configured': status.isConfigured,
        'storageArea': 'credentialSessionMaterial',
      },
    );
  }
}
