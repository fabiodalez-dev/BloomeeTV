import 'dart:async';
import 'package:Bloomee/tv/services/tv_workspace.dart';

import 'package:Bloomee/tv/tv_mode.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Impostato dalla shell TV: porta il focus sul menu laterale.
VoidCallback? tvFocusMenu;

/// Contenitore del pulsante Play del player: all'apertura del player il
/// focus va lì.
final FocusNode tvPlayerAnchor = FocusNode(debugLabel: 'tv-player-play');

/// Colore del riquadro di focus su TV.
const Color kTvFocusColor = Color(0xFFFF4D6D);

/// Tasti che sul telecomando equivalgono a "OK".
final Set<LogicalKeyboardKey> kTvSelectKeys = {
  LogicalKeyboardKey.select,
  LogicalKeyboardKey.enter,
  LogicalKeyboardKey.numpadEnter,
  LogicalKeyboardKey.gameButtonA,
};

/// Rende [child] raggiungibile col D-pad: riquadro evidenziato quando ha il
/// focus, OK = [onTap], OK tenuto premuto = [onLongPress].
class TvFocusable extends StatefulWidget {
  const TvFocusable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
    this.autofocus = false,
    this.focusNode,
    this.scaleOnFocus = 1.0,
    this.debugLabel,
    this.selected = false,
    this.semanticLabel,
  });

  /// Elemento "scelto" della sua riga (es. la scheda attiva): entrando nella
  /// riga dall'alto o dal basso il focus va qui.
  final bool selected;
  final String? semanticLabel;
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius borderRadius;
  final bool autofocus;
  final FocusNode? focusNode;
  final double scaleOnFocus;
  final String? debugLabel;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  static const _longPress = Duration(milliseconds: 550);
  bool _focused = false;
  Timer? _holdTimer;
  bool _longFired = false;
  // OK premuto su questo elemento: il rilascio conta solo in questo caso
  // (dopo la chiusura di un dialogo il focus torna qui e riceverebbe il
  // rilascio del tasto premuto nel dialogo, riaprendolo).
  bool _pressed = false;
  FocusNode? _own;
  FocusNode get _node =>
      widget.focusNode ?? (_own ??= FocusNode(debugLabel: widget.debugLabel));

  @override
  void initState() {
    super.initState();
    tvMarkSelfHighlighted(_node);
    _node.addListener(_sync);
  }

  @override
  void didUpdateWidget(covariant TvFocusable old) {
    super.didUpdateWidget(old);
    final before = old.focusNode ?? _own;
    if (!identical(before, _node)) {
      before?.removeListener(_sync);
      tvMarkSelfHighlighted(_node);
      _node.addListener(_sync);
    }
  }

  // L'evidenziazione segue sempre il focus reale (mai "accesa" per errore).
  void _sync() {
    final f = _node.hasPrimaryFocus;
    if (f != _focused && mounted) setState(() => _focused = f);
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _node.removeListener(_sync);
    _own?.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!kTvSelectKeys.contains(event.logicalKey))
      return KeyEventResult.ignored;
    if (widget.onTap == null && widget.onLongPress == null) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      _pressed = true;
      _longFired = false;
      _holdTimer?.cancel();
      if (widget.onLongPress != null) {
        _holdTimer = Timer(_longPress, () {
          _longFired = true;
          widget.onLongPress?.call();
        });
      }
      return KeyEventResult.handled;
    }
    if (event is KeyRepeatEvent) {
      if (!_pressed) return KeyEventResult.handled;
      // Android ripete il tasto quando è tenuto premuto: è già un long press.
      if (widget.onLongPress != null && !_longFired) {
        _holdTimer?.cancel();
        _longFired = true;
        widget.onLongPress?.call();
      }
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) {
      _holdTimer?.cancel();
      final wasPressed = _pressed;
      _pressed = false;
      if (wasPressed && !_longFired) widget.onTap?.call();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onTap != null || widget.onLongPress != null;
    _focused = _node.hasPrimaryFocus;
    return Semantics(
        label: widget.semanticLabel,
        button: true,
        enabled: interactive,
        selected: widget.selected,
        focusable: interactive,
        focused: _focused,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: GestureDetector(
            excludeFromSemantics: true,
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            child: Focus(
              focusNode: _node,
              autofocus: widget.autofocus,
              canRequestFocus: interactive,
              skipTraversal: !interactive,
              onKeyEvent: _onKey,
              child: AnimatedScale(
                scale: _focused && TvWorkspace.instance['reduceMotion'] != true
                    ? widget.scaleOnFocus
                    : 1.0,
                duration: MediaQuery.disableAnimationsOf(context) ||
                        TvWorkspace.instance['reduceMotion'] == true
                    ? Duration.zero
                    : const Duration(milliseconds: 120),
                child: DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(
                    borderRadius: widget.borderRadius,
                    border: Border.all(
                      color: _focused
                          ? (TvWorkspace.instance['highContrast'] == true
                              ? Colors.white
                              : kTvFocusColor)
                          : Colors.transparent,
                      width:
                          TvWorkspace.instance['strongFocus'] == true ? 5 : 3,
                    ),
                    boxShadow: _focused
                        ? [
                            BoxShadow(
                              color: kTvFocusColor.withValues(alpha: 0.35),
                              blurRadius: 14,
                              spreadRadius: 1,
                            )
                          ]
                        : const [],
                  ),
                  child: widget.child,
                ),
              ),
            )));
  }
}

/// Sostituto di [GestureDetector]: identico fuori dalla TV; su TV, se ha un
/// tocco, diventa anche focusabile e attivabile col telecomando.
class TvGestureDetector extends StatelessWidget {
  const TvGestureDetector({
    super.key,
    this.child,
    this.onTap,
    this.onTapDown,
    this.onTapUp,
    this.onTapCancel,
    this.onDoubleTap,
    this.onLongPress,
    this.onLongPressStart,
    this.onLongPressEnd,
    this.onSecondaryTap,
    this.onSecondaryTapDown,
    this.onVerticalDragStart,
    this.onVerticalDragUpdate,
    this.onVerticalDragEnd,
    this.onHorizontalDragStart,
    this.onHorizontalDragUpdate,
    this.onHorizontalDragEnd,
    this.onPanDown,
    this.onPanStart,
    this.onPanCancel,
    this.onHorizontalDragCancel,
    this.onPanUpdate,
    this.onPanEnd,
    this.behavior,
    this.excludeFromSemantics = false,
    this.tvBorderRadius = const BorderRadius.all(Radius.circular(10)),
    this.tvFocusable = true,
  });

  /// Su TV: false = non riceve il focus (lo ricevono i pulsanti interni).
  final bool tvFocusable;
  final Widget? child;
  final GestureTapCallback? onTap;
  final GestureTapDownCallback? onTapDown;
  final GestureTapUpCallback? onTapUp;
  final GestureTapCancelCallback? onTapCancel;
  final GestureTapCallback? onDoubleTap;
  final GestureLongPressCallback? onLongPress;
  final GestureLongPressStartCallback? onLongPressStart;
  final GestureLongPressEndCallback? onLongPressEnd;
  final GestureTapCallback? onSecondaryTap;
  final GestureTapDownCallback? onSecondaryTapDown;
  final GestureDragStartCallback? onVerticalDragStart;
  final GestureDragUpdateCallback? onVerticalDragUpdate;
  final GestureDragEndCallback? onVerticalDragEnd;
  final GestureDragStartCallback? onHorizontalDragStart;
  final GestureDragUpdateCallback? onHorizontalDragUpdate;
  final GestureDragEndCallback? onHorizontalDragEnd;
  final GestureDragDownCallback? onPanDown;
  final GestureDragStartCallback? onPanStart;
  final GestureDragCancelCallback? onPanCancel;
  final GestureDragCancelCallback? onHorizontalDragCancel;
  final GestureDragUpdateCallback? onPanUpdate;
  final GestureDragEndCallback? onPanEnd;
  final HitTestBehavior? behavior;
  final bool excludeFromSemantics;
  final BorderRadius tvBorderRadius;

  @override
  Widget build(BuildContext context) {
    final detector = GestureDetector(
      onTap: onTap,
      onTapDown: onTapDown,
      onTapUp: onTapUp,
      onTapCancel: onTapCancel,
      onDoubleTap: onDoubleTap,
      onLongPress: onLongPress,
      onLongPressStart: onLongPressStart,
      onLongPressEnd: onLongPressEnd,
      onSecondaryTap: onSecondaryTap,
      onSecondaryTapDown: onSecondaryTapDown,
      onVerticalDragStart: onVerticalDragStart,
      onVerticalDragUpdate: onVerticalDragUpdate,
      onVerticalDragEnd: onVerticalDragEnd,
      onHorizontalDragStart: onHorizontalDragStart,
      onHorizontalDragUpdate: onHorizontalDragUpdate,
      onHorizontalDragEnd: onHorizontalDragEnd,
      onPanDown: onPanDown,
      onPanStart: onPanStart,
      onPanCancel: onPanCancel,
      onHorizontalDragCancel: onHorizontalDragCancel,
      onPanUpdate: onPanUpdate,
      onPanEnd: onPanEnd,
      behavior: behavior,
      excludeFromSemantics: excludeFromSemantics,
      child: child,
    );
    final tap = onTap ?? onDoubleTap ?? onSecondaryTap;
    final long = onLongPress ??
        (onLongPressStart != null
            ? () => onLongPressStart!(const LongPressStartDetails())
            : null);
    if (!TvMode.isTv || !tvFocusable || (tap == null && long == null))
      return detector;
    return TvFocusable(
      onTap: tap,
      onLongPress: long,
      borderRadius: tvBorderRadius,
      child: detector,
    );
  }
}

/// Radice TV: tema con focus visibile, OK = attiva, scorrimento automatico
/// verso l'elemento con focus, primo focus al primo tasto freccia.
/// Nodi che disegnano da soli la propria evidenziazione (TvFocusable, voci
/// del menu): per gli altri (i widget originali di Bloomee) TvRoot disegna un
/// anello di focus ben visibile.
final Expando<bool> _selfHighlighted = Expando<bool>();
void tvMarkSelfHighlighted(FocusNode n) => _selfHighlighted[n] = true;

/// Anello attorno all'elemento con il focus, sopra tutto, per i widget che non
/// hanno un'evidenziazione propria abbastanza visibile su un televisore.
class _FocusRingPainter extends CustomPainter {
  _FocusRingPainter(this.rect) : super();
  final Rect? rect;

  @override
  void paint(Canvas canvas, Size size) {
    final r = rect;
    if (r == null) return;
    final rr = RRect.fromRectAndRadius(
        r.inflate(3), Radius.circular((r.shortestSide / 2).clamp(6, 16)));
    canvas.drawRRect(
        rr,
        Paint()
          ..color = const Color(0x55FF4D7E)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawRRect(
        rr,
        Paint()
          ..color = const Color(0xFFFF4D7E)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);
  }

  @override
  bool shouldRepaint(_FocusRingPainter old) => old.rect != rect;
}

class _FocusRing extends StatefulWidget {
  const _FocusRing();
  @override
  State<_FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<_FocusRing> {
  Rect? _rect;
  bool _alive = true;

  @override
  void initState() {
    super.initState();
    // Il rettangolo cambia anche senza cambi di focus (scorrimento,
    // animazioni): lo ricontrollo a ogni frame, ridisegnando solo se cambia.
    SchedulerBinding.instance.addPersistentFrameCallback(_tick);
    FocusManager.instance.addListener(_check);
  }

  @override
  void dispose() {
    _alive = false;
    FocusManager.instance.removeListener(_check);
    super.dispose();
  }

  void _tick(Duration _) {
    if (_alive) _check();
  }

  void _check() {
    if (!_alive || !mounted) return;
    final p = FocusManager.instance.primaryFocus;
    Rect? r;
    if (p != null &&
        p is! FocusScopeNode &&
        p.context != null &&
        p.context!.mounted &&
        _selfHighlighted[p] != true &&
        p.context!.findAncestorStateOfType<EditableTextState>() == null) {
      final rect = p.rect;
      if (!rect.isEmpty && rect.width > 4 && rect.height > 4) r = rect;
    }
    if (r != _rect) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_alive && mounted) setState(() => _rect = r);
      });
    }
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
      child:
          CustomPaint(painter: _FocusRingPainter(_rect), size: Size.infinite));
}

/// Throttles held arrows without delaying individual key presses.
class TvKeyRepeatGate {
  DateTime? _last;
  bool allow(
      {required bool repeat,
      required DateTime now,
      required Duration interval}) {
    if (repeat && _last != null && now.difference(_last!) < interval)
      return false;
    _last = now;
    return true;
  }
}

class TvRoot extends StatefulWidget {
  const TvRoot({super.key, required this.child});
  final Widget child;

  @override
  State<TvRoot> createState() => _TvRootState();
}

class _TvRootState extends State<TvRoot> {
  final _repeatGate = TvKeyRepeatGate();
  static final _arrows = {
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
  };

  @override
  void initState() {
    super.initState();
    if (!TvMode.isTv) return;
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    FocusManager.instance.addListener(_onFocusChanged);
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    if (TvMode.isTv) {
      FocusManager.instance.removeListener(_onFocusChanged);
      HardwareKeyboard.instance.removeHandler(_onKey);
    }
    super.dispose();
  }

  // Pagina appena aperta: il focus sta sul suo contenitore, invisibile.
  // Appena la pagina ha qualcosa, lo porto sul primo elemento.
  FocusScopeNode? _pendingScope;
  DateTime _pageOpened = DateTime(0);
  void _focusIntoScope(FocusScopeNode scope) {
    if (identical(_pendingScope, scope)) return;
    _pageOpened = DateTime.now();
    _pendingScope = scope;
    for (final ms in const [80, 400, 900, 1800, 3500, 6000]) {
      Future.delayed(Duration(milliseconds: ms), () {
        if (!mounted || !identical(FocusManager.instance.primaryFocus, scope))
          return;
        tvFocusFirstIn(scope);
      });
    }
    Future.delayed(const Duration(milliseconds: 6100), () {
      if (identical(_pendingScope, scope)) _pendingScope = null;
    });
  }

  void _onFocusChanged() {
    final pf = FocusManager.instance.primaryFocus;
    if (pf is FocusScopeNode && pf.context != null) _focusIntoScope(pf);
    if (pf != null && pf is! FocusScopeNode) tvRememberRowFocus(pf);
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null || !ctx.mounted) return;
    if (Scrollable.maybeOf(ctx) == null) return;
    _scrollMinimal(ctx, pf!.rect);
  }

  /// Scorre ogni lista che contiene l'elemento solo di quanto serve perché
  /// si veda per intero, con un margine (titolo della riga sopra, didascalia
  /// sotto). Mai centrare: la pagina non salta e i titoli restano al loro posto.
  void _scrollMinimal(BuildContext ctx, Rect r) {
    BuildContext? c = ctx;
    while (c != null) {
      final st = Scrollable.maybeOf(c);
      if (st == null) return;
      final box = st.context.findRenderObject();
      if (box is RenderBox && box.hasSize) {
        final vp = box.localToGlobal(Offset.zero) & box.size;
        final vertical = axisDirectionToAxis(st.axisDirection) == Axis.vertical;
        // Copertine (alte): spazio per il titolo della riga sopra e la
        // didascalia sotto. Pulsanti e voci: solo un piccolo respiro.
        final card = r.height > 120;
        final start = vertical ? r.top - (card ? 48 : 12) : r.left - 48;
        final end = vertical ? r.bottom + (card ? 56 : 12) : r.right + 48;
        final vs = vertical ? vp.top : vp.left;
        final ve = vertical ? vp.bottom : vp.right;
        double delta = 0;
        if (start < vs) {
          delta = start - vs;
        } else if (end > ve) {
          delta = (end - ve).clamp(0, start - vs).toDouble();
        }
        final pos = st.position;
        if (delta.abs() > 0.5) {
          final reversed = st.axisDirection == AxisDirection.up ||
              st.axisDirection == AxisDirection.left;
          final target = (pos.pixels + (reversed ? -delta : delta))
              .clamp(pos.minScrollExtent, pos.maxScrollExtent);
          if (TvWorkspace.instance['reduceMotion'] == true ||
              MediaQuery.disableAnimationsOf(st.context)) {
            pos.jumpTo(target);
          } else {
            pos.animateTo(target,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut);
          }
        }
      }
      c = st.context;
    }
  }

  /// Se nessun elemento ha il focus, la prima freccia lo porta al primo
  /// elemento interattivo della schermata invece di non fare nulla.
  bool _onKey(KeyEvent event) {
    // Doppio OK: il secondo arriva sulla pagina appena aperta e farebbe
    // partire il suo primo pulsante. Subito dopo l'apertura lo ignoro.
    if (kTvSelectKeys.contains(event.logicalKey) &&
        DateTime.now().difference(_pageOpened) <
            const Duration(milliseconds: 600)) {
      return true;
    }
    if ((event is! KeyDownEvent && event is! KeyRepeatEvent) ||
        !_arrows.contains(event.logicalKey)) {
      return false;
    }
    if (!_repeatGate.allow(
        repeat: event is KeyRepeatEvent,
        now: DateTime.now(),
        interval: Duration(
            milliseconds: (TvWorkspace.instance['keyRepeatMs'] as int? ?? 120)
                .clamp(80, 300)))) return true;
    final primary = FocusManager.instance.primaryFocus;
    // Focus su un contenitore (non un elemento): la freccia va sul primo
    // elemento interattivo al suo interno.
    if (primary != null &&
        primary is! FocusScopeNode &&
        event is KeyDownEvent) {
      final inner = primary.traversalDescendants
          .where((n) => n.canRequestFocus && n is! FocusScopeNode)
          .toList();
      if (inner.isNotEmpty && primary.context?.widget is! EditableText) {
        final ctx = primary.context;
        final isLeaf = ctx == null || inner.every((n) => n.context == null);
        if (!isLeaf) {
          inner.first.requestFocus();
          return true;
        }
      }
    }
    if (primary == null || primary is FocusScopeNode) {
      if (event is! KeyDownEvent) return false;
      // Focus perso (es. dopo Indietro): sinistra apre sempre il menu.
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
          tvFocusMenu != null) {
        tvFocusMenu!();
        return true;
      }
      final scope =
          primary is FocusScopeNode ? primary : FocusManager.instance.rootScope;
      return tvFocusFirstIn(scope) || scope.nextFocus();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (!TvMode.isTv) return widget.child;
    return Shortcuts(
      shortcuts: {
        for (final k in kTvSelectKeys)
          SingleActivator(k): const ActivateIntent(),
      },
      child: Stack(
        textDirection: TextDirection.ltr,
        children: [
          widget.child,
          const Positioned.fill(child: _FocusRing()),
        ],
      ),
    );
  }
}

/// Tema con focus ben visibile per i widget Material nativi (bottoni, voci di
/// lista, InkWell) quando l'app gira su TV.
ThemeData tvTheme(ThemeData base) {
  if (!TvMode.isTv) return base;
  final focus = kTvFocusColor.withValues(alpha: 0.45);
  WidgetStateProperty<BorderSide?> side() =>
      WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.focused)
          ? const BorderSide(color: kTvFocusColor, width: 3)
          : null);
  return base.copyWith(
    focusColor: focus,
    highlightColor: focus,
    listTileTheme: base.listTileTheme.copyWith(selectedTileColor: focus),
    iconButtonTheme: IconButtonThemeData(
      style: (base.iconButtonTheme.style ?? const ButtonStyle()).copyWith(
        side: side(),
        overlayColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.focused) ? focus : null),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: (base.textButtonTheme.style ?? const ButtonStyle())
          .copyWith(side: side()),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: (base.elevatedButtonTheme.style ?? const ButtonStyle())
          .copyWith(side: side()),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: (base.outlinedButtonTheme.style ?? const ButtonStyle())
          .copyWith(side: side()),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: (base.filledButtonTheme.style ?? const ButtonStyle())
          .copyWith(side: side()),
    ),
  );
}

/// Su/giù geometrico. Flutter, dentro una lista verticale, preferisce gli
/// elementi della stessa lista e scavalca le righe orizzontali (che sono
/// liste a parte): qui scelgo la riga immediatamente sopra/sotto e, in
/// quella, l'elemento più vicino in orizzontale.
/// Memoria per riga: l'ultimo elemento che ha avuto il focus in ogni riga
/// orizzontale, così tornando su una riga si riprende da dove si era.
final Expando<FocusNode> _rowMemory = Expando('tv-row-memory');

/// Identità della riga orizzontale di [n]: la lista orizzontale che lo
/// contiene, oppure la fila di pulsanti (Row/Wrap) in cui sta. Null per le
/// griglie e le liste verticali.
Object? tvRowKeyOf(FocusNode n) {
  final ctx = n.context;
  if (ctx == null || !ctx.mounted) return null;
  final s = Scrollable.maybeOf(ctx);
  if (s != null && axisDirectionToAxis(s.axisDirection) == Axis.horizontal)
    return s;
  final h = n.rect.height;
  RenderObject? ro = ctx.findRenderObject()?.parent;
  for (var i = 0; ro != null && i < 14; i++, ro = ro.parent) {
    if (ro is RenderSliver || ro is RenderAbstractViewport) return null;
    if (ro is RenderBox && ro.hasSize && ro.size.height > h * 2.2 + 24)
      return null;
    if (ro is RenderWrap &&
        ro.direction == Axis.horizontal &&
        ro.childCount > 1) return ro;
    if (ro is RenderFlex &&
        ro.direction == Axis.horizontal &&
        ro.childCount > 1) return ro;
  }
  return null;
}

/// Da chiamare a ogni cambio di focus.
void tvRememberRowFocus(FocusNode n) {
  final key = tvRowKeyOf(n);
  if (key != null) _rowMemory[key] = n;
}

// Ultimo spostamento verticale: tornando indietro subito si rientra
// esattamente nell'elemento da cui si era partiti.
FocusNode? _vFrom;
FocusNode? _vTo;
bool _vDown = false;

bool _isSelected(FocusNode n) =>
    n.context?.findAncestorWidgetOfExactType<TvFocusable>()?.selected ?? false;

/// Su/giù "a righe": va alla riga sopra o sotto; dentro quella riga sceglie
/// l'elemento da cui si era usciti, altrimenti quello scelto (scheda attiva),
/// altrimenti quello in colonna. Restituisce false se non c'è niente.
/// [ctx] sta dentro [target], anche attraverso liste annidate (es. una
/// riga orizzontale dentro la pagina che scorre in verticale).
bool _insideScrollable(BuildContext ctx, ScrollableState target) {
  BuildContext? c = ctx;
  while (c != null) {
    final st = Scrollable.maybeOf(c);
    if (st == null) return false;
    if (identical(st, target)) return true;
    c = st.context;
  }
  return false;
}

// Una pagina che deve prima scorrere (righe non ancora costruite) completa il
// passo al frame successivo: fino ad allora le altre pressioni vengono
// ignorate, così premere due volte di fila non fa mai due salti.
bool _vBusy = false;
bool get tvVerticalBusy => _vBusy;

/// Scorre subito a [target] e, appena la pagina è ricostruita, esegue [then].
void tvScrollThen(ScrollPosition pos, double target, VoidCallback then) {
  _vBusy = true;
  pos.jumpTo(target.clamp(pos.minScrollExtent, pos.maxScrollExtent).toDouble());
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _vBusy = false;
    then();
  });
  WidgetsBinding.instance.scheduleFrame();
}

bool tvMoveVertically(FocusNode current, {required bool down}) {
  if (_vBusy) return true;
  final ctx = current.context;
  if (ctx == null || !ctx.mounted) return false;
  // Anche gli elementi fuori dalle liste (es. la freccia indietro in alto)
  // si muovono a righe: niente salti della navigazione standard.
  final scrollable = Scrollable.maybeOf(ctx);
  if (ctx.findAncestorStateOfType<EditableTextState>() != null) return false;
  final scope = current.nearestScope;
  if (scope == null) return false;
  final cur = current.rect;
  const slack = 8.0;
  final candidates = <FocusNode>[];
  for (final n in scope.traversalDescendants) {
    if (identical(n, current) || n is FocusScopeNode || !n.canRequestFocus)
      continue;
    final c = n.context;
    if (c == null || !c.mounted) continue;
    final r = n.rect;
    if (r.isEmpty) continue;
    if (down ? r.top >= cur.bottom - slack : r.bottom <= cur.top + slack) {
      candidates.add(n);
    }
  }
  // Prima si resta nella lista/griglia in cui si è: se fuori schermo ci sono
  // altri elementi in quella direzione, la lista scorre invece di saltare
  // fuori (alle schede o alla barra).
  final pos = scrollable?.position;
  final inSame = scrollable == null
      ? <FocusNode>[]
      : candidates
          .where((n) =>
              n.context != null && _insideScrollable(n.context!, scrollable))
          .toList();
  final more =
      pos != null && (down ? pos.extentAfter > 1 : pos.extentBefore > 1);
  if (pos != null &&
      inSame.isEmpty &&
      more &&
      axisDirectionToAxis(scrollable!.axisDirection) == Axis.vertical) {
    final step = pos.viewportDimension * 0.45 * (down ? 1 : -1);
    tvScrollThen(pos, pos.pixels + step, () {
      if (current.hasPrimaryFocus) tvMoveVertically(current, down: down);
    });
    return true;
  }
  if (inSame.isNotEmpty) {
    candidates
      ..clear()
      ..addAll(inSame);
  }
  if (candidates.isEmpty) return false;
  final back = _vFrom;
  if (identical(_vTo, current) &&
      _vDown != down &&
      back != null &&
      candidates.contains(back)) {
    _vFrom = current;
    _vTo = back;
    _vDown = down;
    back.requestFocus();
    return true;
  }
  double gap(FocusNode n) =>
      down ? n.rect.top - cur.bottom : cur.top - n.rect.bottom;
  final nearest = candidates.reduce((a, b) => gap(a) <= gap(b) ? a : b);
  // La riga: se l'elemento più vicino sta in una riga riconosciuta, tutta
  // quella riga; altrimenti gli elementi alla stessa altezza.
  final key = tvRowKeyOf(nearest);
  final row = key != null
      ? candidates.where((n) => identical(tvRowKeyOf(n), key)).toList()
      : candidates
          .where((n) =>
              (n.rect.center.dy - nearest.rect.center.dy).abs() <
              nearest.rect.height / 2)
          .toList();
  // Prima la scheda attiva, poi l'ultimo elemento usato nella riga.
  FocusNode? target = row.where(_isSelected).firstOrNull;
  if (target == null && key != null) {
    final mem = _rowMemory[key];
    if (mem != null && row.contains(mem)) target = mem;
  }
  if (target == null) {
    final cx = cur.center.dx;
    row.sort((a, b) =>
        (a.rect.center.dx - cx).abs().compareTo((b.rect.center.dx - cx).abs()));
    target = row.first;
  }
  _vFrom = current;
  _vTo = target;
  _vDown = down;
  target.requestFocus();
  return true;
}

/// Azione delle frecce per tutta l'app su TV: su/giù geometrico nelle
/// pagine che scorrono, il resto come Flutter.
class TvDirectionalFocusAction extends DirectionalFocusAction {
  TvDirectionalFocusAction();

  @override
  void invoke(DirectionalFocusIntent intent) {
    final p = primaryFocus;
    if (p != null &&
        (intent.direction == TraversalDirection.up ||
            intent.direction == TraversalDirection.down) &&
        p.context != null) {
      // Solo righe sopra/sotto. Nelle pagine che scorrono, se non c'è niente
      // (inizio o fine pagina) il focus resta dov'è, senza salti.
      final moved = tvMoveVertically(p,
          down: intent.direction == TraversalDirection.down);
      if (moved || Scrollable.maybeOf(p.context!) != null) return;
    }
    if (p != null &&
        intent.direction == TraversalDirection.right &&
        p.context != null &&
        Scrollable.maybeOf(p.context!) != null) {
      tvMoveHorizontally(p, left: false);
      return;
    }
    super.invoke(intent);
  }
}

/// Mette il focus sul primo elemento visibile (in alto a sinistra) dentro
/// [scope]. Restituisce false se non ce n'è ancora nessuno (pagina in
/// caricamento).
bool tvFocusFirstIn(FocusScopeNode scope) {
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final screen = Offset.zero & (view.physicalSize / view.devicePixelRatio);
  FocusNode? best;
  FocusNode? bestBar;
  for (final n in scope.traversalDescendants) {
    if (n is FocusScopeNode || !n.canRequestFocus || n.skipTraversal) continue;
    final c = n.context;
    if (c == null || !c.mounted) continue;
    final r = n.rect;
    if (r.isEmpty || !screen.overlaps(r)) continue;
    // I pulsanti della barra in alto (indietro, aggiorna) solo se la pagina
    // non ha altro: si parte dal contenuto.
    final inAppBar = c.findAncestorWidgetOfExactType<AppBar>() != null;
    final b = inAppBar ? bestBar : best;
    // Prima la riga più in alto (con tolleranza), poi più a sinistra.
    if (b == null ||
        r.top < b.rect.top - 60 ||
        ((r.top - b.rect.top).abs() <= 60 && r.left < b.rect.left)) {
      if (inAppBar) {
        bestBar = n;
      } else {
        best = n;
      }
    }
  }
  final target = best ?? bestBar;
  if (target == null) return false;
  target.requestFocus();
  return true;
}

/// Azioni da passare a MaterialApp su TV.
Map<Type, Action<Intent>>? tvActions() => TvMode.isTv
    ? {
        ...WidgetsApp.defaultActions,
        DirectionalFocusIntent: TvDirectionalFocusAction()
      }
    : null;

/// Sinistra/destra geometrico: solo elementi nella stessa riga (che si
/// sovrappongono in verticale); restituisce false se la riga è finita.
bool tvMoveHorizontally(FocusNode current, {required bool left}) {
  final scope = current.nearestScope;
  if (scope == null) return false;
  final cur = current.rect;
  FocusNode? best;
  var bestDist = double.infinity;
  for (final n in scope.traversalDescendants) {
    if (identical(n, current) || n is FocusScopeNode || !n.canRequestFocus)
      continue;
    final c = n.context;
    if (c == null || !c.mounted) continue;
    final r = n.rect;
    if (r.isEmpty) continue;
    final overlap = (r.bottom < cur.bottom ? r.bottom : cur.bottom) -
        (r.top > cur.top ? r.top : cur.top);
    final minH = r.height < cur.height ? r.height : cur.height;
    if (overlap < minH * 0.5) continue;
    final d = left ? cur.left - r.right : r.left - cur.right;
    if (d < -8) continue;
    if (d < bestDist) {
      bestDist = d;
      best = n;
    }
  }
  if (best == null) return false;
  best.requestFocus();
  return true;
}
