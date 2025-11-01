import 'package:flutter_test/flutter_test.dart';
import 'package:reactive_sqldb/reactive_sqldb_platform_interface.dart';
import 'package:reactive_sqldb/reactive_sqldb_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockReactiveSqldbPlatform
    with MockPlatformInterfaceMixin
    implements ReactiveSqldbPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final ReactiveSqldbPlatform initialPlatform = ReactiveSqldbPlatform.instance;

  test('$MethodChannelReactiveSqldb is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelReactiveSqldb>());
  });

  // test('getPlatformVersion', () async {
  //   ReactiveSqldb reactiveSqldbPlugin = ReactiveSqldb();
  //   MockReactiveSqldbPlatform fakePlatform = MockReactiveSqldbPlatform();
  //   ReactiveSqldbPlatform.instance = fakePlatform;

  //   expect(await reactiveSqldbPlugin.getPlatformVersion(), '42');
  // });
}
