import 'dart:async';

import 'package:Bloomee/blocs/library/cubit/library_items_cubit.dart';
import 'package:Bloomee/blocs/media_player/bloomee_player_cubit.dart';
import 'package:Bloomee/blocs/player_overlay/player_overlay_cubit.dart';
import 'package:Bloomee/core/adapters/track_adapter.dart';
import 'package:Bloomee/screens/screen/player_views/fullscreen_lyrics_view.dart';
import 'package:Bloomee/screens/widgets/snackbar.dart';
import 'package:Bloomee/services/player/player_engine.dart';
import 'package:Bloomee/tv/lidarr_action.dart';
import 'package:Bloomee/tv/tv_focus.dart';
import 'package:Bloomee/tv/ui/tv_widgets.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Player a schermo intero per il televisore: copertina grande, barra di
/// avanzamento comandata con le frecce, comandi grandi e la coda a destra.
///
/// Il focus parte da Play (dentro [tvPlayerAnchor]); destra dai comandi porta
/// alla coda, sinistra dalla coda torna ai comandi, Indietro chiude.
final _queueScope = FocusScopeNode(debugLabel: 'tv-player-queue');
FocusNode? _lastControl;

/// Destra dall'elemento più a destra dei comandi: la coda (sul brano attuale).
KeyEventResult _toQueue(KeyEvent e) {
  if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.arrowRight) return KeyEventResult.ignored;
  final p = FocusManager.instance.primaryFocus;
  if (p == null || p.context == null) return KeyEventResult.ignored;
  // Se a destra c'è un altro comando sulla stessa riga, ci va lui.
  final cur = p.rect;
  final sameRow = p.nearestScope?.traversalDescendants.any((n) =>
          !identical(n, p) &&
          n.canRequestFocus &&
          !_queueScope.descendants.contains(n) &&
          n.rect.left >= cur.right - 4 &&
          n.rect.top < cur.bottom &&
          n.rect.bottom > cur.top) ??
      false;
  if (sameRow) return KeyEventResult.ignored;
  final items = _queueScope.traversalDescendants.where((n) => n.canRequestFocus && n is! FocusScopeNode).toList();
  if (items.isEmpty) return KeyEventResult.handled;
  _lastControl = p;
  final playing = items.firstWhere((n) => n.context?.findAncestorWidgetOfExactType<TvTrackTile>()?.playing ?? false,
      orElse: () => items.first);
  playing.requestFocus();
  return KeyEventResult.handled;
}

/// Sinistra dalla coda: torna al comando da cui si era arrivati.
KeyEventResult _toControls(KeyEvent e) {
  if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.arrowLeft) return KeyEventResult.ignored;
  final last = _lastControl;
  if (last != null && last.context != null && last.canRequestFocus) {
    last.requestFocus();
  } else {
    tvPlayerAnchor.descendants.where((d) => d.canRequestFocus).firstOrNull?.requestFocus();
  }
  return KeyEventResult.handled;
}

class TvPlayerScreen extends StatelessWidget {
  const TvPlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.read<BloomeePlayerCubit>().bloomeePlayer;
    return Scaffold(
      backgroundColor: TvColors.bg,
      body: StreamBuilder<MediaItem?>(
        stream: player.mediaItem,
        builder: (context, snap) {
          final mi = snap.data;
          final art = mi?.artUri?.toString();
          return Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(40, 28, 32, 20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 6,
                      child: FocusTraversalGroup(
                        child: Focus(
                          canRequestFocus: false,
                          skipTraversal: true,
                          onKeyEvent: (n, e) => _toQueue(e),
                          child: _NowPlaying(mi: mi),
                        ),
                      ),
                    ),
                    const SizedBox(width: 32),
                    Expanded(
                      flex: 4,
                      child: FocusScope(
                        node: _queueScope,
                        onKeyEvent: (n, e) => _toControls(e),
                        child: const _Queue(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NowPlaying extends StatelessWidget {
  const _NowPlaying({required this.mi});
  final MediaItem? mi;

  @override
  Widget build(BuildContext context) {
    final player = context.read<BloomeePlayerCubit>().bloomeePlayer;
    final m = mi;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            TvCover(m?.artUri?.toString(), size: 180, radius: 14),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('IN RIPRODUZIONE',
                      style: TextStyle(color: TvColors.accent, fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(m?.title ?? '—',
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: TvText.hero.copyWith(fontSize: 32)),
                  const SizedBox(height: 6),
                  Text(m?.artist ?? '',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TvText.title.copyWith(color: TvColors.textDim, fontSize: 18)),
                  if ((m?.album ?? '').isNotEmpty)
                    Text(m!.album!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TvText.body.copyWith(fontSize: 15)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const _Progress(),
        const SizedBox(height: 14),
        Row(children: [
          StreamBuilder<bool>(
            stream: player.shuffleMode,
            builder: (_, s) => _RoundButton(
              icon: Icons.shuffle_rounded,
              active: s.data ?? false,
              tooltip: 'Casuale',
              onTap: () => player.shuffle(!(s.data ?? false)),
            ),
          ),
          _RoundButton(icon: Icons.skip_previous_rounded, size: 50, tooltip: 'Precedente', onTap: player.skipToPrevious),
          Focus(
            focusNode: tvPlayerAnchor,
            canRequestFocus: false,
            skipTraversal: true,
            child: StreamBuilder<ProgressBarStreams>(
              stream: context.read<BloomeePlayerCubit>().progressStreams,
              builder: (_, s) {
                final playing = s.data?.isPlaying ?? false;
                return _RoundButton(
                  icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 64,
                  primary: true,
                  tooltip: playing ? 'Pausa' : 'Riproduci',
                  onTap: () => playing ? player.pause() : player.play(),
                );
              },
            ),
          ),
          _RoundButton(icon: Icons.skip_next_rounded, size: 50, tooltip: 'Successivo', onTap: player.skipToNext),
          StreamBuilder<LoopMode>(
            stream: player.loopMode,
            builder: (_, s) {
              final mode = s.data ?? LoopMode.off;
              return _RoundButton(
                icon: mode == LoopMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                active: mode != LoopMode.off,
                tooltip: switch (mode) {
                  LoopMode.off => 'Ripeti: no',
                  LoopMode.all => 'Ripeti: tutto',
                  LoopMode.one => 'Ripeti: brano',
                },
                onTap: () => player.setLoopMode(switch (mode) {
                  LoopMode.off => LoopMode.all,
                  LoopMode.all => LoopMode.one,
                  LoopMode.one => LoopMode.off,
                }),
              );
            },
          ),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 12, runSpacing: 12, children: [
          TvPillButton(
            icon: Icons.lyrics_rounded,
            label: 'Testo',
            onTap: () => Navigator.of(context).push(PageRouteBuilder(
              pageBuilder: (_, __, ___) => const FullscreenLyricsView(),
              transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c),
            )),
          ),
          if (m != null) _LikeButton(mi: m),
          if (m != null)
            TvPillButton(
              icon: Icons.download_rounded,
              label: 'Scarica',
              onTap: () {
                final t = mediaItemToTrack(m);
                showDownloadMenu(context, artist: m.artist ?? '', album: m.album ?? '', track: t);
              },
            ),
          TvPillButton(
            icon: Icons.keyboard_arrow_down_rounded,
            label: 'Chiudi',
            onTap: () => context.read<PlayerOverlayCubit>().hidePlayer(),
          ),
        ]),
      ],
    );
  }
}

/// Barra di avanzamento: con il focus, sinistra/destra spostano di 10 s
/// (tenendo premuto si va avanti veloce), OK mette in pausa o riprende.
class _Progress extends StatefulWidget {
  const _Progress();

  @override
  State<_Progress> createState() => _ProgressState();
}

class _ProgressState extends State<_Progress> {
  bool _focused = false;
  // Ha già la sua evidenziazione: niente anello generale.
  late final FocusNode _node = FocusNode(debugLabel: 'tv-progress');
  @override
  void initState() {
    super.initState();
    tvMarkSelfHighlighted(_node);
  }
  Duration? _pending;
  Timer? _commit;

  @override
  void dispose() {
    _node.dispose();
    _commit?.cancel();
    super.dispose();
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e, ProgressBarStreams? p) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final player = context.read<BloomeePlayerCubit>().bloomeePlayer;
    final key = e.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) {
      final dur = p?.duration ?? Duration.zero;
      if (dur == Duration.zero) return KeyEventResult.handled;
      final step = Duration(seconds: e is KeyRepeatEvent ? 20 : 10);
      var target = (_pending ?? p?.position ?? Duration.zero) + (key == LogicalKeyboardKey.arrowRight ? step : -step);
      if (target < Duration.zero) target = Duration.zero;
      if (target > dur) target = dur;
      setState(() => _pending = target);
      _commit?.cancel();
      _commit = Timer(const Duration(milliseconds: 450), () {
        final t = _pending;
        if (t != null) player.seek(t);
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) setState(() => _pending = null);
        });
      });
      return KeyEventResult.handled;
    }
    if (e is KeyDownEvent && kTvSelectKeys.contains(key)) {
      (p?.isPlaying ?? false) ? player.pause() : player.play();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ProgressBarStreams>(
      stream: context.read<BloomeePlayerCubit>().progressStreams,
      builder: (context, snap) {
        final p = snap.data;
        final dur = p?.duration ?? Duration.zero;
        final pos = _pending ?? p?.position ?? Duration.zero;
        final frac = dur.inMilliseconds == 0 ? 0.0 : (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
        return Focus(
          focusNode: _node,
          onFocusChange: (f) => setState(() => _focused = f),
          onKeyEvent: (n, e) => _onKey(n, e, p),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _focused ? TvColors.surfaceHi : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _focused ? TvColors.accent : Colors.transparent, width: 2.5),
            ),
            child: Column(children: [
              LayoutBuilder(builder: (_, c) {
                final w = c.maxWidth;
                return SizedBox(
                  height: 18,
                  child: Stack(alignment: Alignment.centerLeft, children: [
                    Container(height: 6, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(3))),
                    Container(
                        height: 6,
                        width: w * frac,
                        decoration: BoxDecoration(color: TvColors.accent, borderRadius: BorderRadius.circular(3))),
                    Positioned(
                      left: (w * frac - 9).clamp(0.0, w - 18),
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                            color: _focused ? Colors.white : TvColors.accent, shape: BoxShape.circle),
                      ),
                    ),
                  ]),
                );
              }),
              const SizedBox(height: 8),
              Row(children: [
                Text(_fmt(pos), style: TvText.body.copyWith(color: _pending != null ? TvColors.accent : TvColors.textDim)),
                Expanded(
                  child: Text(_focused ? '← indietro 10 s · avanti 10 s →' : '',
                      textAlign: TextAlign.center, style: TvText.body.copyWith(fontSize: 14)),
                ),
                Text(_fmt(dur), style: TvText.body),
              ]),
            ]),
          ),
        );
      },
    );
  }
}

class _RoundButton extends StatefulWidget {
  const _RoundButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.size = 42,
    this.primary = false,
    this.active = false,
  });
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final double size;
  final bool primary;
  final bool active;

  @override
  State<_RoundButton> createState() => _RoundButtonState();
}

class _RoundButtonState extends State<_RoundButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    // Come i pulsanti a pillola: pieno rosa solo con il focus; il pulsante
    // principale (Play) ha il bordo rosa, mai il fondo bianco.
    final fg = _focused
        ? Colors.white
        : (widget.primary || widget.active ? TvColors.accent : TvColors.text);
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onFocusChange: (f) => setState(() => _focused = f),
          child: TvFocusable(
            onTap: widget.onTap,
            scaleOnFocus: 1.08,
            borderRadius: BorderRadius.circular(size),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _focused ? TvColors.accent : TvColors.surfaceHi,
                border: Border.all(
                    color: widget.primary || _focused ? TvColors.accent : Colors.transparent, width: 2),
              ),
              child: Icon(widget.icon, size: size * 0.55, color: fg),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(widget.tooltip, style: TvText.body.copyWith(fontSize: 11)),
      ]),
    );
  }
}

class _LikeButton extends StatefulWidget {
  const _LikeButton({required this.mi});
  final MediaItem mi;

  @override
  State<_LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<_LikeButton> {
  bool _liked = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _LikeButton old) {
    super.didUpdateWidget(old);
    if (old.mi.id != widget.mi.id) _load();
  }

  Future<void> _load() async {
    try {
      final v = await context.read<LibraryItemsCubit>().isTrackLiked(mediaItemToTrack(widget.mi));
      if (mounted) setState(() => _liked = v);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return TvPillButton(
      icon: _liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
      label: _liked ? 'Nei preferiti' : 'Mi piace',
      onTap: () {
        final v = !_liked;
        context.read<LibraryItemsCubit>().setTrackLiked(mediaItemToTrack(widget.mi), v);
        setState(() => _liked = v);
        SnackbarService.showMessage(v ? 'Aggiunto ai preferiti' : 'Tolto dai preferiti');
      },
    );
  }
}

/// Coda di riproduzione: OK su un brano lo fa partire.
class _Queue extends StatelessWidget {
  const _Queue();

  @override
  Widget build(BuildContext context) {
    final player = context.read<BloomeePlayerCubit>().bloomeePlayer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StreamBuilder<String>(
          stream: player.queueTitle,
          builder: (_, s) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Prossimi', style: TvText.title),
            if ((s.data ?? '').isNotEmpty)
              Text('da ${s.data}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TvText.body),
          ]),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: StreamBuilder<List<MediaItem>>(
            stream: player.queue,
            builder: (context, qs) {
              final q = qs.data ?? const <MediaItem>[];
              return StreamBuilder<MediaItem?>(
                stream: player.mediaItem,
                builder: (context, ms) {
                  final current = ms.data?.id;
                  if (q.isEmpty) {
                    return const TvMessage(icon: Icons.queue_music_rounded, text: 'La coda è vuota');
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: 40),
                    itemCount: q.length,
                    itemBuilder: (_, i) => TvTrackTile(
                      index: i + 1,
                      title: q[i].title,
                      subtitle: q[i].artist,
                      duration: q[i].duration,
                      playing: q[i].id == current,
                      onTap: () => player.skipToQueueItem(i),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
