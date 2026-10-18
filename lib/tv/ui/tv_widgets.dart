import 'package:Bloomee/tv/tv_focus.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
                fit: BoxFit.cover,
                memCacheWidth: (size * 1.6).round(),
                placeholder: (_, __) => placeholder,
                errorWidget: (_, __, ___) => placeholder,
              )
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
              onTap: onTap ?? () {},
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
  });

  final String title;
  final String? subtitle;
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
                  child: Text(title,
                      style: TvText.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
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
            height: height,
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
        _focused ? Colors.white : (primary ? TvColors.accent : TvColors.text);
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
              Text(label, style: TvText.card.copyWith(fontSize: 17, color: fg)),
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
class TvTrackTile extends StatelessWidget {
  const TvTrackTile({
    super.key,
    required this.index,
    required this.title,
    this.subtitle,
    this.duration,
    this.onTap,
    this.onLongPress,
    this.playing = false,
    this.autofocus = false,
  });
  final int index;
  final String title;
  final String? subtitle;
  final Duration? duration;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool playing;
  final bool autofocus;

  static String fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: TvFocusable(
        autofocus: autofocus,
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: TvColors.surface,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: playing
                    ? const Icon(Icons.graphic_eq_rounded,
                        color: TvColors.accent)
                    : Text('$index', style: TvText.cardSub),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TvText.card.copyWith(
                            color: playing ? TvColors.accent : TvColors.text)),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TvText.cardSub),
                  ],
                ),
              ),
              if (duration != null && duration! > Duration.zero)
                Text(fmt(duration!), style: TvText.cardSub),
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
  static const _digits = ['1234567890', '@#/:_+()=*%"', 'àèéìòù\'-.,&!?'];

  void _type(String c) => setState(() => _text += _upper ? c.toUpperCase() : c);
  void _back() {
    if (_text.isNotEmpty)
      setState(() => _text = _text.substring(0, _text.length - 1));
  }

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
      setState(() => _text += ch);
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
                  Icon(icon, color: Colors.white, size: 22),
                  if (label.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(label, style: TvText.card)
                  ],
                ])
              : Text(_upper ? label.toUpperCase() : label,
                  style: TvText.card.copyWith(fontSize: 20)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _symbols ? _digits : _letters;
    final shown = widget.obscure ? '•' * _text.length : _text;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onHardware,
      child: Dialog(
        backgroundColor: TvColors.surface,
        insetPadding: const EdgeInsets.all(24),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: FocusTraversalGroup(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.title, style: TvText.cardSub),
                const SizedBox(height: 8),
                Container(
                  width: 840,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  decoration: BoxDecoration(
                      color: TvColors.bg,
                      borderRadius: BorderRadius.circular(10)),
                  child: Text(shown.isEmpty ? ' ' : '$shown|',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TvText.title.copyWith(fontSize: 26)),
                ),
                const SizedBox(height: 14),
                for (var r = 0; r < rows.length; r++)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    for (var i = 0; i < rows[r].length; i++)
                      _key(rows[r][i], () => _type(rows[r][i]),
                          autofocus: r == 0 && i == 0),
                  ]),
                if (!_symbols)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    for (final d in '1234567890'.split(''))
                      _key(d, () => _type(d)),
                  ]),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  _key('', () => setState(() => _upper = !_upper),
                      icon: _upper
                          ? Icons.keyboard_capslock_rounded
                          : Icons.arrow_upward_rounded,
                      width: 80),
                  _key(_symbols ? 'abc' : '#+=',
                      () => setState(() => _symbols = !_symbols),
                      width: 90),
                  _key('Spazio', () => _type(' '),
                      width: 230, icon: Icons.space_bar_rounded),
                  // OK = cancella una lettera; OK tenuto premuto = cancella tutto.
                  _key('', _back,
                      icon: Icons.backspace_rounded,
                      width: 80,
                      onLongPress: () => setState(() => _text = '')),
                  _key('Svuota', () => setState(() => _text = ''),
                      width: 120, icon: Icons.clear_rounded),
                  _key(widget.actionLabel,
                      () => Navigator.of(context).pop(_text),
                      width: 150, icon: Icons.check_rounded, primary: true),
                ]),
              ],
            ),
          ),
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
