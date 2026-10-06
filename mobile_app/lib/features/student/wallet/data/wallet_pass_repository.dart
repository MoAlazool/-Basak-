import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/supabase_tables.dart';
import '../../../../core/network/supabase_service.dart';

enum WalletPlatform { apple, google }

/// What the `student-wallet-pass` function returns: a signed pass for Apple
/// Wallet, or a save link for Google Wallet.
class WalletPassResponse {
  final Uint8List? pkpass;
  final Uri? saveUrl;

  const WalletPassResponse({this.pkpass, this.saveUrl});

  factory WalletPassResponse.fromJson(WalletPlatform platform, Object? data) {
    if (data is! Map) throw const FormatException('unexpected response');
    if (platform == WalletPlatform.apple) {
      final encoded = data['pkpass'];
      if (encoded is! String || encoded.isEmpty) {
        throw const FormatException('missing pkpass');
      }
      return WalletPassResponse(pkpass: base64Decode(encoded));
    }
    final url = Uri.tryParse(data['saveUrl'] is String ? data['saveUrl'] as String : '');
    if (url == null || url.scheme != 'https' || url.host != 'pay.google.com') {
      throw const FormatException('unexpected save link');
    }
    return WalletPassResponse(saveUrl: url);
  }
}

/// Adds the student's card to the phone's wallet. The card itself (identity,
/// permanent QR and the organisation's current design) is built and signed on
/// the server; the app only hands it to the operating system.
class WalletPassRepository {
  static const _channel = MethodChannel('basak/wallet');
  static const _fallbackError = 'تعذرت إضافة البطاقة إلى المحفظة. حاول مرة أخرى.';

  final SupabaseClient _client = SupabaseService.client;

  /// The wallet this device has, or null where there is none (web, desktop).
  static WalletPlatform? platformFor(TargetPlatform platform, {bool isWeb = kIsWeb}) {
    if (isWeb) return null;
    return switch (platform) {
      TargetPlatform.iOS => WalletPlatform.apple,
      TargetPlatform.android => WalletPlatform.google,
      _ => null,
    };
  }

  /// Returns true when the card was added (Apple) or handed to Google Wallet,
  /// false when the student closed the sheet without adding it.
  Future<bool> addToWallet(WalletPlatform platform) async {
    final WalletPassResponse pass;
    try {
      final response = await _client.functions.invoke(
        SupabaseFunctions.studentWalletPass,
        body: {'platform': platform.name},
      );
      pass = WalletPassResponse.fromJson(platform, response.data);
    } on FunctionException catch (error) {
      final details = error.details;
      throw Exception(details is Map && details['error'] is String
          ? details['error'] as String
          : _fallbackError);
    } on FormatException {
      throw Exception(_fallbackError);
    }

    if (platform == WalletPlatform.apple) {
      try {
        final result = await _channel.invokeMethod<String>('addPass', pass.pkpass);
        return result == 'added';
      } on PlatformException catch (error) {
        throw Exception(error.code == 'unavailable'
            ? 'هذا الجهاز لا يدعم إضافة البطاقات إلى Apple Wallet.'
            : _fallbackError);
      }
    }
    if (!await launchUrl(pass.saveUrl!, mode: LaunchMode.externalApplication)) {
      throw Exception('تعذر فتح Google Wallet على هذا الجهاز.');
    }
    return true;
  }
}
