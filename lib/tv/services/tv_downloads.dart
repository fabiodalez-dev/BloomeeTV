import 'dart:io';
import 'package:Bloomee/core/di/service_locator.dart';
import 'package:Bloomee/core/models/exported.dart';
import 'package:Bloomee/services/player/media_resolver_service.dart';
import 'package:Bloomee/services/plugin_cache_codec.dart';
import 'package:http/http.dart' as http;
import 'atomic_audio_download.dart';
import 'tv_operations.dart';
import 'tv_storage.dart';
import 'tv_workspace.dart';
import 'tv_diagnostics.dart';

/// All TV download entry points share quota, atomic writes and operation state.
class TvDownloads {
  static Future<bool> save(Track track,
      {required Future<Directory> Function() directory,
      required Future<void> Function(Track track, String path) register,
      Future<ResolvedMediaSource> Function(Track track)? resolve,
      http.Client Function()? clientFactory}) async {
    final profile = TvWorkspace.instance.generation;
    final client = (clientFactory ?? http.Client.new)();
    try {
      final result = await TvOperations.instance.run<bool>(
          track.id,
          {
            'source': 'locale',
            'title': track.title,
            'track': tvTrackToJson(track),
            'error': ''
          },
          () => TvStorage.withDownloadSlot(() async {
                if (TvOperations.instance.cancelled(track.id))
                  throw StateError('Download annullato');
                final source = await (resolve ??
                    MediaResolverService.create(ServiceLocator.pluginService)
                        .resolve)(track);
                if (source.isOffline) {
                  await TvOperations.instance
                      .update(track.id, {'state': 'pronto'});
                  return true;
                }
                final target = await directory();
                final allowance = await TvStorage.allowance(target);
                var progressAt = DateTime.fromMillisecondsSinceEpoch(0);
                final file = await AtomicAudioDownload.save(
                    client: client,
                    uri: source.uri,
                    headers: source.headers,
                    directory: target,
                    id: track.id,
                    extension: 'audio',
                    maxBytes: allowance,
                    cancelled: () =>
                        TvOperations.instance.cancelled(track.id) ||
                        profile != TvWorkspace.instance.generation,
                    onProgress: (bytes, total) {
                      if (DateTime.now().difference(progressAt).inMilliseconds <
                          750) return;
                      progressAt = DateTime.now();
                      TvOperations.instance.update(track.id, {
                        'bytes': bytes,
                        if (total != null && total > 0)
                          'progress': (100 * bytes / total).floor()
                      }).catchError((Object e) {
                        TvDiagnostics.instance
                            .record('Avanzamento download', e);
                      });
                    });
                if (profile != TvWorkspace.instance.generation ||
                    TvOperations.instance.cancelled(track.id)) {
                  await file.delete();
                  throw StateError('Download annullato');
                }
                await register(track, file.path);
                await TvOperations.instance.update(track.id,
                    {'state': 'pronto', 'path': file.path, 'progress': 100});
                return true;
              }),
          onCancel: client.close);
      return result ?? false;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }
}
