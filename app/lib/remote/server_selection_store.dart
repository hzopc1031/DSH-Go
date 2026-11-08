import 'dart:convert';

import 'package:dsh_remote/dsh_remote.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Remote-only configuration boundary. Does not read credentials or start an
/// account. Legacy Android settings remain owned by RelayServerController.
class RemoteServerSelectionStore {
  RemoteServerSelectionStore(this.preferences);

  static const prefsKey = 'remote_server_selection_v1';
  static const legacyPrefsKey = 'remote_relay_server';
  final SharedPreferences preferences;

  /// The caller supplies installation evidence: a missing legacy server key
  /// alone cannot distinguish a fresh install from a hosted-server upgrade.
  /// Invalid records and failed writes propagate without overwriting old data.
  Future<RemoteServerSelection> load({
    required bool hasLegacySettings,
    String defaultServer = const String.fromEnvironment('DSH_REMOTE_DEFAULT_SERVER_URL'),
  }) async {
    final raw = preferences.getString(prefsKey);
    Map<String, Object?>? saved;
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) throw const FormatException();
        saved = decoded;
      } on FormatException {
        // Rejected persisted input may contain private information.
        throw const FormatException('Invalid saved server selection');
      }
    }
    final selection = RemoteServerSelection.resolve(
      saved: saved,
      hasLegacySettings: hasLegacySettings,
      legacyServer: saved == null ? preferences.getString(legacyPrefsKey) : null,
      defaultServer: defaultServer,
    );
    if (raw == null) await save(selection);
    return selection;
  }

  Future<void> save(RemoteServerSelection selection) async {
    if (!await preferences.setString(prefsKey, jsonEncode(selection.toJson()))) {
      // SharedPreferences updates its cache before the platform write returns.
      // A failed migration must not look persisted on the next load.
      await preferences.reload();
      throw StateError('Server selection was not persisted');
    }
  }
}
