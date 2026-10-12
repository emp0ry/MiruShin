import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/addons/application/title_variant_session.dart';
import 'package:mirushin/features/addons/domain/sora_models.dart';

const ru = SoraTitleVariant(languageCode: 'ru', title: 'Госпожа Кагуя');
const en = SoraTitleVariant(languageCode: 'en', title: 'Kaguya-sama');

void main() {
  test(
    'missing RU settles independently rather than waiting for another language',
    () async {
      final batches = StreamController<List<SoraTitleVariant>>();
      final session = TitleVariantSession(batches.stream);
      addTearDown(session.cancel);
      addTearDown(batches.close);
      batches.add([en]);
      final russian = session.forLanguage('ru');
      session.markLanguageSettled('ru');
      expect(await russian, [en]);
    },
  );

  test(
    'query ledger keeps late names eligible and does not repeat old queries',
    () {
      final ledger = TitleQueryLedger();
      expect(ledger.acceptBatch('ru', ['A', 'B', 'C', 'D']), ['A', 'B', 'C']);
      for (final title in ['A', 'B', 'C']) {
        expect(ledger.claim('addon', 'ru', title), isTrue);
      }
      expect(ledger.acceptBatch('ru', ['A', 'B', 'C', 'D', 'Late']), [
        'Late',
        'A',
        'B',
        'C',
      ]);
      expect(ledger.claim('addon', 'ru', 'a'), isFalse);
      expect(ledger.wasAttempted('addon', 'ru', 'Late'), isFalse);
      expect(ledger.wasAttempted('different-addon', 'ru', 'A'), isFalse);
    },
  );
  test(
    'local Russian is immediately ready while English is still pending',
    () async {
      final batches = StreamController<List<SoraTitleVariant>>();
      final session = TitleVariantSession(batches.stream);
      addTearDown(session.cancel);
      addTearDown(batches.close);
      batches.add([ru]);
      expect(await session.forLanguage('ru'), [ru]);
      bool englishReady = false;
      final english = session.forLanguage('en').then((values) {
        englishReady = true;
        return values;
      });
      await Future<void>.delayed(Duration.zero);
      expect(englishReady, isFalse);
      batches.add([en]);
      expect(await english, [ru, en]);
    },
  );

  test(
    'late titles are published without duplicates and without awaiting completion',
    () async {
      final batches = StreamController<List<SoraTitleVariant>>();
      final session = TitleVariantSession(batches.stream);
      final received = <List<SoraTitleVariant>>[];
      final first = Completer<void>();
      final second = Completer<void>();
      final listener = session.watch().listen((batch) {
        received.add(batch);
        if (received.length == 1) first.complete();
        if (received.length == 2) second.complete();
      });
      batches.add([ru]);
      await first.future;
      batches.add([ru, en]);
      await second.future;
      expect(received, [
        [ru],
        [ru, en],
      ]);
      session.cancel();
      await listener.cancel();
      await batches.close();
    },
  );

  test(
    'cancellation releases language waiters and cancels enrichment exactly once',
    () async {
      final batches = StreamController<List<SoraTitleVariant>>();
      int cancellations = 0;
      final session = TitleVariantSession(
        batches.stream,
        onCancel: () {
          cancellations++;
        },
      );
      batches.add([ru]);
      await session.initial;
      final waiting = session.forLanguage('ja');
      session.cancel();
      session.cancel();
      expect(await waiting, [ru]);
      await session.done;
      expect(cancellations, 1);
      await batches.close();
    },
  );
}
