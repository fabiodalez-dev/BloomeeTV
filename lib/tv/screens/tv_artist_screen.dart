import 'dart:async';

import 'package:Bloomee/blocs/media_player/bloomee_player_cubit.dart';
import 'package:Bloomee/core/di/service_locator.dart';
import 'package:Bloomee/core/models/exported.dart';
import 'package:Bloomee/core/models/media_playlist_model.dart';
import 'package:Bloomee/plugins/blocs/content/content_bloc.dart';
import 'package:Bloomee/plugins/blocs/content/content_event.dart';
import 'package:Bloomee/plugins/blocs/content/content_state.dart';
import 'package:Bloomee/screens/screen/common_views/album_view.dart';
import 'package:Bloomee/src/rust/api/plugin/commands.dart' show ContentSearchFilter;
import 'package:Bloomee/tv/lidarr_action.dart';
import 'package:Bloomee/tv/connectors/ytmusic_account.dart';
import 'package:Bloomee/tv/tv_config.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:Bloomee/tv/ui/tv_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

String? _art(Artwork? a) => a == null ? null : (a.urlHigh ?? a.url);
String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

/// Artista della sorgente online, per TV: top song, album (paginati),
/// "Tutti i brani" (dalla ricerca, filtrati sull'artista e caricati man mano)
/// e artisti simili. Tutto raggiungibile col telecomando.
class TvArtistScreen extends StatefulWidget {
  const TvArtistScreen({super.key, required this.artist, required this.pluginId});
  final ArtistSummary artist;
  final String pluginId;

  @override
  State<TvArtistScreen> createState() => _TvArtistScreenState();
}

class _TvArtistScreenState extends State<TvArtistScreen> {
  final _details = ContentBloc(pluginService: ServiceLocator.pluginService);
  final _songs = ContentBloc(pluginService: ServiceLocator.pluginService);
  // Alcuni artisti (es. Green Day) arrivano senza album: li cerco a parte.
  final _albumSearch = ContentBloc(pluginService: ServiceLocator.pluginService);
  final _playNode = FocusNode();
  bool _focused = false;
  YtArtistInfo? _yt;

  /// Dati extra da YouTube Music (anche senza account): ascoltatori mensili,
  /// iscritti, descrizione completa, foto grande.
  Future<void> _loadYt() async {
    try {
      final c = TvConfig.youtube;
      final local = widget.artist.id.split('::').last;
      final ch = local.startsWith('UC') ? local : await c.findArtistChannel(widget.artist.name);
      if (ch == null) return;
      final info = await c.artist(ch);
      if (mounted) setState(() => _yt = info);
    } catch (_) {}
  }

  void _showAbout(String text) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TvColors.surface,
        title: Text(widget.artist.name, style: TvText.title),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(child: Text(text, style: TvText.body.copyWith(fontSize: 18, color: TvColors.text))),
        ),
        actions: [TextButton(autofocus: true, onPressed: () => Navigator.pop(ctx), child: const Text('Chiudi'))],
      ),
    );
  }
  bool _extraStarted = false;
  StreamSubscription<ContentState>? _detailsSub;
  int _pages = 0;

  @override
  void initState() {
    super.initState();
    _details.add(LoadArtistDetails(pluginId: widget.pluginId, artistId: widget.artist.id));
    _loadYt();
    // Le ricerche partono solo dopo i dettagli: richieste parallele alla
    // sorgente facevano arrivare l'artista senza album.
    _detailsSub = _details.stream.listen((st) {
      if (_extraStarted) return;
      if (st.artistDetailStatus == DetailStatus.loaded || st.artistDetailStatus == DetailStatus.error) {
        _extraStarted = true;
        _songs.add(SetActiveContentPlugin(pluginId: widget.pluginId));
        _songs.add(SearchContent(query: widget.artist.name, filter: ContentSearchFilter.track));
        if ((st.artistDetails?.albums.items.length ?? 0) < 4) {
          _albumSearch.add(SetActiveContentPlugin(pluginId: widget.pluginId));
          _albumSearch.add(SearchContent(query: widget.artist.name, filter: ContentSearchFilter.album));
        }
      }
    });
  }

  @override
  void dispose() {
    _detailsSub?.cancel();
    _details.close();
    _songs.close();
    _albumSearch.close();
    _playNode.dispose();
    super.dispose();
  }

  bool _isByArtist(Track t) {
    final a = _norm(widget.artist.name);
    return t.artists.any((x) => x.id == widget.artist.id || _norm(x.name) == a || _norm(x.name).contains(a));
  }

  /// Top song + brani dalla ricerca, senza doppioni.
  List<Track> _allTracks(ContentState d, ContentState s) {
    final seen = <String>{};
    final out = <Track>[];
    for (final t in [
      ...?d.artistDetails?.topTracks,
      ...?s.searchResults?.items.whereType<MediaItem_Track>().map((e) => e.field0).where(_isByArtist),
    ]) {
      if (seen.add(_norm(t.title))) out.add(t);
    }
    return out;
  }

  List<AlbumSummary> _mergeAlbums(List<AlbumSummary> own, ContentState search) {
    final a = _norm(widget.artist.name);
    final seen = <String>{for (final x in own) _norm(x.title)};
    final out = [...own];
    for (final x in search.searchResults?.items.whereType<MediaItem_Album>().map((e) => e.field0) ?? const <AlbumSummary>[]) {
      final byArtist = x.artists.any((y) => y.id == widget.artist.id || _norm(y.name) == a);
      if (byArtist && seen.add(_norm(x.title))) out.add(x);
    }
    return out;
  }

  void _play(List<Track> tracks, int i, {bool shuffle = false}) {
    if (tracks.isEmpty) return;
    context.read<BloomeePlayerCubit>().bloomeePlayer.loadPlaylist(
        Playlist(tracks: tracks, title: widget.artist.name), idx: i, doPlay: true, shuffling: shuffle);
  }

  void _maybeLoadMoreSongs(ContentState s) {
    final next = s.searchResults?.nextPageToken;
    if (next != null && _pages < 15 && s.searchStatus != SearchStatus.loadingMore && s.searchStatus != SearchStatus.loading) {
      _pages++;
      _songs.add(LoadMoreSearchContent(pageToken: next));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TvColors.bg,
      body: BlocBuilder<ContentBloc, ContentState>(
        bloc: _albumSearch,
        builder: (context, _) => BlocBuilder<ContentBloc, ContentState>(
        bloc: _details,
        builder: (context, d) => BlocBuilder<ContentBloc, ContentState>(
          bloc: _songs,
          builder: (context, s) {
            final det = d.artistDetails;
            final top = det?.topTracks ?? const <Track>[];
            final albums = _mergeAlbums(det?.albums.items ?? const [], _albumSearch.state);
            final related = det?.relatedArtists ?? const <ArtistSummary>[];
            final all = _allTracks(d, s);
            final extra = all.skip(top.length).toList();
            // Pochi brani dell'artista nella prima pagina: ne carico subito altre.
            if (extra.length < 40) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _maybeLoadMoreSongs(_songs.state);
              });
            }
            if (!_focused && all.isNotEmpty) {
              _focused = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _playNode.requestFocus();
              });
            }
            final image = _art(det?.summary.thumbnail ?? widget.artist.thumbnail);
            final about = (_yt?.description?.isNotEmpty ?? false) ? _yt!.description! : (det?.description ?? '');
            final banner = _yt?.banner;
            return Stack(children: [
              if (banner != null)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 420,
                  child: ShaderMask(
                    shaderCallback: (r) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.white, Colors.transparent],
                    ).createShader(r),
                    blendMode: BlendMode.dstIn,
                    child: Opacity(
                      opacity: 0.45,
                      child: CachedNetworkImage(imageUrl: banner, fit: BoxFit.cover, alignment: Alignment.topCenter, memCacheWidth: 1280),
                    ),
                  ),
                ),
              CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(48, 40, 48, 24),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        TvCover(image, size: 190, circle: true),
                        const SizedBox(width: 32),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('ARTISTA', style: TextStyle(color: TvColors.accent, letterSpacing: 1.6, fontFamily: 'Gilroy')),
                              Text(widget.artist.name, style: TvText.hero, maxLines: 1, overflow: TextOverflow.ellipsis),
                              if (_yt?.monthlyListeners != null || _yt?.subscribers != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    [if (_yt?.monthlyListeners != null) _yt!.monthlyListeners!, if (_yt?.subscribers != null) '${_yt!.subscribers} iscritti'].join(' · '),
                                    style: TvText.body.copyWith(color: TvColors.text, fontSize: 18),
                                  ),
                                ),
                              if (about.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(about, maxLines: 2, overflow: TextOverflow.ellipsis, style: TvText.body),
                                ),
                              const SizedBox(height: 18),
                              Wrap(spacing: 14, runSpacing: 12, children: [
                                  TvPillButton(
                                    focusNode: _playNode,
                                    icon: Icons.play_arrow_rounded,
                                    label: 'Riproduci tutto (${all.length})',
                                    primary: true,
                                    onTap: all.isEmpty ? null : () => _play(all, 0),
                                  ),
                                  TvPillButton(
                                    icon: Icons.shuffle_rounded,
                                    label: 'Casuale',
                                    onTap: all.isEmpty ? null : () => _play(all, 0, shuffle: true),
                                  ),
                                  if (about.length > 120)
                                    TvPillButton(
                                      icon: Icons.info_outline_rounded,
                                      label: 'Biografia',
                                      onTap: () => _showAbout(about),
                                    ),
                                ]),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (d.artistDetailStatus == DetailStatus.loading && det == null)
                  const SliverToBoxAdapter(child: TvMessage(icon: Icons.hourglass_empty, text: 'Carico l\'artista…', loading: true)),
                if (all.isNotEmpty)
                  SliverToBoxAdapter(
                    child: TvRow(
                      title: 'Brani più famosi',
                      // Subito le top song, poi la riga si allunga man mano
                      // che arrivano gli altri brani.
                      itemCount: all.length.clamp(0, 20),
                      itemBuilder: (_, i) => TvCard(
                        title: all[i].title,
                        subtitle: all[i].album?.title ?? widget.artist.name,
                        imageUrl: _art(all[i].thumbnail),
                        badge: Icons.play_arrow_rounded,
                        onTap: () => _play(all, i),
                        onLongPress: all[i].album == null
                            ? null
                            : () => downloadAlbumWithLidarr(context, artist: widget.artist.name, album: all[i].album!.title),
                      ),
                    ),
                  ),
                if (albums.isNotEmpty)
                  SliverToBoxAdapter(
                    child: TvRow(
                      title: 'Album e singoli',
                      subtitle: 'OK per aprire · tieni premuto OK per scaricare',
                      itemCount: albums.length,
                      itemBuilder: (_, i) {
                        final next = det?.albums.nextPageToken;
                        if (i == albums.length - 3 && next != null) {
                          _details.add(LoadMoreArtistAlbums(pluginId: widget.pluginId, artistId: widget.artist.id, pageToken: next));
                        }
                        final a = albums[i];
                        return TvCard(
                          title: a.title,
                          subtitle: [if (a.year != null) '${a.year}', if (a.subtitle != null) a.subtitle!].join(' · '),
                          imageUrl: _art(a.thumbnail),
                          onTap: () => Navigator.of(context)
                              .push(MaterialPageRoute(builder: (_) => AlbumView(album: a, pluginId: widget.pluginId))),
                          onLongPress: () => downloadAlbumWithLidarr(context, artist: widget.artist.name, album: a.title),
                        );
                      },
                    ),
                  ),
                if (related.isNotEmpty)
                  SliverToBoxAdapter(
                    child: TvRow(
                      title: 'Artisti simili',
                      itemCount: related.length,
                      itemBuilder: (_, i) => TvCard(
                        title: related[i].name,
                        subtitle: related[i].subtitle,
                        imageUrl: _art(related[i].thumbnail),
                        circle: true,
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => TvArtistScreen(artist: related[i], pluginId: widget.pluginId))),
                      ),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(48, 4, 48, 12),
                    child: Text('Tutti i brani${extra.isEmpty ? '' : ' (${extra.length}${s.searchResults?.nextPageToken != null ? '+' : ''})'}',
                        style: TvText.title),
                  ),
                ),
                if (extra.isEmpty && s.searchStatus == SearchStatus.loading)
                  const SliverToBoxAdapter(child: TvMessage(icon: Icons.hourglass_empty, text: 'Cerco altri brani…', loading: true)),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(48, 0, 48, 140),
                  sliver: SliverGrid.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 560,
                      mainAxisExtent: 76,
                      crossAxisSpacing: 18,
                    ),
                    itemCount: extra.length,
                    itemBuilder: (_, i) {
                      if (i >= extra.length - 6) _maybeLoadMoreSongs(s);
                      final t = extra[i];
                      return TvTrackTile(
                        index: top.length + i + 1,
                        title: t.title,
                        subtitle: t.album?.title,
                        duration: t.durationMs == null ? null : Duration(milliseconds: t.durationMs!.toInt()),
                        onTap: () => _play(all, top.length + i),
                        onLongPress: t.album == null
                            ? null
                            : () => downloadAlbumWithLidarr(context, artist: widget.artist.name, album: t.album!.title),
                      );
                    },
                  ),
                ),
              ],
            ),
            ]);
          },
        ),
      ),
      ),
    );
  }
}
