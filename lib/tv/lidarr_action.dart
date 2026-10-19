import 'package:Bloomee/tv/services/tv_downloads.dart';
import 'package:Bloomee/tv/services/tv_operations.dart';

import 'package:Bloomee/blocs/downloader/cubit/downloader_cubit.dart';
import 'package:Bloomee/core/di/service_locator.dart';
import 'package:Bloomee/core/models/exported.dart';
import 'package:Bloomee/plugins/utils/media_id.dart';
import 'package:Bloomee/screens/widgets/snackbar.dart';
import 'package:Bloomee/src/rust/api/plugin/commands.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:Bloomee/tv/connectors/lidarr_client.dart';
import 'package:Bloomee/tv/tv_config.dart';
import 'package:Bloomee/tv/ui/tv_widgets.dart';
import 'package:flutter/material.dart';

/// Menu "Scarica" (OK tenuto premuto): l'album sul server con Lidarr, oppure
/// il brano o l'album sul Chromecast con il download di Bloomee (ascolto
/// senza rete, compaiono in "Scaricati").
Future<void> showDownloadMenu(
  BuildContext context, {
  required String artist,
  required String album,
  Track? track,
  Future<List<Track>> Function()? albumTracks,
  String? listTitle,
  List<Track>? listTracks,
  bool allowLidarr = true,
}) async {
  final name = listTitle ?? (album.isNotEmpty ? album : track?.title ?? '');
  // Playlist: gli album dei suoi brani, da chiedere a Lidarr.
  final lidarrAlbums = !allowLidarr
      ? const <({String artist, String album})>[]
      : album.isNotEmpty
          ? [(artist: artist, album: album)]
          : albumsOfTracks(listTracks ?? const [], fallbackTitle: listTitle);
  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: TvColors.surface,
      title: Row(children: [
        const Icon(Icons.download_rounded, color: TvColors.accent),
        const SizedBox(width: 12),
        Expanded(
          child: Text(track?.title ?? name,
              style: TvText.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
      ]),
      content: SizedBox(
        width: 560,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (lidarrAlbums.isNotEmpty)
            ListTile(
              autofocus: true,
              leading: const Icon(Icons.cloud_download_rounded,
                  color: TvColors.text),
              title:
                  const Text('Lidarr', style: TextStyle(color: TvColors.text)),
              subtitle: Text(
                  lidarrAlbums.length == 1
                      ? 'Scarica l\'album "${lidarrAlbums.first.album}" sul server: poi lo trovi in La tua musica (Jellyfin)'
                      : 'Scarica sul server i ${lidarrAlbums.length} album di questi brani: poi li trovi in La tua musica (Jellyfin)',
                  style: const TextStyle(color: TvColors.textDim)),
              onTap: () => Navigator.pop(ctx, 'lidarr'),
            ),
          if (track != null)
            ListTile(
              autofocus: lidarrAlbums.isEmpty,
              leading: const Icon(Icons.download_for_offline_rounded,
                  color: TvColors.text),
              title:
                  const Text('Locale', style: TextStyle(color: TvColors.text)),
              subtitle: const Text(
                  'Scarica il brano sul Chromecast, in Scaricati',
                  style: TextStyle(color: TvColors.textDim)),
              onTap: () => Navigator.pop(ctx, 'track'),
            ),
          if (albumTracks != null)
            ListTile(
              autofocus: lidarrAlbums.isEmpty && track == null,
              leading:
                  const Icon(Icons.library_music_rounded, color: TvColors.text),
              title:
                  const Text('Locale', style: TextStyle(color: TvColors.text)),
              subtitle: Text(
                  'Scarica tutti i brani di "$name" sul Chromecast, in Scaricati',
                  style: const TextStyle(color: TvColors.textDim)),
              onTap: () => Navigator.pop(ctx, 'album'),
            ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
      ],
    ),
  );
  if (choice == null || !context.mounted) return;
  final downloader = context.read<DownloaderCubit>();
  switch (choice) {
    case 'lidarr':
      if (lidarrAlbums.length == 1) {
        await downloadAlbumWithLidarr(context,
            artist: lidarrAlbums.first.artist, album: lidarrAlbums.first.album);
      } else {
        await _requestManyWithLidarr(lidarrAlbums);
      }
    case 'track':
      if (!await _downloadTvTrack(downloader, track!))
        SnackbarService.showMessage(
            'Download non riuscito: apri Centro operazioni');
    case 'album':
      SnackbarService.showMessage('Preparo i brani di "$name"…');
      final list = await albumTracks!();
      if (!context.mounted) return;
      await downloadTracksToDevice(context, list, name);
  }
}

/// Scarica tutti i brani (di un album o una playlist) sul dispositivo con il
/// download di Bloomee: finiscono in "Scaricati".
Future<void> downloadTracksToDevice(
    BuildContext context, List<Track> tracks, String title) async {
  if (tracks.isEmpty) {
    SnackbarService.showMessage('Non trovo i brani di "$title".');
    return;
  }
  final downloader = context.read<DownloaderCubit>();
  SnackbarService.showMessage(
      'Scarico ${tracks.length} brani di "$title" sul Chromecast: li trovi in Scaricati.',
      duration: const Duration(seconds: 5));
  var failed = 0;
  for (final t in List.of(tracks)) {
    if (!await _downloadTvTrack(downloader, t)) failed++;
  }
  if (failed > 0)
    SnackbarService.showMessage(
        '$failed brani di "$title" non sono stati scaricati.');
}

/// I brani Jellyfin non passano dal downloader dei plugin: scarico il file
/// originale dal server e lo registro in "Scaricati".
Future<bool> _downloadTvTrack(DownloaderCubit downloader, Track track) =>
    TvDownloads.save(track,
        directory: downloader.downloadDirectory,
        register: downloader.registerExternalDownload);

/// Album distinti (artista principale, titolo) dei brani di una playlist. Se
/// i brani non dicono l'album ma sono tutti dello stesso artista, uso il
/// titolo della playlist ripulito (es. "Green Day American Idiot (Deluxe)").
List<({String artist, String album})> albumsOfTracks(List<Track> tracks,
    {String? fallbackTitle}) {
  final seen = <String>{};
  final out = <({String artist, String album})>[];
  for (final t in tracks) {
    final al = t.album?.title.trim() ?? '';
    final ar = t.artists.isNotEmpty ? t.artists.first.name : '';
    if (al.isEmpty || ar.isEmpty) continue;
    if (seen.add('${ar.toLowerCase()}|${al.toLowerCase()}'))
      out.add((artist: ar, album: al));
  }
  if (out.isEmpty && fallbackTitle != null && tracks.isNotEmpty) {
    final artists = {
      for (final t in tracks)
        if (t.artists.isNotEmpty) t.artists.first.name
    };
    if (artists.length == 1) {
      final ar = artists.first;
      var al = fallbackTitle
          .replaceAll(RegExp(r'\s*[\(\[][^\)\]]*[\)\]]'), '')
          .trim();
      if (al.toLowerCase().startsWith(ar.toLowerCase()))
        al = al.substring(ar.length).replaceFirst(RegExp(r'^[\s\-–:]+'), '');
      if (al.isNotEmpty) out.add((artist: ar, album: al));
    }
  }
  return out;
}

Future<void> _requestManyWithLidarr(
    List<({String artist, String album})> albums) async {
  final client = TvConfig.lidarr;
  if (client == null) {
    SnackbarService.showMessage(
        'Lidarr non configurato: apri Impostazioni nel menu a sinistra',
        duration: const Duration(seconds: 4));
    return;
  }
  SnackbarService.showMessage(
      'Chiedo ${albums.length} album a Lidarr… (può volerci qualche minuto)',
      duration: const Duration(seconds: 6));
  var ok = 0, already = 0, missing = 0;
  for (final a in albums) {
    final r =
        await requestTrackedLidarr(client, artist: a.artist, album: a.album);
    switch (r.status) {
      case LidarrRequestStatus.requested:
        ok++;
      case LidarrRequestStatus.alreadyMonitored:
      case LidarrRequestStatus.alreadyPresent:
        already++;
      case LidarrRequestStatus.notFound:
      case LidarrRequestStatus.error:
        missing++;
    }
  }
  SnackbarService.showMessage(
      'Lidarr: $ok album in download, $already già presenti o richiesti, $missing non trovati.',
      duration: const Duration(seconds: 6));
}

/// Brani di un album di un plugin (prima pagina, di solito l'album intero).
Future<List<Track>> pluginAlbumTracks(AlbumSummary a) async {
  final pluginId = pluginIdOf(a.id);
  if (pluginId == null) return [];
  try {
    final r = await ServiceLocator.pluginService.execute(
      pluginId: pluginId,
      request: PluginRequest.contentResolver(
        ContentResolverCommand.getAlbumDetails(id: localIdOf(a.id) ?? a.id),
      ),
    );
    return r.maybeWhen(
        albumDetails: (d) => d.tracks.items, orElse: () => <Track>[]);
  } catch (_) {
    return [];
  }
}

/// "Scarica questo album": trova l'album su Lidarr, chiede conferma
/// mostrando cosa ha trovato, poi lo fa scaricare sul server.
Future<void> downloadAlbumWithLidarr(
  BuildContext context, {
  required String artist,
  required String album,
}) async {
  final client = TvConfig.lidarr;
  if (client == null) {
    SnackbarService.showMessage(
        'Lidarr non configurato: apri Impostazioni nel menu a sinistra',
        duration: const Duration(seconds: 4));
    return;
  }

  final preview = await showDialog<LidarrRequestResult>(
    context: context,
    builder: (ctx) => _LookupDialog(
      future: client.findAlbum(artist: artist, album: album),
      artist: artist,
      album: album,
    ),
  );
  if (preview == null || !context.mounted) return;

  SnackbarService.showMessage(
      'Richiesta a Lidarr in corso… (può volerci un minuto)',
      duration: const Duration(seconds: 6));
  final r = await requestTrackedLidarr(client,
      artist: artist, album: album, expectedAlbumId: preview.albumId);
  final name = '${r.artistName ?? artist} – ${r.albumTitle ?? album}';
  switch (r.status) {
    case LidarrRequestStatus.requested:
      SnackbarService.showMessage(
          'Richiesta inviata: $name. Lidarr deve ancora trovare, scaricare e importare l’album.',
          duration: const Duration(seconds: 5));
    case LidarrRequestStatus.alreadyMonitored:
      SnackbarService.showMessage(
          'Già richiesto: $name. Ho rilanciato la ricerca.',
          duration: const Duration(seconds: 5));
    case LidarrRequestStatus.alreadyPresent:
      SnackbarService.showMessage('Ce l\'hai già: $name è nella libreria.',
          duration: const Duration(seconds: 5));
    case LidarrRequestStatus.notFound:
      SnackbarService.showMessage('Lidarr non trova "$album" di $artist.',
          duration: const Duration(seconds: 5));
    case LidarrRequestStatus.error:
      SnackbarService.showMessage('Errore Lidarr: ${r.message ?? ''}',
          duration: const Duration(seconds: 6));
  }
}

class _LookupDialog extends StatelessWidget {
  const _LookupDialog(
      {required this.future, required this.artist, required this.album});
  final Future<LidarrRequestResult> future;
  final String artist;
  final String album;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LidarrRequestResult>(
      future: future,
      builder: (context, snap) {
        final r = snap.data;
        Widget content;
        List<Widget> actions;
        if (r == null) {
          content = const Padding(
            padding: EdgeInsets.all(12),
            child: TvMessage(
                icon: Icons.search, text: 'Cerco su Lidarr…', loading: true),
          );
          actions = [
            TextButton(
                key: const ValueKey('ld-cancel-loading'),
                autofocus: true,
                onPressed: () => Navigator.pop(context),
                child: const Text('Annulla')),
          ];
        } else if (r.status == LidarrRequestStatus.requested) {
          content = Text(
            '${r.artistName} – ${r.albumTitle}${r.year != null ? ' (${r.year})' : ''}\n\n'
            'Lo scarico sul server? Lidarr lo mette in Musica/Artista/Album e Jellyfin lo mostra appena finito.',
            style: TvText.body.copyWith(color: TvColors.text, fontSize: 18),
          );
          actions = [
            TextButton(
                key: const ValueKey('ld-cancel-confirm'),
                onPressed: () => Navigator.pop(context),
                child: const Text('Annulla')),
            FilledButton.icon(
              key: const ValueKey('ld-confirm'),
              autofocus: true,
              icon: const Icon(Icons.download_rounded),
              onPressed: () => Navigator.pop(context, r),
              label: const Text('Scarica album'),
            ),
          ];
        } else {
          content = Text(
            r.status == LidarrRequestStatus.notFound
                ? 'Lidarr non trova "$album" di $artist nel suo catalogo (MusicBrainz).'
                : 'Errore: ${r.message}',
            style: TvText.body.copyWith(fontSize: 18),
          );
          actions = [
            TextButton(
                autofocus: true,
                onPressed: () => Navigator.pop(context),
                child: const Text('Chiudi')),
          ];
        }
        return AlertDialog(
          backgroundColor: TvColors.surface,
          title: const Row(children: [
            Icon(Icons.cloud_download_rounded, color: TvColors.accent),
            SizedBox(width: 12),
            Text('Scarica questo album', style: TvText.title),
          ]),
          content: SizedBox(width: 520, child: content),
          actions: actions,
        );
      },
    );
  }
}

Future<LidarrRequestResult> requestTrackedLidarr(LidarrClient client,
    {required String artist,
    required String album,
    String? expectedAlbumId}) async {
  final id = 'lidarr:$artist|$album';
  final result = await TvOperations.instance.run<LidarrRequestResult>(
      id, {'source': 'lidarr', 'title': album, 'artist': artist}, () async {
    final r = await client.requestAlbum(
        artist: artist, album: album, expectedAlbumId: expectedAlbumId);
    await TvOperations.instance.update(id, {
      'state': switch (r.status) {
        LidarrRequestStatus.alreadyPresent => 'pronto',
        LidarrRequestStatus.requested ||
        LidarrRequestStatus.alreadyMonitored =>
          'richiesto',
        _ => 'errore'
      },
      'error': r.message ?? ''
    });
    return r;
  });
  return result ??
      const LidarrRequestResult(LidarrRequestStatus.alreadyMonitored);
}
