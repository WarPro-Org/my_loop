/// Where changed game rules come from (FR1): the server's `GET /api/rules`.
library;

import 'package:myloop/shared/services/api_service.dart';

import 'package:myloop/shared/rules/game_rules.dart';

/// Rules as received from the server, with the fingerprint the server gave them.
class SavedRules {
  final GameRules rules;

  /// Server fingerprint of [rules]; null for the built-in copy (never came from the server).
  final String? tag;

  const SavedRules(this.rules, this.tag);
}

abstract class RulesSource {
  /// The server's rules when they differ from the ones fingerprinted by [knownTag], or null when
  /// the app already has them. Throws when the server can't be reached.
  Future<SavedRules?> fetchIfChanged(String? knownTag);
}

class ApiRulesSource implements RulesSource {
  final ApiService _api;

  ApiRulesSource(this._api);

  @override
  Future<SavedRules?> fetchIfChanged(String? knownTag) async {
    final response = await _api.getRules(knownTag);
    return response == null ? null : SavedRules(GameRules.fromJson(response.json), response.tag);
  }
}
