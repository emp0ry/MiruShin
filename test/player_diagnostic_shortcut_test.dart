import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/core/diagnostics/player_diagnostics.dart';
import 'package:mirushin/features/player/presentation/widgets/player_diagnostics_controls.dart';

List<dynamic> events(PlayerDiagnostics recorder) =>
    jsonDecode(recorder.report())['events'] as List;

int marks(PlayerDiagnostics recorder) => events(
  recorder,
).where((event) => event['type'] == 'user.microPause').length;

Future<void> pumpKeyboard(
  WidgetTester tester,
  PlayerDiagnostics recorder, {
  bool enabled = true,
  bool textInput = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Focus(
          autofocus: !textInput,
          onKeyEvent: (_, event) => handlePlayerDiagnosticKeyEvent(
            event,
            enabled: enabled,
            recorder: recorder,
          ),
          child: textInput
              ? const TextField(autofocus: true)
              : const Text('Video surface'),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  late PlayerDiagnostics recorder;
  setUp(() {
    recorder = PlayerDiagnostics()..setEnabled(true);
  });
  tearDown(() => recorder.setEnabled(false));

  testWidgets('plain D marks once; repeat/up do not control playback', (
    tester,
  ) async {
    await pumpKeyboard(tester, recorder);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
    expect(marks(recorder), 1);
    expect(
      events(recorder).where((event) => event['type'] == 'engine.command'),
      isEmpty,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    expect(marks(recorder), 2);
  });

  testWidgets('disabled preference or recorder leaves D inactive', (
    tester,
  ) async {
    await pumpKeyboard(tester, recorder, enabled: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    expect(marks(recorder), 0);

    recorder.setEnabled(false);
    await pumpKeyboard(tester, recorder);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    expect(marks(recorder), 0);
    expect(recorder.observing, isFalse);
  });

  for (final modifier in [
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.shiftLeft,
  ]) {
    testWidgets('${modifier.keyLabel} + D does not mark', (tester) async {
      await pumpKeyboard(tester, recorder);
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(modifier);
      expect(marks(recorder), 0);
    });
  }

  testWidgets('D does not consume text input or unrelated keys', (
    tester,
  ) async {
    await pumpKeyboard(tester, recorder, textInput: true);
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<EditableText>(),
      isNotNull,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.enterText(find.byType(TextField), 'diagnostic text');
    expect(find.text('diagnostic text'), findsOneWidget);
    expect(marks(recorder), 0);

    await pumpKeyboard(tester, recorder);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    expect(marks(recorder), 0);
  });
}
