import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Adds an Android-TV-style "dot" cursor to a [WebViewWidget] so it can be
/// driven with the D-pad (for pages that expect a mouse, e.g. the AniList
/// login or an embedded player).
///
/// Platform views don't reliably receive hardware keys through Flutter, so we
/// capture the D-pad on the Flutter side and forward it to an injected
/// JavaScript cursor: arrows move the dot (auto-scrolling at the edges) and the
/// select/centre key synthesises a real click at the dot's position.
///
/// Call [inject] from the WebView's `onPageFinished`, and wrap the
/// [WebViewWidget] in a [TvWebCursor] (only when running on a TV).
class TvWebCursor extends StatefulWidget {
  const TvWebCursor({
    required this.controller,
    required this.child,
    this.enabled = true,
    this.step = 16,
    super.key,
  });

  final WebViewController controller;
  final Widget child;
  final bool enabled;
  final int step;

  static const MethodChannel _deviceChannel = MethodChannel('mirushin/device');

  /// Injects (idempotently) the cursor into the currently loaded page.
  static Future<void> inject(WebViewController controller) async {
    try {
      await controller.runJavaScript(_cursorScript);
    } catch (_) {
      // Some pages block script injection mid-navigation; harmless to skip.
    }
  }

  @override
  State<TvWebCursor> createState() => _TvWebCursorState();
}

class _TvWebCursorState extends State<TvWebCursor> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'TvWebCursor');
  bool _textInputMode = false;
  bool _channelRegistered = false;

  // Coalesced cursor movement: at most one runJavaScript call is in flight and
  // key repeats accumulate into it, so the platform channel never builds a
  // backlog (the old fire-per-event approach made the dot lag further and
  // further behind while a D-pad direction was held).
  int _pendingDx = 0;
  int _pendingDy = 0;
  bool _moveInFlight = false;
  int _repeatStreak = 0;

  // Pending verification that an 'idle' message really means typing is over.
  Timer? _idleRestoreTimer;

  @override
  void initState() {
    super.initState();
    _registerChannel();
  }

  @override
  void didUpdateWidget(covariant TvWebCursor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _channelRegistered = false;
      _registerChannel();
    }
  }

  @override
  void dispose() {
    _idleRestoreTimer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _registerChannel() {
    if (_channelRegistered) return;
    _channelRegistered = true;
    try {
      widget.controller.addJavaScriptChannel(
        'MiruShinTvCursor',
        onMessageReceived: (JavaScriptMessage message) {
          if (!mounted) return;
          switch (message.message) {
            case 'editing':
              _idleRestoreTimer?.cancel();
              _enterTextInputMode();
              break;
            case 'idle':
              _scheduleIdleRestore();
              break;
          }
        },
      );
    } catch (_) {
      // The channel may already exist on reused controllers.
    }
  }

  /// 'idle' can be a transient blur (the page re-rendering its form while the
  /// keyboard opens). Restoring immediately stole native focus back from the
  /// WebView and closed the keyboard, so verify the input really lost focus
  /// before bringing the cursor back.
  void _scheduleIdleRestore() {
    if (!_textInputMode) return;
    _idleRestoreTimer?.cancel();
    _idleRestoreTimer = Timer(const Duration(milliseconds: 200), () async {
      if (!mounted || !_textInputMode) return;
      if (await _hasEditableFocus()) return;
      if (!mounted || !_textInputMode) return;
      _restoreCursorMode();
    });
  }

  void _run(String body) {
    // Guard so a not-yet-injected page can't throw.
    unawaited(
      widget.controller
          .runJavaScript('window.__tvCursor && window.__tvCursor.$body')
          .catchError((_) {}),
    );
  }

  void _queueMove(int dx, int dy, {required bool isRepeat}) {
    // Gentle acceleration: single presses stay precise, holding a direction
    // ramps the step up so crossing the page doesn't take forever.
    _repeatStreak = isRepeat ? _repeatStreak + 1 : 0;
    final double boost = (1 + _repeatStreak * 0.25).clamp(1.0, 3.0);
    _pendingDx += (dx * boost).round();
    _pendingDy += (dy * boost).round();
    _flushMove();
  }

  void _flushMove() {
    if (_moveInFlight || (_pendingDx == 0 && _pendingDy == 0)) return;
    final int dx = _pendingDx;
    final int dy = _pendingDy;
    _pendingDx = 0;
    _pendingDy = 0;
    _moveInFlight = true;
    widget.controller
        .runJavaScript('window.__tvCursor && window.__tvCursor.move($dx,$dy)')
        .catchError((_) {})
        .whenComplete(() {
          _moveInFlight = false;
          if (mounted) _flushMove();
        });
  }

  Future<void> _click() async {
    final _TapInfo tap = await _tapInfo();

    // For an editable target, hand the keys over to the IME *before* the tap:
    // the real tap focuses the input inside the WebView and raises the
    // keyboard, and nothing on the Flutter side must fight it for focus while
    // that happens.
    if (tap.valid && tap.editable) {
      _enterTextInputMode();
    }

    bool nativeTapped = false;
    if (tap.valid) {
      try {
        nativeTapped =
            await TvWebCursor._deviceChannel.invokeMethod<bool>(
              'tapFocusedWebView',
              <String, Object?>{'x': tap.x * tap.dpr, 'y': tap.y * tap.dpr},
            ) ??
            false;
      } catch (_) {
        nativeTapped = false;
      }
    }

    // Only synthesise a JS click when the real tap could not be delivered.
    // Re-clicking after a successful native tap re-fired focus/blur on the
    // page and was what made the keyboard pop up and immediately close (or
    // stay open with the focus knocked out of the text box).
    bool wantsKeyboard = tap.valid && tap.editable;
    if (!nativeTapped) {
      wantsKeyboard = await _fallbackJsClick() || wantsKeyboard;
    }

    if (!wantsKeyboard) {
      if (_textInputMode) _restoreCursorMode();
      return;
    }
    if (!_textInputMode) _enterTextInputMode();
    // Safety net: a real tap on an editable normally raises the IME by
    // itself. Give it a moment, then ask explicitly (no-op if already shown).
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted || !_textInputMode) return;
    if (!await _hasEditableFocus()) {
      // The tap didn't actually land in a text box — give the D-pad back to
      // the cursor instead of stranding it in typing mode.
      _leaveTextInputMode();
      return;
    }
    try {
      await TvWebCursor._deviceChannel.invokeMethod<void>('showSoftKeyboard');
    } catch (_) {
      // Non-Android platforms or WebView implementations without the hook.
    }
  }

  Future<bool> _hasEditableFocus() async {
    try {
      final Object result = await widget.controller
          .runJavaScriptReturningResult(
            'window.__tvCursor ? window.__tvCursor.hasEditableFocus() : false',
          );
      return result == true || result.toString() == 'true';
    } catch (_) {
      // Can't tell — assume the editable focus is fine and keep typing mode.
      return true;
    }
  }

  Future<_TapInfo> _tapInfo() async {
    try {
      final Object
      result = await widget.controller.runJavaScriptReturningResult(
        'window.__tvCursor ? JSON.stringify(window.__tvCursor.tapInfo()) : "{}"',
      );
      Object? decoded = result;
      if (decoded is String) {
        decoded = jsonDecode(decoded);
        if (decoded is String) decoded = jsonDecode(decoded);
      }
      if (decoded is! Map) return const _TapInfo.invalid();
      final Object? x = decoded['x'];
      final Object? y = decoded['y'];
      final Object? dpr = decoded['dpr'];
      return _TapInfo(
        x: (x as num?)?.toDouble() ?? 0,
        y: (y as num?)?.toDouble() ?? 0,
        dpr: (dpr as num?)?.toDouble() ?? 1,
        editable: decoded['editable'] == true,
      );
    } catch (_) {
      return const _TapInfo.invalid();
    }
  }

  Future<bool> _fallbackJsClick() async {
    try {
      final Object result = await widget.controller
          .runJavaScriptReturningResult(
            'window.__tvCursor ? window.__tvCursor.click() : false',
          );
      return result == true || result.toString() == 'true';
    } catch (_) {
      try {
        await widget.controller.runJavaScript(
          'window.__tvCursor && window.__tvCursor.click()',
        );
      } catch (_) {}
    }
    return false;
  }

  void _enterTextInputMode() {
    if (!_textInputMode && mounted) {
      setState(() => _textInputMode = true);
    }
    _run('setEditing(true)');
    _focusNode.unfocus();
  }

  void _restoreCursorMode() {
    if (!_textInputMode) return;
    setState(() => _textInputMode = false);
    _run('setEditing(false)');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.enabled) _focusNode.requestFocus();
    });
  }

  void _leaveTextInputMode() {
    if (!_textInputMode) return;
    _restoreCursorMode();
    _run('blurActive()');
    unawaited(
      TvWebCursor._deviceChannel
          .invokeMethod<void>('hideSoftKeyboard')
          .catchError((_) {}),
    );
  }

  KeyEventResult _handleTextInputMode(LogicalKeyboardKey key, KeyEvent event) {
    if (_exitTextInputKeys.contains(key) && event is KeyDownEvent) {
      _leaveTextInputMode();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final LogicalKeyboardKey key = event.logicalKey;
    if (_textInputMode) {
      return _handleTextInputMode(key, event);
    }
    final bool isRepeat = event is KeyRepeatEvent;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _queueMove(-widget.step, 0, isRepeat: isRepeat);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _queueMove(widget.step, 0, isRepeat: isRepeat);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _queueMove(0, -widget.step, isRepeat: isRepeat);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _queueMove(0, widget.step, isRepeat: isRepeat);
    } else if (_activateKeys.contains(key)) {
      if (!isRepeat) unawaited(_click());
    } else {
      // Let BACK and everything else bubble up (so the page can be closed).
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  static final Set<LogicalKeyboardKey> _activateKeys = <LogicalKeyboardKey>{
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.space,
    LogicalKeyboardKey.gameButtonA,
  };

  static final Set<LogicalKeyboardKey> _exitTextInputKeys =
      <LogicalKeyboardKey>{
        LogicalKeyboardKey.escape,
        LogicalKeyboardKey.goBack,
        LogicalKeyboardKey.browserBack,
      };

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    // While typing, BACK must end typing mode (bring the cursor back) instead
    // of popping the page. With the keyboard up the IME consumes BACK itself,
    // so this fires on the press after the keyboard has closed.
    return PopScope<Object?>(
      canPop: !_textInputMode,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) _leaveTextInputMode();
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: !_textInputMode,
        onKeyEvent: _onKey,
        child: widget.child,
      ),
    );
  }
}

class _TapInfo {
  const _TapInfo({
    required this.x,
    required this.y,
    required this.dpr,
    required this.editable,
  }) : valid = true;

  const _TapInfo.invalid()
    : x = 0,
      y = 0,
      dpr = 1,
      editable = false,
      valid = false;

  final double x;
  final double y;
  final double dpr;
  final bool editable;
  final bool valid;
}

const String _cursorScript = r'''
(function () {
  if (window.__tvCursor) { window.__tvCursor.ensure(); return; }
  var x = window.innerWidth / 2, y = window.innerHeight / 2;
  var dot = document.createElement('div');
  dot.setAttribute('data-tv-cursor', '1');
  // Positioned exclusively via transform: compositor-only updates, no layout
  // work per move, so the dot keeps up with held D-pad repeats.
  dot.style.cssText =
    'position:fixed;left:0;top:0;width:20px;height:20px;border-radius:50%;' +
    'background:rgba(139,92,246,0.85);border:2px solid #ffffff;' +
    'box-shadow:0 0 10px rgba(0,0,0,0.6);z-index:2147483647;' +
    'pointer-events:none;will-change:transform;';
  function ensure() {
    if (!dot.parentNode && document.body) {
      document.body.appendChild(dot);
      place();
    }
  }
  function place() {
    dot.style.transform =
      'translate3d(' + (x - 12) + 'px,' + (y - 12) + 'px,0)';
  }
  function setEditing(editing) {
    ensure();
    // Hide the dot entirely while typing so it never sits over the text box.
    dot.style.opacity = editing ? '0' : '1';
  }
  function move(dx, dy) {
    ensure();
    var margin = 70;
    var hScroll = Math.max(24, Math.abs(dx) * 2);
    var vScroll = Math.max(24, Math.abs(dy) * 2);
    if (dx < 0 && x <= margin) window.scrollBy(-hScroll, 0);
    if (dx > 0 && x >= window.innerWidth - margin) window.scrollBy(hScroll, 0);
    if (dy < 0 && y <= margin) window.scrollBy(0, -vScroll);
    if (dy > 0 && y >= window.innerHeight - margin) window.scrollBy(0, vScroll);
    x = Math.max(6, Math.min(window.innerWidth - 6, x + dx));
    y = Math.max(6, Math.min(window.innerHeight - 6, y + dy));
    place();
  }
  function firePointer(el, type, buttons) {
    if (!window.PointerEvent) return true;
    var ev = new PointerEvent(type, {
      bubbles: true, cancelable: true, view: window, clientX: x, clientY: y,
      pointerId: 1, pointerType: 'mouse', isPrimary: true,
      button: 0, buttons: buttons || 0
    });
    return el.dispatchEvent(ev);
  }
  function fire(el, type, buttons) {
    var ev = new MouseEvent(type, {
      bubbles: true, cancelable: true, view: window, clientX: x, clientY: y,
      button: 0, buttons: buttons || 0
    });
    return el.dispatchEvent(ev);
  }
  function editableTarget(el) {
    for (var node = el; node && node !== document.documentElement; node = node.parentElement) {
      var name = (node.tagName || '').toLowerCase();
      if (name === 'textarea') return node;
      if (name === 'input') {
        var type = (node.type || 'text').toLowerCase();
        if (['button', 'checkbox', 'color', 'file', 'hidden', 'image', 'radio', 'range', 'reset', 'submit'].indexOf(type) === -1) {
          return node;
        }
      }
      if (node.isContentEditable) return node;
    }
    return null;
  }
  function notify(state) {
    try {
      if (window.MiruShinTvCursor && window.MiruShinTvCursor.postMessage) {
        window.MiruShinTvCursor.postMessage(state);
      }
    } catch (e) {}
  }
  function activeEditable() {
    return editableTarget(document.activeElement);
  }
  function installKeyboardWatcher() {
    var vv = window.visualViewport;
    if (!vv || window.__tvCursorKbWatchInstalled) return;
    window.__tvCursorKbWatchInstalled = true;
    var maxH = vv.height;
    vv.addEventListener('resize', function () {
      if (vv.height > maxH) maxH = vv.height;
      // Viewport back to full height while an input is still focused: the
      // soft keyboard was dismissed (IME Done/Back) without blurring the
      // input. End editing so the host brings the cursor back.
      if (vv.height >= maxH - 24) {
        var editable = activeEditable();
        if (editable) {
          try { editable.blur(); } catch (e) {}
          setEditing(false);
          notify('idle');
        }
      }
    });
  }
  function installEditListeners() {
    if (window.__tvCursorEditListenersInstalled) return;
    window.__tvCursorEditListenersInstalled = true;
    document.addEventListener('focusin', function (event) {
      if (editableTarget(event.target)) {
        setEditing(true);
        notify('editing');
      }
    }, true);
    document.addEventListener('focusout', function (event) {
      if (editableTarget(event.target)) {
        // Generous debounce: while the soft keyboard is coming up the input
        // can transiently lose focus; reporting 'idle' for that instant made
        // the Flutter side yank focus back and close the keyboard.
        setTimeout(function () {
          if (!activeEditable()) {
            setEditing(false);
            notify('idle');
          }
        }, 250);
      }
    }, true);
    // Escape ends editing explicitly. Enter is deliberately left to the page:
    // on login forms the keyboard's Next/Done action arrives as Enter, and
    // blurring on it kept closing the keyboard between fields.
    document.addEventListener('keydown', function (event) {
      var editable = activeEditable();
      if (!editable) return;
      if (event.key === 'Escape') {
        setTimeout(function () {
          try { editable.blur(); } catch (e) {}
          setEditing(false);
          notify('idle');
        }, 120);
      }
    }, true);
  }
  function tapInfo() {
    ensure();
    var el = document.elementFromPoint(x, y);
    return {
      x: x,
      y: y,
      dpr: window.devicePixelRatio || 1,
      editable: !!editableTarget(el)
    };
  }
  function blurActive() {
    try {
      var active = document.activeElement;
      if (active && active.blur) active.blur();
    } catch (e) {}
  }
  function click() {
    ensure();
    var el = document.elementFromPoint(x, y);
    if (!el) return false;
    var editable = editableTarget(el);
    var target = editable || el;
    firePointer(target, 'pointerover', 0);
    fire(target, 'mouseover', 0);
    firePointer(target, 'pointerdown', 1);
    fire(target, 'mousedown', 1);
    try { if (target.focus) target.focus({ preventScroll: true }); } catch (e) {
      try { if (target.focus) target.focus(); } catch (_) {}
    }
    firePointer(target, 'pointerup', 0);
    fire(target, 'mouseup', 0);
    fire(target, 'click', 0);
    if (editable) {
      setTimeout(function () {
        try { editable.focus(); } catch (e) {}
      }, 0);
      return true;
    }
    return false;
  }
  window.__tvCursor = {
    move: move,
    click: click,
    ensure: ensure,
    tapInfo: tapInfo,
    blurActive: blurActive,
    setEditing: setEditing,
    hasEditableFocus: function () { return !!activeEditable(); }
  };
  installEditListeners();
  installKeyboardWatcher();
  ensure();
})();
''';
