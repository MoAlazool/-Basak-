import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/supabase_tables.dart';
import '../../../../core/network/supabase_service.dart';
import '../models/chat_message_model.dart';

class ChatRepository {
  final SupabaseClient _client = SupabaseService.client;

  /// Fetch previous messages in the conversation
  Future<List<ChatMessageModel>> getMessages({
    required String studentId,
    required String supervisorId,
  }) async {
    final response = await _client
        .from(SupabaseTables.chatMessages)
        .select()
        .eq('student_id', studentId)
        .eq('supervisor_id', supervisorId)
        .order('created_at', ascending: true);

    return (response as List<dynamic>)
        .map((e) => ChatMessageModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Send a message
  Future<ChatMessageModel> sendMessage({
    required String studentId,
    required String supervisorId,
    required String senderRole,
    required String message,
  }) async {
    final inserted = await _client
        .from(SupabaseTables.chatMessages)
        .insert({
          'student_id': studentId,
          'supervisor_id': supervisorId,
          'sender_role': senderRole,
          'message': message.trim(),
        })
        .select()
        .single();

    return ChatMessageModel.fromJson(inserted);
  }

  /// Subscribe to Realtime messages for this conversation
  RealtimeChannel subscribeToConversation({
    required String studentId,
    required String supervisorId,
    required void Function(ChatMessageModel message) onMessageReceived,
  }) {
    final channel = _client.channel('chat:${studentId}_$supervisorId');

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: SupabaseTables.chatMessages,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'student_id',
            value: studentId,
          ),
          callback: (payload) {
            final newRecord = payload.newRecord;
            if (newRecord['supervisor_id'] == supervisorId) {
              onMessageReceived(ChatMessageModel.fromJson(newRecord));
            }
          },
        )
        .subscribe();

    return channel;
  }
}
