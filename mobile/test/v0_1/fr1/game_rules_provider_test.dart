/// FR1 — the app always has usable rules: built-in → saved copy → server update.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myloop/shared/rules/game_rules.dart';
import 'package:myloop/shared/rules/game_rules_provider.dart';
import 'package:myloop/shared/rules/rules_source.dart';
import 'package:myloop/shared/rules/rules_store.dart';
import 'package:myloop/shared/services/api_service.dart';

SavedRules _version(int v) =>
    SavedRules(GameRules.fromJson({...defaultGameRules.toJson(), 'version': v}), 'tag-$v');

class _MemoryStore implements RulesStore {
  _MemoryStore([this.saved]);
  SavedRules? saved;
  int saves = 0;
  @override
  Future<SavedRules?> load() async => saved;
  @override
  Future<void> save(SavedRules rules) async {
    saved = rules;
    saves++;
  }
}

class _BrokenStore implements RulesStore {
  int saveAttempts = 0;
  @override
  Future<SavedRules?> load() async => throw Exception('no documents directory');
  @override
  Future<void> save(SavedRules rules) async {
    saveAttempts++;
    throw Exception('no documents directory');
  }
}

class _FakeSource implements RulesSource {
  _FakeSource({this.serverRules, this.offline = false});
  final SavedRules? serverRules;
  final bool offline;
  /// Fingerprint sent with each request, in order.
  final askedWithTags = <String?>[];
  int get fetches => askedWithTags.length;
  @override
  Future<SavedRules?> fetchIfChanged(String? knownTag) async {
    askedWithTags.add(knownTag);
    if (offline) throw DioException(requestOptions: RequestOptions(), message: 'no internet');
    return serverRules == null || serverRules!.tag == knownTag ? null : serverRules;
  }
}

Future<GameRules> _settle(ProviderContainer container) async {
  container.read(gameRulesProvider);
  await container.read(gameRulesProvider.notifier).refresh();
  return container.read(gameRulesProvider);
}

ProviderContainer _container(RulesStore store, RulesSource source) {
  final container = ProviderContainer(overrides: [
    rulesStoreProvider.overrideWithValue(store),
    rulesSourceProvider.overrideWithValue(source),
  ]);
  addTearDown(container.dispose);
  return container;
}

/// The network under a real Dio: every request gets the same status, content type and body, or
/// fails to connect while [offline]. A test may change the reply between requests.
class _FixedReply implements HttpClientAdapter {
  _FixedReply(this.status, this.contentType, this.body);
  int status;
  String contentType;
  String body;
  bool offline = false;
  int requests = 0;

  @override
  Future<ResponseBody> fetch(
      RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests++;
    if (offline) {
      throw DioException(requestOptions: options, type: DioExceptionType.connectionError, message: 'no internet');
    }
    return ResponseBody.fromString(body, status, headers: {
      Headers.contentTypeHeader: [contentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

/// The real ApiService, Dio and parser, answered by [reply].
RulesSource _realSource(_FixedReply reply) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))..httpClientAdapter = reply;
  final api = ApiService(dio: dio);
  // The sign-in interceptor needs Firebase, which tests don't have; left in, it would fail every
  // request before it reaches [reply], and the tests below would pass for that reason instead.
  dio.interceptors.clear();
  return ApiRulesSource(api);
}

/// Doesn't answer its first request until the test calls [firstAnswer] (e.g. the sign-in token step
/// stuck offline); answers later requests with [rules] at once.
class _StuckOnce implements RulesSource {
  _StuckOnce(this.rules);
  final SavedRules rules;
  final firstAnswer = Completer<SavedRules?>();
  int fetches = 0;
  @override
  Future<SavedRules?> fetchIfChanged(String? knownTag) {
    fetches++;
    return fetches == 1 ? firstAnswer.future : Future.value(rules);
  }
}

/// Runs [body] in fake time, with every pending microtask run after each step it takes.
void _inFakeTime(void Function(FakeAsync async) body) => fakeAsync((async) {
      body(async);
      async.flushMicrotasks();
    });

/// The server refuses the app start's request with [status]: the rules and the saved copy are
/// kept, nothing asks again on its own for an hour, and the next trigger (start, resume, login,
/// walk start) asks again and applies new rules.
void _refusedThenAskedAgain(int status) => _inFakeTime((async) {
      final reply = _FixedReply(status, ContentType.text.mimeType, 'refused');
      final store = _MemoryStore(_version(1));
      final container = _container(store, _realSource(reply));
      container.read(gameRulesProvider);
      async.elapse(Duration.zero); // Dio sends on a zero-length timer

      expect(reply.requests, 1, reason: 'the app start asked the server');
      expect(container.read(gameRulesProvider).version, 1);
      expect(store.saved?.rules.version, 1);
      expect(store.saves, 0);

      async.elapse(const Duration(hours: 1));
      expect(reply.requests, 1, reason: 'no retry without a trigger');

      reply
        ..status = HttpStatus.ok
        ..contentType = ContentType.json.mimeType
        ..body = jsonEncode({...defaultGameRules.toJson(), 'version': 2});
      container.read(gameRulesProvider.notifier).refresh();
      async.elapse(Duration.zero);
      expect(reply.requests, 2, reason: 'the next trigger asked again');
      expect(container.read(gameRulesProvider).version, 2);
      expect(store.saved?.rules.version, 2);
    });

void main() {
  test('first launch with no saved copy asks the server without a fingerprint', () async {
    final source = _FakeSource(serverRules: _version(2));
    final container = _container(_MemoryStore(), source);

    expect((await _settle(container)).version, 2);
    expect(source.askedWithTags.first, isNull);
  });

  test('first launch with no internet uses the built-in copy', () async {
    final container = _container(_MemoryStore(), _FakeSource(offline: true));

    expect(container.read(gameRulesProvider).version, defaultGameRules.version);
    expect((await _settle(container)).version, defaultGameRules.version);
  });

  test('offline with a saved copy uses the saved copy', () async {
    final container = _container(_MemoryStore(_version(5)), _FakeSource(offline: true));

    expect((await _settle(container)).version, 5);
  });

  test('changed server rules replace the current ones and are saved', () async {
    final store = _MemoryStore(_version(5));
    final source = _FakeSource(serverRules: _version(6));
    final container = _container(store, source);

    final rules = await _settle(container);

    expect(rules.version, 6);
    expect(store.saved?.rules.version, 6);
    expect(source.askedWithTags.first, 'tag-5');
  });

  test('up-to-date app asks with its saved fingerprint and saves nothing', () async {
    final store = _MemoryStore(_version(5));
    final source = _FakeSource(serverRules: _version(5));
    final container = _container(store, source);

    final rules = await _settle(container);

    expect(rules.version, 5);
    expect(source.askedWithTags.first, 'tag-5');
    expect(store.saves, 0);
  });

  test('broken phone storage still falls back to built-in rules and checks the server', () async {
    final source = _FakeSource(serverRules: _version(3));
    final store = _BrokenStore();
    final container = ProviderContainer(overrides: [
      rulesStoreProvider.overrideWithValue(store),
      rulesSourceProvider.overrideWithValue(source),
    ]);
    addTearDown(container.dispose);

    // _settle awaits refresh(): it must complete normally, with the server's rules applied.
    expect((await _settle(container)).version, 3);
    // Building the provider starts a refresh and _settle asks for another. The second run sees
    // the new fingerprint, gets "not modified" and saves nothing.
    expect(store.saveAttempts, 1);
  });

  test('overlapping refreshes never fetch in parallel or save twice', () async {
    final store = _MemoryStore();
    final source = _GatedSource();
    final container = _container(store, source);

    container.read(gameRulesProvider); // app start starts a refresh
    await pumpEventQueue();
    final second = container.read(gameRulesProvider.notifier).refresh(); // login, mid-request

    source.answerNext(_version(4)); // first request: new rules
    await pumpEventQueue();
    source.answerNext(null); // follow-up request: already up to date
    await second;

    expect(source.maxOpenAtOnce, 1);
    expect(source.fetches, 2);
    expect(store.saves, 1);
    expect(container.read(gameRulesProvider).version, 4);
  });

  test('a refresh asked for as the last request finishes is never lost', () async {
    // Try every moment around the end of the request, one microtask apart.
    for (var hops = 0; hops <= 10; hops++) {
      final source = _GatedSource();
      final container = _container(_MemoryStore(), source);

      container.read(gameRulesProvider);
      await pumpEventQueue();
      source.answerNext(null); // the only request finishes: nothing changed
      for (var i = 0; i < hops; i++) {
        await Future<void>.microtask(() {});
      }
      final late = container.read(gameRulesProvider.notifier).refresh();
      await pumpEventQueue();
      if (source.hasPending) source.answerNext(null);
      await late;

      expect(source.fetches, 2, reason: 'refresh after $hops microtasks was dropped');
    }
  });

  test('a refresh after login is not lost behind a signed-out request that got a 401', () async {
    final source = _ScriptedSource();
    final container = _container(_MemoryStore(), source);

    container.read(gameRulesProvider); // app start: signed out
    await pumpEventQueue();
    final loginRefresh = container.read(gameRulesProvider.notifier).refresh(); // after login

    source.first.completeError(DioException(requestOptions: RequestOptions(), message: '401'));
    await loginRefresh;

    expect(source.fetches, 2);
    expect(container.read(gameRulesProvider).version, 4);
  });

  test('a failure that is not a network error keeps the current rules, and later refreshes still work',
      () async {
    final source = _FailsOnceSource(_TokenExpired());
    final container = _container(_MemoryStore(_version(3)), source);

    container.read(gameRulesProvider); // app start: its refresh is the one that fails
    await pumpEventQueue();
    expect(source.fetches, 1, reason: 'positive control: the failing request ran');
    expect(container.read(gameRulesProvider).version, 3);

    await container.read(gameRulesProvider.notifier).refresh();
    expect(container.read(gameRulesProvider).version, 5, reason: 'the refresh after the failure applied');
  });

  test('a bug in a refresh reaches the error reporter even while a walk start waits on it', () async {
    final reported = <Object>[];
    int? versionAfterBug;
    int? versionAfterNextRefresh;
    await runZonedGuarded(() async {
      final container = _container(_MemoryStore(_version(3)), _FailsOnceSource(StateError('bug')));
      container.read(gameRulesProvider); // the app-start refresh hits the bug
      await container.read(gameRulesProvider.notifier).settled(limit: const Duration(seconds: 1));
      await pumpEventQueue();
      versionAfterBug = container.read(gameRulesProvider).version;
      await container.read(gameRulesProvider.notifier).refresh();
      versionAfterNextRefresh = container.read(gameRulesProvider).version;
    }, (error, _) => reported.add(error));

    expect(reported, [isA<StateError>()]);
    expect(versionAfterBug, 3, reason: 'the rules the app had are kept');
    expect(versionAfterNextRefresh, 5, reason: 'the next refresh still runs');
  });

  test('a server reply the app cannot read keeps the current rules and the saved copy', () async {
    final store = _MemoryStore(_version(3));
    final container = ProviderContainer(overrides: [
      rulesStoreProvider.overrideWithValue(store),
      rulesSourceProvider.overrideWithValue(ApiRulesSource(_UnreadableRulesApi())),
    ]);
    addTearDown(container.dispose);

    final rules = await _settle(container);

    expect(_UnreadableRulesApi.calls, greaterThan(0), reason: 'positive control: the server was asked');
    expect(rules.version, 3);
    expect(store.saved?.tag, 'tag-3');
    expect(store.saves, 0);
  });

  group('a reply that is not rules keeps the current rules and the saved copy', () {
    final newRules = jsonEncode({...defaultGameRules.toJson(), 'version': 2});

    test('positive control: real rules through the same setup are applied', () async {
      final reply = _FixedReply(HttpStatus.ok, ContentType.json.mimeType, newRules);
      final store = _MemoryStore(_version(1));
      final container = _container(store, _realSource(reply));

      expect((await _settle(container)).version, 2);
      expect(reply.requests, isPositive);
    });

    test('a captive portal (Wi-Fi sign-in page sent as HTML)', () async {
      final reply = _FixedReply(HttpStatus.ok, ContentType.html.mimeType, '<html>Sign in to Wi-Fi</html>');
      final store = _MemoryStore(_version(1));
      final container = _container(store, _realSource(reply));

      expect((await _settle(container)).version, 1);
      expect(reply.requests, isPositive, reason: 'the request reached the network');
      expect(store.saved?.rules.version, 1);
      expect(store.saves, 0);
    });

    test('the server is down (503)', () async {
      final reply = _FixedReply(HttpStatus.serviceUnavailable, ContentType.text.mimeType, 'Service Unavailable');
      final store = _MemoryStore(_version(1));
      final container = _container(store, _realSource(reply));

      expect((await _settle(container)).version, 1);
      expect(reply.requests, isPositive, reason: 'the request reached the network');
      expect(store.saved?.rules.version, 1);
      expect(store.saves, 0);
    });
  });

  group('a refused request keeps the rules and the saved copy, never retries on its own, and the next refresh asks again', () {
    test('a 400 (bad request)', () => _refusedThenAskedAgain(HttpStatus.badRequest));
    test('a 403 (forbidden)', () => _refusedThenAskedAgain(HttpStatus.forbidden));
    test('a 404 (not found)', () => _refusedThenAskedAgain(HttpStatus.notFound));
    test('a 429 (too many requests)', () => _refusedThenAskedAgain(HttpStatus.tooManyRequests));
    test('a 500 (server error)', () => _refusedThenAskedAgain(HttpStatus.internalServerError));
    test('a 503 (server down)', () => _refusedThenAskedAgain(HttpStatus.serviceUnavailable));
  });

  test('first launch offline with nothing saved uses the built-in copy, and the next refresh still runs', () async {
    final reply = _FixedReply(HttpStatus.ok, ContentType.json.mimeType,
        jsonEncode({...defaultGameRules.toJson(), 'version': 2}))
      ..offline = true;
    final store = _MemoryStore();
    final container = _container(store, _realSource(reply));

    expect((await _settle(container)).version, defaultGameRules.version);
    expect(store.saves, 0);

    reply.offline = false;
    expect((await _settle(container)).version, 2);
    expect(store.saved?.rules.version, 2);
  });

  test('a request that never answers gives up at the limit, the next refresh is not blocked, and a late answer is dropped', () {
    _inFakeTime((async) {
      final source = _StuckOnce(_version(2));
      final store = _MemoryStore(_version(1));
      final container = _container(store, source);
      var firstDone = false;
      container.read(gameRulesProvider); // the app start's refresh: its request never answers
      container
          .read(gameRulesProvider.notifier)
          .settled(limit: const Duration(hours: 1))
          .then((_) => firstDone = true);

      async.elapse(rulesRequestLimit - const Duration(milliseconds: 1));
      expect(firstDone, isFalse, reason: 'still waiting just before the limit');
      async.elapse(const Duration(milliseconds: 1));
      expect(firstDone, isTrue, reason: 'gave up exactly at the limit');
      expect(container.read(gameRulesProvider).version, 1, reason: 'kept the rules it had');
      expect(source.fetches, 1);

      container.read(gameRulesProvider.notifier).refresh();
      async.flushMicrotasks();
      expect(source.fetches, 2, reason: 'the next refresh ran');
      expect(container.read(gameRulesProvider).version, 2);

      source.firstAnswer.complete(_version(99)); // the timed-out request finally answers
      async.elapse(const Duration(seconds: 1));
      expect(container.read(gameRulesProvider).version, 2, reason: 'a late answer is dropped');
      expect(store.saved?.rules.version, 2);
    });
  });
}

/// A sign-in token that expired while offline fails before any request is sent.
class _TokenExpired implements Exception {}

/// Fails the first request with [failure]; later requests return rules version 5.
class _FailsOnceSource implements RulesSource {
  _FailsOnceSource(this.failure);
  final Object failure;
  int fetches = 0;
  @override
  Future<SavedRules?> fetchIfChanged(String? knownTag) async {
    fetches++;
    if (fetches == 1) throw failure;
    return _version(5);
  }
}

/// A server that answers 200 with a body missing the loop fields.
class _UnreadableRulesApi extends ApiService {
  _UnreadableRulesApi() : super(baseUrl: 'http://localhost');
  static int calls = 0;
  @override
  Future<({Map<String, dynamic> json, String? tag})?> getRules(String? knownTag) async {
    calls++;
    return (json: <String, dynamic>{'version': 9}, tag: '9-broken');
  }
}

/// First call waits on [first] (the signed-out request); later calls return rules version 4.
class _ScriptedSource implements RulesSource {
  final first = Completer<SavedRules?>();
  int fetches = 0;
  @override
  Future<SavedRules?> fetchIfChanged(String? knownTag) {
    fetches++;
    return fetches == 1 ? first.future : Future.value(_version(4));
  }
}

/// Each request waits until the test answers it; records how many were open at the same time.
class _GatedSource implements RulesSource {
  final _pending = <Completer<SavedRules?>>[];
  int fetches = 0;
  int _open = 0;
  int maxOpenAtOnce = 0;

  @override
  Future<SavedRules?> fetchIfChanged(String? knownTag) async {
    fetches++;
    _open++;
    if (_open > maxOpenAtOnce) maxOpenAtOnce = _open;
    final answer = Completer<SavedRules?>();
    _pending.add(answer);
    try {
      return await answer.future;
    } finally {
      _open--;
    }
  }

  bool get hasPending => _pending.isNotEmpty;

  void answerNext(SavedRules? rules) => _pending.removeAt(0).complete(rules);
}
