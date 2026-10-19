import 'dart:ui';
import 'package:Bloomee/tv/services/tv_workspace.dart';
import 'package:Bloomee/tv/services/tv_saved_library.dart';
import 'package:Bloomee/tv/services/tv_catalog_cache.dart';
import 'package:Bloomee/tv/screens/tv_control_center.dart';

import 'package:Bloomee/blocs/explore/cubit/explore_cubits.dart';
import 'package:Bloomee/blocs/media_player/bloomee_player_cubit.dart';
import 'package:Bloomee/blocs/settings_cubit/cubit/settings_cubit.dart';
import 'package:Bloomee/core/di/service_locator.dart';
import 'package:Bloomee/core/models/exported.dart';
import 'package:Bloomee/core/models/media_playlist_model.dart';
import 'package:Bloomee/plugins/blocs/chart/chart_bloc.dart';
import 'package:Bloomee/plugins/blocs/chart/chart_event.dart';
import 'package:Bloomee/plugins/blocs/chart/chart_state.dart';
import 'package:Bloomee/plugins/blocs/content/content_bloc.dart';
import 'package:Bloomee/plugins/blocs/content/content_event.dart';
import 'package:Bloomee/plugins/blocs/content/content_state.dart';
import 'package:Bloomee/plugins/blocs/plugin/plugin_bloc.dart';
import 'package:Bloomee/plugins/blocs/plugin/plugin_state.dart';
import 'package:Bloomee/screens/screen/chart/chart_view.dart';
import 'package:Bloomee/screens/screen/common_views/album_view.dart';
import 'package:Bloomee/screens/screen/common_views/artist_view.dart';
import 'package:Bloomee/screens/screen/common_views/playlist_view.dart';
import 'package:Bloomee/tv/connectors/jellyfin_client.dart';
import 'package:Bloomee/tv/lidarr_action.dart';
import 'package:Bloomee/tv/screens/tv_jellyfin_screen.dart';
import 'package:Bloomee/tv/tv_config.dart';
import 'package:Bloomee/tv/connectors/ytmusic_account.dart';
import 'package:Bloomee/tv/screens/tv_youtube_screen.dart';
import 'package:Bloomee/tv/ui/tv_widgets.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Cosa mostra la testata in alto: l'elemento con il focus.
class _HeroInfo {
  const _HeroInfo(this.title, this.subtitle, this.image, {this.kind});
  final String title;
  final String subtitle;
  final String? image;
  final String? kind;
}

String? _art(Artwork? a) => a == null ? null : (a.urlHigh ?? a.url);
String _artists(List<ArtistSummary> a) => a.map((e) => e.name).join(', ');

/// Home per TV: testata con sfondo sfocato dell'elemento selezionato e righe
/// orizzontali grandi (Jellyfin, ascoltati di recente, classifiche, sezioni
/// della sorgente online).
class TvHomeScreen extends StatefulWidget {
  const TvHomeScreen({super.key});

  @override
  State<TvHomeScreen> createState() => _TvHomeScreenState();
}

class _TvHomeScreenState extends State<TvHomeScreen> {
  late final ContentBloc _content =
      ContentBloc(pluginService: ServiceLocator.pluginService);
  late final ChartBloc _charts =
      ChartBloc(pluginService: ServiceLocator.pluginService);
  final _hero = ValueNotifier<_HeroInfo>(
      const _HeroInfo('Bloomee TV', 'Scegli qualcosa da ascoltare', null));

  List<YtItem> _ytHistory = const [];
  List<YtSection> _ytHome = const [];
  List<JfItem> _jfRecent = const [];
  List<JfItem> _jfRandom = const [];
  String? _jfError;
  int _jfGeneration = 0, _ytGeneration = 0;
  bool _showGuide = false;
  void _preferencesChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    TvWorkspace.instance.addListener(_preferencesChanged);
    TvWorkspace.instance
        .claimGuidePrompt(
            configured: TvConfig.hasJellyfin ||
                TvConfig.hasLidarr ||
                TvConfig.hasYouTube)
        .then((show) {
      if (mounted) setState(() => _showGuide = show);
    });
    _tryLoadHome();
    _tryLoadCharts();
    _loadJellyfin();
    _loadYouTube();
    TvConfig.changes.addListener(_loadJellyfin);
    TvConfig.changes.addListener(_loadYouTube);
  }

  @override
  void dispose() {
    TvConfig.changes.removeListener(_loadJellyfin);
    TvConfig.changes.removeListener(_loadYouTube);
    TvWorkspace.instance.removeListener(_preferencesChanged);
    _jfGeneration++;
    _ytGeneration++;
    _content.close();
    _charts.close();
    _hero.dispose();
    super.dispose();
  }

  Future<void> _loadJellyfin() async {
    final generation = ++_jfGeneration;
    final jf = TvConfig.jellyfin;
    if (jf == null) {
      setState(() {
        _jfRecent = const [];
        _jfRandom = const [];
      });
      return;
    }
    try {
      final r = await Future.wait(
          [jf.recentAlbums(limit: 20), jf.randomAlbums(limit: 20)]);
      if (!mounted || generation != _jfGeneration) return;
      setState(() {
        _jfRecent = r[0];
        _jfRandom = r[1];
        _jfError = null;
      });
    } catch (e) {
      if (mounted && generation == _jfGeneration)
        setState(() => _jfError = 'Verifica il server o riprova');
    }
  }

  Future<void> _loadYouTube() async {
    final generation = ++_ytGeneration;
    if (!TvConfig.hasYouTube) {
      if (mounted)
        setState(() {
          _ytHistory = const [];
          _ytHome = const [];
        });
      return;
    }
    final c = TvConfig.youtube;
    try {
      final h = await c.history();
      if (mounted && generation == _ytGeneration)
        setState(() =>
            _ytHistory = h.where((i) => i.videoId != null).take(30).toList());
    } catch (_) {}
    try {
      final home = await c.home();
      if (mounted && generation == _ytGeneration)
        setState(() => _ytHome = home.take(5).toList());
    } catch (_) {}
  }

  Widget _ytRow(String title, List<YtItem> items, {YtSection? section}) {
    if (items.isEmpty) return const SizedBox.shrink();
    return TvRow(
      title: title,
      subtitle: 'YouTube Music',
      onTitleTap: section == null ? null : ytSectionMore(context, section),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final it = items[i];
        return ytCard(context, it, items, title,
            onFocused: () => _focus(_HeroInfo(
                it.title,
                it.artistNames.isNotEmpty ? it.artistNames : it.subtitle,
                it.thumbnail,
                kind:
                    '${it.kind == 'song' ? 'Brano' : it.kind == 'album' ? 'Album' : it.kind == 'artist' ? 'Artista' : 'Playlist'} · $title')));
      },
    );
  }

  void _tryLoadHome() {
    final settings = context.read<SettingsCubit>().state;
    if (!settings.settingsReady) return;
    final ps = context.read<PluginBloc>().state;
    final resolvers = ps.loadedContentResolvers;
    if (resolvers.isEmpty) return;
    final pref = settings.homePluginId;
    if (pref.isNotEmpty && !resolvers.any((p) => p.manifest.id == pref)) {
      if (ps.availablePlugins.any((p) => p.manifest.id == pref)) return;
    }
    final id = resolvers.any((p) => p.manifest.id == pref)
        ? pref
        : resolvers.first.manifest.id;
    if (_content.state.activePluginId == id &&
        _content.state.homeSections != null) return;
    _content.add(GetHomeSections(pluginId: id));
  }

  void _tryLoadCharts() {
    final providers = context.read<PluginBloc>().state.loadedChartProviders;
    if (providers.isEmpty) return;
    final id = providers.first.manifest.id;
    if (_charts.state.activePluginId == id && _charts.state.charts.isNotEmpty)
      return;
    _charts.add(LoadCharts(pluginId: id));
  }

  void _focus(_HeroInfo info) => _hero.value = info;

  // ── Azioni ───────────────────────────────────────────────────────────

  void _push(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  void _openItem(MediaItem item, Section section, String pluginId) {
    item.when(
      track: (t) {
        final tracks = section.items
            .whereType<MediaItem_Track>()
            .map((e) => e.field0)
            .toList();
        final idx = tracks.indexWhere((e) => e.id == t.id);
        context.read<BloomeePlayerCubit>().bloomeePlayer.loadPlaylist(
            Playlist(tracks: tracks, title: section.title),
            idx: idx < 0 ? 0 : idx,
            doPlay: true);
      },
      album: (a) => _push(AlbumView(album: a, pluginId: pluginId)),
      artist: (a) => _push(ArtistView(artist: a, pluginId: pluginId)),
      playlist: (p) => _push(OnlPlaylistView(playlist: p, pluginId: pluginId)),
    );
  }

  /// OK tenuto premuto su un album o un brano: "Scarica questo album".
  VoidCallback? _longPressFor(MediaItem item) => item.when(
        track: (t) => () => showDownloadMenu(context,
            artist: _artists(t.artists), album: t.album?.title ?? '', track: t),
        album: (a) => () => showDownloadMenu(context,
            artist: _artists(a.artists),
            album: a.title,
            albumTracks: () => pluginAlbumTracks(a)),
        artist: (_) => null,
        playlist: (_) => null,
      );

  // ── Righe ─────────────────────────────────────────────────────────────

  Widget _mediaCard(MediaItem item, Section section, String pluginId,
      {bool autofocus = false}) {
    final (title, sub, img, circle, kind) = item.when(
      track: (t) =>
          (t.title, _artists(t.artists), _art(t.thumbnail), false, 'Brano'),
      album: (a) =>
          (a.title, _artists(a.artists), _art(a.thumbnail), false, 'Album'),
      artist: (a) =>
          (a.name, a.subtitle ?? 'Artista', _art(a.thumbnail), true, 'Artista'),
      playlist: (p) => (
        p.title,
        p.owner ?? 'Playlist',
        _art(p.thumbnail),
        false,
        'Playlist'
      ),
    );
    return TvCard(
      title: title,
      subtitle: sub,
      imageUrl: img,
      circle: circle,
      autofocus: autofocus,
      badge: kind == 'Brano' ? Icons.play_arrow_rounded : null,
      onFocused: () =>
          _focus(_HeroInfo(title, sub, img, kind: '$kind · ${section.title}')),
      onTap: () => _openItem(item, section, pluginId),
      onLongPress: () => showTvReferenceMenu(context, TvReference.item(item),
          download: _longPressFor(item)),
    );
  }

  Widget _jfRow(String title, List<JfItem> items) {
    final jf = TvConfig.jellyfin;
    if (jf == null || items.isEmpty) return const SizedBox.shrink();
    return TvRow(
      title: title,
      subtitle: 'Jellyfin',
      itemCount: items.length,
      itemBuilder: (_, i) {
        final a = items[i];
        final img = a.imageItemId == null
            ? null
            : jf.imageUrl(a.imageItemId!, maxSize: 400);
        return TvCard(
          title: a.name,
          subtitle: a.albumArtist,
          imageUrl: img,
          onFocused: () => _focus(_HeroInfo(
              a.name,
              '${a.albumArtist}${a.year != null ? ' · ${a.year}' : ''}',
              a.imageItemId == null
                  ? null
                  : jf.imageUrl(a.imageItemId!, maxSize: 900),
              kind: 'Nella tua libreria')),
          onTap: () => _push(TvJellyfinAlbumScreen(album: a)),
          onLongPress: () => showTvReferenceMenu(
              context, TvReference.item(a.toMedia(jf)),
              download: () => showDownloadMenu(context,
                  artist: a.albumArtist,
                  album: a.name,
                  albumTracks: () async => (await jf.albumTracks(a.id))
                      .map((t) => t.toTrack(jf))
                      .toList())),
        );
      },
    );
  }

  Widget _recentRow() {
    return BlocBuilder<RecentlyCubit, RecentlyCubitState>(
      builder: (context, state) {
        final tracks = state.tracks;
        if (tracks.isEmpty) return const SizedBox.shrink();
        return TvRow(
          title: 'Ascoltati di recente',
          itemCount: tracks.length.clamp(0, 25),
          itemBuilder: (_, i) {
            final t = tracks[i];
            final img = _art(t.thumbnail);
            return TvCard(
              title: t.title,
              subtitle: _artists(t.artists),
              imageUrl: img,
              badge: Icons.play_arrow_rounded,
              onFocused: () => _focus(_HeroInfo(
                  t.title, _artists(t.artists), img,
                  kind: 'Ascoltato di recente')),
              onTap: () => context
                  .read<BloomeePlayerCubit>()
                  .bloomeePlayer
                  .loadPlaylist(
                      Playlist(tracks: tracks, title: 'Ascoltati di recente'),
                      idx: i,
                      doPlay: true),
              onLongPress: () => showDownloadMenu(context,
                  artist: _artists(t.artists),
                  album: t.album?.title ?? '',
                  track: t),
            );
          },
        );
      },
    );
  }

  Widget _chartsRow() {
    return BlocBuilder<ChartBloc, ChartState>(
      bloc: _charts,
      builder: (context, state) {
        final charts = state.charts;
        final pluginId = state.activePluginId;
        if (charts.isEmpty || pluginId == null) return const SizedBox.shrink();
        return TvRow(
          title: 'Classifiche',
          itemCount: charts.length,
          itemBuilder: (_, i) {
            final c = charts[i];
            return TvCard(
              title: c.title,
              subtitle: c.description,
              imageUrl: _art(c.thumbnail),
              onFocused: () => _focus(_HeroInfo(
                  c.title, c.description ?? 'Classifica', _art(c.thumbnail),
                  kind: 'Classifica')),
              onTap: () => _push(ChartScreen(
                  pluginId: pluginId, chartId: c.id, chartTitle: c.title)),
            );
          },
        );
      },
    );
  }

  Widget _sections() {
    return BlocBuilder<ContentBloc, ContentState>(
      bloc: _content,
      builder: (context, state) {
        final sections = state.homeSections;
        final pluginId = state.activePluginId ?? '';
        if (sections == null || sections.isEmpty) {
          if (state.homeSectionsStatus == DetailStatus.error) {
            return Padding(
              padding: const EdgeInsets.all(48),
              child: TvMessage(
                  icon: Icons.cloud_off_rounded,
                  text:
                      'Sorgente online non disponibile: ${state.error ?? ''}'),
            );
          }
          if (state.homeSectionsStatus == DetailStatus.loading) {
            return const Padding(
              padding: EdgeInsets.all(48),
              child: TvMessage(
                  icon: Icons.hourglass_empty,
                  text: 'Carico le novità…',
                  loading: true),
            );
          }
          return const SizedBox.shrink();
        }
        return Column(
          children: [
            for (final s in sections)
              if (s.items.isNotEmpty)
                TvRow(
                  title: s.title,
                  subtitle: s.subtitle,
                  itemCount: s.items.length,
                  itemBuilder: (_, i) => _mediaCard(s.items[i], s, pluginId),
                ),
          ],
        );
      },
    );
  }

  List<Widget> _orderedRows() {
    final rows = <String, Widget>{
      'jfRecent': _jfRow('Aggiunti di recente', _jfRecent),
      'ytHistory': _ytRow('Ascoltati di recente su YouTube', _ytHistory),
      'ytHome': Column(children: [
        for (final sec in _ytHome) _ytRow(sec.title, sec.items, section: sec)
      ]),
      'recent': _recentRow(),
      'jfRandom': _jfRow('Scelti per te', _jfRandom),
      'charts': _chartsRow(),
      'sections': _sections(),
    };
    final order = List<String>.from(
        TvWorkspace.instance['homeOrder'] as List? ?? rows.keys.toList());
    final first = TvWorkspace.instance['startSection'];
    if (first is String && order.remove(first)) order.insert(0, first);
    final hidden = TvWorkspace.instance['hiddenRows'] as List? ?? [];
    return [
      for (final key in order)
        if (!hidden.contains(key) && rows.containsKey(key)) rows[key]!
    ];
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<SettingsCubit, SettingsState>(
          listenWhen: (a, b) =>
              a.homePluginId != b.homePluginId ||
              (!a.settingsReady && b.settingsReady),
          listener: (_, __) {
            _content.add(const ClearHomeSections());
            _tryLoadHome();
          },
        ),
        BlocListener<PluginBloc, PluginState>(
          listenWhen: (a, b) =>
              a.loadedContentResolvers != b.loadedContentResolvers ||
              a.loadedPluginIds != b.loadedPluginIds,
          listener: (_, __) {
            _tryLoadHome();
            _tryLoadCharts();
          },
        ),
      ],
      child: Scaffold(
        backgroundColor: TvColors.bg,
        body: Stack(
          children: [
            Positioned.fill(child: _Backdrop(hero: _hero)),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HeroHeader(hero: _hero),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(top: 12, bottom: 24),
                    children: [
                      if (!TvConfig.hasJellyfin)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(48, 0, 48, 24),
                          child: Text(
                            'Collega Jellyfin da Impostazioni (menu a sinistra) per vedere qui la tua musica.',
                            style: TvText.body,
                          ),
                        ),
                      if (_jfError != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(48, 0, 48, 24),
                          child: Text('Jellyfin non raggiungibile: $_jfError',
                              style: TvText.body),
                        ),
                      if (_showGuide &&
                          TvWorkspace.instance['onboardedTv'] != true)
                        Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 48),
                            child: TvPillButton(
                                icon: Icons.play_circle_outline,
                                label:
                                    'Inizia: guida ai servizi e al telecomando',
                                onTap: () {
                                  setState(() => _showGuide = false);
                                  openTvControlCenter(context);
                                })),
                      Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 48),
                          child: Wrap(spacing: 12, children: [
                            TvPillButton(
                                icon: Icons.dashboard_customize,
                                label: 'Personalizza',
                                onTap: () =>
                                    openTvControlCenter(context, TvTool.home)),
                            TvPillButton(
                                icon: Icons.account_circle,
                                label: TvProfiles.instance.selected.name,
                                onTap: () => openTvControlCenter(
                                    context, TvTool.profili)),
                            TvPillButton(
                                icon: Icons.favorite,
                                label: 'Preferiti unificati',
                                onTap: () => openTvControlCenter(
                                    context, TvTool.preferiti)),
                          ])),
                      ListenableBuilder(
                          listenable: TvCatalogCache.instance,
                          builder: (_, __) => TvCatalogCache
                                  .instance.offlineSources.isEmpty
                              ? const SizedBox.shrink()
                              : Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Text(
                                      'Catalogo da cache: ${TvCatalogCache.instance.offlineSources.entries.map((e) => '${e.key}, aggiornato ${e.value.toLocal()}').join(' · ')}',
                                      style: TvText.body))),
                      if (TvSavedLibrary.instance.pins.isNotEmpty)
                        TvRow(
                            title: 'Fissati',
                            itemCount: TvSavedLibrary.instance.pins.length,
                            itemBuilder: (_, i) {
                              final item = TvSavedLibrary.instance.pins[i];
                              return TvCard(
                                  title: item.title,
                                  subtitle: item.subtitle,
                                  imageUrl: item.image,
                                  onTap: () => openTvReference(context, item),
                                  onLongPress: () =>
                                      showTvReferenceMenu(context, item));
                            }),
                      ..._orderedRows(),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Sfondo: copertina dell'elemento selezionato, sfocata e sfumata.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.hero});
  final ValueNotifier<_HeroInfo> hero;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_HeroInfo>(
      valueListenable: hero,
      builder: (_, h, __) => Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 450),
            child: h.image == null || h.image!.isEmpty
                ? const SizedBox.expand(key: ValueKey('none'))
                : ImageFiltered(
                    key: ValueKey(h.image),
                    imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                    child: Opacity(
                      opacity: 0.55,
                      child: CachedNetworkImage(
                        imageUrl: h.image!,
                        httpHeaders: TvConfig.artworkHeaders(h.image!),
                        fit: BoxFit.cover,
                        memCacheWidth: 320,
                        errorWidget: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x330B0810), Color(0xCC0B0810), TvColors.bg],
                stops: [0, 0.45, 0.8],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.hero});
  final ValueNotifier<_HeroInfo> hero;

  @override
  Widget build(BuildContext context) {
    // Compatta: sopra la barra restano ~450 punti e una riga di copertine
    // ne chiede ~316, così la riga selezionata si vede sempre per intero.
    return SizedBox(
      height: 132,
      child: ValueListenableBuilder<_HeroInfo>(
        valueListenable: hero,
        builder: (_, h, __) => Padding(
          padding: const EdgeInsets.fromLTRB(48, 20, 48, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (h.image != null && h.image!.isNotEmpty) ...[
                TvCover(h.image, size: 104, radius: 12),
                const SizedBox(width: 24),
              ],
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (h.kind != null)
                      Text(h.kind!.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TvText.cardSub.copyWith(
                              letterSpacing: 1.6, color: TvColors.accent)),
                    const SizedBox(height: 4),
                    Text(h.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TvText.hero.copyWith(fontSize: 34)),
                    const SizedBox(height: 4),
                    Text(h.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TvText.body.copyWith(fontSize: 18)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
