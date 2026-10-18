import 'dart:async';

import 'package:Bloomee/tv/tv_mode.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  });

  /// Elemento "scelto" della sua riga (es. la scheda attiva): entrando nella
  /// riga dall'alto o dal basso il focus va qui.
  final bool selected;
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

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!kTvSelectKeys.contains(event.logicalKey)) return KeyEventResult.ignored;
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
    return Focus(
      focusNode: widget.focusNode,
      debugLabel: widget.debugLabel,
      autofocus: widget.autofocus,
      canRequestFocus: interactive,
      skipTraversal: !interactive,
      onKeyEvent: _onKey,
      onFocusChange: (f) => setState(() => _focused = f),
      child: AnimatedScale(
        scale: _focused ? widget.scaleOnFocus : 1.0,
        duration: const Duration(milliseconds: 120),
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            border: Border.all(
              color: _focused ? kTvFocusColor : Colors.transparent,
              width: 3,
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
    );
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
  });

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
    if (!TvMode.isTv || (tap == null && long == null)) return detector;
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
class TvRoot extends StatefulWidget {
  const TvRoot({super.key, required this.child});
  final Widget child;

  @override
  State<TvRoot> createState() => _TvRootState();
}

class _TvRootState extends State<TvRoot> {
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

  void _onFocusChanged() {
    final pf = FocusManager.instance.primaryFocus;
    if (pf != null && pf is! FocusScopeNode) tvRememberRowFocus(pf);
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null || !ctx.mounted) return;
    if (Scrollable.maybeOf(ctx) == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.4,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  /// Se nessun elemento ha il focus, la prima freccia lo porta al primo
  /// elemento interattivo della schermata invece di non fare nulla.
  bool _onKey(KeyEvent event) {
    if ((event is! KeyDownEvent && event is! KeyRepeatEvent) ||
        !_arrows.contains(event.logicalKey)) {
      return false;
    }
    final primary = FocusManager.instance.primaryFocus;
    // Focus su un contenitore (non un elemento): la freccia va sul primo
    // elemento interattivo al suo interno.
    if (primary != null && primary is! FocusScopeNode && event is KeyDownEvent) {
      final inner = primary.traversalDescendants.where((n) => n.canRequestFocus && n is! FocusScopeNode).toList();
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
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft && tvFocusMenu != null) {
        tvFocusMenu!();
        return true;
      }
      final scope = primary is FocusScopeNode
          ? primary
          : FocusManager.instance.rootScope;
      return scope.nextFocus();
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
      child: widget.child,
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
  if (s != null && axisDirectionToAxis(s.axisDirection) == Axis.horizontal) return s;
  final h = n.rect.height;
  RenderObject? ro = ctx.findRenderObject()?.parent;
  for (var i = 0; ro != null && i < 14; i++, ro = ro.parent) {
    if (ro is RenderSliver || ro is RenderAbstractViewport) return null;
    if (ro is RenderBox && ro.hasSize && ro.size.height > h * 2.2 + 24) return null;
    if (ro is RenderWrap && ro.direction == Axis.horizontal && ro.childCount > 1) return ro;
    if (ro is RenderFlex && ro.direction == Axis.horizontal && ro.childCount > 1) return ro;
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
bool tvMoveVertically(FocusNode current, {required bool down}) {
  final ctx = current.context;
  if (ctx == null || !ctx.mounted) return false;
  // Solo nelle pagine che scorrono in verticale (menu e dialoghi restano
  // alla gestione normale).
  final scrollable = Scrollable.maybeOf(ctx);
  if (scrollable == null) return false;
  if (ctx.findAncestorStateOfType<EditableTextState>() != null) return false;
  final scope = current.nearestScope;
  if (scope == null) return false;
  final cur = current.rect;
  const slack = 8.0;
  final candidates = <FocusNode>[];
  for (final n in scope.traversalDescendants) {
    if (identical(n, current) || n is FocusScopeNode || !n.canRequestFocus) continue;
    final c = n.context;
    if (c == null || !c.mounted) continue;
    final r = n.rect;
    if (r.isEmpty) continue;
    if (down ? r.top >= cur.bottom - slack : r.bottom <= cur.top + slack) {
      candidates.add(n);
    }
  }
  if (candidates.isEmpty) return false;
  final back = _vFrom;
  if (identical(_vTo, current) && _vDown != down && back != null && candidates.contains(back)) {
    _vFrom = current;
    _vTo = back;
    _vDown = down;
    back.requestFocus();
    return true;
  }
  double gap(FocusNode n) => down ? n.rect.top - cur.bottom : cur.top - n.rect.bottom;
  final nearest = candidates.reduce((a, b) => gap(a) <= gap(b) ? a : b);
  // La riga: se l'elemento più vicino sta in una riga riconosciuta, tutta
  // quella riga; altrimenti gli elementi alla stessa altezza.
  final key = tvRowKeyOf(nearest);
  final row = key != null
      ? candidates.where((n) => identical(tvRowKeyOf(n), key)).toList()
      : candidates.where((n) => (n.rect.center.dy - nearest.rect.center.dy).abs() < nearest.rect.height / 2).toList();
  FocusNode? target;
  if (key != null) {
    final mem = _rowMemory[key];
    if (mem != null && row.contains(mem)) target = mem;
  }
  target ??= row.where(_isSelected).firstOrNull;
  if (target == null) {
    final cx = cur.center.dx;
    row.sort((a, b) => (a.rect.center.dx - cx).abs().compareTo((b.rect.center.dx - cx).abs()));
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
        (intent.direction == TraversalDirection.up || intent.direction == TraversalDirection.down) &&
        p.context != null &&
        Scrollable.maybeOf(p.context!) != null) {
      // Nelle pagine: solo righe sopra/sotto. Se non c'è niente (inizio o
      // fine pagina) il focus resta dov'è, senza salti imprevedibili.
      tvMoveVertically(p, down: intent.direction == TraversalDirection.down);
      return;
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
  for (final n in scope.traversalDescendants) {
    if (n is FocusScopeNode || !n.canRequestFocus || n.skipTraversal) continue;
    final c = n.context;
    if (c == null || !c.mounted) continue;
    final r = n.rect;
    if (r.isEmpty || !screen.overlaps(r)) continue;
    if (best == null) {
      best = n;
      continue;
    }
    final b = best.rect;
    // Prima la riga più in alto (con tolleranza), poi più a sinistra.
    if (r.top < b.top - 60 || ((r.top - b.top).abs() <= 60 && r.left < b.left)) best = n;
  }
  if (best == null) return false;
  best.requestFocus();
  return true;
}

/// Azioni da passare a MaterialApp su TV.
Map<Type, Action<Intent>>? tvActions() => TvMode.isTv
    ? {...WidgetsApp.defaultActions, DirectionalFocusIntent: TvDirectionalFocusAction()}
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
    if (identical(n, current) || n is FocusScopeNode || !n.canRequestFocus) continue;
    final c = n.context;
    if (c == null || !c.mounted) continue;
    final r = n.rect;
    if (r.isEmpty) continue;
    final overlap = (r.bottom < cur.bottom ? r.bottom : cur.bottom) - (r.top > cur.top ? r.top : cur.top);
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
