/// Where changed game rules come from (FR1): the server's `GET /api/rules`.
library;

import 'package:myloop/shared/services/api_service.dart';

import 'game_rules.dart';

abstract class RulesSource {
  /// The server's rules when they differ from [knownVersion], or null when the app is already
  /// up to date. Throws when the server can't be reached.
  Future<GameRules?> fetchIfChanged(int knownVersion);
}

class ApiRulesSource implements RulesSource {
  final ApiService _api;

  ApiRulesSource(this._api);

  @override
  Future<GameRules?> fetchIfChanged(int knownVersion) async {
    final json = await _api.getRules(knownVersion);
    return json == null ? null : GameRules.fromJson(json);
  }
}
