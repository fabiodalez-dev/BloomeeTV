import 'package:Bloomee/tv/services/tv_workspace.dart';
import 'package:Bloomee/tv/services/tv_diagnostics.dart';
import 'package:Bloomee/blocs/media_player/bloomee_player_cubit.dart';
import 'package:Bloomee/core/models/media_playlist_model.dart';
import 'package:Bloomee/screens/widgets/snackbar.dart';
import 'package:Bloomee/tv/connectors/jellyfin_client.dart';
import 'package:Bloomee/tv/lidarr_action.dart';
import 'package:Bloomee/tv/tv_config.dart';
import 'package:Bloomee/tv/ui/tv_widgets.dart';
import 'package:flutter/material.dart';
import 'package:Bloomee/tv/screens/tv_control_center.dart';
import 'package:Bloomee/tv/services/tv_saved_library.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Riproduce un album Jellyfin dall'inizio (o in ordine casuale).
Future<void> playJellyfinAlbum(BuildContext context, JfItem album,
    {bool shuffle = false, int index = 0, List<JfItem>? tracks}) async {
  final jf = TvConfig.jellyfin;
  if (jf == null) return;
  try {
    final items = tracks ?? await jf.albumTracks(album.id);
    if (items.isEmpty) {
      SnackbarService.showMessage('Album vuoto');
      return;
    }
    if (!context.mounted) return;
    await context.read<BloomeePlayerCubit>().bloomeePlayer.loadPlaylist(
          Playlist(
              tracks: items.map((e) => e.toTrack(jf)).toList(),
              title: album.name),
          idx: index,
          doPlay: true,
          shuffling: shuffle,
        );
  } catch (e) {
    SnackbarService.showMessage('Jellyfin: $e');
  }
}

enum _JfTab { recent, albums, artists, random, search }

/// La libreria musicale di Jellyfin a schermo intero, a griglia.
class TvJellyfinScreen extends StatefulWidget {
  const TvJellyfinScreen({super.key});

  @override
  State<TvJellyfinScreen> createState() => _TvJellyfinScreenState();
}

class _TvJellyfinScreenState extends State<TvJellyfinScreen> {
  _JfTab _tab = _JfTab.recent;
  Future<List<JfItem>>? _future;
  final _query = TextEditingController();
  String? _genre;
  int? _year;
  String? _initial;
  String _sort = 'SortName';

  static const _labels = {
    _JfTab.recent: ('Recenti', Icons.new_releases_rounded),
    _JfTab.albums: ('Album A-Z', Icons.album_rounded),
    _JfTab.artists: ('Artisti', Icons.person_rounded),
    _JfTab.random: ('Casuali', Icons.shuffle_rounded),
    _JfTab.search: ('Cerca', Icons.search_rounded),
  };

  @override
  void initState() {
    super.initState();
    final filters = TvWorkspace.instance['jellyfinFilters'] as Map? ?? {};
    _genre = filters['genre'] as String?;
    _year = filters['year'] as int?;
    _initial = filters['initial'] as String?;
    _sort = filters['sort'] as String? ?? 'SortName';
    _load();
    TvConfig.changes.addListener(_load);
  }

  @override
  void dispose() {
    TvConfig.changes.removeListener(_load);
    _query.dispose();
    super.dispose();
  }

  void _load() {
    if (TvWorkspace.instance.initialized)
      TvWorkspace.instance.set('jellyfinFilters', {
        'genre': _genre,
        'year': _year,
        'initial': _initial,
        'sort': _sort
      }).catchError((Object e) {
        TvDiagnostics.instance.record('Filtri Jellyfin', e);
      });
    final jf = TvConfig.jellyfin;
    if (jf == null) {
      setState(() => _future = null);
      return;
    }
    setState(() {
      _future = switch (_tab) {
        _JfTab.recent => jf.recentAlbums(limit: 60),
        _JfTab.albums => jf.albums(
            genre: _genre, year: _year, startsWith: _initial, sortBy: _sort),
        _JfTab.artists => jf.artists(limit: 400),
        _JfTab.random => jf.randomAlbums(limit: 60),
        _JfTab.search => _query.text.trim().isEmpty
            ? Future.value(const <JfItem>[])
            : jf.search(_query.text.trim(), limit: 60),
      };
    });
  }

  void _openItem(JfItem it) {
    final jf = TvConfig.jellyfin!;
    switch (it.type) {
      case 'MusicArtist':
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => TvJellyfinArtistScreen(artist: it)));
      case 'Audio':
        context
            .read<BloomeePlayerCubit>()
            .bloomeePlayer
            .updateQueueTracks([it.toTrack(jf)], doPlay: true);
      default:
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => TvJellyfinAlbumScreen(album: it)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final jf = TvConfig.jellyfin;
    return Scaffold(
      backgroundColor: TvColors.bg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(48, 36, 48, 16),
            child: Text('La tua musica', style: TvText.hero),
          ),
          if (jf == null)
            const Expanded(
              child: TvMessage(
                icon: Icons.dns_rounded,
                text:
                    'Jellyfin non è collegato.\nApri Impostazioni nel menu a sinistra.',
              ),
            )
          else ...[
            SizedBox(
              height: 64,
              child: FocusTraversalGroup(
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 48, vertical: 4),
                  children: [
                    for (final t in _JfTab.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: TvPillButton(
                          icon: _labels[t]!.$2,
                          label: _labels[t]!.$1,
                          primary: t == _tab,
                          autofocus: t == _JfTab.recent,
                          onTap: () {
                            _tab = t;
                            _load();
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_tab == _JfTab.search)
              Padding(
                padding: const EdgeInsets.fromLTRB(48, 12, 48, 0),
                child: TvTextField(
                  controller: _query,
                  label: 'Artista, album o brano',
                  prefixIcon: Icons.search,
                  onSubmitted: (_) => _load(),
                ),
              ),
            if (_tab == _JfTab.albums)
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: Wrap(spacing: 10, children: [
                    TvPillButton(
                        icon: Icons.sort_by_alpha,
                        label: _initial ?? 'Iniziale',
                        onTap: () async {
                          final value = await showTvKeyboard(context,
                              title: 'Iniziale (vuoto = tutte)');
                          if (!mounted || value == null) return;
                          _initial = value.trim().isEmpty ? null : value.trim();
                          _load();
                        }),
                    TvPillButton(
                        icon: Icons.category,
                        label: _genre ?? 'Genere',
                        onTap: () async {
                          final value = await showTvKeyboard(context,
                              title: 'Genere esatto (vuoto = tutti)');
                          if (!mounted || value == null) return;
                          _genre = value.trim().isEmpty ? null : value.trim();
                          _load();
                        }),
                    TvPillButton(
                        icon: Icons.date_range,
                        label: _year?.toString() ?? 'Anno',
                        onTap: () async {
                          final value = await showTvKeyboard(context,
                              title: 'Anno (vuoto = tutti)');
                          if (!mounted || value == null) return;
                          _year = int.tryParse(value);
                          _load();
                        }),
                    TvPillButton(
                        icon: Icons.sort,
                        label: _sort == 'SortName' ? 'Titolo A–Z' : 'Anno',
                        onTap: () {
                          _sort = _sort == 'SortName'
                              ? 'ProductionYear,SortName'
                              : 'SortName';
                          _load();
                        }),
                    TvPillButton(
                        icon: Icons.refresh,
                        label: 'Azzera filtri',
                        onTap: () {
                          _genre = null;
                          _year = null;
                          _initial = null;
                          _load();
                        }),
                  ])),
            Expanded(
              child: FutureBuilder<List<JfItem>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const TvMessage(
                        icon: Icons.hourglass_empty,
                        text: 'Carico…',
                        loading: true);
                  }
                  if (snap.hasError) {
                    return TvMessage(
                        icon: Icons.cloud_off_rounded,
                        text:
                            'Jellyfin non risponde. Verifica il server nelle Impostazioni.',
                        action: TextButton(
                            onPressed: _load, child: const Text('Riprova')));
                  }
                  final items = snap.data ?? const [];
                  if (items.isEmpty) {
                    return TvMessage(
                        icon: Icons.library_music_outlined,
                        text: _tab == _JfTab.search
                            ? 'Scrivi qualcosa e premi Cerca'
                            : 'Niente da mostrare');
                  }
                  return GridView.builder(
                    padding: const EdgeInsets.fromLTRB(48, 20, 48, 120),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 200,
                      mainAxisExtent: 250,
                      crossAxisSpacing: 22,
                      mainAxisSpacing: 14,
                    ),
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final it = items[i];
                      final circle = it.type == 'MusicArtist';
                      return TvCard(
                        title: it.name,
                        subtitle: switch (it.type) {
                          'MusicArtist' => 'Artista',
                          'Audio' => '${it.albumArtist} · brano',
                          _ =>
                            '${it.albumArtist}${it.year != null ? ' · ${it.year}' : ''}',
                        },
                        imageUrl: it.imageItemId == null
                            ? null
                            : jf.imageUrl(it.imageItemId!, maxSize: 400),
                        circle: circle,
                        badge: it.type == 'Audio'
                            ? Icons.play_arrow_rounded
                            : null,
                        onTap: () => _openItem(it),
                        onLongPress: () => showTvReferenceMenu(
                            context, TvReference.item(it.toMedia(jf)),
                            download: it.type == 'MusicAlbum'
                                ? () => showDownloadMenu(context,
                                    artist: it.albumArtist,
                                    album: it.name,
                                    albumTracks: () async =>
                                        (await jf.albumTracks(it.id))
                                            .map((t) => t.toTrack(jf))
                                            .toList())
                                : null),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Album Jellyfin: copertina grande, Riproduci / Casuale, lista brani.
class TvJellyfinAlbumScreen extends StatefulWidget {
  const TvJellyfinAlbumScreen({super.key, required this.album});
  final JfItem album;

  @override
  State<TvJellyfinAlbumScreen> createState() => _TvJellyfinAlbumScreenState();
}

class _TvJellyfinAlbumScreenState extends State<TvJellyfinAlbumScreen> {
  late final Future<List<JfItem>> _tracks =
      TvConfig.jellyfin!.albumTracks(widget.album.id)
        ..then((_) => WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _playNode.requestFocus();
            }));
  final _playNode = FocusNode();

  @override
  void dispose() {
    _playNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final jf = TvConfig.jellyfin!;
    final a = widget.album;
    final cover = a.imageItemId == null
        ? null
        : jf.imageUrl(a.imageItemId!, maxSize: 700);
    return Scaffold(
      backgroundColor: TvColors.bg,
      body: FutureBuilder<List<JfItem>>(
        future: _tracks,
        builder: (context, snap) {
          final tracks = snap.data ?? const <JfItem>[];
          final total =
              tracks.fold<Duration>(Duration.zero, (s, t) => s + t.duration);
          return TvCollectionLayout(
            cover: TvCover(cover, size: 240, radius: 14),
            title: a.name,
            meta: [
              a.albumArtist,
              if (a.year != null) '${a.year}',
              if (tracks.isNotEmpty)
                '${tracks.length} brani · ${total.inMinutes} min'
            ].join(' · '),
            loading: snap.connectionState != ConnectionState.done,
            error: snap.hasError ? 'Errore: ${snap.error}' : null,
            actions: [
              TvPillButton(
                icon: Icons.play_arrow_rounded,
                label: 'Riproduci',
                primary: true,
                focusNode: _playNode,
                onTap: tracks.isEmpty
                    ? null
                    : () => playJellyfinAlbum(context, a, tracks: tracks),
              ),
              TvPillButton(
                icon: Icons.shuffle_rounded,
                label: 'Casuale',
                onTap: tracks.isEmpty
                    ? null
                    : () => playJellyfinAlbum(context, a,
                        tracks: tracks, shuffle: true),
              ),
              TvPillButton(
                icon: Icons.download_rounded,
                label: 'Scarica',
                onTap: tracks.isEmpty
                    ? null
                    : () => showDownloadMenu(
                          context,
                          artist: a.albumArtist,
                          album: a.name,
                          allowLidarr: false,
                          albumTracks: () async =>
                              tracks.map((e) => e.toTrack(jf)).toList(),
                        ),
              ),
            ],
            itemCount: tracks.length,
            itemBuilder: (_, i) => TvTrackTile(
              index: tracks[i].trackNumber ?? i + 1,
              title: tracks[i].name,
              subtitle: tracks[i].albumArtist != a.albumArtist
                  ? tracks[i].albumArtist
                  : null,
              duration: tracks[i].duration,
              onTap: () =>
                  playJellyfinAlbum(context, a, tracks: tracks, index: i),
            ),
          );
        },
      ),
    );
  }
}

/// Artista Jellyfin: i suoi album a griglia.
class TvJellyfinArtistScreen extends StatelessWidget {
  const TvJellyfinArtistScreen({super.key, required this.artist});
  final JfItem artist;

  @override
  Widget build(BuildContext context) {
    final jf = TvConfig.jellyfin!;
    return Scaffold(
      backgroundColor: TvColors.bg,
      body: FutureBuilder<List<JfItem>>(
        future: jf.albumsOfArtist(artist.id),
        builder: (context, snap) {
          final albums = snap.data ?? const <JfItem>[];
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(48, 40, 48, 20),
                  child: Row(children: [
                    TvCover(
                        artist.imageItemId == null
                            ? null
                            : jf.imageUrl(artist.imageItemId!, maxSize: 300),
                        size: 140,
                        circle: true),
                    const SizedBox(width: 28),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(artist.name, style: TvText.hero),
                            Text('${albums.length} album nella tua libreria',
                                style: TvText.body),
                          ]),
                    ),
                  ]),
                ),
              ),
              if (snap.connectionState != ConnectionState.done)
                const SliverToBoxAdapter(
                    child: TvMessage(
                        icon: Icons.hourglass_empty,
                        text: 'Carico…',
                        loading: true))
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(48, 8, 48, 120),
                  sliver: SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 200,
                      mainAxisExtent: 250,
                      crossAxisSpacing: 22,
                      mainAxisSpacing: 14,
                    ),
                    itemCount: albums.length,
                    itemBuilder: (_, i) {
                      final a = albums[i];
                      return TvCard(
                        autofocus: i == 0,
                        title: a.name,
                        subtitle: a.year?.toString(),
                        imageUrl: a.imageItemId == null
                            ? null
                            : jf.imageUrl(a.imageItemId!, maxSize: 400),
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) =>
                                    TvJellyfinAlbumScreen(album: a))),
                        onLongPress: () => playJellyfinAlbum(context, a),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
