import 'package:dsh_remote/dsh_remote.dart';
import 'package:test/test.dart';

void main() {
  test('fresh installation without build default stays unconfigured', () {
    final selection = RemoteServerSelection.resolve(defaultServer: '');
    expect(selection.choice, RemoteServerChoice.unconfigured);
    expect(selection.origin, isNull);
  });

  test('build default is normalized with equivalent origins sharing scope', () {
    final selection = RemoteServerSelection.buildDefault(' HTTPS://REMOTE.EXAMPLE.COM:443/ ');
    expect(selection.origin!.origin, 'https://remote.example.com');
    expect(RemoteServerSelection.selfHosted('remote.example.com').origin, selection.origin);
    expect(RemoteServerSelection.selfHosted('remote.example.com:8443').origin!.port, 8443);
  });

  test('saved explicit address wins over changed defaults and legacy settings', () {
    final selection = RemoteServerSelection.resolve(
      saved: RemoteServerSelection.selfHosted('a.example.com').toJson(),
      hasLegacySettings: true,
      legacyServer: 'b.example.com',
      defaultServer: 'c.example.com',
    );
    expect(selection.origin!.host, 'a.example.com');
  });

  test('saved unconfigured choice wins over build default', () {
    final selection = RemoteServerSelection.resolve(
      saved: const RemoteServerSelection.unconfigured().toJson(),
      defaultServer: 'remote.example.com',
    );
    expect(selection.origin, isNull);
    expect(selection.choice, RemoteServerChoice.unconfigured);
  });

  test('legacy explicit server is normalized and migration is idempotent', () {
    final selection = RemoteServerSelection.resolve(legacyServer: 'REMOTE.example.com:8443/');
    final restored = RemoteServerSelection.resolve(saved: selection.toJson(), defaultServer: 'other.example.com');
    expect(restored.toJson(), selection.toJson());
    expect(restored.origin!.origin, 'https://remote.example.com:8443');
  });

  for (final legacy in [null, '']) {
    test('legacy public default ($legacy) requires confirmation without a connectable origin', () {
      final selection = RemoteServerSelection.resolve(
        hasLegacySettings: true,
        legacyServer: legacy,
        defaultServer: 'new.example.com',
      );
      expect(selection.choice, RemoteServerChoice.hosted);
      expect(selection.requiresConfirmation, isTrue);
      expect(selection.origin, isNull);
      expect(RemoteServerSelection.fromJson(selection.toJson()).toJson(), selection.toJson());
    });
  }

  test('explicit public address remains explicit and does not change authentication type', () {
    final selection = RemoteServerSelection.resolve(legacyServer: defaultRemoteServer.origin);
    expect(selection.choice, RemoteServerChoice.selfHosted);
    expect(selection.origin, defaultRemoteServer);
  });

  test('invalid legacy or saved input never falls back to a default', () {
    for (final address in [' ', 'https://host.example/path', 'https://user:password@host.example']) {
      expect(
        () => RemoteServerSelection.resolve(legacyServer: address, defaultServer: 'ok.example'),
        throwsFormatException,
      );
      expect(
        () => RemoteServerSelection.fromJson({'schemaVersion': 1, 'choice': 'selfHosted', 'origin': address}),
        throwsFormatException,
      );
    }
  });

  test('remote-only selection rejects HTTP including private hosts and malformed origins', () {
    for (final address in [
      'http://localhost',
      'http://192.168.1.1',
      'https://',
      'https://example.com//',
      'https://example.com?q=1',
      'https://example.com#fragment',
      'wss://example.com',
    ]) {
      expect(() => RemoteServerSelection.selfHosted(address), throwsFormatException);
    }
    // Existing Android/LAN callers keep the shared normalizer's HTTP contract.
    expect(normalizeServerUrl('http://localhost').scheme, 'http');
  });

  test('unknown or inconsistent records fail closed', () {
    for (final json in <Map<String, Object?>>[
      {},
      {'schemaVersion': 2, 'choice': 'unconfigured'},
      {'schemaVersion': 1, 'choice': 'unknown'},
      {'schemaVersion': 1, 'choice': 'selfHosted'},
      {'schemaVersion': 1, 'choice': 'hosted', 'origin': 'https://example.com'},
      {'schemaVersion': 1, 'choice': 'unconfigured', 'origin': 'https://example.com'},
    ]) {
      expect(() => RemoteServerSelection.fromJson(json), throwsFormatException);
    }
  });

  test('invalid address exceptions do not disclose rejected credentials', () {
    try {
      RemoteServerSelection.selfHosted('https://user:secret@example.com');
      fail('expected invalid origin');
    } on FormatException catch (error) {
      expect(error.toString(), isNot(contains('secret')));
    }
  });
}
