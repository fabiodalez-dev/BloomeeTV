import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'tv_workspace.dart';

class TvStorage {
  static Future<void> _transfers = Future.value();
  static Future<T> withDownloadSlot<T>(Future<T> Function() work) {
    final task = _transfers.then((_) => work());
    _transfers = task.then<void>((_) {}, onError: (Object _) {});
    return task;
  }

  static const channel = MethodChannel('bloomee_tv/storage');
  static Future<int> Function(String path) freeBytes = (path) async =>
      (await channel.invokeMethod<int>('freeBytes', {'path': path})) ?? 0;
  static Future<int> usedBytes(Directory directory) async {
    var total = 0;
    if (!await directory.exists()) return 0;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File &&
          RegExp(r'\.(mp3|flac|ogg|opus|m4a|aac|wav|audio|part)$')
              .hasMatch(entity.path.toLowerCase()))
        total += await entity.length();
    }
    return total;
  }

  static Future<int> allowance(Directory directory) async {
    await directory.create(recursive: true);
    final quota =
        ((TvWorkspace.instance['quotaMb'] as num? ?? 2048) * 1024 * 1024)
            .toInt();
    final used = await usedBytes(directory);
    final free = await freeBytes(directory.path);
    final allowed = min(quota - used, free - 32 * 1024 * 1024);
    if (allowed <= 0)
      throw const FileSystemException(
          'Spazio insufficiente: apri Gestione spazio');
    return allowed;
  }
}
