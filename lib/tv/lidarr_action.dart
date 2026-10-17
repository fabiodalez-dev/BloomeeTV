import 'package:Bloomee/screens/widgets/snackbar.dart';
import 'package:Bloomee/tv/connectors/lidarr_client.dart';
import 'package:Bloomee/tv/tv_config.dart';
import 'package:Bloomee/tv/ui/tv_widgets.dart';
import 'package:flutter/material.dart';

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

  SnackbarService.showMessage('Richiesta a Lidarr in corso… (può volerci un minuto)', duration: const Duration(seconds: 6));
  final r = await client.requestAlbum(artist: artist, album: album);
  final name = '${r.artistName ?? artist} – ${r.albumTitle ?? album}';
  switch (r.status) {
    case LidarrRequestStatus.requested:
      SnackbarService.showMessage(
          'Download avviato: $name. Comparirà in Jellyfin a fine download.',
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
