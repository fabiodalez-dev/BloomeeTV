import 'dart:async';

import 'package:Bloomee/tv/tv_mode.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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
  });

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
    if (event is KeyRepeatEvent) return KeyEventResult.handled;
    if (event is KeyUpEvent) {
      _holdTimer?.cancel();
      if (!_longFired) widget.onTap?.call();
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
  double gap(FocusNode n) => down ? n.rect.top - cur.bottom : cur.top - n.rect.bottom;
  final nearest = candidates.map(gap).reduce((a, b) => a < b ? a : b);
  // La "riga" più vicina: tutti gli elementi entro metà altezza del primo.
  final row = candidates.where((n) => gap(n) <= nearest + 40).toList();
  final cx = cur.center.dx;
  row.sort((a, b) => (a.rect.center.dx - cx).abs().compareTo((b.rect.center.dx - cx).abs()));
  row.first.requestFocus();
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
        tvMoveVertically(p, down: intent.direction == TraversalDirection.down)) {
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
