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
    this.step = 30,
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
  bool _textInputMode = false;

  void _run(String body) {
    // Guard so a not-yet-injected page can't throw.
    unawaited(
      widget.controller
          .runJavaScript('window.__tvCursor && window.__tvCursor.$body')
          .catchError((_) {}),
    );
  }

  Future<void> _click() async {
    final _TapInfo tap = await _tapInfo();
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

    bool wantsKeyboard = tap.editable;
    if (!nativeTapped) {
      wantsKeyboard = await _fallbackJsClick() || wantsKeyboard;
    }
    if (!wantsKeyboard) return;
    if (mounted) {
      setState(() => _textInputMode = true);
    }
    _run('setEditing(true)');
    await Future<void>.delayed(const Duration(milliseconds: 80));
    try {
      await TvWebCursor._deviceChannel.invokeMethod<void>('showSoftKeyboard');
    } catch (_) {
      // Non-Android platforms or WebView implementations without the hook.
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

  void _leaveTextInputMode() {
    if (!_textInputMode) return;
    setState(() => _textInputMode = false);
    _run('blurActive();setEditing(false)');
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
    if (key == LogicalKeyboardKey.arrowLeft) {
      _run('move(-${widget.step},0)');
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _run('move(${widget.step},0)');
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _run('move(0,-${widget.step})');
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _run('move(0,${widget.step})');
    } else if (_activateKeys.contains(key)) {
      unawaited(_click());
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
    return Focus(
      autofocus: !_textInputMode,
      onKeyEvent: _onKey,
      child: widget.child,
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
  dot.style.cssText =
    'position:fixed;width:20px;height:20px;border-radius:50%;' +
    'background:rgba(139,92,246,0.85);border:2px solid #ffffff;' +
    'box-shadow:0 0 10px rgba(0,0,0,0.6);z-index:2147483647;' +
    'pointer-events:none;transform:translate3d(-50%,-50%,0);' +
    'will-change:left,top;';
  function ensure() {
    if (!dot.parentNode && document.body) {
      document.body.appendChild(dot);
      place();
    }
  }
  function place() { dot.style.left = x + 'px'; dot.style.top = y + 'px'; }
  function setEditing(editing) {
    ensure();
    dot.style.display = editing ? 'none' : 'block';
  }
  function move(dx, dy) {
    ensure();
    var margin = 70;
    if (dx < 0 && x <= margin) window.scrollBy(-28, 0);
    if (dx > 0 && x >= window.innerWidth - margin) window.scrollBy(28, 0);
    if (dy < 0 && y <= margin) window.scrollBy(0, -28);
    if (dy > 0 && y >= window.innerHeight - margin) window.scrollBy(0, 28);
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
    setEditing: setEditing
  };
  ensure();
})();
''';
