import 'server_api.dart';

/// Persisted choice for a remote-only client. Hosted migrations require an
/// explicit user decision; only [RemoteServerChoice.selfHosted] has an origin.
enum RemoteServerChoice { unconfigured, selfHosted, hosted }

/// Pure configuration parsing, without storage, credentials or network effects.
/// Existing RemoteAccount callers retain their default-server contract.
class RemoteServerSelection {
  const RemoteServerSelection._(this.choice, this.origin);

  const RemoteServerSelection.unconfigured() : this._(RemoteServerChoice.unconfigured, null);

  const RemoteServerSelection._hosted() : this._(RemoteServerChoice.hosted, null);

  factory RemoteServerSelection.selfHosted(String address) =>
      RemoteServerSelection._(RemoteServerChoice.selfHosted, _httpsOrigin(address));

  final RemoteServerChoice choice;
  final Uri? origin;

  bool get requiresConfirmation => choice == RemoteServerChoice.hosted;

  /// A blank build default deliberately leaves a new installation unconfigured.
  factory RemoteServerSelection.buildDefault([
    String address = const String.fromEnvironment('DSH_REMOTE_DEFAULT_SERVER_URL'),
  ]) => address.trim().isEmpty ? const RemoteServerSelection.unconfigured() : RemoteServerSelection.selfHosted(address);

  /// Precedence: versioned choice, old installation, then build default.
  /// The caller must determine [hasLegacySettings] from installation evidence:
  /// the old missing server key alone cannot distinguish a fresh installation.
  /// Invalid input throws; callers must retain it for correction, not fall back.
  factory RemoteServerSelection.resolve({
    Map<String, Object?>? saved,
    bool hasLegacySettings = false,
    String? legacyServer,
    String defaultServer = const String.fromEnvironment('DSH_REMOTE_DEFAULT_SERVER_URL'),
  }) {
    if (saved != null) return RemoteServerSelection.fromJson(saved);
    if (legacyServer != null && legacyServer.isNotEmpty) {
      return RemoteServerSelection.selfHosted(legacyServer);
    }
    if (hasLegacySettings) return const RemoteServerSelection._hosted();
    return RemoteServerSelection.buildDefault(defaultServer);
  }

  factory RemoteServerSelection.fromJson(Map<String, Object?> json) {
    if (json['schemaVersion'] != 1) throw const FormatException('Unsupported server selection version');
    switch (json['choice']) {
      case 'unconfigured':
        if (json['origin'] != null) throw const FormatException('Unexpected server origin');
        return const RemoteServerSelection.unconfigured();
      case 'hosted':
        if (json['origin'] != null) throw const FormatException('Unexpected server origin');
        return const RemoteServerSelection._hosted();
      case 'selfHosted':
        final origin = json['origin'];
        if (origin is! String) throw const FormatException('Missing server origin');
        return RemoteServerSelection.selfHosted(origin);
      default:
        throw const FormatException('Unknown server selection');
    }
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'choice': choice.name,
    if (origin != null) 'origin': origin!.origin,
  };

  static Uri _httpsOrigin(String address) {
    try {
      final text = address.trim();
      final explicitScheme = RegExp(r'^[a-z][a-z\d+.-]*://', caseSensitive: false).hasMatch(text);
      final entered = Uri.parse(explicitScheme ? text : 'https://$text');
      if (!entered.hasAuthority || entered.host.isEmpty || (entered.path.isNotEmpty && entered.path != '/')) {
        throw const FormatException();
      }
      final origin = normalizeServerUrl(address);
      if (origin.scheme != 'https' || origin.host.isEmpty) throw const FormatException();
      return origin;
    } on FormatException {
      throw const FormatException('Server selection requires a bare HTTPS origin');
    } on ArgumentError {
      // Do not include input: a rejected URL may contain credentials.
      throw const FormatException('Server selection requires a bare HTTPS origin');
    }
  }
}
