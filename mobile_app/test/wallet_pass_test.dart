import 'dart:convert';

import 'package:basak_mobile/features/student/qr/data/student_qr_repository.dart';
import 'package:basak_mobile/features/student/wallet/data/wallet_pass_repository.dart';
import 'package:basak_mobile/features/student/wallet/presentation/add_to_wallet_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const qr = '11111111-2222-3333-4444-555555555555';

  test('each phone is offered its own wallet and other platforms none', () {
    expect(WalletPassRepository.platformFor(TargetPlatform.iOS, isWeb: false), WalletPlatform.apple);
    expect(WalletPassRepository.platformFor(TargetPlatform.android, isWeb: false), WalletPlatform.google);
    expect(WalletPassRepository.platformFor(TargetPlatform.macOS, isWeb: false), isNull);
    expect(WalletPassRepository.platformFor(TargetPlatform.android, isWeb: true), isNull);
  });

  test('the wallet card is offered for the student, whatever the subscription status', () {
    for (final status in ['active', 'pending_payment', 'pending_review', 'rejected', 'expired', null]) {
      expect(
        AddToWalletButton.canOffer(
            StudentPassDetails(qrValue: qr, subscriptionStatus: status), WalletPlatform.apple),
        isTrue,
        reason: 'status $status',
      );
    }
  });

  test('the wallet card is not offered without a QR, offline, or without a wallet', () {
    expect(AddToWalletButton.canOffer(const StudentPassDetails(), WalletPlatform.apple), isFalse);
    expect(AddToWalletButton.canOffer(const StudentPassDetails(qrValue: ''), WalletPlatform.google), isFalse);
    expect(
        AddToWalletButton.canOffer(
            const StudentPassDetails(qrValue: qr, isOfflineCache: true), WalletPlatform.apple),
        isFalse);
    expect(AddToWalletButton.canOffer(const StudentPassDetails(qrValue: qr), null), isFalse);
  });

  test('an Apple response carries the signed pass bytes', () {
    final pass = WalletPassResponse.fromJson(
        WalletPlatform.apple, {'pkpass': base64Encode([80, 75, 3, 4])});
    expect(pass.pkpass, [80, 75, 3, 4]);
    expect(() => WalletPassResponse.fromJson(WalletPlatform.apple, {'saveUrl': 'x'}), throwsFormatException);
    expect(() => WalletPassResponse.fromJson(WalletPlatform.apple, 'nope'), throwsFormatException);
  });

  test('a Google response must be a Google Wallet save link', () {
    final pass = WalletPassResponse.fromJson(
        WalletPlatform.google, {'saveUrl': 'https://pay.google.com/gp/v/save/abc.def.ghi'});
    expect(pass.saveUrl!.host, 'pay.google.com');
    expect(
        () => WalletPassResponse.fromJson(WalletPlatform.google, {'saveUrl': 'https://evil.example/save'}),
        throwsFormatException);
    expect(
        () => WalletPassResponse.fromJson(WalletPlatform.google, {'saveUrl': 'http://pay.google.com/x'}),
        throwsFormatException);
  });

  testWidgets('the button shows on Android and disappears for offline data', (tester) async {
    Widget host(StudentPassDetails pass) => ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: AddToWalletButton(pass: pass, platform: WalletPlatform.google),
            ),
          ),
        );
    await tester.pumpWidget(host(const StudentPassDetails(qrValue: qr)));
    expect(find.text('إضافة إلى Google Wallet'), findsOneWidget);

    await tester.pumpWidget(host(const StudentPassDetails(qrValue: qr, isOfflineCache: true)));
    expect(find.text('إضافة إلى Google Wallet'), findsNothing);
  });
}
