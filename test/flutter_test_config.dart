import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final configFile = File('.dart_tool/package_config.json').absolute;
  final config = jsonDecode(await configFile.readAsString()) as Map;
  final package = (config['packages'] as List)
      .firstWhere((p) => p['name'] == 'isar_community_flutter_libs');
  final root = configFile.uri.resolve('${package['rootUri']}/');
  final relative = Platform.isMacOS
      ? 'macos/libisar.dylib'
      : Platform.isLinux
          ? 'linux/libisar.so'
          : 'windows/isar.dll';
  await Isar.initializeIsarCore(
      libraries: {Abi.current(): root.resolve(relative).toFilePath()});
  await testMain();
}
