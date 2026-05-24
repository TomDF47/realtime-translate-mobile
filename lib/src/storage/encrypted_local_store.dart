import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class EncryptedLocalStore {
  bool get isEncryptedAtRest;

  String get storageDescription;

  Future<String?> read({required String key});

  Future<void> write({required String key, required String value});

  Future<void> delete({required String key});
}

class FlutterSecureEncryptedLocalStore implements EncryptedLocalStore {
  FlutterSecureEncryptedLocalStore({
    this.storage = const FlutterSecureStorage(
      aOptions: AndroidOptions(
        migrateWithBackup: true,
        storageNamespace: 'live_translate_secure_store',
      ),
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
      ),
    ),
  });

  final FlutterSecureStorage storage;

  @override
  bool get isEncryptedAtRest => true;

  @override
  String get storageDescription =>
      'flutter_secure_storage with Android KeyStore and iOS Keychain backing';

  @override
  Future<String?> read({required String key}) {
    return storage.read(key: key);
  }

  @override
  Future<void> write({required String key, required String value}) {
    return storage.write(key: key, value: value);
  }

  @override
  Future<void> delete({required String key}) {
    return storage.delete(key: key);
  }
}

class MemoryEncryptedLocalStore implements EncryptedLocalStore {
  final Map<String, String> _values = {};

  @override
  bool get isEncryptedAtRest => true;

  @override
  String get storageDescription => 'in-memory encrypted test double';

  @override
  Future<String?> read({required String key}) async => _values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    _values.remove(key);
  }
}
