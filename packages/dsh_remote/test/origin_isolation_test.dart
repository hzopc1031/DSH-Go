import 'package:dsh_remote/dsh_remote.dart';
import 'package:test/test.dart';

import 'support/fake_remote.dart';

void main() {
  test('A to B to A isolates identity, credentials, Host pins and revocation', () async {
    final a = await FakeRemoteServer.start();
    final b = await FakeRemoteServer.start();
    addTearDown(a.close);
    addTearDown(b.close);
    // Same Host id on two origins must still require separate trust decisions.
    final hostA = await FakeRemoteHost.start(a, deviceId: 'same-host');
    final hostB = await FakeRemoteHost.start(b, deviceId: 'same-host');
    addTearDown(hostA.close);
    addTearDown(hostB.close);
    final secrets = MemorySecretStore();
    RemoteAccount account(Uri origin) {
      final value = RemoteAccount(secrets: secrets, serverUrl: origin);
      addTearDown(value.close);
      return value;
    }

    final first = account(a.url);
    final userA = await first.loginWithPassword(FakeRemoteServer.account, FakeRemoteServer.password);
    final foundA = (await first.listHosts()).single;
    final client = await first.connectHost(foundA, confirmNewHost: (_) async => true);
    await client.close();
    expect((await first.listHosts()).single.trust, RemoteHostTrust.pinned);
    final second = account(b.url);
    expect(await second.currentUser(), isNull);
    final userB = await second.loginWithPassword(FakeRemoteServer.account, FakeRemoteServer.password);
    expect(userB.deviceId, isNot(userA.deviceId));
    final foundB = (await second.listHosts()).single;
    expect(foundB.trust, RemoteHostTrust.unpinned);
    expect(foundB.identityKey, isNot(foundA.identityKey));
    final restored = account(a.url);
    expect((await restored.currentUser())!.deviceId, userA.deviceId);
    expect((await restored.listHosts()).single.trust, RemoteHostTrust.pinned);
    await second.logout();
    expect(b.devices[userB.deviceId]!.revoked, isTrue);
    expect(a.devices[userA.deviceId]!.revoked, isFalse);
    expect((await restored.listHosts()).single.trust, RemoteHostTrust.pinned);
    expect(a.protocolErrors, isEmpty);
    expect(b.protocolErrors, isEmpty);
  });
}
