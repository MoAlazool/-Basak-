import 'dart:convert';

import 'package:basak_mobile/features/auth/biometrics/biometric_device.dart';
import 'package:basak_mobile/features/auth/biometrics/biometric_sign_in.dart';
import 'package:basak_mobile/features/auth/biometrics/biometric_vault.dart';

/// A phone's biometrics the test decides: what it offers and how each check
/// ends (one answer per prompt, the last one repeated).
class FakeBiometricDevice implements BiometricDevice {
  FakeBiometricDevice({this.current = faceId, List<BiometricCheck>? checks})
      : checks = checks ?? [BiometricCheck.passed];

  static const faceId = BiometricOffer(kind: BiometricKind.faceId, enrolled: 'face', mark: 'state-1');
  static const touchId = BiometricOffer(kind: BiometricKind.touchId, enrolled: 'fingerprint', mark: 'state-1');
  static const fingerprint = BiometricOffer(kind: BiometricKind.fingerprint, enrolled: 'strong,weak', mark: 'valid');
  static const android = BiometricOffer(kind: BiometricKind.fingerprintOrFace, enrolled: 'strong,weak', mark: 'valid');

  /// Null: nothing enrolled.
  BiometricOffer? current;
  final List<BiometricCheck> checks;

  int prompts = 0;
  int renewals = 0;

  @override
  Future<BiometricOffer?> offer({bool renew = false}) async {
    if (renew) renewals++;
    return current;
  }

  @override
  Future<BiometricCheck> check() async {
    final answer = checks[prompts < checks.length ? prompts : checks.length - 1];
    prompts++;
    return answer;
  }
}

/// The keychain in memory; it remembers which entries were read.
class MemorySecretStore implements SecretStore {
  final Map<String, String> values = {};
  final List<String> reads = [];

  @override
  Future<String?> read(String key) async {
    reads.add(key);
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<bool> has(String key) async => values.containsKey(key);

  int readsOf(String key) => reads.where((read) => read == key).length;
}

class MemoryInstallMarker implements InstallMarker {
  bool there = false;

  @override
  Future<bool> exists() async => there;

  @override
  Future<void> create() async => there = true;
}

/// A vault in memory, with what is behind it at hand.
class FakeVault {
  final store = MemorySecretStore();
  final install = MemoryInstallMarker();
  late final vault = BiometricVault(store: store, install: install);

  /// The token waiting for [userId] (by default the one account most tests have).
  String? tokenOf(String userId) => store.values[BiometricVault.tokenKeyOf(userId)];
  bool enabledFor(String userId) => store.values.containsKey(BiometricVault.accountKeyOf(userId));

  /// The ids the sign-in is switched on for, the most recently used first.
  List<String> get index => [
        for (final id in jsonDecode(store.values[BiometricVault.indexKey] ?? '[]') as List) id as String,
      ];

  String? get token => index.isEmpty ? null : tokenOf(index.first);
  bool get enabled => index.isNotEmpty;
}

const saraDraft = BiometricAccountDraft(
  userId: 'student-1',
  role: 'student',
  fullName: 'سارة أحمد محمود',
  identifier: '01012346789',
);

const omarDraft = BiometricAccountDraft(
  userId: 'student-2',
  role: 'student',
  fullName: 'عمر خالد',
  identifier: '01155557777',
);

const supervisorDraft = BiometricAccountDraft(
  userId: 'supervisor-1',
  role: 'supervisor',
  fullName: 'محمود السيد',
  identifier: '01155550321',
);

/// The stored sign-in of [draft] as [offer] would have saved it, with a token
/// waiting: the phone of someone who signed out.
Future<void> storeSignIn(
  FakeVault fake, {
  BiometricAccountDraft draft = saraDraft,
  BiometricOffer offer = FakeBiometricDevice.faceId,
  String token = 'refresh-1',
}) async {
  await fake.vault.enable(BiometricAccount(
    userId: draft.userId,
    role: draft.role,
    firstName: BiometricAccount.firstNameOf(draft.fullName),
    maskedPhone: BiometricAccount.mask(draft.identifier),
    kind: offer.kind,
    enrolled: offer.enrolled,
    mark: offer.mark,
  ));
  await fake.vault.hold(draft.userId, token);
}
