import 'dart:convert';

import 'package:dsh_app/remote/relay/dsh_remote_backend.dart';
import 'package:dsh_app/remote/secret_store.dart';
import 'package:dsh_app/remote/server_selection_store.dart';
import 'package:dsh_remote/dsh_remote.dart' as remote;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'support/fake_relay.dart';

class _FailedWrites extends InMemorySharedPreferencesStore {
  _FailedWrites() : super.withData({});

  @override
  Future<bool> setValue(String valueType, String key, Object value) async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<RemoteServerSelectionStore> store(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return RemoteServerSelectionStore(await SharedPreferences.getInstance());
  }

  test('fresh install persists unconfigured across a later build default', () async {
    final storage = await store({});
    final first = await storage.load(hasLegacySettings: false, defaultServer: '');
    expect(first.choice, remote.RemoteServerChoice.unconfigured);
    final restored = await storage.load(hasLegacySettings: false, defaultServer: 'new.example');
    expect(restored.toJson(), first.toJson());
  });

  test('missing legacy key on an upgrade stays hosted and cannot construct an account', () async {
    final storage = await store({});
    final selection = await storage.load(hasLegacySettings: true, defaultServer: 'new.example');
    expect(selection.requiresConfirmation, isTrue);
    expect(() => backend(selection, MemorySecretStore()), throwsStateError);
    expect((await storage.load(hasLegacySettings: false)).toJson(), selection.toJson());
  });

  test('legacy origin migrates once and retains legacy and unrelated preferences', () async {
    final storage = await store({
      RemoteServerSelectionStore.legacyPrefsKey: 'HTTPS://A.EXAMPLE:443/',
      'active_host': 'user-owned',
    });
    expect((await storage.load(hasLegacySettings: true)).origin!.origin, 'https://a.example');
    await storage.preferences.setString(RemoteServerSelectionStore.legacyPrefsKey, 'b.example');
    expect((await storage.load(hasLegacySettings: true)).origin!.origin, 'https://a.example');
    expect(storage.preferences.getString('active_host'), 'user-owned');
    expect(storage.preferences.getString(RemoteServerSelectionStore.legacyPrefsKey), 'b.example');
  });

  for (final raw in [
    'not json secret',
    '[]',
    '{"schemaVersion":99}',
    '{"schemaVersion":1,"choice":"selfHosted","origin":"https://user:secret@a.example"}',
  ]) {
    test('invalid persisted choice is retained and never falls back: ${raw.length}', () async {
      final storage = await store({RemoteServerSelectionStore.prefsKey: raw});
      await expectLater(
        storage.load(hasLegacySettings: false, defaultServer: 'ok.example'),
        throwsA(isA<FormatException>().having((e) => e.toString(), 'redacted', isNot(contains('secret')))),
      );
      expect(storage.preferences.getString(RemoteServerSelectionStore.prefsKey), raw);
    });
  }

  test('invalid legacy origin does not write a migration marker', () async {
    final storage = await store({RemoteServerSelectionStore.legacyPrefsKey: 'http://localhost'});
    await expectLater(storage.load(hasLegacySettings: true), throwsFormatException);
    expect(storage.preferences.containsKey(RemoteServerSelectionStore.prefsKey), isFalse);
    expect(storage.preferences.getString(RemoteServerSelectionStore.legacyPrefsKey), 'http://localhost');
  });

  test('versioned choice wins even when the unused legacy preference has the wrong type', () async {
    final storage = await store({
      RemoteServerSelectionStore.prefsKey: jsonEncode(const remote.RemoteServerSelection.unconfigured().toJson()),
      RemoteServerSelectionStore.legacyPrefsKey: 42,
    });
    expect((await storage.load(hasLegacySettings: true)).choice, remote.RemoteServerChoice.unconfigured);
  });

  test('A to B to A persists only configuration, with separate approval caches', () async {
    final storage = await store({});
    final secrets = MemorySecretStore({'unrelated': 'retained'});
    final a = remote.RemoteServerSelection.selfHosted('a.example');
    final b = remote.RemoteServerSelection.selfHosted('b.example:8443');
    final first = backend(a, secrets);
    final second = backend(b, secrets);
    final third = backend(a, secrets);
    addTearDown(first.close);
    addTearDown(second.close);
    addTearDown(third.close);
    first.approveHost(sampleRelayHosts.first);
    expect(first.approves('mac', sampleRelayHosts.first.fingerprint), isTrue);
    expect(second.approves('mac', sampleRelayHosts.first.fingerprint), isFalse);
    expect(third.approves('mac', sampleRelayHosts.first.fingerprint), isFalse);
    for (final selection in [a, b, a]) {
      await storage.save(selection);
      expect((await storage.load(hasLegacySettings: false)).origin, selection.origin);
    }
    expect(jsonDecode(storage.preferences.getString(RemoteServerSelectionStore.prefsKey)!), a.toJson());
    expect(secrets.values, {'unrelated': 'retained'});
    expect(second.account.serverUrl.origin, 'https://b.example:8443');
    expect(first.account.peerConnector, isNull);
    expect(first.account.preferredTransports, isNull);
    expect(first.account.platform, 'dsh-app-test');
  });

  test('unconfigured cannot silently create the public backend', () {
    expect(() => backend(const remote.RemoteServerSelection.unconfigured(), MemorySecretStore()), throwsStateError);
  });

  test('a failed preference write is reported', () async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesStorePlatform.instance = _FailedWrites();
    final storage = RemoteServerSelectionStore(await SharedPreferences.getInstance());
    await expectLater(storage.load(hasLegacySettings: false), throwsStateError);
    expect(storage.preferences.containsKey(RemoteServerSelectionStore.prefsKey), isFalse);
    await expectLater(storage.load(hasLegacySettings: false), throwsStateError);
  });
}

DshRemoteRelayBackend backend(remote.RemoteServerSelection selection, MemorySecretStore secrets) =>
    DshRemoteRelayBackend.fromSelection(
      selection: selection,
      secrets: secrets,
      deviceName: 'test device',
      platform: 'dsh-app-test',
    );
