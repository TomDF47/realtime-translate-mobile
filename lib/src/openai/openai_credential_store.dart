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
  OpenAiCredentialStore({required this.repository});

  static const apiKeyStorageKey = 'openai_user_provided_api_key';
  static const configuredAtStorageKey =
      'openai_user_provided_api_key_configured_at';

  final LocalMeetingRepository repository;

  Future<OpenAiCredentialStatus> loadStatus() async {
    final material = await repository.loadCredentialSessionMaterial();
    final credential = material[apiKeyStorageKey]?.trim();
    if (credential == null || credential.isEmpty) {
      return const OpenAiCredentialStatus.missing();
    }

    return OpenAiCredentialStatus(
      availability: OpenAiCredentialAvailability.configured,
      configuredAt: DateTime.tryParse(material[configuredAtStorageKey] ?? ''),
    );
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
  }

  Future<String?> readCredentialForNetworkUse() async {
    final material = await repository.loadCredentialSessionMaterial();
    final credential = material[apiKeyStorageKey]?.trim();
    if (credential == null || credential.isEmpty) {
      return null;
    }

    return credential;
  }

  Future<void> clearCredential() {
    return repository.deleteCredentialSessionMaterialKeys({
      apiKeyStorageKey,
      configuredAtStorageKey,
    });
  }
}
