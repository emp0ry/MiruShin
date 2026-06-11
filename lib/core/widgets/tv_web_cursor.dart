import 'dart:async';

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
class TvWebCursor extends StatelessWidget {
  const TvWebCursor({
    required this.controller,
    required this.child,
    this.enabled = true,
    this.step = 56,
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

  void _run(String body) {
    // Guard so a not-yet-injected page can't throw.
    unawaited(
      controller
          .runJavaScript('window.__tvCursor && window.__tvCursor.$body')
          .catchError((_) {}),
    );
  }

  Future<void> _click() async {
    bool wantsKeyboard = false;
    try {
      final Object result = await controller.runJavaScriptReturningResult(
        'window.__tvCursor ? window.__tvCursor.click() : false',
      );
      wantsKeyboard = result == true || result.toString() == 'true';
    } catch (_) {
      try {
        await controller.runJavaScript(
          'window.__tvCursor && window.__tvCursor.click()',
        );
      } catch (_) {}
    }
    if (!wantsKeyboard) return;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    try {
      await _deviceChannel.invokeMethod<void>('showSoftKeyboard');
    } catch (_) {
      // Non-Android platforms or WebView implementations without the hook.
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final LogicalKeyboardKey key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _run('move(-$step,0)');
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _run('move($step,0)');
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _run('move(0,-$step)');
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _run('move(0,$step)');
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

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return Focus(autofocus: true, onKeyEvent: _onKey, child: child);
  }
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
  function move(dx, dy) {
    ensure();
    var margin = 70;
    if (dx < 0 && x <= margin) window.scrollBy(-40, 0);
    if (dx > 0 && x >= window.innerWidth - margin) window.scrollBy(40, 0);
    if (dy < 0 && y <= margin) window.scrollBy(0, -40);
    if (dy > 0 && y >= window.innerHeight - margin) window.scrollBy(0, 40);
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
  window.__tvCursor = { move: move, click: click, ensure: ensure };
  ensure();
})();
''';
