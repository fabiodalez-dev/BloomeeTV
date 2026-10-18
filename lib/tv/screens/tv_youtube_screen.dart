import 'package:Bloomee/blocs/media_player/bloomee_player_cubit.dart';
import 'package:Bloomee/core/models/media_playlist_model.dart';
import 'package:Bloomee/core/models/exported.dart';
import 'package:Bloomee/screens/widgets/snackbar.dart';
import 'package:Bloomee/tv/connectors/ytmusic_account.dart';
import 'package:Bloomee/tv/lidarr_action.dart';
import 'package:Bloomee/tv/screens/tv_artist_screen.dart';
import 'package:Bloomee/tv/tv_config.dart';
import 'package:Bloomee/tv/ui/tv_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

const _channel = MethodChannel('bloomee_tv/voice');

/// Accesso a YouTube Music: apre la pagina di login Google, poi salva i
/// cookie e il nome dell'account. true se riuscito.
Future<bool> loginYouTube() async {
  try {
    final r = await _channel.invokeMethod<Map>('ytLogin');
    if (r == null) return false;
    final cookie = r['cookie'] as String? ?? '';
    final visitor = r['visitorData'] as String? ?? '';
    final dataSync = r['dataSyncId'] as String? ?? '';
    final c = YtMusicClient(cookie: cookie, visitorData: visitor, dataSyncId: dataSync);
    final name = await c.accountName() ?? 'account Google';
    await TvConfig.saveYouTube(cookie: cookie, visitor: visitor, dataSync: dataSync, name: name);
    return true;
  } catch (e) {
    SnackbarService.showMessage('Accesso YouTube non riuscito: $e', duration: const Duration(seconds: 5));
    return false;
  }
}

/// Brani di un album o playlist di YouTube Music (per scaricarli sul Chromecast).
Future<List<Track>> ytCollectionTracks(String browseId) async {
  try {
    final c = await TvConfig.youtube.collection(browseId);
    return [for (final t in c.tracks) t.toTrack()];
  } catch (_) {
    return [];
  }
}

Future<void> logoutYouTube() async {
  try {
    await _channel.invokeMethod('ytLogout');
  } catch (_) {}
  await TvConfig.saveYouTube(cookie: '', visitor: '', dataSync: '', name: '');
}

/// Riproduce una lista di elementi YouTube (solo i brani).
void playYtItems(BuildContext context, List<YtItem> items, int index, String title, {bool shuffle = false}) {
  final songs = items.where((i) => i.videoId != null).toList();
  if (songs.isEmpty) return;
  final start = index < items.length ? songs.indexOf(items[index]) : 0;
  context.read<BloomeePlayerCubit>().bloomeePlayer.loadPlaylist(
        Playlist(tracks: songs.map((e) => e.toTrack()).toList(), title: title),
        idx: start < 0 ? 0 : start,
        doPlay: true,
        shuffling: shuffle,
      );
}

/// Apre un elemento YouTube: brano = suona, album/playlist = pagina, artista = pagina artista.
void openYtItem(BuildContext context, YtItem it, List<YtItem> context_, String listTitle) {
  switch (it.kind) {
    case 'song':
      playYtItems(context, context_, context_.indexOf(it), listTitle);
    case 'artist':
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TvArtistScreen(artist: it.toArtist(), pluginId: kYtMusicPluginId)));
    default:
      if (it.browseId != null) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => TvYtCollectionScreen(browseId: it.browseId!, fallbackTitle: it.title)));
      }
  }
}

/// Card per un elemento YouTube.
Widget ytCard(BuildContext context, YtItem it, List<YtItem> all, String listTitle, {VoidCallback? onFocused}) {
  return TvCard(
    title: it.title,
    subtitle: it.kind == 'artist' ? 'Artista' : (it.artistNames.isNotEmpty ? it.artistNames : it.subtitle),
    imageUrl: it.thumbnail,
    circle: it.kind == 'artist',
    badge: it.kind == 'song' ? Icons.play_arrow_rounded : null,
    onFocused: onFocused,
    onTap: () => openYtItem(context, it, all, listTitle),
    onLongPress: it.kind == 'album'
        ? () => showDownloadMenu(context,
            artist: it.artistNames.isNotEmpty ? it.artistNames : it.subtitle.split(' • ').last,
            album: it.title,
            albumTracks: it.browseId == null ? null : () => ytCollectionTracks(it.browseId!))
        : (it.kind == 'song'
            ? () => showDownloadMenu(context, artist: it.artistNames, album: it.album?.name ?? '', track: it.toTrack())
            : null),
  );
}

enum _YtTab { forYou, history, liked, playlists, albums, artists }

/// "Il mio YouTube": home personalizzata, cronologia, Mi piace, playlist,
/// album e artisti seguiti dell'account collegato.
class TvYouTubeScreen extends StatefulWidget {
  const TvYouTubeScreen({super.key});

  @override
  State<TvYouTubeScreen> createState() => _TvYouTubeScreenState();
}

class _TvYouTubeScreenState extends State<TvYouTubeScreen> {
  _YtTab _tab = _YtTab.forYou;
  Future<Object>? _future;

  static const _labels = {
    _YtTab.forYou: ('Per te', Icons.auto_awesome_rounded),
    _YtTab.history: ('Cronologia', Icons.history_rounded),
    _YtTab.liked: ('Mi piace', Icons.thumb_up_rounded),
    _YtTab.playlists: ('Playlist', Icons.queue_music_rounded),
    _YtTab.albums: ('Album', Icons.album_rounded),
    _YtTab.artists: ('Artisti', Icons.person_rounded),
  };

  @override
  void initState() {
    super.initState();
    _load();
    TvConfig.changes.addListener(_load);
  }

  @override
  void dispose() {
    TvConfig.changes.removeListener(_load);
    super.dispose();
  }

  void _load() {
    if (!TvConfig.hasYouTube) {
      setState(() => _future = null);
      return;
    }
    final c = TvConfig.youtube;
    setState(() {
      _future = switch (_tab) {
        _YtTab.forYou => c.home(),
        _YtTab.history => c.history(),
        _YtTab.liked => c.likedSongs(),
        _YtTab.playlists => c.libraryPlaylists(),
        _YtTab.albums => c.libraryAlbums(),
        _YtTab.artists => c.subscribedArtists(),
      };
    });
  }

  Widget _grid(List<YtItem> items, String title) {
    final songs = items.any((i) => i.kind == 'song');
    if (!songs) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(48, 12, 48, 24),
        children: [
          Wrap(
            spacing: 22,
            runSpacing: 14,
            children: [for (final it in items) SizedBox(height: 250, child: ytCard(context, it, items, title))],
          ),
        ],
      );
    }
    // Brani: pulsanti fissi sopra, la lista scorre sotto.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(48, 12, 48, 12),
          child: Row(children: [
            TvPillButton(icon: Icons.play_arrow_rounded, label: 'Riproduci tutto', primary: true, onTap: () => playYtItems(context, items, 0, title)),
            const SizedBox(width: 12),
            TvPillButton(icon: Icons.shuffle_rounded, label: 'Casuale', onTap: () => playYtItems(context, items, 0, title, shuffle: true)),
            const SizedBox(width: 12),
            TvPillButton(
              icon: Icons.download_rounded,
              label: 'Scarica',
              onTap: () => showDownloadMenu(context,
                  artist: '',
                  album: '',
                  listTitle: title,
                  listTracks: [for (final t in items) t.toTrack()],
                  albumTracks: () async => [for (final t in items) t.toTrack()]),
            ),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(48, 4, 48, 24),
            itemCount: items.length,
            itemBuilder: (_, i) => TvTrackTile(
              index: i + 1,
              title: items[i].title,
              subtitle: [items[i].artistNames, if (items[i].album != null) items[i].album!.name].where((e) => e.isNotEmpty).join(' · '),
              duration: items[i].duration,
              onTap: () => playYtItems(context, items, i, title),
              onLongPress: () => showDownloadMenu(context, artist: items[i].artistNames, album: items[i].album?.name ?? '', track: items[i].toTrack()),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TvColors.bg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(48, 36, 48, 16),
            child: Row(children: [
              const Text('Il mio YouTube', style: TvText.hero),
              const SizedBox(width: 20),
              if (TvConfig.hasYouTube) Text(TvConfig.ytName, style: TvText.body),
            ]),
          ),
          if (!TvConfig.hasYouTube)
            Expanded(
              child: TvMessage(
                icon: Icons.account_circle_rounded,
                text: 'Collega il tuo account YouTube Music per vedere\ncronologia, Mi piace, playlist e artisti seguiti.',
                action: TvPillButton(
                  icon: Icons.login_rounded,
                  label: 'Accedi con Google',
                  primary: true,
                  autofocus: true,
                  onTap: () async {
                    if (await loginYouTube()) _load();
                  },
                ),
              ),
            )
          else ...[
            SizedBox(
              height: 64,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 4),
                children: [
                  for (final t in _YtTab.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: TvPillButton(
                        icon: _labels[t]!.$2,
                        label: _labels[t]!.$1,
                        primary: t == _tab,
                        autofocus: t == _YtTab.forYou,
                        onTap: () {
                          _tab = t;
                          _load();
                        },
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<Object>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const TvMessage(icon: Icons.hourglass_empty, text: 'Carico…', loading: true);
                  }
                  if (snap.hasError) {
                    return TvMessage(icon: Icons.cloud_off_rounded, text: '${snap.error}');
                  }
                  final data = snap.data;
                  if (data is List<YtSection>) {
                    return ListView(
                      padding: const EdgeInsets.only(top: 12, bottom: 24),
                      children: [
                        for (final s in data)
                          TvRow(
                            title: s.title,
                            itemCount: s.items.length,
                            itemBuilder: (_, i) => ytCard(context, s.items[i], s.items, s.title),
                          ),
                      ],
                    );
                  }
                  final items = (data as List<YtItem>?) ?? const [];
                  if (items.isEmpty) return const TvMessage(icon: Icons.inbox_rounded, text: 'Niente da mostrare');
                  return _grid(items, _labels[_tab]!.$1);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Playlist o album di YouTube Music: copertina, Riproduci/Casuale, brani.
class TvYtCollectionScreen extends StatefulWidget {
  const TvYtCollectionScreen({super.key, required this.browseId, this.fallbackTitle = ''});
  final String browseId;
  final String fallbackTitle;

  @override
  State<TvYtCollectionScreen> createState() => _TvYtCollectionScreenState();
}

class _TvYtCollectionScreenState extends State<TvYtCollectionScreen> {
  late final _future = TvConfig.youtube.collection(widget.browseId);
  final _playNode = FocusNode();
  bool _focused = false;

  @override
  void dispose() {
    _playNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAlbum = widget.browseId.startsWith('MPREb');
    return Scaffold(
      backgroundColor: TvColors.bg,
      body: FutureBuilder(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return TvMessage(icon: Icons.error_outline, text: '${snap.error}');
          if (snap.connectionState != ConnectionState.done) {
            return const TvMessage(icon: Icons.hourglass_empty, text: 'Carico…', loading: true);
          }
          final c = snap.data!;
          final title = c.title.isEmpty ? widget.fallbackTitle : c.title;
          final tracks = c.tracks;
          if (!_focused) {
            _focused = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _playNode.requestFocus();
            });
          }
          final artist = tracks.isNotEmpty && tracks.first.artistNames.isNotEmpty ? tracks.first.artistNames : (c.subtitle ?? '');
          return TvCollectionLayout(
            cover: TvCover(c.thumbnail, size: 240, radius: 14),
            title: title,
            meta: [if (c.subtitle != null) c.subtitle!, '${tracks.length} brani'].join(' · '),
            actions: [
              TvPillButton(
                focusNode: _playNode,
                icon: Icons.play_arrow_rounded,
                label: 'Riproduci',
                primary: true,
                onTap: tracks.isEmpty ? null : () => playYtItems(context, tracks, 0, title),
              ),
              TvPillButton(
                icon: Icons.shuffle_rounded,
                label: 'Casuale',
                onTap: tracks.isEmpty ? null : () => playYtItems(context, tracks, 0, title, shuffle: true),
              ),
              TvPillButton(
                icon: Icons.download_rounded,
                label: 'Scarica',
                onTap: () => showDownloadMenu(context,
                    artist: artist,
                    album: isAlbum ? title : '',
                    listTitle: title,
                    listTracks: [for (final t in tracks) t.toTrack()],
                    albumTracks: () async => [for (final t in tracks) t.toTrack()]),
              ),
            ],
            itemCount: tracks.length,
            itemBuilder: (_, i) => TvTrackTile(
              index: i + 1,
              title: tracks[i].title,
              subtitle: isAlbum ? null : tracks[i].artistNames,
              duration: tracks[i].duration,
              onTap: () => playYtItems(context, tracks, i, title),
              onLongPress: () => showDownloadMenu(context, artist: tracks[i].artistNames, album: tracks[i].album?.name ?? '', track: tracks[i].toTrack()),
            ),
          );
        },
      ),
    );
  }
}
