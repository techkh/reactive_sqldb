import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:math';

class DbKeyManager {
  static const _keyName = 'db_encryption_key';
  static final _storage = FlutterSecureStorage();

  static Future<String> getKey() async {
    String? key = await _storage.read(key: _keyName);
    if (key != null) return key;

    // Generate strong random key
    final rand = Random.secure();
    final bytes = List<int>.generate(32, (_) => rand.nextInt(256));
    key = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    await _storage.write(key: _keyName, value: key);
    return key;
  }
}
