import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'reactive_sqldb_method_channel.dart';

abstract class ReactiveSqldbPlatform extends PlatformInterface {
  /// Constructs a ReactiveSqldbPlatform.
  ReactiveSqldbPlatform() : super(token: _token);

  static final Object _token = Object();

  static ReactiveSqldbPlatform _instance = MethodChannelReactiveSqldb();

  /// The default instance of [ReactiveSqldbPlatform] to use.
  ///
  /// Defaults to [MethodChannelReactiveSqldb].
  static ReactiveSqldbPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [ReactiveSqldbPlatform] when
  /// they register themselves.
  static set instance(ReactiveSqldbPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
