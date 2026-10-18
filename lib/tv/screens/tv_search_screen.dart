import 'package:Bloomee/blocs/media_player/bloomee_player_cubit.dart';
import 'package:Bloomee/blocs/settings_cubit/cubit/settings_cubit.dart';
import 'package:Bloomee/core/di/service_locator.dart';
import 'package:Bloomee/core/models/exported.dart';
import 'package:Bloomee/core/models/media_playlist_model.dart';
import 'package:Bloomee/plugins/blocs/content/content_bloc.dart';
import 'package:Bloomee/plugins/blocs/content/content_event.dart';
import 'package:Bloomee/plugins/blocs/content/content_state.dart';
import 'package:Bloomee/plugins/blocs/plugin/plugin_bloc.dart';
import 'package:Bloomee/screens/screen/common_views/album_view.dart';
import 'package:Bloomee/screens/screen/common_views/artist_view.dart';
import 'package:Bloomee/screens/screen/common_views/playlist_view.dart';
import 'package:Bloomee/screens/widgets/snackbar.dart';
import 'package:Bloomee/src/rust/api/plugin/commands.dart' show ContentSearchFilter;
import 'package:Bloomee/tv/connectors/jellyfin_client.dart';
import 'package:Bloomee/tv/lidarr_action.dart';
import 'package:Bloomee/tv/screens/tv_jellyfin_screen.dart';
import 'package:Bloomee/tv/tv_config.dart';
import 'package:Bloomee/tv/ui/tv_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

const _voice = MethodChannel('bloomee_tv/voice');

/// Ricerca vocale: mostra "Ti ascolto…" con le parole riconosciute mentre
/// parli; restituisce il testo finale, o null se annullata.
Future<String?> listenVoice(BuildContext context) async {
  final partial = ValueNotifier<String>('');
  final state = ValueNotifier<String>('ready');
  _voice.setMethodCallHandler((call) async {
    if (call.method == 'partial') partial.value = call.arguments as String;
    if (call.method == 'state') state.value = call.arguments as String;
  });
  var dialogOpen = true;
  final nav = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    builder: (_) => _ListeningDialog(partial: partial, state: state),
  ).then((_) {
    if (dialogOpen) {
      dialogOpen = false;
      _voice.invokeMethod('cancel');
    }
  });
  String? text;
  try {
    text = await _voice.invokeMethod<String>('listen', {'lang': 'it-IT'});
  } on PlatformException catch (e) {
    SnackbarService.showMessage(e.message ?? 'Ricerca vocale non disponibile');
  } on MissingPluginException {
    text = null;
  }
  if (dialogOpen) {
    dialogOpen = false;
    nav.pop();
  }
  _voice.setMethodCallHandler(null);
  final result = (text == null || text.trim().isEmpty) ? partial.value : text;
  partial.dispose();
  state.dispose();
  return result.trim().isEmpty ? null : result;
}

class _ListeningDialog extends StatelessWidget {
  const _ListeningDialog({required this.partial, required this.state});
  final ValueNotifier<String> partial;
  final ValueNotifier<String> state;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: TvColors.surface,
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(color: TvColors.accent, shape: BoxShape.circle),
              child: const Icon(Icons.mic_rounded, size: 52, color: Colors.white),
            ),
            const SizedBox(height: 20),
            ValueListenableBuilder<String>(
              valueListenable: state,
              builder: (_, s, __) => Text(
                switch (s) {
                  'processing' => 'Un attimo…',
                  'speech' => 'Ti ascolto…',
                  _ => 'Parla ora: artista, album o brano',
                },
                style: TvText.body.copyWith(fontSize: 18),
              ),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<String>(
              valueListenable: partial,
              builder: (_, p, __) => Text(p.isEmpty ? ' ' : p, textAlign: TextAlign.center, style: TvText.hero.copyWith(fontSize: 34)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(autofocus: true, onPressed: () => Navigator.of(context).pop(), child: const Text('Annulla')),
      ],
    );
  }
}

String? _art(Artwork? a) => a == null ? null : (a.urlHigh ?? a.url);
String _artists(List<ArtistSummary> a) => a.map((e) => e.name).join(', ');

/// Cerca per TV: barra in alto (OK per scrivere), microfono, filtri e
/// risultati a griglia. Prima i risultati della tua libreria Jellyfin, poi
/// quelli della sorgente online.
class TvSearchScreen extends StatefulWidget {
  const TvSearchScreen({super.key});

  @override
  State<TvSearchScreen> createState() => _TvSearchScreenState();
}

class _TvSearchScreenState extends State<TvSearchScreen> {
  final _content = ContentBloc(pluginService: ServiceLocator.pluginService);
  final _query = TextEditingController();
  final _micNode = FocusNode();
  ContentSearchFilter _filter = ContentSearchFilter.all;
  String _last = '';
  List<JfItem> _jf = const [];

  static const _filters = {
    ContentSearchFilter.all: 'Tutto',
    ContentSearchFilter.track: 'Brani',
    ContentSearchFilter.album: 'Album',
    ContentSearchFilter.artist: 'Artisti',
    ContentSearchFilter.playlist: 'Playlist',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _micNode.requestFocus());
  }

  @override
  void dispose() {
    _content.close();
    _query.dispose();
    _micNode.dispose();
    super.dispose();
  }

  String? _pluginId() {
    final resolvers = context.read<PluginBloc>().state.loadedContentResolvers;
    if (resolvers.isEmpty) return null;
    final pref = context.read<SettingsCubit>().state.searchPluginId;
    return resolvers.any((p) => p.manifest.id == pref) ? pref : resolvers.first.manifest.id;
  }

  void _search() {
    final q = _query.text.trim();
    if (q.isEmpty) return;
    _last = q;
    final id = _pluginId();
    if (id != null) {
      _content.add(SetActiveContentPlugin(pluginId: id));
      _content.add(SearchContent(query: q, filter: _filter));
    }
    final jf = TvConfig.jellyfin;
    if (jf != null) {
      jf.search(q, limit: 30).then((r) {
        if (mounted && _last == q) setState(() => _jf = r);
      }).catchError((_) {});
    }
    setState(() {});
  }

  Future<void> _voiceSearch() async {
    final text = await listenVoice(context);
    if (text == null || text.trim().isEmpty || !mounted) return;
    _query.text = text;
    _search();
  }

  void _push(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

  Widget _onlineCard(MediaItem item, List<MediaItem> all, String pluginId) {
    final (title, sub, img, circle) = item.when(
      track: (t) => (t.title, _artists(t.artists), _art(t.thumbnail), false),
      album: (a) => (a.title, _artists(a.artists), _art(a.thumbnail), false),
      artist: (a) => (a.name, 'Artista', _art(a.thumbnail), true),
      playlist: (p) => (p.title, p.owner ?? 'Playlist', _art(p.thumbnail), false),
    );
    return TvCard(
      title: title,
      subtitle: sub,
      imageUrl: img,
      circle: circle,
      badge: item is MediaItem_Track ? Icons.play_arrow_rounded : null,
      onTap: () => item.when(
        track: (t) {
          final tracks = all.whereType<MediaItem_Track>().map((e) => e.field0).toList();
          final i = tracks.indexWhere((e) => e.id == t.id);
          context.read<BloomeePlayerCubit>().bloomeePlayer.loadPlaylist(
              Playlist(tracks: tracks, title: 'Ricerca: $_last'), idx: i < 0 ? 0 : i, doPlay: true);
        },
        album: (a) => _push(AlbumView(album: a, pluginId: pluginId)),
        artist: (a) => _push(ArtistView(artist: a, pluginId: pluginId)),
        playlist: (p) => _push(OnlPlaylistView(playlist: p, pluginId: pluginId)),
      ),
      onLongPress: item.when(
        track: (t) => () => showDownloadMenu(context, artist: _artists(t.artists), album: t.album?.title ?? '', track: t),
        album: (a) => () => showDownloadMenu(context, artist: _artists(a.artists), album: a.title, albumTracks: () => pluginAlbumTracks(a)),
        artist: (_) => null,
        playlist: (_) => null,
      ),
    );
  }

  Widget _jfRow() {
    final jf = TvConfig.jellyfin;
    if (jf == null || _jf.isEmpty) return const SizedBox.shrink();
    return TvRow(
      title: 'Nella tua libreria',
      subtitle: 'Jellyfin',
      itemCount: _jf.length,
      itemBuilder: (_, i) {
        final it = _jf[i];
        return TvCard(
          title: it.name,
          subtitle: switch (it.type) {
            'MusicArtist' => 'Artista',
            'Audio' => '${it.albumArtist} · brano',
            _ => it.albumArtist,
          },
          imageUrl: it.imageItemId == null ? null : jf.imageUrl(it.imageItemId!, maxSize: 400),
          circle: it.type == 'MusicArtist',
          badge: it.type == 'Audio' ? Icons.play_arrow_rounded : null,
          onTap: () => switch (it.type) {
            'MusicArtist' => _push(TvJellyfinArtistScreen(artist: it)),
            'Audio' => context.read<BloomeePlayerCubit>().bloomeePlayer.updateQueueTracks([it.toTrack(jf)], doPlay: true),
            _ => _push(TvJellyfinAlbumScreen(album: it)),
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TvColors.bg,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(48, 36, 48, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Cerca', style: TvText.hero),
                  const SizedBox(height: 18),
                  FocusTraversalGroup(
                    child: Row(
                      children: [
                        TvPillButton(
                          focusNode: _micNode,
                          icon: Icons.mic_rounded,
                          label: 'Parla',
                          primary: true,
                          onTap: _voiceSearch,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TvTextField(
                            controller: _query,
                            label: 'Artista, album o brano',
                            prefixIcon: Icons.search_rounded,
                            actionLabel: 'Cerca',
                            onSubmitted: (_) => _search(),
                          ),
                        ),
                        const SizedBox(width: 16),
                        TvPillButton(icon: Icons.search_rounded, label: 'Cerca', onTap: _search),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  FocusTraversalGroup(
                    child: Wrap(spacing: 12, runSpacing: 10, children: [
                      for (final f in _filters.entries)
                        TvPillButton(
                          icon: f.key == _filter ? Icons.check_rounded : Icons.filter_list_rounded,
                          label: f.value,
                          primary: f.key == _filter,
                          onTap: () {
                            setState(() => _filter = f.key);
                            _search();
                          },
                        ),
                    ]),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.only(top: 16), child: _jfRow())),
          BlocBuilder<ContentBloc, ContentState>(
            bloc: _content,
            builder: (context, state) {
              final items = state.searchResults?.items ?? const <MediaItem>[];
              final pluginId = state.activePluginId ?? '';
              if (_last.isEmpty) {
                return const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(48),
                    child: TvMessage(
                        icon: Icons.mic_none_rounded,
                        text: 'Premi "Parla" e di\' cosa vuoi ascoltare,\noppure vai sulla barra e premi OK per scrivere.'),
                  ),
                );
              }
              if (items.isEmpty) {
                final loading = state.searchStatus == SearchStatus.loading;
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(48),
                    child: TvMessage(
                      icon: Icons.search_off_rounded,
                      loading: loading,
                      text: loading ? 'Cerco "$_last"…' : 'Nessun risultato online per "$_last"',
                    ),
                  ),
                );
              }
              return SliverMainAxisGroup(slivers: [
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(48, 0, 48, 12),
                    child: Text('Online', style: TvText.title),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(48, 0, 48, 120),
                  sliver: SliverGrid.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 200,
                      mainAxisExtent: 250,
                      crossAxisSpacing: 22,
                      mainAxisSpacing: 14,
                    ),
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final next = state.searchResults?.nextPageToken;
                      if (i == items.length - 4 && next != null && state.searchStatus != SearchStatus.loadingMore) {
                        _content.add(LoadMoreSearchContent(pageToken: next));
                      }
                      return _onlineCard(items[i], items, pluginId);
                    },
                  ),
                ),
              ]);
            },
          ),
        ],
      ),
    );
  }
}
