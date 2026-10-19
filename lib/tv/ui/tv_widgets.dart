import 'dart:io';
import 'package:Bloomee/tv/tv_focus.dart';
import 'package:Bloomee/tv/tv_config.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:characters/characters.dart';
import 'package:Bloomee/tv/services/tv_pairing_server.dart';

/// Palette dell'interfaccia TV.
/// Mostra un segreto come pallini più le ultime 4 cifre, per riconoscerlo
/// senza rivelarlo.
String maskSecret(String s) => s.isEmpty
    ? ''
    : s.length <= 4
        ? '•' * 8
        : '${'•' * 8}${s.substring(s.length - 4)}';

class TvColors {
  static const bg = Color(0xFF0B0810);
  static const surface = Color(0xFF17121F);
  static const surfaceHi = Color(0xFF231B2E);
  static const text = Color(0xFFF4EEF8);
  static const textDim = Color(0xFFA79BB3);
  static const accent = kTvFocusColor;
  static const ok = Color(0xFF7BE495);
  static const warn = Color(0xFFFFC46B);
  static const error = Color(0xFFFF6B7A);
}

class TvText {
  static const hero = TextStyle(
      fontFamily: 'Fjalla', fontSize: 44, height: 1.05, color: TvColors.text);
  static const title = TextStyle(
      fontFamily: 'Gilroy',
      fontSize: 22,
      fontWeight: FontWeight.w700,
      color: TvColors.text);
  static const body = TextStyle(
      fontFamily: 'Gilroy', fontSize: 16, color: TvColors.textDim, height: 1.3);
  static const card = TextStyle(
      fontFamily: 'Gilroy',
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: TvColors.text);
  static const cardSub =
      TextStyle(fontFamily: 'Gilroy', fontSize: 13, color: TvColors.textDim);
}

/// Copertina da rete con segnaposto.
class TvCover extends StatelessWidget {
  const TvCover(this.url,
      {super.key, this.size = 170, this.circle = false, this.radius = 12});
  final String? url;
  final double size;
  final bool circle;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: TvColors.surfaceHi,
      alignment: Alignment.center,
      child: Icon(circle ? Icons.person_rounded : Icons.album_rounded,
          color: TvColors.textDim, size: size * 0.35),
    );
    final img = (url == null || url!.isEmpty)
        ? placeholder
        : url!.startsWith('http')
            ? CachedNetworkImage(
                imageUrl: url!,
                cacheKey: '${TvConfig.profileId}:$url',
                httpHeaders: TvConfig.artworkHeaders(url),
                fit: BoxFit.cover,
                memCacheWidth: (size * 1.6).round(),
                placeholder: (_, __) => placeholder,
                errorWidget: (_, __, ___) => placeholder,
              )
            : (Uri.tryParse(url!)?.scheme == 'file' || url!.startsWith('/'))
                ? Image.file(
                    url!.startsWith('/')
                        ? File(url!)
                        : File.fromUri(Uri.parse(url!)),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => placeholder)
                : placeholder;
    return SizedBox(
      width: size,
      height: size,
      child: circle
          ? ClipOval(child: img)
          : ClipRRect(borderRadius: BorderRadius.circular(radius), child: img),
    );
  }
}

/// Card focusabile: copertina grande, titolo e sottotitolo. Quando riceve il
/// focus si ingrandisce e avvisa [onFocused] (la home aggiorna lo sfondo).
class TvCard extends StatelessWidget {
  const TvCard({
    super.key,
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.onTap,
    this.onLongPress,
    this.onFocused,
    this.circle = false,
    this.size = 170,
    this.autofocus = false,
    this.focusNode,
    this.badge,
  });

  final String title;
  final String? subtitle;
  final String? imageUrl;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onFocused;
  final bool circle;
  final double size;
  final bool autofocus;
  final FocusNode? focusNode;
  final IconData? badge;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (f) {
          if (f) onFocused?.call();
        },
        child: Column(
          crossAxisAlignment:
              circle ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            TvFocusable(
              autofocus: autofocus,
              focusNode: focusNode,
              semanticLabel:
                  [title, if (subtitle != null) subtitle!].join(', '),
              onTap: onTap,
              onLongPress: onLongPress,
              scaleOnFocus: 1.07,
              borderRadius: circle
                  ? BorderRadius.circular(size)
                  : BorderRadius.circular(12),
              child: Stack(
                children: [
                  TvCover(imageUrl, size: size, circle: circle),
                  if (badge != null)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                            color: Colors.black54, shape: BoxShape.circle),
                        child: Icon(badge, size: 18, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: circle ? TextAlign.center : TextAlign.start,
                style: TvText.card),
            if (subtitle != null && subtitle!.isNotEmpty)
              Text(subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: circle ? TextAlign.center : TextAlign.start,
                  style: TvText.cardSub),
          ],
        ),
      ),
    );
  }
}

/// Riga orizzontale con titolo, come nelle home di Google TV.
class TvRow extends StatelessWidget {
  const TvRow({
    super.key,
    required this.title,
    required this.itemCount,
    required this.itemBuilder,
    this.height = 250,
    this.subtitle,
    this.trailing,
    this.onTitleTap,
  });

  final String title;
  final String? subtitle;

  /// Se c'è, il titolo diventa un pulsante "Titolo ›" che apre l'elenco completo.
  final VoidCallback? onTitleTap;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double height;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(48, 0, 48, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: onTitleTap == null
                      ? Text(title,
                          style: TvText.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis)
                      : TvFocusable(
                          onTap: onTitleTap!,
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              Flexible(
                                child: Text(title,
                                    style: TvText.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ),
                              const SizedBox(width: 6),
                              const Text('Tutti',
                                  style: TextStyle(
                                      color: TvColors.accent,
                                      fontSize: 18,
                                      fontFamily: 'Gilroy')),
                              const Icon(Icons.chevron_right_rounded,
                                  color: TvColors.accent, size: 30),
                            ]),
                          ),
                        ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(width: 12),
                  Text(subtitle!, style: TvText.cardSub),
                ],
                if (trailing != null) ...[const Spacer(), trailing!],
              ],
            ),
          ),
          SizedBox(
            height: height +
                (MediaQuery.textScalerOf(context).scale(16) / 16 - 1)
                        .clamp(0, 2) *
                    120,
            // Niente FocusTraversalGroup: con i gruppi la freccia giù
            // scavalcava le righe orizzontali.
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 8),
              itemCount: itemCount,
              separatorBuilder: (_, __) => const SizedBox(width: 22),
              itemBuilder: itemBuilder,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pulsante a pillola per le azioni principali (Riproduci, Casuale, Scarica…).
class TvPillButton extends StatefulWidget {
  const TvPillButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.autofocus = false,
    this.focusNode,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  State<TvPillButton> createState() => _TvPillButtonState();
}

class _TvPillButtonState extends State<TvPillButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final primary = widget.primary;
    final icon = widget.icon;
    final label = widget.label;
    // Focus: pieno rosa. Principale/scheda attiva: solo bordo rosa.
    final fg =
        _focused ? TvColors.bg : (primary ? TvColors.accent : TvColors.text);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (f) => setState(() => _focused = f),
      child: TvFocusable(
        autofocus: widget.autofocus,
        focusNode: widget.focusNode,
        onTap: widget.onTap,
        selected: primary,
        scaleOnFocus: 1.05,
        borderRadius: BorderRadius.circular(40),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
          // "Principale" o scheda attiva: bordo e testo colorati, mai pieno,
          // così non si confonde con l'elemento che ha il focus (che è pieno).
          decoration: BoxDecoration(
            color: _focused ? TvColors.accent : TvColors.surfaceHi,
            borderRadius: BorderRadius.circular(40),
            border: Border.all(
                color:
                    primary || _focused ? TvColors.accent : Colors.transparent,
                width: 2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: fg, size: 24),
              const SizedBox(width: 10),
              Flexible(
                  child: Text(label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TvText.card.copyWith(fontSize: 17, color: fg))),
            ],
          ),
        ),
      ),
    );
  }
}

/// Messaggio centrale (vuoto, errore, caricamento) con azione opzionale.
class TvMessage extends StatelessWidget {
  const TvMessage(
      {super.key,
      required this.icon,
      required this.text,
      this.action,
      this.loading = false});
  final IconData icon;
  final String text;
  final Widget? action;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            const SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(color: TvColors.accent))
          else
            Icon(icon, size: 64, color: TvColors.textDim),
          const SizedBox(height: 18),
          Text(text, style: TvText.body, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 22), action!],
        ],
      ),
    );
  }
}

/// Riga di brano focusabile per le liste di tracce.
/// Titolo del brano in riproduzione (lo aggiorna la shell TV): le righe dei
/// brani lo usano per mostrare quale sta suonando.
final ValueNotifier<String?> tvNowPlayingTitle = ValueNotifier<String?>(null);

// Riga che sta suonando: se il focus è su di lei quando il brano cambia, il
// focus passa alla riga del brano nuovo (segue la riproduzione).
FocusNode? _playingTileNode;

class TvTrackTile extends StatefulWidget {
  const TvTrackTile({
    super.key,
    required this.index,
    required this.title,
    this.subtitle,
    this.duration,
    this.onTap,
    this.onLongPress,
    this.playing,
    this.autofocus = false,
  });
  final int index;
  final String title;
  final String? subtitle;
  final Duration? duration;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Se null, la riga capisce da sola se è il brano in riproduzione.
  final bool? playing;
  final bool autofocus;

  static String fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  State<TvTrackTile> createState() => _TvTrackTileState();
}

class _TvTrackTileState extends State<TvTrackTile> {
  final _node = FocusNode(debugLabel: 'tv-track');

  static String _norm(String? s) =>
      (s ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

  bool get _isPlaying =>
      widget.playing ??
      (_norm(tvNowPlayingTitle.value) == _norm(widget.title) &&
          widget.title.isNotEmpty);

  @override
  void initState() {
    super.initState();
    tvNowPlayingTitle.addListener(_onTrackChanged);
    if (_isPlaying) _playingTileNode = _node;
  }

  @override
  void dispose() {
    tvNowPlayingTitle.removeListener(_onTrackChanged);
    if (identical(_playingTileNode, _node)) _playingTileNode = null;
    _node.dispose();
    super.dispose();
  }

  void _onTrackChanged() {
    if (!mounted) return;
    final nowPlaying = _isPlaying;
    if (nowPlaying) {
      final prev = _playingTileNode;
      _playingTileNode = _node;
      // Il focus era sulla riga del brano precedente: lo sposto qui.
      if (prev != null && !identical(prev, _node) && prev.hasPrimaryFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _node.requestFocus();
        });
      }
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final playing = _isPlaying;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: TvFocusable(
        focusNode: _node,
        autofocus: widget.autofocus,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: playing ? TvColors.surfaceHi : TvColors.surface,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: playing
                    ? const Icon(Icons.graphic_eq_rounded,
                        color: TvColors.accent)
                    : Text('${widget.index}', style: TvText.cardSub),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TvText.card.copyWith(
                            color: playing ? TvColors.accent : TvColors.text)),
                    if (widget.subtitle != null && widget.subtitle!.isNotEmpty)
                      Text(widget.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TvText.cardSub),
                  ],
                ),
              ),
              if (playing)
                const Padding(
                  padding: EdgeInsets.only(right: 14),
                  child: Text('In riproduzione',
                      style: TextStyle(
                          color: TvColors.accent,
                          fontSize: 14,
                          fontFamily: 'Gilroy')),
                ),
              if (widget.duration != null && widget.duration! > Duration.zero)
                Text(TvTrackTile.fmt(widget.duration!), style: TvText.cardSub),
            ],
          ),
        ),
      ),
    );
  }
}

/// Campo di testo per il telecomando: OK apre la tastiera a griglia di
/// Bloomee TV (la tastiera di sistema su Flutter non riceve le frecce).
class TvTextField extends StatefulWidget {
  const TvTextField({
    super.key,
    required this.controller,
    required this.label,
    this.obscure = false,
    this.onSubmitted,
    this.prefixIcon,
    this.actionLabel = 'Fatto',
    this.placeholder,
    this.showFilled = false,
    this.revealTail = false,
    this.focusNode,
  });
  final TextEditingController controller;
  final String label;
  final bool obscure;

  /// Testo grigio quando il campo è vuoto (es. "Non inserita"). Con un
  /// placeholder l'etichetta resta sempre visibile sopra il valore.
  final String? placeholder;

  /// Spunta verde a destra quando il campo contiene qualcosa.
  final bool showFilled;

  /// Con [obscure], mostra le ultime 4 cifre (utile per le chiavi API).
  final bool revealTail;
  final FocusNode? focusNode;
  final ValueChanged<String>? onSubmitted;
  final IconData? prefixIcon;
  final String actionLabel;

  @override
  State<TvTextField> createState() => _TvTextFieldState();
}

class _TvTextFieldState extends State<TvTextField> {
  bool _focused = false;

  Future<void> _edit() async {
    final r = await showTvKeyboard(context,
        title: widget.label,
        initial: widget.controller.text,
        obscure: widget.obscure,
        actionLabel: widget.actionLabel);
    if (r == null || !mounted) return;
    widget.controller.text = r;
    setState(() {});
    widget.onSubmitted?.call(r);
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    final shown = !widget.obscure
        ? text
        : widget.revealTail
            ? maskSecret(text)
            : '•' * text.length.clamp(0, 16);
    final ph = widget.placeholder;
    final filled = text.isNotEmpty;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (f) => setState(() => _focused = f),
      child: TvFocusable(
        focusNode: widget.focusNode,
        onTap: _edit,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
              color: TvColors.surfaceHi,
              borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            if (widget.prefixIcon != null) ...[
              Icon(widget.prefixIcon, color: TvColors.textDim),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (filled || ph != null)
                    Text(widget.label,
                        style: TvText.cardSub.copyWith(fontSize: 12)),
                  Text(
                    filled
                        ? shown
                        : _focused
                            ? 'Premi OK per scrivere'
                            : ph ?? widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: filled
                        ? TvText.card.copyWith(
                            fontSize: 17,
                            letterSpacing: widget.obscure ? 1.5 : null)
                        : TvText.cardSub.copyWith(
                            fontSize: 16,
                            fontStyle: ph != null && !_focused
                                ? FontStyle.italic
                                : null,
                            color:
                                _focused ? TvColors.accent : TvColors.textDim),
                  ),
                ],
              ),
            ),
            if (widget.showFilled && filled) ...[
              const Icon(Icons.check_circle_rounded,
                  color: TvColors.ok, size: 22),
              const SizedBox(width: 10),
            ],
            Icon(Icons.keyboard_rounded,
                color: _focused ? TvColors.accent : TvColors.textDim),
          ]),
        ),
      ),
    );
  }
}

/// Tastiera a griglia per il telecomando. Accetta anche una tastiera fisica
/// (o quella del Mac via scrcpy). Restituisce il testo, null se annullata.
Future<String?> showTvKeyboard(BuildContext context,
    {required String title,
    String initial = '',
    bool obscure = false,
    String actionLabel = 'Fatto'}) {
  return showDialog<String>(
    context: context,
    barrierColor: Colors.black87,
    builder: (_) => _TvKeyboard(
        title: title,
        initial: initial,
        obscure: obscure,
        actionLabel: actionLabel),
  );
}

class _TvKeyboard extends StatefulWidget {
  const _TvKeyboard(
      {required this.title,
      required this.initial,
      required this.obscure,
      required this.actionLabel});
  final String title;
  final String initial;
  final bool obscure;
  final String actionLabel;

  @override
  State<_TvKeyboard> createState() => _TvKeyboardState();
}

class _TvKeyboardState extends State<_TvKeyboard> {
  late String _text = widget.initial;
  late int _cursor = widget.initial.characters.length;
  final _firstKey = FocusNode(debugLabel: 'tv-kb-a');

  @override
  void initState() {
    super.initState();
    // Focus sempre sulla prima lettera, anche se il dialogo si apre mentre
    // un altro elemento lo sta trattenendo.
    for (final ms in const [0, 150, 400]) {
      Future.delayed(Duration(milliseconds: ms), () {
        if (!mounted) return;
        final p = FocusManager.instance.primaryFocus;
        final insideKey = p != null && p.debugLabel == 'tv-kb-key';
        if (!insideKey) _firstKey.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _firstKey.dispose();
    super.dispose();
  }

  bool _upper = false;
  bool _symbols = false;

  static const _letters = ['abcdefghijklm', 'nopqrstuvwxyz', 'àèéìòù\'-.,&!?'];
  static final _digits = [
    String.fromCharCodes(List.generate(94, (i) => i + 33))
  ];

  void _type(String c, {bool applyCase = true}) => setState(() {
        final chars = _text.characters.toList();
        final insert =
            (applyCase && _upper ? c.toUpperCase() : c).characters.toList();
        chars.insertAll(_cursor, insert);
        _cursor += insert.length;
        _text = chars.join();
      });
  void _back() {
    if (_cursor == 0) return;
    setState(() {
      final chars = _text.characters.toList();
      chars.removeAt(--_cursor);
      _text = chars.join();
    });
  }

  void _clear() => setState(() {
        _text = '';
        _cursor = 0;
      });
  KeyEventResult _onHardware(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent)
      return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.backspace) {
      _back();
      return KeyEventResult.handled;
    }
    final ch = e.character;
    if (ch != null &&
        ch.isNotEmpty &&
        ch.runes.first >= 32 &&
        !kTvSelectKeys.contains(e.logicalKey)) {
      _type(ch, applyCase: false);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _key(String label, VoidCallback onTap,
      {double width = 56,
      IconData? icon,
      bool primary = false,
      bool autofocus = false,
      VoidCallback? onLongPress}) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: TvFocusable(
        focusNode: autofocus ? _firstKey : null,
        debugLabel: 'tv-kb-key',
        onTap: onTap,
        onLongPress: onLongPress,
        scaleOnFocus: 1.08,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: width,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: primary ? TvColors.accent : TvColors.surfaceHi,
            borderRadius: BorderRadius.circular(10),
          ),
          child: icon != null
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon,
                      color: primary ? TvColors.bg : TvColors.text, size: 22),
                  if (label.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(label, style: TvText.card)
                  ],
                ])
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(_upper ? label.toUpperCase() : label,
                      style: TvText.card.copyWith(
                          fontSize: 20,
                          color: primary ? TvColors.bg : TvColors.text))),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keys = (_symbols ? _digits.join() : '${_letters.join()}1234567890')
        .characters
        .toList();
    final display = widget.obscure
        ? List.filled(_text.characters.length, '•')
        : _text.characters.toList();
    final shown =
        [...display.take(_cursor), '│', ...display.skip(_cursor)].join();
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onHardware,
      child: Dialog(
        backgroundColor: TvColors.surface,
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 900,
          height: MediaQuery.sizeOf(context).height - 48,
          child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                Text(widget.title, style: TvText.title),
                const SizedBox(height: 8),
                Container(
                    width: double.infinity,
                    color: TvColors.bg,
                    padding: const EdgeInsets.all(10),
                    child: Text(shown.isEmpty ? ' ' : '$shown|',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TvText.title)),
                if (!widget.obscure)
                  ListenableBuilder(
                      listenable: tvPairing,
                      builder: (_, __) => tvPairing.pendingText == null
                          ? const SizedBox.shrink()
                          : TextButton(
                              onPressed: () => setState(() {
                                    _text = tvPairing.takeText()!;
                                    _cursor = _text.characters.length;
                                  }),
                              child: const Text(
                                  'Usa il testo inviato dal telefono'))),
                const SizedBox(height: 8),
                Expanded(
                    child: LayoutBuilder(
                        builder: (_, constraints) => GridView.builder(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: (constraints.maxWidth / 62)
                                        .floor()
                                        .clamp(4, 13),
                                    mainAxisExtent: 60),
                            itemCount: keys.length,
                            itemBuilder: (_, i) => _key(
                                keys[i], () => _type(keys[i]),
                                autofocus: i == 0)))),
                Wrap(alignment: WrapAlignment.center, children: [
                  _key(_upper ? 'abc' : 'ABC',
                      () => setState(() => _upper = !_upper),
                      width: 85),
                  _key(_symbols ? 'Lettere' : 'Simboli',
                      () => setState(() => _symbols = !_symbols),
                      width: 110),
                  _key('Spazio', () => _type(' '), width: 110),
                  _key('Cancella', _back, width: 110, onLongPress: _clear),
                  _key('Svuota', _clear, width: 100),
                  _key(
                      'Cursore ←',
                      () => setState(() => _cursor =
                          (_cursor - 1).clamp(0, _text.characters.length)),
                      width: 110),
                  _key(
                      'Cursore →',
                      () => setState(() => _cursor =
                          (_cursor + 1).clamp(0, _text.characters.length)),
                      width: 110),
                  _key(widget.actionLabel, () => Navigator.pop(context, _text),
                      width: 140, primary: true),
                ]),
              ])),
        ),
      ),
    );
  }
}

/// Pagina di un album o di una playlist: a sinistra copertina, titolo e dati;
/// a destra i pulsanti, fissi in alto su una riga sola, e sotto la lista dei
/// brani, che scorre da sola. Così i pulsanti non scorrono via e non vengono
/// tagliati, e tutto sta sopra la barra del player.
class TvCollectionLayout extends StatelessWidget {
  const TvCollectionLayout({
    super.key,
    required this.cover,
    required this.title,
    required this.meta,
    required this.actions,
    required this.itemCount,
    required this.itemBuilder,
    this.loading = false,
    this.error,
  });

  final Widget cover;
  final String title;
  final String meta;
  final List<Widget> actions;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final bool loading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 320,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(48, 32, 24, 16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              cover,
              const SizedBox(height: 16),
              Text(title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TvText.hero.copyWith(fontSize: 28, height: 1.1)),
              const SizedBox(height: 6),
              Text(meta,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TvText.body.copyWith(fontSize: 16)),
            ]),
          ),
        ),
        Expanded(
          child: FocusTraversalGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 32, 32, 14),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    child: Row(children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const SizedBox(width: 12),
                        actions[i],
                      ],
                    ]),
                  ),
                ),
                Expanded(
                  child: loading
                      ? const TvMessage(
                          icon: Icons.hourglass_empty,
                          text: 'Carico i brani…',
                          loading: true)
                      : error != null
                          ? TvMessage(icon: Icons.error_outline, text: error!)
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 4, 32, 24),
                              itemCount: itemCount,
                              itemBuilder: itemBuilder,
                            ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
