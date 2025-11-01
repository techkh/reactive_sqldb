import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'reactive_sqldb_platform_interface.dart';

/// An implementation of [ReactiveSqldbPlatform] that uses method channels.
class MethodChannelReactiveSqldb extends ReactiveSqldbPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('reactive_sqldb');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
