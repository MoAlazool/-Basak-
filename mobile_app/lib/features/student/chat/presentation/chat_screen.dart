import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/network/supabase_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../../core/widgets/glass_scaffold.dart';
import '../data/chat_repository.dart';
import '../models/chat_message_model.dart';
import '../../home/presentation/student_home_screen.dart';

final chatRepoProvider = Provider((ref) => ChatRepository());

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessageModel> _messages = [];
  bool _isLoading = true;
  @override
  void initState() {
    super.initState();
    _loadConversation();
  }

  Future<void> _loadConversation() async {
    final sub = await ref.read(currentSubscriptionProvider.future);
    final user = SupabaseService.currentUser;
    if (sub == null || user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final repo = ref.read(chatRepoProvider);

    try {
      final messages = await repo.getMessages(
        studentId: user.id,
        supervisorId: sub.lineId, // Or supervisor UUID
      );
      if (mounted) {
        setState(() {
          _messages.addAll(messages);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;

    final user = SupabaseService.currentUser;
    final sub = await ref.read(currentSubscriptionProvider.future);
    if (user == null || sub == null) return;

    _msgController.clear();
    final repo = ref.read(chatRepoProvider);

    try {
      final msg = await repo.sendMessage(
        studentId: user.id,
        supervisorId: sub.lineId,
        senderRole: 'student',
        message: text,
      );
      setState(() => _messages.add(msg));
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 60,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل الإرسال: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      body: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.babyBlueLight.withOpacity(0.5),
                  child: const Icon(LucideIcons.userCheck, color: AppColors.babyBlueDark),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('مشرف الخط', style: AppTextStyles.titleMedium),
                    Text('محادثة فورية مباشرة', style: AppTextStyles.labelSmall.copyWith(color: AppColors.success)),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Messages list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Text(
                          'لا توجد رسائل سابقة. يمكنك الاستفسار من مشرف الخط هنا.',
                          style: AppTextStyles.bodyMedium,
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          final isMe = msg.isFromStudent;

                          return Align(
                            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: GlassContainer(
                                blur: 12,
                                opacity: isMe ? 0.85 : 0.70,
                                color: isMe ? AppColors.babyBlueLight : Colors.white,
                                borderRadius: 18,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                child: Text(
                                  msg.message,
                                  style: AppTextStyles.bodyLarge.copyWith(
                                    color: isMe ? const Color(0xFF0C4A6E) : AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),

          // Glass Input Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 90), // Bottom nav bar clearance
            child: GlassContainer(
              blur: 16,
              opacity: 0.85,
              borderRadius: 28,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _msgController,
                      style: AppTextStyles.bodyLarge,
                      decoration: const InputDecoration(
                        hintText: 'اكتب رسالتك للمشرف...',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _sendMessage,
                    icon: const Icon(LucideIcons.send, color: AppColors.babyBlueDark),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
