import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/supabase_config.dart';
import '../../../../core/network/network_errors.dart';

/// Sends a receipt image to the private bucket and reports how much of it has
/// left the phone.
///
/// The storage library uploads in one piece and cannot tell how far it is, so
/// the image is sent here as one streamed request to the same storage address,
/// with the same sign-in and the same rules on the server (bucket, path and
/// policies are unchanged). The pieces are handed to the connection only as
/// fast as it takes them, so the progress follows the network, not memory.
/// Works the same on Android and iOS (both use the Dart HTTP client).
class ReceiptImageUpload {
  final SupabaseClient _client;
  ReceiptImageUpload(this._client);

  static const _pieceSize = 16 * 1024;

  /// Nothing from the server for this long: the connection is taken as lost.
  static const answerTimeout = Duration(seconds: 90);

  Future<void> send(String path, Uint8List bytes, {void Function(int sent, int total)? onProgress}) async {
    final http.Client connection = http.Client();
    try {
      await post(
        client: connection,
        url: Uri.parse('${SupabaseConfig.supabaseUrl}/storage/v1/object/${SupabaseConfig.receiptsBucket}/$path'),
        headers: {
          ..._client.storage.headers,
          'apikey': SupabaseConfig.supabaseAnonKey,
          'Authorization': 'Bearer ${await _accessToken()}',
        },
        bytes: bytes,
        onProgress: onProgress,
      );
    } on StorageException {
      rethrow;
    } catch (error) {
      if (isNetworkFailure(error)) rethrow;
      // Anything unexpected about the streamed request: the library's own
      // upload does the same job, without progress.
      await _client.storage.from(SupabaseConfig.receiptsBucket).uploadBinary(path, bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true));
      onProgress?.call(bytes.length, bytes.length);
    } finally {
      connection.close();
    }
  }

  /// The session's token, renewed first when it is about to run out.
  Future<String> _accessToken() async {
    var session = _client.auth.currentSession;
    if (session == null || session.isExpired) {
      session = (await _client.auth.refreshSession()).session;
    }
    if (session == null) throw Exception('المستخدم غير مسجل.');
    return session.accessToken;
  }

  /// One POST of [bytes] to [url], replacing a file already there
  /// (`x-upsert`), telling [onProgress] after each piece the connection took.
  static Future<void> post({
    required http.Client client,
    required Uri url,
    required Map<String, String> headers,
    required Uint8List bytes,
    void Function(int sent, int total)? onProgress,
  }) async {
    final request = _PiecewiseRequest(url, bytes, _pieceSize, onProgress)
      ..headers.addAll(headers)
      ..headers['x-upsert'] = 'true'
      ..headers['cache-control'] = 'max-age=3600'
      ..headers['content-type'] = 'image/jpeg';
    final response = await http.Response.fromStream(await client.send(request).timeout(answerTimeout))
        .timeout(answerTimeout);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      onProgress?.call(bytes.length, bytes.length);
      return;
    }
    String message = response.body;
    try {
      final body = jsonDecode(response.body);
      if (body is Map) message = (body['message'] ?? body['error'] ?? response.body).toString();
    } catch (_) {}
    throw StorageException(message, statusCode: '${response.statusCode}');
  }
}

class _PiecewiseRequest extends http.BaseRequest {
  final Uint8List _bytes;
  final int _pieceSize;
  final void Function(int sent, int total)? _onProgress;

  _PiecewiseRequest(Uri url, this._bytes, this._pieceSize, this._onProgress) : super('POST', url) {
    contentLength = _bytes.length;
  }

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_pieces());
  }

  // A generator is only asked for the next piece when the connection is ready
  // for it, which is what makes the count a real one.
  Stream<List<int>> _pieces() async* {
    final total = _bytes.length;
    for (var start = 0; start < total; start += _pieceSize) {
      final end = start + _pieceSize < total ? start + _pieceSize : total;
      yield Uint8List.sublistView(_bytes, start, end);
      // The last piece is only "sent" once the server has answered.
      if (end < total) _onProgress?.call(end, total);
    }
  }
}
