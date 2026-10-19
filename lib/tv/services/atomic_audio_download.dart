import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Writes a unique ID-based file; a failed transfer never replaces valid audio.
class AtomicAudioDownload {
  static String fileName(String id, String extension) {
    if (!RegExp(r'^[a-z0-9]{1,10}$').hasMatch(extension))
      throw ArgumentError('Estensione non valida');
    return '${sha256.convert(utf8.encode(id))}.$extension';
  }

  static Future<File> save(
      {required http.Client client,
      required Uri uri,
      required Directory directory,
      required String id,
      required String extension,
      Map<String, String>? headers,
      void Function(int bytes, int? total)? onProgress,
      bool Function()? cancelled,
      int maxBytes = 1024 * 1024 * 1024,
      Duration timeout = const Duration(seconds: 30)}) async {
    await directory.create(recursive: true);
    final target = File('${directory.path}/${fileName(id, extension)}');
    final part =
        File('${target.path}.${DateTime.now().microsecondsSinceEpoch}.part');
    RandomAccessFile? sink;
    if (maxBytes <= 0) throw ArgumentError('Quota non valida');
    try {
      final response = await client
          .send(http.Request('GET', uri)..headers.addAll(headers ?? {}))
          .timeout(timeout);
      if (response.statusCode != 200)
        throw HttpException('Download: HTTP ${response.statusCode}');
      final total = response.contentLength;
      if (total != null && total > maxBytes)
        throw const FileSystemException('Quota download insufficiente');
      sink = await part.open(mode: FileMode.write);
      var bytes = 0;
      await for (final chunk in response.stream.timeout(timeout)) {
        if (cancelled?.call() ?? false)
          throw const FileSystemException('Download annullato');
        bytes += chunk.length;
        if (bytes > maxBytes)
          throw const FileSystemException('Quota download insufficiente');
        await sink.writeFrom(chunk);
        onProgress?.call(bytes, total);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (bytes == 0 || (total != null && bytes != total))
        throw const FileSystemException('Download incompleto');
      if (cancelled?.call() ?? false)
        throw const FileSystemException('Download annullato');
      await part.rename(target.path);
      return target;
    } finally {
      await sink?.close();
      if (await part.exists()) await part.delete();
    }
  }
}
