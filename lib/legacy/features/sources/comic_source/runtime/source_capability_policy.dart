const Set<String> _sensitiveCryptoTypes = <String>{
  'aes-ecb',
  'aes-cbc',
  'aes-cfb',
  'aes-ofb',
  'rsa',
};

const String sourceSecurityField = 'security';
const String allowSensitiveCryptoField = 'allowSensitiveCrypto';
const bool defaultAllowSensitiveCrypto = true;
const String allowPrivateHttpField = 'allowPrivateHttp';
const bool defaultAllowPrivateHttp = false;

final Set<String> _trustedCryptoSourceKeys = <String>{};
final Set<String> _trustedHttpSourceKeys = <String>{};

void configureTrustedCryptoSources(Iterable<String> sourceKeys) {
  _trustedCryptoSourceKeys
    ..clear()
    ..addAll(sourceKeys.where((key) => key.trim().isNotEmpty));
}

bool isSensitiveCryptoType(String type) {
  return _sensitiveCryptoTypes.contains(type);
}

bool canUseSensitiveCrypto({required String sourceKey}) {
  if (_trustedCryptoSourceKeys.isEmpty) {
    return true;
  }
  return _trustedCryptoSourceKeys.contains(sourceKey);
}

void configureTrustedHttpSources(Iterable<String> sourceKeys) {
  _trustedHttpSourceKeys
    ..clear()
    ..addAll(sourceKeys.where((key) => key.trim().isNotEmpty));
}

bool canUsePrivateHttpTargets({required String sourceKey}) {
  if (_trustedHttpSourceKeys.isEmpty) {
    return defaultAllowPrivateHttp;
  }
  return _trustedHttpSourceKeys.contains(sourceKey);
}

Set<String> buildTrustedCryptoSourceKeys({
  required Iterable<String> sourceKeys,
  required Iterable<String> deniedSourceKeys,
  String? mandatorySourceKey,
}) {
  final trusted = <String>{...sourceKeys};
  if (mandatorySourceKey != null && mandatorySourceKey.isNotEmpty) {
    trusted.add(mandatorySourceKey);
  }
  trusted.removeAll(deniedSourceKeys);
  return trusted;
}
