import 'package:Bloomee/tv/services/tv_remote_server.dart';
import 'dart:async';
import 'package:Bloomee/tv/services/tv_cast_service.dart';
import 'package:Bloomee/tv/screens/tv_settings_screen.dart';
import 'package:Bloomee/tv/screens/tv_artist_screen.dart';
import 'package:Bloomee/blocs/downloader/cubit/downloader_cubit.dart';
import 'package:Bloomee/blocs/media_player/bloomee_player_cubit.dart';
import 'package:Bloomee/core/models/exported.dart' hide MediaItem;
import 'package:Bloomee/services/db/db_provider.dart';
import 'package:Bloomee/services/db/dao/download_dao.dart';
import 'package:Bloomee/services/db/dao/playlist_dao.dart';
import 'package:Bloomee/services/db/dao/track_dao.dart';
import 'package:Bloomee/services/db/global_db.dart';
import 'package:Bloomee/services/db/mappers/media_item_mapper.dart';
import 'package:Bloomee/services/player/sleep_timer.dart';
import 'package:Bloomee/services/plugin_cache_codec.dart';
import 'package:Bloomee/tv/services/tv_workspace.dart';
import 'package:Bloomee/tv/services/tv_catalog_cache.dart';
import 'package:Bloomee/tv/services/tv_diagnostics.dart';
import 'package:Bloomee/tv/services/tv_operations.dart';
import 'package:Bloomee/tv/services/tv_pairing_server.dart';
import 'package:Bloomee/tv/services/tv_saved_library.dart';
import 'package:Bloomee/tv/services/tv_storage.dart';
import 'package:Bloomee/tv/tv_config.dart';
import 'package:Bloomee/tv/connectors/jellyfin_client.dart';
import 'package:Bloomee/tv/connectors/ytmusic_account.dart';
import 'package:Bloomee/tv/ui/tv_widgets.dart';
import 'package:Bloomee/tv/lidarr_action.dart';
import 'package:Bloomee/tv/screens/tv_jellyfin_screen.dart';
import 'package:Bloomee/tv/screens/tv_youtube_screen.dart';
import 'package:Bloomee/screens/screen/common_views/album_view.dart';
import 'package:Bloomee/screens/screen/common_views/artist_view.dart';
import 'package:Bloomee/screens/screen/common_views/playlist_view.dart';
import 'package:Bloomee/screens/widgets/snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

enum TvTool {
  guida,
  profili,
  home,
  accessibilita,
  telefono,
  operazioni,
  spazio,
  preferiti,
  playlist,
  timer,
  audio,
  diagnostica
}

Future<void> openTvControlCenter(BuildContext context,
        [TvTool tool = TvTool.guida]) =>
    Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => TvControlCenter(initial: tool)));

Future<void> openTvReference(
    BuildContext context, TvReference reference) async {
  final item = reference.item;
  final id = reference.id;
  final source = id.split('::').first;
  final local = id.split('::').skip(1).join('::');
  Widget? page;
  item.when(
    track: (track) => context
        .read<BloomeePlayerCubit>()
        .bloomeePlayer
        .updateQueueTracks([track], doPlay: true),
    album: (album) {
      if (source == kJellyfinPluginId) {
        page = TvJellyfinAlbumScreen(
            album: JfItem({
          'Id': local,
          'Name': album.title,
          'AlbumArtist': reference.subtitle,
          'Type': 'MusicAlbum'
        }));
      } else if (source == kYtMusicPluginId) {
        page = TvYtCollectionScreen(
            browseId: local, fallbackTitle: reference.title);
      } else {
        page = AlbumView(album: album, pluginId: source);
      }
    },
    artist: (artist) => page = source == kJellyfinPluginId
        ? TvJellyfinArtistScreen(
            artist: JfItem(
                {'Id': local, 'Name': artist.name, 'Type': 'MusicArtist'}))
        : source == kYtMusicPluginId
            ? TvArtistScreen(artist: artist, pluginId: source)
            : ArtistView(artist: artist, pluginId: source),
    playlist: (playlist) => page = source == kYtMusicPluginId
        ? TvYtCollectionScreen(browseId: local, fallbackTitle: reference.title)
        : OnlPlaylistView(playlist: playlist, pluginId: source),
  );
  if (page != null && context.mounted)
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page!));
}

Future<void> showTvReferenceMenu(BuildContext context, TvReference item,
    {VoidCallback? download}) async {
  final action = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(title: Text(item.title), children: [
            SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, 'pin'),
                child: const Text('Fissa / rimuovi dalla Home')),
            SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, 'favorite'),
                child: const Text('Salva nei preferiti unificati')),
            if (download != null)
              SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, 'download'),
                  child: const Text('Scarica…')),
            if (item.item is MediaItem_Track)
              SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, 'next'),
                  child: const Text('Riproduci dopo')),
          ]));
  if (!context.mounted || action == null) return;
  try {
    switch (action) {
      case 'pin':
        await TvSavedLibrary.instance.togglePin(item);
      case 'favorite':
        await TvSavedLibrary.instance.addFavorite(item);
      case 'download':
        download?.call();
      case 'next':
        await context
            .read<BloomeePlayerCubit>()
            .bloomeePlayer
            .addPlayNextTrack((item.item as MediaItem_Track).field0);
    }
  } catch (e) {
    SnackbarService.showMessage(TvDiagnostics.redact(e.toString()));
  }
}

class TvControlCenter extends StatefulWidget {
  const TvControlCenter({super.key, this.initial = TvTool.guida});
  final TvTool initial;
  @override
  State<TvControlCenter> createState() => _TvControlCenterState();
}

class _TvControlCenterState extends State<TvControlCenter> {
  late TvTool _tool = widget.initial;
  String? _message;
  bool _working = false;
  bool _polling = false;
  Timer? _poll;
  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_tool == TvTool.operazioni) _refreshLidarr();
    });
  }

  Future<void> _refreshLidarr() async {
    final client = TvConfig.lidarr;
    if (_polling || client == null) return;
    _polling = true;
    final profile = _workspace.generation;
    try {
      for (final entry in TvOperations.instance.entries
          .where((e) => e['source'] == 'lidarr' && e['state'] != 'pronto')) {
        final state = await client.albumStatus(
            entry['artist'] as String, entry['title'] as String);
        if (!mounted || profile != _workspace.generation) return;
        await TvOperations.instance
            .update(entry['id'] as String, {'state': state});
      }
    } catch (e) {
      TvDiagnostics.instance.record('Stato Lidarr', e);
    } finally {
      _polling = false;
    }
  }

  final _workspace = TvWorkspace.instance;
  PlaylistDAO get _playlists =>
      PlaylistDAO(DBProvider.db, TrackDAO(DBProvider.db));
  DownloadDAO get _downloads =>
      DownloadDAO(DBProvider.db, TrackDAO(DBProvider.db), _playlists);
  Future<void> _run(Future<void> Function() action) async {
    if (_working) return;
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted)
        setState(() => _message = TvDiagnostics.redact(e.toString()));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    if (_tool == TvTool.telefono) tvPairing.close();
    super.dispose();
  }

  Widget _action(String text, Future<void> Function() action,
          {IconData icon = Icons.chevron_right}) =>
      Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: TvPillButton(
              icon: icon,
              label: text,
              onTap: _working ? null : () => _run(action)));
  Widget _text(String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(value, style: TvText.body.copyWith(fontSize: 18)));
  Future<String?> _name(String title, [String initial = '']) =>
      showTvKeyboard(context, title: title, initial: initial);
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: Listenable.merge([
        _workspace,
        TvProfiles.instance,
        tvPairing,
        tvRemote,
        TvOperations.instance,
        TvDiagnostics.instance
      ]),
      builder: (_, __) => Scaffold(
            backgroundColor: TvColors.bg,
            appBar: AppBar(title: const Text('Centro TV')),
            body: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                          height: 64,
                          child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                for (final tool in TvTool.values)
                                  Padding(
                                      padding: const EdgeInsets.only(right: 10),
                                      child: TvPillButton(
                                          icon: Icons.tune,
                                          label: tool.name,
                                          primary: tool == _tool,
                                          onTap: () {
                                            if (_tool == TvTool.telefono)
                                              tvPairing.close();
                                            setState(() => _tool = tool);
                                          }))
                              ])),
                      if (_message != null) _text(_message!),
                      if (_working) const LinearProgressIndicator(),
                      Expanded(
                          child: ListView(
                              padding: const EdgeInsets.all(8),
                              children: _content())),
                    ])),
          ));
  List<Widget> _content() => switch (_tool) {
        TvTool.guida => _guide(),
        TvTool.profili => _profiles(),
        TvTool.home => _home(),
        TvTool.accessibilita => _accessibility(),
        TvTool.telefono => _phone(),
        TvTool.operazioni => _operations(),
        TvTool.spazio => _storage(),
        TvTool.preferiti => _favorites(),
        TvTool.playlist => _playlistList(),
        TvTool.timer => _timer(),
        TvTool.audio => _audio(),
        TvTool.diagnostica => _diagnostics(),
      };
  List<Widget> _guide() => [
        const Text('Inizia ad ascoltare', style: TvText.hero),
        _text(
            'Frecce per muoverti, OK per scegliere, Indietro per tornare. Puoi usare l’app senza collegare tutti i servizi.'),
        _text(
            'Online: cerca un artista o un brano. I plugin si gestiscono dalle Impostazioni. Google è facoltativo e serve per leggere le tue raccolte.'),
        _text(
            'Jellyfin: musica del tuo server. Lidarr: richieste di album al server, che deve ancora trovarli e importarli. Locale: file salvati sulla TV.'),
        _text(
            'Il cuore nel player salva un preferito locale. Non aggiunge Mi piace al tuo account YouTube.'),
        _action('Prova i comandi: apri la tastiera', () async {
          await _name('Scrivi qualcosa e premi Fatto');
        }),
        _action('Collega i servizi dalle Impostazioni', () async {
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => const TvSettingsScreen()));
        }),
        _action('Ho capito, termina configurazione', () async {
          await _workspace.set('onboardedTv', true);
          if (mounted) Navigator.pop(context);
        }),
        _action('Salta per ora', () async {
          await _workspace.set('onboardedTv', true);
          if (mounted) Navigator.pop(context);
        }),
      ];
  List<Widget> _profiles() => [
        const Text('Profili domestici', style: TvText.title),
        _text(
            'Ogni profilo ha database, credenziali, preferiti e cache separati. Il cambio ferma la musica. I file scaricati appartengono al profilo che li ha registrati.'),
        for (final profile in TvProfiles.instance.profiles)
          _action(
              '${profile.id == TvProfiles.instance.selectedId ? '✓ ' : ''}${profile.name}',
              () => TvProfiles.instance.select(profile.id)),
        _action('Crea profilo', () async {
          final name = await _name('Nome del nuovo profilo');
          if (name != null) await TvProfiles.instance.create(name);
        }),
        _action('Entra come ospite', () async {
          final p = await TvProfiles.instance.create(
              'Ospite ${DateTime.now().millisecondsSinceEpoch}',
              guest: true);
          await TvProfiles.instance.select(p.id);
        }),
      ];
  static const _rows = {
    'jfRecent': 'Jellyfin recenti',
    'ytHistory': 'Cronologia YouTube',
    'ytHome': 'Per te su YouTube',
    'recent': 'Ascoltati di recente',
    'jfRandom': 'Jellyfin casuali',
    'charts': 'Classifiche',
    'sections': 'Sorgente online'
  };
  List<Widget> _home() {
    final order = List<String>.from(
        _workspace['homeOrder'] as List? ?? _rows.keys.toList());
    final hidden = List<String>.from(_workspace['hiddenRows'] as List? ?? []);
    return [
      const Text('Personalizza Home', style: TvText.title),
      for (var i = 0; i < order.length; i++) ...[
        _text(_rows[order[i]] ?? order[i]),
        Wrap(spacing: 10, children: [
          _action(hidden.contains(order[i]) ? 'Mostra' : 'Nascondi', () async {
            hidden.contains(order[i])
                ? hidden.remove(order[i])
                : hidden.add(order[i]);
            await _workspace.set('hiddenRows', hidden);
          }),
          if (i > 0)
            _action('Sposta su', () async {
              final r = order.removeAt(i);
              order.insert(i - 1, r);
              await _workspace.set('homeOrder', order);
            }),
          _action('Apri all’avvio qui', () async {
            await _workspace.set('startSection', order[i]);
          }),
        ]),
      ],
      const Text('Elementi fissati', style: TvText.title),
      for (var i = 0; i < TvSavedLibrary.instance.pins.length; i++) ...[
        _text(TvSavedLibrary.instance.pins[i].title),
        Wrap(spacing: 10, children: [
          _action('Sposta su', () => TvSavedLibrary.instance.movePin(i, -1)),
          _action(
              'Rimuovi',
              () => TvSavedLibrary.instance
                  .togglePin(TvSavedLibrary.instance.pins[i]))
        ]),
      ],
      _text(
          'Tieni premuto OK su una copertina per fissarla alla Home o salvarla nei preferiti.'),
    ];
  }

  List<Widget> _accessibility() => [
        const Text('Leggibilità e movimento', style: TvText.title),
        for (final scale in [1.0, 1.25, 1.5])
          _action('Testo ${(scale * 100).round()}%',
              () => _workspace.set('textScale', scale)),
        for (final entry in {
          'reduceMotion': 'Riduci animazioni',
          'strongFocus': 'Focus più marcato',
          'highContrast': 'Contrasto elevato'
        }.entries)
          _action('${_workspace[entry.key] == true ? '✓ ' : ''}${entry.value}',
              () => _workspace.set(entry.key, _workspace[entry.key] != true)),
        for (final delay in [80, 120, 240])
          _action(
              'Ripetizione frecce: ${delay == 80 ? 'veloce' : delay == 120 ? 'normale' : 'lenta'}',
              () => _workspace.set('keyRepeatMs', delay)),
        _action('Ripristina leggibilità', () async {
          for (final key in ['reduceMotion', 'strongFocus', 'highContrast']) {
            await _workspace.set(key, false);
          }
          await _workspace.set('textScale', 1.0);
        }),
      ];
  List<Widget> _phone() => [
        const Text('Telecomando musicale', style: TvText.title),
        _text('Installa Bloomee Remote sul cellulare e collegalo alla stessa rete della TV. Il codice vale 5 minuti; dopo l’abbinamento i controlli restano attivi fino alla chiusura dell’app TV, per un massimo di 12 ore.'),
        if (!tvRemote.active)
          _action('Collega Bloomee Remote', () => tvRemote.start()),
        if (tvRemote.active) ...[
          _text('Indirizzo TV: ${tvRemote.address}\nCodice: ${tvRemote.code}'),
          _action('Nuovo codice / scollega telefoni', () => tvRemote.start()),
          _action('Disattiva telecomando', tvRemote.close),
        ],
        const SizedBox(height: 24),
        const Text('Scrivi dal telefono', style: TvText.title),
        _text(
            'Abbinamento temporaneo sulla rete di casa. In questa versione invia solo ricerche e indirizzi pubblici: password, cookie e chiavi API vanno inseriti direttamente sulla TV.'),
        if (!tvPairing.active)
          _action('Apri abbinamento per 5 minuti', () => tvPairing.start()),
        if (tvPairing.active) ...[
          Align(
              alignment: Alignment.centerLeft,
              child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(12),
                  child: QrImageView(data: tvPairing.address!, size: 180))),
          _text('${tvPairing.address}\nCodice: ${tvPairing.code}'),
          _action('Chiudi abbinamento', tvPairing.close),
          if (tvPairing.pendingText != null)
            _text(
                'Testo ricevuto: ${tvPairing.pendingText}\nApri Cerca e confermalo nella tastiera.'),
        ],
      ];
  List<Widget> _operations() => [
        const Text('Download e richieste', style: TvText.title),
        _action('Aggiorna stato Lidarr', () async {
          final client = TvConfig.lidarr;
          if (client == null) throw StateError('Lidarr non collegato');
          for (final e in TvOperations.instance.entries.where(
              (e) => e['source'] == 'lidarr' && e['state'] != 'pronto')) {
            final state = await client.albumStatus(
                e['artist'] as String, e['title'] as String);
            await TvOperations.instance
                .update(e['id'] as String, {'state': state});
          }
        }),
        BlocBuilder<DownloaderCubit, DownloaderState>(
            builder: (_, state) =>
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final download in state.downloads) ...[
                    _text(
                        '${download.task.song.title}: ${download.status.state.name}'),
                    Wrap(spacing: 10, children: [
                      _action(
                          'Pausa',
                          () => context
                              .read<DownloaderCubit>()
                              .pauseDownload(download.task.taskId)),
                      _action(
                          'Riprendi',
                          () => context
                              .read<DownloaderCubit>()
                              .resumeDownload(download.task.taskId)),
                      _action(
                          'Annulla',
                          () => context
                              .read<DownloaderCubit>()
                              .cancelDownload(download.task.taskId))
                    ])
                  ],
                ])),
        for (final e in TvOperations.instance.entries.reversed) ...[
          _text(
              '${e['title']} · ${e['source']} · ${e['state']}${e['progress'] == null ? '' : ' · ${e['progress']}%'}\n${e['error'] ?? ''}'),
          if (e['source'] == 'locale' && e['state'] == 'in corso')
            _action('Annulla trasferimento', () async {
              TvOperations.instance.cancel(e['id'] as String);
            }),
          if (['errore', 'interrotto', 'annullato'].contains(e['state']) &&
              e['source'] == 'lidarr')
            _action('Riprova richiesta album', () async {
              final c = TvConfig.lidarr;
              if (c == null) throw StateError('Lidarr non collegato');
              await requestTrackedLidarr(c,
                  artist: e['artist'] as String, album: e['title'] as String);
            }),
          if (['errore', 'interrotto', 'annullato'].contains(e['state']) &&
              e['source'] == 'locale' &&
              e['track'] != null)
            _action('Riprova download locale', () async {
              final track =
                  tvTrackFromJson(Map<String, dynamic>.from(e['track'] as Map));
              await downloadTracksToDevice(context, [track], track.title);
            }),
        ],
        _text(
            'Una richiesta Lidarr accettata non garantisce che il file sia già disponibile. L’annullamento della ricerca sul server non è esposto qui.'),
      ];
  List<Widget> _storage() => [
        const Text('Spazio locale', style: TvText.title),
        FutureBuilder<(int, int)>(
            future: () async {
              final d =
                  await context.read<DownloaderCubit>().downloadDirectory();
              return (
                await TvStorage.usedBytes(d),
                await TvStorage.freeBytes(d.path)
              );
            }(),
            builder: (_, s) => _text(s.hasData
                ? 'Audio: ${s.data!.$1 ~/ (1024 * 1024)} MB · Liberi: ${s.data!.$2 ~/ (1024 * 1024)} MB'
                : 'Calcolo spazio…')),
        _text('Quota: ${_workspace['quotaMb'] ?? 2048} MB'),
        Wrap(spacing: 10, children: [
          for (final q in [512, 1024, 2048, 4096])
            _action('$q MB', () => _workspace.set('quotaMb', q))
        ]),
        _action(
            'Pulisci solo cache catalogo', TvCatalogCache.instance.clearAll),
        FutureBuilder<List<DownloadDB>>(
            future: _downloads.getValidDownloads(),
            builder: (_, snapshot) =>
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final d in snapshot.data ?? <DownloadDB>[]) ...[
                    _text(d.fileName),
                    _action(
                        (_workspace['protectedDownloads'] as List? ?? [])
                                .contains(d.mediaId)
                            ? '✓ Protetto (rimuovi protezione)'
                            : 'Proteggi dalla pulizia', () async {
                      final ids = List<String>.from(
                          _workspace['protectedDownloads'] as List? ?? []);
                      ids.contains(d.mediaId)
                          ? ids.remove(d.mediaId)
                          : ids.add(d.mediaId);
                      await _workspace.set('protectedDownloads', ids);
                    }),
                    if (!(_workspace['protectedDownloads'] as List? ?? [])
                        .contains(d.mediaId))
                      _action('Elimina questo download', () async {
                        final player =
                            context.read<BloomeePlayerCubit>().bloomeePlayer;
                        if (player.currentTrackInfo.id == d.mediaId)
                          throw StateError(
                              'Ferma e cambia il brano prima di eliminarlo');
                        final yes = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                                    title: Text('Eliminare ${d.fileName}?'),
                                    actions: [
                                      TextButton(
                                          autofocus: true,
                                          onPressed: () =>
                                              Navigator.pop(ctx, false),
                                          child: const Text('Annulla')),
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, true),
                                          child: const Text('Elimina'))
                                    ]));
                        if (yes == true)
                          await _downloads.removeDownload(d.mediaId);
                      }),
                  ],
                ])),
      ];
  List<Widget> _favorites() => [
        const Text('Preferiti unificati', style: TvText.title),
        _text(
            'Ogni elemento conserva tutte le versioni salvate e una sorgente preferita. Nessuna scrittura sul tuo account YouTube.'),
        for (final group in TvSavedLibrary.instance.favorites) ...[
          for (final raw in group['variants'] as List)
            Builder(builder: (_) {
              final reference =
                  TvReference(Map<String, dynamic>.from(raw as Map));
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _text(
                        '${reference.title} · ${reference.subtitle} · ${reference.id.split('::').first}'),
                    Wrap(spacing: 10, children: [
                      _action('Riproduci / apri',
                          () => openTvReference(context, reference)),
                      _action(
                          group['preferred'] == reference.id
                              ? '✓ Sorgente preferita'
                              : 'Preferisci questa sorgente',
                          () => TvSavedLibrary.instance.prefer(
                              group['identity'] as String, reference.id)),
                      _action(
                          'Separa versione',
                          () => TvSavedLibrary.instance.split(
                              group['identity'] as String, reference.id)),
                      _action('Fissa / rimuovi Home',
                          () => TvSavedLibrary.instance.togglePin(reference))
                    ]),
                  ]);
            }),
          _action(
              'Rimuovi preferito',
              () => TvSavedLibrary.instance
                  .removeFavorite(group['identity'] as String)),
          _action('Unisci a un altro preferito', () async {
            final choices = TvSavedLibrary.instance.favorites
                .where((g) => g['identity'] != group['identity'])
                .toList();
            final target = await showDialog<String>(
                context: context,
                builder: (ctx) => SimpleDialog(
                        title:
                            const Text('Scegli il preferito di destinazione'),
                        children: [
                          for (final g in choices)
                            SimpleDialogOption(
                                onPressed: () =>
                                    Navigator.pop(ctx, g['identity']),
                                child: Text(TvReference(
                                        Map<String, dynamic>.from(
                                            (g['variants'] as List).first
                                                as Map))
                                    .title))
                        ]));
            if (target != null)
              await TvSavedLibrary.instance
                  .merge(group['identity'] as String, target);
          }),
        ],
      ];
  List<Widget> _playlistList() => [
        const Text('Playlist locali', style: TvText.title),
        _action('Crea playlist', () async {
          final name = await _name('Nome playlist');
          if (name != null && name.trim().isNotEmpty) {
            if (await _playlists.getPlaylistByName(name) != null)
              throw StateError('Nome già usato');
            await _playlists.createPlaylist(name);
          }
        }),
        FutureBuilder<List<PlaylistDB>>(
            future: _playlists.getAllPlaylists(),
            builder: (_, snapshot) =>
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final playlist in snapshot.data ?? <PlaylistDB>[])
                    if (!DBProvider.standardPlaylists.contains(playlist.name))
                      _action(playlist.name, () async {
                        await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => TvTrackEditor(
                                    playlistId: playlist.id,
                                    title: playlist.name)));
                      }),
                ])),
      ];
  List<Widget> _timer() {
    final p = context.read<BloomeePlayerCubit>().bloomeePlayer;
    return [
      ListenableBuilder(
          listenable: p.sleepTimer,
          builder: (_, __) => _text(p.sleepTimer.label)),
      for (final minutes in [15, 30, 45, 60, 90])
        _action(
            'Tra $minutes minuti',
            () => p.sleepTimer.start(SleepMode.duration,
                duration: Duration(minutes: minutes))),
      _action(
          'Alla fine di questo brano',
          () => p.sleepTimer.start(SleepMode.track,
              trackId: p.queueTracks.isEmpty ? null : p.currentTrackInfo.id)),
      _action(
          'Alla fine di questo album',
          () => p.sleepTimer
              .start(SleepMode.album, albumId: p.currentTrackInfo.album?.id)),
      _action('Annulla timer', p.sleepTimer.cancel),
      _text(
          'Ferma l’audio con dissolvenza, non spegne fisicamente il televisore. Il cambio profilo annulla il timer.'),
    ];
  }

  List<Widget> _audio() {
    final engine = context.read<BloomeePlayerCubit>().bloomeePlayer.engine;
    return [
      _text('Volume uniforme (ReplayGain)'),
      _text(
          'Usa i tag di loudness del file, con protezione dal clipping e margine di −6 dB. Se i tag mancano, il volume resta invariato. Non analizza né normalizza in tempo reale gli stream senza metadati.'),
      _action(
          engine.loudnessEnabled ? 'Disattiva ReplayGain' : 'Attiva ReplayGain',
          () async {
        await engine.setLoudnessEnabled(!engine.loudnessEnabled);
        await _workspace.set('loudness', engine.loudnessEnabled);
      }),
    ];
  }

  List<Widget> _diagnostics() => [
        _text('Stato connessioni e sessione multimediale'),
        _action('Verifica servizi', () async {
          for (final pair in <(String, Future<Object?> Function())>[
            if (TvConfig.hasJellyfin)
              ('Jellyfin', () => TvConfig.jellyfin!.serverName()),
            if (TvConfig.hasLidarr) ('Lidarr', () => TvConfig.lidarr!.ping()),
            if (TvConfig.hasYouTube)
              ('YouTube', () => TvConfig.youtube.accountName()),
          ]) {
            try {
              await pair.$2().timeout(const Duration(seconds: 30));
              TvDiagnostics.instance.record(pair.$1, 'Collegamento riuscito');
            } catch (e) {
              TvDiagnostics.instance.record(pair.$1, e);
            }
          }
        }),
        StreamBuilder(
            stream: context.read<BloomeePlayerCubit>().bloomeePlayer.mediaItem,
            builder: (_, s) => _text(
                'Sessione Android: ${s.data?.title ?? 'nessun brano'} · ${s.data?.artist ?? ''}\nCopertina: ${s.data?.artUri == null ? 'assente' : 'pubblicata'}')),
        FutureBuilder<String>(
            future: TvCastService.status(),
            builder: (_, s) => _text(s.data ?? 'Verifico Cast…')),
        _action('Esporta rapporto (anteprima)', () async {
          final report = TvDiagnostics.instance.export();
          final yes = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                      title: const Text('Rapporto senza credenziali'),
                      content:
                          SingleChildScrollView(child: SelectableText(report)),
                      actions: [
                        TextButton(
                            autofocus: true,
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Annulla')),
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Condividi'))
                      ]));
          if (yes == true)
            await SharePlus.instance.share(
                ShareParams(text: report, subject: 'Diagnostica Bloomee TV'));
        }),
        _action('Cancella diagnostica', () async {
          TvDiagnostics.instance.clear();
        }),
        for (final event in TvDiagnostics.instance.events.reversed)
          _text('${event['time']} · ${event['area']}\n${event['message']}'),
      ];
}

/// Shared D-pad editor: actions are explicit, with one-step undo and occurrence
/// indices so duplicate IDs in an imported queue do not select the wrong row.
class TvTrackEditor extends StatefulWidget {
  const TvTrackEditor({super.key, this.playlistId, this.title = 'Coda'});
  final int? playlistId;
  final String title;
  @override
  State<TvTrackEditor> createState() => _TvTrackEditorState();
}

class _EditableTrack {
  _EditableTrack(this.track);
  final Track track;
}

class _TvTrackEditorState extends State<TvTrackEditor> {
  final _dao = PlaylistDAO(DBProvider.db, TrackDAO(DBProvider.db));
  List<_EditableTrack>? _entries, _undo;
  final Set<_EditableTrack> _selected = {};
  String? _message;
  String _query = '';
  bool _saving = false;
  late String _title = widget.title;
  List<Track> get _tracks => _entries!.map((e) => e.track).toList();
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final id = widget.playlistId;
      final tracks = id == null
          ? context.read<BloomeePlayerCubit>().bloomeePlayer.queueTracks
          : (await _dao.getPlaylistTracks(id)).map(trackDBToTrack).toList();
      if (mounted)
        setState(() {
          _entries = tracks.map(_EditableTrack.new).toList();
          _undo = null;
          _selected.clear();
          _message = null;
        });
    } catch (e) {
      if (mounted)
        setState(() => _message = TvDiagnostics.redact(e.toString()));
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted)
        setState(() => _message = TvDiagnostics.redact(e.toString()));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _apply(List<_EditableTrack> next) => _run(() async {
        final before = List<_EditableTrack>.of(_entries!);
        final tracks = next.map((e) => e.track).toList();
        if (widget.playlistId != null) {
          await _dao.setPlaylistTracks(widget.playlistId!, tracks);
        } else {
          await context
              .read<BloomeePlayerCubit>()
              .bloomeePlayer
              .editQueueTracks(before.map((e) => e.track).toList(), tracks,
                  next.map(before.indexOf).toList());
        }
        if (mounted)
          setState(() {
            _undo = before;
            _entries = next;
            _selected.clear();
          });
      });
  Future<void> _saveCopy() => _run(() async {
        final name =
            await showTvKeyboard(context, title: 'Nome della playlist');
        if (name == null || name.trim().isEmpty) return;
        if (await _dao.getPlaylistByName(name.trim()) != null)
          throw StateError('Nome già usato');
        final id = await _dao.createPlaylist(name.trim());
        if (id != null) await _dao.setPlaylistTracks(id, _tracks);
        if (mounted) setState(() => _message = 'Playlist salvata');
      });
  Widget _button(IconData icon, String label, VoidCallback? action) =>
      TvPillButton(icon: icon, label: label, onTap: _saving ? null : action);
  @override
  Widget build(BuildContext context) {
    final player = context.read<BloomeePlayerCubit>().bloomeePlayer;
    return Scaffold(
        appBar: AppBar(title: Text(_title)),
        body: Column(children: [
          if (_message != null)
            Padding(padding: const EdgeInsets.all(8), child: Text(_message!)),
          if (_saving) const LinearProgressIndicator(),
          Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(spacing: 12, runSpacing: 8, children: [
                _button(Icons.refresh, 'Ricarica lista', _load),
                _button(Icons.undo, 'Annulla ultima modifica',
                    _undo == null ? null : () => _apply(List.of(_undo!))),
                _button(Icons.playlist_add, 'Salva una copia',
                    _entries == null ? null : _saveCopy),
                _button(
                    Icons.delete,
                    'Rimuovi selezionati',
                    _selected.isEmpty
                        ? null
                        : () => _apply(_entries!
                            .where((e) => !_selected.contains(e))
                            .toList())),
                _button(Icons.search,
                    _query.isEmpty ? 'Cerca nella lista' : 'Filtro: $_query',
                    () async {
                  final q = await showTvKeyboard(context,
                      title: 'Filtra titolo o artista', initial: _query);
                  if (q != null && mounted) setState(() => _query = q);
                }),
                if (widget.playlistId != null) ...[
                  _button(
                      Icons.edit,
                      'Rinomina',
                      () => _run(() async {
                            final name = await showTvKeyboard(context,
                                title: 'Nuovo nome', initial: _title);
                            if (name == null ||
                                name.trim().isEmpty ||
                                name.trim() == _title) return;
                            if (await _dao.getPlaylistByName(name.trim()) !=
                                null) throw StateError('Nome già usato');
                            await _dao.updatePlaylistMeta(widget.playlistId!,
                                name: name.trim());
                            if (mounted) setState(() => _title = name.trim());
                          })),
                  _button(
                      Icons.image,
                      'Copertina',
                      () => _run(() async {
                            final url = await showTvKeyboard(context,
                                title: 'URL pubblico HTTPS della copertina');
                            if (url == null) return;
                            final uri = Uri.tryParse(url);
                            if (uri?.scheme != 'https' ||
                                uri!.host.isEmpty ||
                                uri.userInfo.isNotEmpty)
                              throw ArgumentError('Indirizzo HTTPS non valido');
                            await _dao.updatePlaylistThumbnail(
                                widget.playlistId!, url);
                          })),
                  _button(
                      Icons.add,
                      'Aggiungi la coda attuale',
                      _entries == null
                          ? null
                          : () => _apply([
                                ..._entries!,
                                ...player.queueTracks.map(_EditableTrack.new)
                              ])),
                  _button(
                      Icons.delete_forever,
                      'Elimina playlist',
                      () => _run(() async {
                            final yes = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                        title: Text('Eliminare $_title?'),
                                        actions: [
                                          TextButton(
                                              autofocus: true,
                                              onPressed: () =>
                                                  Navigator.pop(ctx, false),
                                              child: const Text('Annulla')),
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, true),
                                              child: const Text('Elimina'))
                                        ]));
                            if (yes == true) {
                              await _dao.deletePlaylist(widget.playlistId!);
                              if (mounted) Navigator.pop(context);
                            }
                          })),
                ],
              ])),
          if (widget.playlistId == null)
            const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                    'Su e Giù cambiano l’ordine effettivo e disattivano la riproduzione casuale. Il brano in ascolto continua; se lo rimuovi la riproduzione si ferma.')),
          Expanded(
              child: _entries == null
                  ? const Center(child: CircularProgressIndicator())
                  : _entries!.isEmpty
                      ? const Center(child: Text('La lista è vuota'))
                      : StreamBuilder(
                          stream: player.playbackState,
                          builder: (_, __) => ListView.builder(
                              itemCount: _entries!.length,
                              itemBuilder: (_, i) {
                                final entry = _entries![i];
                                final track = entry.track;
                                if (!tvNormalize(
                                        '${track.title} ${track.artists.map((a) => a.name).join(' ')}')
                                    .contains(tvNormalize(_query)))
                                  return const SizedBox.shrink();
                                final playing = widget.playlistId == null &&
                                    i == player.currentQueueIndex;
                                return Padding(
                                    key: ObjectKey(entry),
                                    padding: const EdgeInsets.all(10),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                              '${i + 1}. ${track.title}${playing ? ' · In ascolto' : ''}',
                                              style: TvText.title),
                                          Text(
                                              track.artists
                                                  .map((a) => a.name)
                                                  .join(', '),
                                              style: TvText.body),
                                          Wrap(
                                              spacing: 10,
                                              runSpacing: 6,
                                              children: [
                                                _button(
                                                    _selected.contains(entry)
                                                        ? Icons.check_box
                                                        : Icons
                                                            .check_box_outline_blank,
                                                    'Seleziona',
                                                    () => setState(() =>
                                                        _selected
                                                                .contains(entry)
                                                            ? _selected
                                                                .remove(entry)
                                                            : _selected
                                                                .add(entry))),
                                                _button(
                                                    Icons.arrow_upward,
                                                    'Su',
                                                    i == 0
                                                        ? null
                                                        : () {
                                                            final next = List<
                                                                    _EditableTrack>.of(
                                                                _entries!);
                                                            next.insert(
                                                                i - 1,
                                                                next.removeAt(
                                                                    i));
                                                            _apply(next);
                                                          }),
                                                _button(
                                                    Icons.arrow_downward,
                                                    'Giù',
                                                    i == _entries!.length - 1
                                                        ? null
                                                        : () {
                                                            final next = List<
                                                                    _EditableTrack>.of(
                                                                _entries!);
                                                            next.insert(
                                                                i + 1,
                                                                next.removeAt(
                                                                    i));
                                                            _apply(next);
                                                          }),
                                                _button(
                                                    Icons.delete_outline,
                                                    'Rimuovi',
                                                    () => _apply(
                                                        List<_EditableTrack>.of(
                                                            _entries!)
                                                          ..removeAt(i))),
                                              ]),
                                        ]));
                              }),
                        )),
        ]));
  }
}
