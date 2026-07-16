import 'package:closer/core/utils/app_utils.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../shared/providers/app_providers.dart';
import '../../../vibe/presentation/widgets/sync_status_chip.dart';
import '../../../call/providers/call_providers.dart';
import '../../../call/call_manager.dart';
import '../../../call/presentation/screens/call_screen.dart';
import '../../../../data/services/notification_service.dart';



// ─── Colors ───────────────────────────────────────────────────────────────────

const Color _pinkDark = Color(0xFFE8647A);     // rose — my bubbles
const Color _pinkLight = Color(0xFFFFE4EC);    // blush — background tint
const Color _bubbleMine = Color(0xFFE8647A);   // rose bubble (me)
const Color _bubblePartner = Color(0xFFFFFFFF); // white bubble (partner)
const Color _bgTop = Color(0xFFFFF0F3);
const Color _bgBottom = Color(0xFFFFE4EC);
const Color _appBarPink = Color(0xFFE8647A);

// ─── Chat Screen ──────────────────────────────────────────────────────────────

class ChatScreen extends ConsumerStatefulWidget {
  final String spaceId;
  final List<String> memberIds;
  final String deviceId;
  final String deviceName;

  const ChatScreen({
    super.key,
    required this.spaceId,
    required this.memberIds,
    required this.deviceId,
    required this.deviceName,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  late final ChatRepository _repo;
  late final PresenceRepository _presenceRepo;

  bool _isTyping = false;
  Timer? _typingTimer;

  String get _partnerId => widget.memberIds
      .firstWhere((id) => id != widget.deviceId, orElse: () => '');

  @override
  void initState() {
    super.initState();
    _repo = ChatRepository();
    _presenceRepo = ref.read(presenceRepositoryProvider);
    _controller.addListener(_onTextChanged);
    _presenceRepo.setPresent(widget.spaceId, 'chat', widget.deviceId);
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _repo.setTyping(widget.spaceId, widget.deviceId, false);
    _presenceRepo.setAbsent(widget.spaceId, 'chat', widget.deviceId);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final typing = _controller.text.isNotEmpty;
    if (typing != _isTyping) {
      setState(() => _isTyping = typing);
      _repo.setTyping(widget.spaceId, widget.deviceId, typing);
    }
    // Auto-clear typing after 3s of no keypresses
    _typingTimer?.cancel();
    if (typing) {
      _typingTimer = Timer(const Duration(seconds: 3), () {
        _repo.setTyping(widget.spaceId, widget.deviceId, false);
      });
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    _repo.setTyping(widget.spaceId, widget.deviceId, false);
    try {
      await _repo.sendMessage(
        spaceId: widget.spaceId,
        senderId: widget.deviceId,
        senderName: widget.deviceName,
        text: text,
      );
      if (_partnerId.isNotEmpty) {
        NotificationService.pingPartnerForChatMessage(
          _partnerId,
          widget.deviceName,
          text,
        );
      }
      _scrollToBottom();
    } catch (e) {
      // Restore the text so the user doesn't lose their message
      _controller.text = text;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to send message. Check your connection.'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync =
        ref.watch(chatMessagesProvider(widget.spaceId));
    final partnerTypingAsync = _partnerId.isEmpty
        ? const AsyncData(false)
        : ref.watch(chatPartnerTypingProvider(
            (spaceId: widget.spaceId, partnerId: _partnerId)));

    final partnerPresentAsync = _partnerId.isEmpty
        ? const AsyncData(false)
        : ref.watch(featurePresenceProvider(
            (spaceId: widget.spaceId, featureId: 'chat', partnerId: _partnerId)));
    final partnerPresent = partnerPresentAsync.valueOrNull ?? false;

    // Auto-scroll whenever messages update
    ref.listen(chatMessagesProvider(widget.spaceId), (_, __) {
      _scrollToBottom();
    });

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_bgTop, _bgBottom],
          ),
        ),
        child: Column(
          children: [
            // ── App Bar ───────────────────────────────────────────────
            _ChatAppBar(
              memberCount: widget.memberIds.length,
              partnerPresent: partnerPresent,
              onCallTap: () async {
                final manager = ref.read(callManagerProvider);
                if (manager.currentState != CallManagerState.idle) return;
                manager.startCall(
                  spaceId: widget.spaceId,
                  myDeviceId: widget.deviceId,
                  myName: widget.deviceName,
                  remoteDeviceId: _partnerId,
                );
                if (!mounted) return;
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CallScreen(
                      spaceId: widget.spaceId,
                      myDeviceId: widget.deviceId,
                      remoteDisplayName: 'Your Partner',
                    ),
                  ),
                );
              },
            ),

            // ── Messages ──────────────────────────────────────────────────
            Expanded(
              child: messagesAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: _pinkDark),
                ),
                error: (e, _) => Center(child: Text(AppUtils.getFriendlyErrorMessage(e), textAlign: TextAlign.center,)),
                data: (messages) {
                  if (messages.isEmpty) {
                    return _EmptyState();
                  }
                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    // Pre-render 1200px above and below the viewport.
                    // Eliminates white-flash jank when the user scrolls fast.
                    cacheExtent: 1200,
                    // Premium iOS-style bounce physics.
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    itemCount: messages.length,
                    itemBuilder: (ctx, i) {
                      final msg = messages[i];
                      final isMe = msg.senderId == widget.deviceId;
                      final showName = !isMe &&
                          (i == 0 ||
                              messages[i - 1].senderId != msg.senderId);
                      final showTime = i == messages.length - 1 ||
                          messages[i + 1].senderId != msg.senderId;
                      return _MessageBubble(
                        message: msg,
                        isMe: isMe,
                        showName: showName,
                        showTime: showTime,
                      );
                    },
                  );
                },
              ),
            ),

            // ── Typing indicator ──────────────────────────────────────────
            partnerTypingAsync.when(
              data: (typing) =>
                  typing ? const _TypingIndicator() : const SizedBox.shrink(),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),

            // ── Input bar ─────────────────────────────────────────────────
            _InputBar(
              controller: _controller,
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── App Bar ─────────────────────────────────────────────────────────────────

class _ChatAppBar extends StatelessWidget {
  final int memberCount;
  final bool partnerPresent;
  final VoidCallback? onCallTap;

  const _ChatAppBar({
    required this.memberCount,
    required this.partnerPresent,
    this.onCallTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        bottom: 16,
        left: 20,
        right: 20,
      ),
      decoration: const BoxDecoration(
        color: _appBarPink,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x30E8647A),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar stack
          SizedBox(
            width: 52,
            height: 38,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                      border: Border.all(color: _appBarPink, width: 2),
                    ),
                    child: const Center(
                      child: Text('💕', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Only Us 💕',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
              Text(
                memberCount > 1 ? 'Your private space' : 'Waiting for partner...',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Call button
          if (memberCount > 1)
            GestureDetector(
              onTap: onCallTap,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.2),
                ),
                child: const Icon(
                  Icons.call_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          const SizedBox(width: 8),
          // Online status chip
          SyncStatusChip(
            state: partnerPresent ? SyncState.inSync : SyncState.partnerLeft,
          ),
        ],
      ),
    );
  }
}

// ─── Message Bubble ───────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;
  final bool showName;
  final bool showTime;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.showName,
    required this.showTime,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: showName ? 12 : 2,
        bottom: showTime ? 4 : 2,
      ),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (showName && !isMe)
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 4),
              child: Text(
                message.senderName,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _pinkDark.withValues(alpha: 0.7),
                ),
              ),
            ),
          Row(
            mainAxisAlignment:
                isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe) ...[
                // Partner avatar
                Container(
                  width: 28,
                  height: 28,
                  margin: const EdgeInsets.only(right: 6, bottom: 2),
                  decoration: const BoxDecoration(
                    color: _pinkLight,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Text('💕', style: TextStyle(fontSize: 13)),
                  ),
                ),
              ],
              // Bubble
              Flexible(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.72,
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 11),
                  decoration: BoxDecoration(
                    color: isMe ? _bubbleMine : _bubblePartner,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(20),
                      topRight: const Radius.circular(20),
                      bottomLeft: Radius.circular(isMe ? 20 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 20),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isMe
                            ? _pinkDark.withValues(alpha: 0.25)
                            : Colors.black.withValues(alpha: 0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: message.type == 'call'
                      ? _buildCallContent()
                      : Text(
                          message.text,
                          style: TextStyle(
                            color: isMe ? Colors.white : const Color(0xFF2A1020),
                            fontSize: 15,
                            height: 1.4,
                          ),
                        ),
                ),
              ),
            ],
          ),
          if (showTime)
            Padding(
              padding: EdgeInsets.only(
                left: isMe ? 0 : 42,
                right: isMe ? 4 : 0,
                top: 4,
              ),
              child: Text(
                DateFormat('h:mm a').format(message.timestamp),
                style: TextStyle(
                  fontSize: 10,
                  color: _pinkDark.withValues(alpha: 0.45),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCallContent() {
    final isMissed = message.callState == 'missed';
    final isDeclined = message.callState == 'declined';
    final color = isMe ? Colors.white : const Color(0xFF2A1020);
    final iconColor = (isMissed || isDeclined) ? (isMe ? Colors.white : Colors.red.shade400) : color;

    String title;
    if (isMissed) {
      title = 'Missed voice call';
    } else if (isDeclined) {
      title = 'Voice call declined';
    } else {
      title = 'Voice call ended';
    }

    String subtitle = '';
    if (message.callDuration != null && message.callDuration! > 0) {
      final mins = message.callDuration! ~/ 60;
      final secs = message.callDuration! % 60;
      subtitle = mins > 0 ? '${mins}m ${secs}s' : '${secs}s';
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isMe ? Colors.white.withValues(alpha: 0.2) : _pinkLight.withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isMissed ? Icons.phone_missed_rounded : Icons.call_end_rounded,
            color: iconColor,
            size: 18,
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (subtitle.isNotEmpty)
              Text(
                subtitle,
                style: TextStyle(
                  color: color.withValues(alpha: 0.8),
                  fontSize: 12,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ─── Typing Indicator ────────────────────────────────────────────────────────

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, bottom: 6),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              color: _pinkLight,
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text('💕', style: TextStyle(fontSize: 13)),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: AnimatedBuilder(
              animation: _animController,
              builder: (ctx, _) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (i) {
                    final delay = i / 3;
                    final progress = (_animController.value + delay) % 1.0;
                    final opacity = (progress < 0.5
                            ? progress * 2
                            : (1 - progress) * 2)
                        .clamp(0.3, 1.0);
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: _pinkDark.withValues(alpha: opacity),
                        shape: BoxShape.circle,
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Input Bar ───────────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;

  const _InputBar({required this.controller, required this.onSend});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 12,
        top: 10,
        bottom: MediaQuery.of(context).padding.bottom + 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: _pinkDark.withValues(alpha: 0.1),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Text field
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: _pinkLight,
                borderRadius: BorderRadius.circular(28),
              ),
              child: TextField(
                controller: controller,
                textCapitalization: TextCapitalization.sentences,
                maxLines: null,
                style: const TextStyle(
                  color: Color(0xFF2A1020),
                  fontSize: 15,
                ),
                decoration: InputDecoration(
                  hintText: 'Say something sweet... 🌸',
                  hintStyle: TextStyle(
                    color: _pinkDark.withValues(alpha: 0.5),
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Send button
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, value, __) {
              final hasText = value.text.trim().isNotEmpty;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: hasText ? _pinkDark : _pinkLight,
                  shape: BoxShape.circle,
                  boxShadow: hasText
                      ? [
                          BoxShadow(
                            color: _pinkDark.withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : [],
                ),
                child: IconButton(
                  onPressed: hasText ? onSend : null,
                  icon: Icon(
                    Icons.send_rounded,
                    color: hasText
                        ? Colors.white
                        : _pinkDark.withValues(alpha: 0.4),
                    size: 20,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─── Empty State ─────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: _pinkLight,
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text('💕', style: TextStyle(fontSize: 38)),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Just the two of you',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _pinkDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Send your first message ✨',
            style: TextStyle(
              fontSize: 14,
              color: _pinkDark.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}
