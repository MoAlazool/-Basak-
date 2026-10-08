import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Shown instead of raw socket errors when an action needs the server.
const offlineActionMessage =
    'لا يوجد اتصال بالإنترنت. هذا الإجراء يحتاج إلى اتصال، حاول مرة أخرى عند عودة الشبكة.';

/// True when [error] means the server could not be reached (no network, DNS
/// failure, timeout), as opposed to the server answering with an error.
bool isNetworkFailure(Object error) {
  if (error is SocketException ||
      error is TimeoutException ||
      error is HttpException ||
      error is HandshakeException ||
      error is AuthRetryableFetchException) {
    return true;
  }
  final message = error.toString().toLowerCase();
  return message.contains('failed host lookup') ||
      message.contains('network is unreachable') ||
      message.contains('connection refused') ||
      message.contains('connection reset') ||
      message.contains('connection closed') ||
      message.contains('connection abort') ||
      message.contains('socketexception') ||
      message.contains('clientexception') ||
      message.contains('timed out') ||
      message.contains('timeout');
}

/// Text for showing [error] to the user: the offline message for network
/// failures, otherwise the error without Dart's "Exception: " prefix.
String errorMessage(Object error) {
  if (isNetworkFailure(error)) return offlineActionMessage;
  return error.toString().replaceFirst('Exception: ', '');
}

/// Runs a server write; a network failure becomes a clear Arabic message.
/// Writes are never queued: attendance, rides and payments must reach the
/// server while the student or supervisor is still looking at the screen.
Future<T> requireOnline<T>(Future<T> Function() action) async {
  try {
    return await action();
  } catch (error) {
    if (isNetworkFailure(error)) throw Exception(offlineActionMessage);
    rethrow;
  }
}
