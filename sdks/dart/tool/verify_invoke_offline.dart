// Invoking after the socket has gone away must be catchable, not fatal.
//
// Run:  dart run tool/verify_invoke_offline.dart <ws-url> <api-key>
import 'package:openhuman_sdk_dart/openhuman.dart';

Future<void> main(List<String> args) async {
  final client = OpenHumanClient();

  // What the panel now does: await inside try/catch.
  Future<void> safeInvoke(String where) async {
    try {
      await client.invokeTool('cnv_none', 'some_tool', {});
      print('  $where: 调用返回（未抛异常）');
    } catch (e) {
      print('  $where: 已捕获 -> $e');
    }
  }

  print('--- 未连接时 ---');
  await safeInvoke('idle');

  await client.connect(args[0], args[1]);
  for (var i = 0;
      i < 120 && client.currentState != ConnectionState.connected;
      i++) {
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  print('--- 已连接 --- state: ${client.currentState.name}');
  await safeInvoke('connected');

  await client.disconnect();
  await Future<void>.delayed(const Duration(milliseconds: 500));
  print('--- 断开后 --- state: ${client.currentState.name}');
  await safeInvoke('disconnected');

  print('--- 到这里说明没有未捕获异常终止进程 ---');
  client.dispose();
}
