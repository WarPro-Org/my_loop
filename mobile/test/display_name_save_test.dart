/// Regression test for #190 — a rename the API refuses must not look saved.
///
/// The API can reject a name the client cannot pre-check (the moderation blocklist). Rename
/// used to be optimistic and fire-and-forget: the new name was shown immediately while the
/// server kept the old one, and the player was told "Name updated!". updateDisplayName now
/// waits for the API and returns the reason instead.
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myloop/shared/services/api_service.dart';
import 'package:myloop/shared/services/user_state.dart';
import 'package:myloop/shared/util/display_name.dart';

/// ApiService double: only [updateUser] is overridden, so no request is made.
class _FakeApi extends ApiService {
  _FakeApi(this.behaviour);

  final Future<void> Function() behaviour;
  String? sentName;

  @override
  Future<void> updateUser({
    required String userId,
    String? displayName,
    int? avatarId,
    String? color,
  }) {
    sentName = displayName;
    return behaviour();
  }
}

DioException _badRequest(String message) {
  final request = RequestOptions(path: '/api/users/u1');
  return DioException(
    requestOptions: request,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: request, statusCode: 400, data: message),
  );
}

DioException _unreachable() => DioException(
      requestOptions: RequestOptions(path: '/api/users/u1'),
      type: DioExceptionType.unknown,
      error: const SocketException('Connection refused'),
    );

void main() {
  ProviderContainer containerWith(_FakeApi api) {
    final container = ProviderContainer(overrides: [
      apiServiceProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);
    container.read(userProfileProvider.notifier).setFromApi(
          userId: 'u1',
          avatarId: 0,
          color: '#00D4AA',
          displayName: 'Robin',
        );
    return container;
  }

  test('an accepted rename updates the profile with the canonical name', () async {
    final api = _FakeApi(() async {});
    final container = containerWith(api);

    final error = await container.read(userProfileProvider.notifier).updateDisplayName(' O’Brien ');

    expect(error, isNull);
    expect(api.sentName, "O'Brien");
    expect(container.read(userProfileProvider).displayName, "O'Brien");
  });

  test('a rename the API refuses keeps the old name and returns the server reason', () async {
    final container = containerWith(_FakeApi(() async => throw _badRequest("This name isn't allowed")));

    final error = await container.read(userProfileProvider.notifier).updateDisplayName('Blocked');

    expect(error, "This name isn't allowed");
    expect(container.read(userProfileProvider).displayName, 'Robin');
  });

  test('a server error page is never shown as the reason', () async {
    final request = RequestOptions(path: '/api/users/u1');
    final gatewayError = DioException(
      requestOptions: request,
      type: DioExceptionType.badResponse,
      response: Response(requestOptions: request, statusCode: 502, data: '<html>Bad Gateway</html>'),
    );
    final container = containerWith(_FakeApi(() async => throw gatewayError));

    final error = await container.read(userProfileProvider.notifier).updateDisplayName('Kai');

    expect(error, displayNameSaveFailedError);
    expect(container.read(userProfileProvider).displayName, 'Robin');
  });

  test('a rename while offline keeps the old name and says why', () async {
    final container = containerWith(_FakeApi(() async => throw _unreachable()));

    final error = await container.read(userProfileProvider.notifier).updateDisplayName('Kai');

    expect(error, displayNameOfflineError);
    expect(container.read(userProfileProvider).displayName, 'Robin');
  });
}
