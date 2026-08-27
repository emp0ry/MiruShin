import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/addons/domain/sora_models.dart';
import 'package:mirushin/features/watch/application/watch_session.dart';

void main() {
  test('stale auto-next stream keys cannot consume current request state', () {
    final AutoNextStreamResolutionState state = AutoNextStreamResolutionState();

    state.begin('episode-1', autoNext: true);
    state.begin('episode-2', autoNext: false);

    expect(state.isCurrent('episode-1'), isFalse);
    expect(state.takeAutoNext('episode-1'), isTrue);
    expect(state.isCurrent('episode-2'), isTrue);
    expect(state.takeAutoNext('episode-2'), isFalse);
    expect(state.activeKey, isNull);
  });

  test('current auto-next request is consumed exactly once', () {
    final AutoNextStreamResolutionState state = AutoNextStreamResolutionState();

    state.begin('episode-3', autoNext: true);

    expect(state.isCurrent('episode-3'), isTrue);
    expect(state.takeAutoNext('episode-3'), isTrue);
    expect(state.takeAutoNext('episode-3'), isFalse);
    expect(state.activeKey, isNull);
  });

  test('stream claim retains transition and bounded retry attempt', () {
    final AutoNextStreamResolutionState state = AutoNextStreamResolutionState();

    state.begin(
      'episode-4',
      autoNext: true,
      transitionId: 17,
      resolutionAttempt: 2,
    );
    final AutoNextStreamResolutionClaim? claim = state.take('episode-4');

    expect(claim?.isAutoNext, isTrue);
    expect(claim?.transitionId, 17);
    expect(claim?.resolutionAttempt, 2);
    expect(state.take('episode-4'), isNull);
  });

  test('duplicate active completion creates one transition', () {
    final EpisodeAdvanceCoordinator coordinator = EpisodeAdvanceCoordinator();

    final EpisodeAdvanceOperation? first = coordinator.begin(
      currentKey: 'addon|media|s1e1',
      reason: 'completion',
    );
    final EpisodeAdvanceOperation? duplicate = coordinator.begin(
      currentKey: 'addon|media|s1e1',
      reason: 'position-tick',
    );

    expect(first, isNotNull);
    expect(duplicate, isNull);
    expect(coordinator.active?.id, first?.id);
  });

  test('failed transition clears dedupe and permits immediate retry', () {
    final EpisodeAdvanceCoordinator coordinator = EpisodeAdvanceCoordinator();
    final EpisodeAdvanceOperation first = coordinator.begin(
      currentKey: 'addon|media|s1e1',
      reason: 'completion',
    )!;

    expect(coordinator.fail(first.id), isTrue);
    final EpisodeAdvanceOperation? retry = coordinator.begin(
      currentKey: 'addon|media|s1e1',
      reason: 'retry',
    );

    expect(retry, isNotNull);
    expect(retry?.id, isNot(first.id));
  });

  test('failed stream resolution claim permits a new transition', () {
    final EpisodeAdvanceCoordinator coordinator = EpisodeAdvanceCoordinator();
    final AutoNextStreamResolutionState streams =
        AutoNextStreamResolutionState();
    final EpisodeAdvanceOperation first = coordinator.begin(
      currentKey: 'addon|media|s1e1',
      reason: 'completion',
    )!;
    streams.begin(
      'episode-2',
      autoNext: true,
      transitionId: first.id,
      resolutionAttempt: 3,
    );

    final AutoNextStreamResolutionClaim claim = streams.take('episode-2')!;
    expect(claim.resolutionAttempt, 3);
    expect(coordinator.fail(claim.transitionId!), isTrue);
    expect(
      coordinator.begin(
        currentKey: 'addon|media|s1e1',
        reason: 'retry-stream-resolution',
      ),
      isNotNull,
    );
  });

  test('committed transition blocks a stale duplicate for old episode', () {
    final EpisodeAdvanceCoordinator coordinator = EpisodeAdvanceCoordinator();
    final EpisodeAdvanceOperation first = coordinator.begin(
      currentKey: 'addon|media|s1e1',
      reason: 'completion',
    )!;

    expect(coordinator.complete(first.id), isTrue);
    expect(
      coordinator.begin(
        currentKey: 'addon|media|s1e1',
        reason: 'stale-completion',
      ),
      isNull,
    );
    expect(
      coordinator.begin(currentKey: 'addon|media|s1e2', reason: 'completion'),
      isNotNull,
    );
  });

  test('next lookup normalizes href and ignores same-number aliases', () {
    final SoraNextEpisodeLookup lookup = findNextSoraEpisode(
      episodes: <SoraEpisode>[
        _episode(3, '/show/3'),
        _episode(1, 'HTTPS://Provider.Test/show/1/?token=new'),
        _episode(2, '/show/2?server=alias-a'),
        _episode(2, '/show/2?server=alias-b'),
      ],
      currentHref: 'https://provider.test/show/1?token=expired',
      currentSeason: 1,
      currentNumber: 1,
    );

    expect(lookup.episode?.number, 2);
    expect(lookup.reason, 'logical-successor');
  });

  test('next lookup crosses seasons in a reordered provider list', () {
    final SoraNextEpisodeLookup lookup = findNextSoraEpisode(
      episodes: <SoraEpisode>[
        _episode(2, '/s2/e2', season: 2),
        _episode(1, '/s2/e1', season: 2),
        _episode(12, '/s1/e12', season: 1),
        _episode(11, '/s1/e11', season: 1),
      ],
      currentHref: '/s1/e12',
      currentSeason: 1,
      currentNumber: 12,
    );

    expect(lookup.episode?.season, 2);
    expect(lookup.episode?.number, 1);
  });

  test('no-next result is explicit', () {
    final SoraNextEpisodeLookup lookup = findNextSoraEpisode(
      episodes: <SoraEpisode>[_episode(12, '/s1/e12', season: 1)],
      currentHref: '/s1/e12',
      currentSeason: 1,
      currentNumber: 12,
    );

    expect(lookup.episode, isNull);
    expect(lookup.reason, 'final-episode');
  });

  test('resolved stream episode must exactly match the requested episode', () {
    final SoraEpisode requested = _episode(2, '/show/2', season: 1);

    expect(
      sameSoraPlaybackEpisode(requested, _episode(2, '/show/2', season: 1)),
      isTrue,
    );
    expect(
      sameSoraPlaybackEpisode(requested, _episode(1, '/show/1', season: 1)),
      isFalse,
    );
    expect(
      sameSoraPlaybackEpisode(requested, _episode(2, '/show/2', season: 2)),
      isFalse,
    );
  });
}

SoraEpisode _episode(double number, String href, {int season = 0}) {
  return SoraEpisode(
    number: number,
    href: href,
    title: 'Episode $number',
    image: '',
    description: '',
    duration: '',
    raw: season > 0 ? <String, dynamic>{'season': season} : const {},
  );
}
