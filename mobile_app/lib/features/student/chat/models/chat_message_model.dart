class ChatMessageModel {
  final String id;
  final String studentId;
  final String supervisorId;
  final String senderRole; // student | supervisor
  final String message;
  final String createdAt;

  ChatMessageModel({
    required this.id,
    required this.studentId,
    required this.supervisorId,
    required this.senderRole,
    required this.message,
    required this.createdAt,
  });

  bool get isFromStudent => senderRole == 'student';
  bool get isFromSupervisor => senderRole == 'supervisor';

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) {
    return ChatMessageModel(
      id: json['id'] as String,
      studentId: json['student_id'] as String,
      supervisorId: json['supervisor_id'] as String,
      senderRole: json['sender_role'] as String,
      message: json['message'] as String,
      createdAt: json['created_at'] as String,
    );
  }
}
