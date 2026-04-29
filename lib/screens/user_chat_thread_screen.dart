import 'dart:async';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';

import '../app_constants.dart';
import '../config/supabase_ready.dart';
import '../models/chat_forward_draft.dart';
import '../models/conversation_list_item.dart';
import '../services/chat_download_share.dart';
import '../services/open_chat_tracker.dart';
import '../services/chat_service.dart';
import '../services/chat_unread_badge.dart';
import '../services/city_data_service.dart';
import '../core/auth/app_auth.dart';
import '../core/config/backend_mode.dart';
import '../features/chat/data/api/chat_connection_controller.dart';
import '../features/chat/data/chat_messages_factory.dart';
import '../features/chat/domain/chat_exceptions.dart';
import '../features/chat/domain/chat_messages_repository.dart';
import '../features/chat/presentation/chat_list_scroll_anchor.dart';
import '../features/chat/presentation/chat_place_share_resolution_cache.dart';
import '../features/chat/presentation/chat_thread_messages_notifier.dart';
import '../features/chat/presentation/chat_user_profile_cache.dart';
import '../features/chat/presentation/models/group_chat_sender_display.dart';
import '../features/chat/presentation/widgets/chat_thread/chat_place_share_card.dart';
import '../features/chat/presentation/widgets/chat_thread/forwarded_tiny_avatar.dart';
import 'chat_full_image_viewer_screen.dart';
import 'direct_peer_profile_screen.dart';
import 'forward_conversation_picker_screen.dart';
import 'group_chat_info_screen.dart';
import 'place_detail_screen.dart';
import '../widgets/city_network_image.dart';
import '../features/chat/domain/chat_message_snippet.dart';
import '../features/chat/domain/chat_reply_draft.dart';
import '../features/chat/domain/chat_reply_strip_data.dart';
import '../features/chat/domain/chat_message.dart';
import '../features/chat/presentation/widgets/chat_message_reply_strip.dart';
import '../features/chat/presentation/widgets/chat_reply_draft_banner.dart';
import '../features/chat/presentation/widgets/chat_image_bubble.dart';
import '../features/chat/presentation/widgets/chat_voice_message_bubble.dart';
import '../features/chat/presentation/widgets/chat_voice_record_button.dart';

class UserChatThreadScreen extends StatefulWidget {
  const UserChatThreadScreen({
    super.key,
    required this.conversationId,
    required this.title,
    this.listItem,
    this.directPeerUserId,
    this.initialForwardDraft,
  });

  final String conversationId;
  final String title;
  final ConversationListItem? listItem;

  /// Собеседник в личном чате, если экран открыт не из списка (например, из вакансии).
  final String? directPeerUserId;

  /// Открыть чат с черновиком пересылки (панель над полем ввода, отправка по «Отправить»).
  final List<ChatForwardDraft>? initialForwardDraft;

  @override
  State<UserChatThreadScreen> createState() => _UserChatThreadScreenState();
}

class _UserChatThreadScreenState extends State<UserChatThreadScreen> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  bool _sending = false;
  bool _sendingImage = false;
  bool _sendingFile = false;
  bool _sendingVoice = false;
  bool _showEmoji = false;
  String _headerTitle = '';
  bool? _isGroup;
  bool? _isOpen;
  String? _myRole;
  String? _peerUserId;
  String? _peerAvatarUrl;
  Timer? _readDebounce;

  /// Лента сообщений: пагинация + Realtime (см. [ChatThreadMessagesNotifier]).
  ChatThreadMessagesNotifier? _threadMessages;

  /// Курсор «прочитано до» (для стиля входящих + галочек исходящих).
  DateTime? _myReadCursor;
  Map<String, DateTime?> _otherReadByUser = <String, DateTime?>{};

  bool _selectingMessages = false;
  final Set<String> _selectedMessageIds = <String>{};

  /// Актуальная лента (для порядка пересылки); обновляется из [ _MessagesList ] без setState.
  List<Map<String, dynamic>> _messageRowsForForward = <Map<String, dynamic>>[];

  List<ChatForwardDraft>? _pendingForwardDrafts;

  /// Режим ответа (как в Telegram): ссылка на сообщение + снимок для API.
  ChatReplyDraft? _replyDraft;

  final GlobalKey<_MessagesListState> _messagesListKey =
      GlobalKey<_MessagesListState>();

  @override
  void initState() {
    super.initState();
    OpenChatTracker.setOpen(widget.conversationId);
    if (widget.initialForwardDraft != null &&
        widget.initialForwardDraft!.isNotEmpty) {
      _pendingForwardDrafts = List<ChatForwardDraft>.from(
        widget.initialForwardDraft!,
      );
    }
    _headerTitle = widget.title;
    _isGroup = widget.listItem?.isGroup;
    _isOpen = widget.listItem?.isOpen;
    _myRole = widget.listItem?.myRole;
    _loadMeta();
    unawaited(_bootstrapReadState());
    final ChatMessagesRepository? cr = ChatMessagesFactory.tryRepository();
    if (cr != null) {
      _threadMessages = ChatThreadMessagesNotifier(
        conversationId: widget.conversationId,
        repository: cr,
        ownUserId: AppAuth.I.currentUserId,
      );
    }
  }

  Future<void> _loadMeta() async {
    if (widget.listItem != null) {
      setState(() {
        _isGroup = widget.listItem!.isGroup;
        _isOpen = widget.listItem!.isOpen;
        _myRole = widget.listItem!.myRole;
      });
    } else {
      final Map<String, dynamic>? row = await ChatService.fetchConversation(
        widget.conversationId,
      );
      if (row != null && mounted) {
        setState(() {
          _isGroup =
              row['is_group'] as bool? ?? !(row['is_direct'] as bool? ?? true);
          _isOpen = row['is_open'] as bool?;
          if (_isGroup == true) {
            _headerTitle = (row['group_name'] as String?)?.trim() ?? 'Группа';
          }
        });
      }
      final String? r = await ChatService.getMyRoleInConversation(
        widget.conversationId,
      );
      if (mounted) {
        setState(() => _myRole = r ?? _myRole);
      }
    }

    if (_isGroup == true) {
      return;
    }
    String? peer = widget.directPeerUserId?.trim();
    peer ??= widget.listItem?.otherUserId;
    if (peer == null || peer.isEmpty) {
      peer = await ChatService.otherParticipantId(widget.conversationId);
    }
    if (!mounted || peer == null || peer.isEmpty) {
      return;
    }
    final Map<String, dynamic>? prof = await CityDataService.fetchProfileRow(
      peer,
    );
    if (mounted) {
      setState(() {
        _peerUserId = peer;
        _peerAvatarUrl = (prof?['avatar_url'] as String?)?.trim();
        if (_peerAvatarUrl != null && _peerAvatarUrl!.isEmpty) {
          _peerAvatarUrl = null;
        }
      });
    }
  }

  @override
  void dispose() {
    OpenChatTracker.setOpen(null);
    _readDebounce?.cancel();
    _threadMessages?.dispose();
    _inputFocus.dispose();
    _input.dispose();
    unawaited(ChatUnreadBadge.refresh());
    super.dispose();
  }

  double get _inputBarBottom {
    final MediaQueryData mq = MediaQuery.of(context);
    if (mq.viewInsets.bottom > 0) {
      // Клавиатура: `Scaffold` уже учитывает viewInsets, не дублируем.
      return 4;
    }
    return 4 + mq.viewPadding.bottom;
  }

  /// Тонкая полоса: состояние WebSocket к chat-api (только [BackendMode.rest]).
  Widget _chatWireStatusBar() {
    return ListenableBuilder(
      listenable: ChatConnectionController.instance,
      builder: (BuildContext context, Widget? _) {
        final ChatWireStatus s = ChatConnectionController.instance.status;
        if (s == ChatWireStatus.idle) {
          return const SizedBox.shrink();
        }
        if (s == ChatWireStatus.connected) {
          return ColoredBox(
            color: Colors.green.shade600,
            child: const SizedBox(height: 2, width: double.infinity),
          );
        }
        final ThemeData theme = Theme.of(context);
        if (s == ChatWireStatus.connecting) {
          return _chatWireLabelStrip(
            Colors.amber.shade800,
            'Подключение к чату…',
          );
        }
        if (s == ChatWireStatus.reconnecting) {
          return _chatWireLabelStrip(
            Colors.amber.shade800,
            'Восстановление связи…',
          );
        }
        if (s == ChatWireStatus.offline) {
          return _chatWireLabelStrip(
            theme.colorScheme.error,
            'Нет связи с сервером чата',
          );
        }
        if (s == ChatWireStatus.error) {
          return _chatWireLabelStrip(
            theme.colorScheme.error,
            'Ошибка: ${ChatConnectionController.instance.lastLog ?? "см. лог"}',
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  static Widget _chatWireLabelStrip(Color bg, String label) {
    return Material(
      color: bg,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  void _toggleEmoji() {
    if (_showEmoji) {
      setState(() => _showEmoji = false);
    } else {
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => _showEmoji = true);
    }
  }

  Future<void> _attachImage() async {
    if (_sending || _sendingImage || _sendingFile || _sendingVoice) {
      return;
    }
    final ImagePicker p = ImagePicker();
    final XFile? f = await p.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (f == null) {
      return;
    }
    setState(() => _sendingImage = true);
    try {
      final String url = await CityDataService.uploadChatImage(f);
      final ChatReplyDraft? r = _replyDraft;
      final String? repUid = r?.authorUserId.trim();
      await ChatService.sendImageMessage(
        widget.conversationId,
        url,
        replyToMessageId: r?.targetMessageId,
        replySnippet: r?.snippet,
        replyAuthorId: (repUid != null && repUid.isNotEmpty) ? repUid : null,
        replyAuthorLabel: r?.authorLabel,
      );
      if (mounted) {
        setState(() => _replyDraft = null);
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Фото: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _sendingImage = false);
      }
    }
  }

  static String _mimeFromFileName(String name) {
    final int dot = name.lastIndexOf('.');
    final String ext = dot >= 0 && dot < name.length - 1
        ? name.substring(dot + 1).toLowerCase()
        : '';
    const Map<String, String> ct = <String, String>{
      'png': 'image/png',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'pdf': 'application/pdf',
      'mp3': 'audio/mpeg',
      'ogg': 'audio/ogg',
      'wav': 'audio/wav',
      'mp4': 'video/mp4',
      'webm': 'video/webm',
      'mov': 'video/quicktime',
      'mkv': 'video/x-matroska',
      'apk': 'application/vnd.android.package-archive',
      'xml': 'application/xml',
      'zip': 'application/zip',
      'txt': 'text/plain',
      'json': 'application/json',
    };
    return ct[ext] ?? 'application/octet-stream';
  }

  Future<void> _attachFile() async {
    if (_sending || _sendingImage || _sendingFile || _sendingVoice) {
      return;
    }
    final FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) {
      return;
    }
    final PlatformFile pf = result.files.single;
    late final XFile xf;
    if (kIsWeb) {
      final Uint8List? bytes = pf.bytes;
      if (bytes == null) {
        return;
      }
      xf = XFile.fromData(bytes, name: pf.name);
    } else {
      final String? path = pf.path;
      if (path == null || path.isEmpty) {
        return;
      }
      xf = XFile(path, name: pf.name);
    }
    final String displayName = pf.name.isNotEmpty
        ? pf.name
        : (xf.name.isNotEmpty ? xf.name : 'file');
    setState(() => _sendingFile = true);
    try {
      final String url = await CityDataService.uploadChatAttachment(xf);
      final ChatReplyDraft? r = _replyDraft;
      final String? repUid = r?.authorUserId.trim();
      await ChatService.sendFileMessage(
        widget.conversationId,
        ChatFileMeta(
          url: url,
          name: displayName,
          mime: _mimeFromFileName(displayName),
        ),
        replyToMessageId: r?.targetMessageId,
        replySnippet: r?.snippet,
        replyAuthorId: (repUid != null && repUid.isNotEmpty) ? repUid : null,
        replyAuthorLabel: r?.authorLabel,
      );
      if (mounted) {
        setState(() => _replyDraft = null);
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Файл: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _sendingFile = false);
      }
    }
  }

  void _openPeerProfile() {
    final String? id = _peerUserId;
    if (id == null || id.isEmpty) {
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext c) => DirectPeerProfileScreen(
          conversationId: widget.conversationId,
          peerUserId: id,
          title: _headerTitle,
        ),
      ),
    );
  }

  Future<void> _bootstrapReadState() async {
    if (!supabaseAppReady) {
      return;
    }
    final DateTime? first = await ChatService.getMyLastReadInConversation(
      widget.conversationId,
    );
    if (mounted) {
      setState(() => _myReadCursor = first);
    }
    await ChatService.markConversationRead(widget.conversationId);
    final DateTime? after = await ChatService.getMyLastReadInConversation(
      widget.conversationId,
    );
    final Map<String, DateTime?> other =
        await ChatService.getOtherParticipantsLastReadMap(
          widget.conversationId,
        );
    if (mounted) {
      setState(() {
        _myReadCursor = after ?? _myReadCursor;
        _otherReadByUser = other;
      });
    }
    await ChatUnreadBadge.refresh();
  }

  void _scheduleReadSync() {
    _readDebounce?.cancel();
    _readDebounce = Timer(const Duration(milliseconds: 300), () async {
      if (!supabaseAppReady) {
        return;
      }
      await ChatService.markConversationRead(widget.conversationId);
      if (!mounted) {
        return;
      }
      final DateTime? after = await ChatService.getMyLastReadInConversation(
        widget.conversationId,
      );
      final Map<String, DateTime?> other =
          await ChatService.getOtherParticipantsLastReadMap(
            widget.conversationId,
          );
      if (mounted) {
        setState(() {
          _myReadCursor = after ?? _myReadCursor;
          _otherReadByUser = other;
        });
      }
      await ChatUnreadBadge.refresh();
    });
  }

  String _timeLabel(String? iso) {
    if (iso == null || iso.isEmpty) {
      return '';
    }
    try {
      final DateTime d = DateTime.parse(iso).toLocal();
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    } on Object {
      return '';
    }
  }

  void _beginReplyToMessage(Map<String, dynamic> m, String authorLabel) {
    final String s = chatMessageSnippetForReply(m);
    if (s.isEmpty) {
      return;
    }
    final String? mid = m['id']?.toString();
    final String? sid = m['sender_id']?.toString();
    if (mid == null || mid.isEmpty) {
      return;
    }
    setState(
      () => _replyDraft = ChatReplyDraft(
        targetMessageId: mid,
        authorUserId: sid ?? '',
        authorLabel: authorLabel,
        snippet: s,
      ),
    );
    _inputFocus.requestFocus();
  }

  Future<void> _send() async {
    if (_sending || _sendingImage || _sendingFile || _sendingVoice) {
      return;
    }
    if (ChatMessagesFactory.tryRepository() == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Слой сообщений недоступен: проверьте BACKEND_MODE и API_BASE_URL',
            ),
          ),
        );
      }
      return;
    }
    final String t = _input.text.trim();
    final bool hasForward =
        _pendingForwardDrafts != null && _pendingForwardDrafts!.isNotEmpty;
    if (!hasForward && t.isEmpty) {
      return;
    }
    setState(() => _sending = true);
    try {
      if (hasForward) {
        for (final ChatForwardDraft d in _pendingForwardDrafts!) {
          await ChatService.sendMessage(
            widget.conversationId,
            d.innerBody,
            forwardedFromUserId: d.originalSenderId,
            forwardedFromLabel: d.originalSenderLabel,
          );
        }
        if (mounted) {
          setState(() {
            _pendingForwardDrafts = null;
            _replyDraft = null;
          });
        }
        unawaited(ChatUnreadBadge.refresh());
      }
      if (t.isNotEmpty) {
        final ChatReplyDraft? r = _replyDraft;
        final String? repUid = r?.authorUserId.trim();
        await ChatService.sendMessage(
          widget.conversationId,
          t,
          replyToMessageId: r?.targetMessageId,
          replySnippet: r?.snippet,
          replyAuthorId: (repUid != null && repUid.isNotEmpty) ? repUid : null,
          replyAuthorLabel: r?.authorLabel,
        );
        _input.clear();
        if (mounted) {
          setState(() => _replyDraft = null);
        }
        unawaited(ChatUnreadBadge.refresh());
      }
    } on ChatFloodException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } on ChatApiNetworkException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Сеть недоступна. Проверьте подключение.'),
            action: SnackBarAction(label: 'Повторить', onPressed: _send),
          ),
        );
      }
    } on ChatApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            action: SnackBarAction(label: 'Повторить', onPressed: _send),
          ),
        );
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Не удалось отправить')));
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _sendVoice(String filePath, int durationMs) async {
    if (_sending || _sendingImage || _sendingFile || _sendingVoice) {
      return;
    }
    if (parseBackendMode() != BackendMode.rest) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Голосовые — при BACKEND_MODE=rest и API_BASE_URL'),
          ),
        );
      }
      return;
    }
    if (ChatMessagesFactory.tryRepository() == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Чат-API не настроен')));
      }
      return;
    }
    setState(() => _sendingVoice = true);
    try {
      final ChatReplyDraft? r = _replyDraft;
      final String? repUid = r?.authorUserId.trim();
      await ChatService.sendVoiceMessage(
        widget.conversationId,
        filePath,
        durationMs: durationMs,
        replyToMessageId: r?.targetMessageId,
        replySnippet: r?.snippet,
        replyAuthorId: (repUid != null && repUid.isNotEmpty) ? repUid : null,
        replyAuthorLabel: r?.authorLabel,
      );
      if (mounted) {
        setState(() => _replyDraft = null);
      }
      unawaited(ChatUnreadBadge.refresh());
    } on ChatFloodException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } on UnsupportedError {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('В режиме Supabase голосовые не поддерживаются'),
          ),
        );
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось отправить аудио')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sendingVoice = false);
      }
    }
  }

  Future<String> _displayLabelForUserId(String userId) async {
    final Map<String, dynamic>? row = await CityDataService.fetchProfileRow(
      userId,
    );
    final String? uname = (row?['username'] as String?)?.trim();
    final String fn = (row?['first_name'] as String?)?.trim() ?? '';
    final String ln = (row?['last_name'] as String?)?.trim() ?? '';
    final String full = ('$fn $ln').trim();
    if (full.isNotEmpty) {
      return full;
    }
    if (uname != null && uname.isNotEmpty) {
      return '@$uname';
    }
    return 'Участник';
  }

  Future<List<ChatForwardDraft>> _buildForwardDrafts() async {
    final List<ChatForwardDraft> out = <ChatForwardDraft>[];
    final Map<String, String> labelCache = <String, String>{};
    for (final Map<String, dynamic> row in _messageRowsForForward) {
      final String? id = row['id']?.toString();
      if (id == null || !_selectedMessageIds.contains(id)) {
        continue;
      }
      if (row['deleted_at'] != null) {
        continue;
      }
      final String raw = (row['body'] as String?) ?? '';
      if (raw.trim().isEmpty) {
        continue;
      }
      final String? existingFwdUid = row['forwarded_from_user_id']?.toString();
      final String? existingFwdLabel = row['forwarded_from_label'] as String?;
      final String origId;
      final String origLabel;
      if (existingFwdUid != null &&
          existingFwdLabel != null &&
          existingFwdLabel.trim().isNotEmpty) {
        origId = existingFwdUid;
        origLabel = existingFwdLabel.trim();
      } else {
        final String sid = row['sender_id']?.toString() ?? '';
        if (sid.isEmpty) {
          continue;
        }
        origId = sid;
        origLabel = labelCache[sid] ?? await _displayLabelForUserId(sid);
        labelCache[sid] = origLabel;
      }
      out.add(
        ChatForwardDraft(
          originalSenderId: origId,
          originalSenderLabel: origLabel,
          innerBody: raw,
        ),
      );
    }
    return out;
  }

  bool _canDeleteMessage(Map<String, dynamic> m, String? me) {
    if (me == null) {
      return false;
    }
    final String? sid = m['sender_id']?.toString();
    if (m['deleted_at'] != null) {
      return false;
    }
    // Только автор (RLS + RPC soft_delete_group_message — мигр. 035).
    return sid == me;
  }

  Future<void> _deleteMessage(String messageId) async {
    try {
      await ChatService.softDeleteMessage(messageId);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Не удалось удалить')));
      }
    }
  }

  void _exitMessageSelection() {
    setState(() {
      _selectingMessages = false;
      _selectedMessageIds.clear();
    });
  }

  void _toggleMessageSelection(String messageId) {
    setState(() {
      if (_selectedMessageIds.contains(messageId)) {
        _selectedMessageIds.remove(messageId);
      } else {
        _selectedMessageIds.add(messageId);
      }
    });
  }

  void _beginForwardSelection(String messageId) {
    setState(() {
      _selectingMessages = true;
      _selectedMessageIds
        ..clear()
        ..add(messageId);
    });
  }

  void _onMessagesSnapshot(List<Map<String, dynamic>> rows) {
    _messageRowsForForward = List<Map<String, dynamic>>.from(rows);
  }

  Future<void> _forwardSelected() async {
    if (_selectedMessageIds.isEmpty) {
      return;
    }
    final List<ChatForwardDraft> drafts = await _buildForwardDrafts();
    if (drafts.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Нечего пересылать')));
      }
      return;
    }
    if (!mounted) {
      return;
    }
    final ConversationListItem? target = await Navigator.of(context)
        .push<ConversationListItem>(
          MaterialPageRoute<ConversationListItem>(
            builder: (BuildContext c) => ForwardConversationPickerScreen(
              excludeConversationId: widget.conversationId,
            ),
          ),
        );
    if (!mounted || target == null) {
      return;
    }
    _exitMessageSelection();
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext c) => UserChatThreadScreen(
          conversationId: target.id,
          title: target.title,
          listItem: target,
          initialForwardDraft: drafts,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!supabaseAppReady) {
      return const Scaffold(
        body: Center(
          child: Text('Приложение не инициализировано (нужен Supabase в main)'),
        ),
      );
    }
    final String? me = AppAuth.I.currentUserId;
    final bool isGroup = _isGroup == true;
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;
    final Color chatBg = isDark
        ? theme.scaffoldBackgroundColor
        : const Color(0xFFF0F2F5);
    final Color appBarBg = isDark ? cs.surface : Colors.white;
    final Color appBarIcon = isDark ? cs.onSurface : kPrimaryBlue;

    return Scaffold(
      backgroundColor: chatBg,
      appBar: AppBar(
        backgroundColor: appBarBg,
        foregroundColor: cs.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            _selectingMessages ? Icons.close : Icons.arrow_back,
            color: appBarIcon,
          ),
          onPressed: _selectingMessages
              ? _exitMessageSelection
              : () => Navigator.of(context).pop(),
        ),
        title: _selectingMessages
            ? Text(
                _selectedMessageIds.isEmpty
                    ? 'Выберите сообщения'
                    : 'Выбрано: ${_selectedMessageIds.length}',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              )
            : (!isGroup && (_peerUserId != null && _peerUserId!.isNotEmpty)
                  ? InkWell(
                      onTap: _openPeerProfile,
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: <Widget>[
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: kPrimaryBlue.withValues(
                                alpha: 0.2,
                              ),
                              child:
                                  _peerAvatarUrl != null &&
                                      _peerAvatarUrl!.isNotEmpty
                                  ? CityNetworkImage.avatar(
                                      context: context,
                                      imageUrl: _peerAvatarUrl,
                                      diameter: 40,
                                    )
                                  : Text(
                                      _headerTitle.isNotEmpty
                                          ? _headerTitle[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                        color: kPrimaryBlue,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _headerTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: cs.onSurface,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Text(
                      _headerTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    )),
        actions: <Widget>[
          if (_selectingMessages)
            IconButton(
              icon: Icon(Icons.forward, color: appBarIcon),
              tooltip: 'Переслать',
              onPressed: _selectedMessageIds.isEmpty
                  ? null
                  : () => _forwardSelected(),
            )
          else if (isGroup)
            IconButton(
              icon: Icon(Icons.group_outlined, color: appBarIcon),
              onPressed: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (BuildContext c) => GroupChatInfoScreen(
                      conversationId: widget.conversationId,
                      title: _headerTitle,
                      isOpen: _isOpen ?? false,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (parseBackendMode() == BackendMode.rest) _chatWireStatusBar(),
          Expanded(
            child: _MessagesList(
              key: _messagesListKey,
              conversationId: widget.conversationId,
              messageNotifier: _threadMessages,
              isGroup: isGroup,
              me: me,
              timeLabel: _timeLabel,
              canDeleteMessage: _canDeleteMessage,
              onDelete: _deleteMessage,
              myReadAt: _myReadCursor,
              otherReadByUser: _otherReadByUser,
              onStreamChanged: _scheduleReadSync,
              selectingMessages: _selectingMessages,
              selectedMessageIds: _selectedMessageIds,
              onToggleMessageSelection: _toggleMessageSelection,
              onBeginForwardSelection: _beginForwardSelection,
              onMessagesSnapshot: _onMessagesSnapshot,
              onReplyMessage: _beginReplyToMessage,
              directPeerName: isGroup ? null : _headerTitle,
            ),
          ),
          if (!_selectingMessages && _replyDraft != null)
            ChatReplyDraftBanner(
              draft: _replyDraft!,
              onCancel: () => setState(() => _replyDraft = null),
            ),
          if (!_selectingMessages && _showEmoji)
            SizedBox(
              height: 256,
              child: EmojiPicker(
                textEditingController: _input,
                config: Config(
                  height: 256,
                  checkPlatformCompatibility: !kIsWeb,
                  locale: const Locale('en'),
                  emojiViewConfig: const EmojiViewConfig(
                    backgroundColor: Color(0xFF1E2733),
                    emojiSizeMax: 28,
                    buttonMode: ButtonMode.MATERIAL,
                  ),
                  categoryViewConfig: const CategoryViewConfig(
                    backgroundColor: Color(0xFF1E2733),
                    indicatorColor: kPrimaryBlue,
                    iconColor: Colors.white70,
                    iconColorSelected: kPrimaryBlue,
                    backspaceColor: kPrimaryBlue,
                  ),
                  bottomActionBarConfig: const BottomActionBarConfig(
                    backgroundColor: Color(0xFF1E2733),
                    buttonIconColor: Colors.white70,
                    buttonColor: Color(0xFF2A3441),
                    showSearchViewButton: true,
                  ),
                ),
              ),
            ),
          if (!_selectingMessages &&
              _pendingForwardDrafts != null &&
              _pendingForwardDrafts!.isNotEmpty)
            _PendingForwardBanner(
              drafts: _pendingForwardDrafts!,
              onCancel: () => setState(() => _pendingForwardDrafts = null),
            ),
          if (!_selectingMessages)
            Material(
              color: isDark ? cs.surface : Colors.white,
              child: Padding(
                padding: EdgeInsets.fromLTRB(4, 4, 8, _inputBarBottom),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: _toggleEmoji,
                      icon: Icon(
                        _showEmoji
                            ? Icons.keyboard_rounded
                            : Icons.emoji_emotions_outlined,
                        color: appBarIcon,
                      ),
                      tooltip: _showEmoji ? 'Клавиатура' : 'Смайлики',
                    ),
                    PopupMenuButton<int>(
                      enabled:
                          !_sendingImage && !_sendingFile && !_sendingVoice,
                      icon: _sendingImage || _sendingFile
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: appBarIcon,
                              ),
                            )
                          : Icon(Icons.attach_file, color: appBarIcon),
                      tooltip: 'Прикрепить',
                      onSelected: (int v) {
                        if (v == 0) {
                          unawaited(_attachImage());
                        } else if (v == 1) {
                          unawaited(_attachFile());
                        }
                      },
                      itemBuilder: (BuildContext menuContext) {
                        return <PopupMenuEntry<int>>[
                          const PopupMenuItem<int>(
                            value: 0,
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.photo_outlined),
                              title: Text('Фото'),
                            ),
                          ),
                          const PopupMenuItem<int>(
                            value: 1,
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.insert_drive_file_outlined),
                              title: Text('Файл'),
                            ),
                          ),
                        ];
                      },
                    ),
                    Expanded(
                      child: TextField(
                        controller: _input,
                        focusNode: _inputFocus,
                        minLines: 1,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        style: TextStyle(color: cs.onSurface, fontSize: 16),
                        decoration: InputDecoration(
                          hintText: isGroup
                              ? 'Сообщение в группе…'
                              : 'Сообщение…',
                          hintStyle: TextStyle(color: cs.onSurfaceVariant),
                          filled: true,
                          fillColor: isDark
                              ? cs.surfaceContainerHigh
                              : const Color(0xFFF0F0F0),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                        ),
                        onTap: () {
                          if (_showEmoji) {
                            setState(() => _showEmoji = false);
                          }
                        },
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    if (!kIsWeb &&
                        parseBackendMode() == BackendMode.rest &&
                        ChatMessagesFactory.tryRepository() != null)
                      ChatVoiceRecordButton(
                        enabled:
                            !_sending &&
                            !_sendingImage &&
                            !_sendingFile &&
                            !_sendingVoice,
                        onCancel: () {},
                        onSend: _sendVoice,
                      ),
                    const SizedBox(width: 2),
                    IconButton.filled(
                      onPressed: (_sending || _sendingVoice) ? null : _send,
                      icon: _sending || _sendingVoice
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
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

class _MessagesList extends StatefulWidget {
  const _MessagesList({
    super.key,
    required this.conversationId,
    required this.messageNotifier,
    required this.isGroup,
    required this.me,
    required this.timeLabel,
    required this.canDeleteMessage,
    required this.onDelete,
    required this.myReadAt,
    required this.otherReadByUser,
    required this.onStreamChanged,
    required this.selectingMessages,
    required this.selectedMessageIds,
    required this.onToggleMessageSelection,
    required this.onBeginForwardSelection,
    required this.onMessagesSnapshot,
    required this.onReplyMessage,
    this.directPeerName,
  });

  final String conversationId;
  final ChatThreadMessagesNotifier? messageNotifier;
  final bool isGroup;
  final String? me;
  final String Function(String? iso) timeLabel;
  final bool Function(Map<String, dynamic> m, String? me) canDeleteMessage;
  final void Function(String messageId) onDelete;
  final DateTime? myReadAt;
  final Map<String, DateTime?> otherReadByUser;
  final VoidCallback onStreamChanged;
  final bool selectingMessages;
  final Set<String> selectedMessageIds;
  final void Function(String messageId) onToggleMessageSelection;
  final void Function(String messageId) onBeginForwardSelection;
  final void Function(List<Map<String, dynamic>> rows) onMessagesSnapshot;
  final void Function(Map<String, dynamic> row, String authorLabel)
  onReplyMessage;

  /// Имя собеседника в личном чате (подпись «Ответ на …»).
  final String? directPeerName;

  @override
  State<_MessagesList> createState() => _MessagesListState();
}

class _MessagesListState extends State<_MessagesList> {
  String? _dataSig;
  String? _rowsReportSig;
  final Map<String, GlobalKey> _bubbleKeys = <String, GlobalKey>{};
  Timer? _onStreamDebounce;

  final ScrollController _scroll = ScrollController();
  bool _didInitScrollToBottom = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scroll.hasClients) {
      return;
    }
    if (_scroll.position.pixels < 120) {
      // ignore: discarded_futures
      _loadOlderWithScrollPreserve();
    }
  }

  /// Подгрузка старых: якорь по [maxScrollExtent] (без визуального скачка).
  Future<void> _loadOlderWithScrollPreserve() async {
    final ChatThreadMessagesNotifier? n = widget.messageNotifier;
    if (n == null || n.loadingOlder || !n.hasMoreOlder) {
      return;
    }
    final ChatListExtentAnchor? anchor = ChatListExtentAnchor.capture(_scroll);
    if (!_scroll.hasClients) {
      await n.loadOlder();
      return;
    }
    await n.loadOlder();
    if (!mounted) {
      return;
    }
    applyPrependScrollRecovery(controller: _scroll, extentAnchor: anchor);
  }

  void _maybeInitScrollToBottom() {
    if (!mounted || _didInitScrollToBottom) {
      return;
    }
    final ChatThreadMessagesNotifier? n = widget.messageNotifier;
    if (n == null || n.initialLoading || n.messageCount == 0) {
      return;
    }
    _didInitScrollToBottom = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _onStreamDebounce?.cancel();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _scheduleOnStreamChanged() {
    _onStreamDebounce?.cancel();
    _onStreamDebounce = Timer(const Duration(milliseconds: 64), () {
      if (mounted) {
        widget.onStreamChanged();
      }
    });
  }

  /// Прокрутить ленту так, чтобы сообщение [messageId] оказалось в зоне видимости.
  void scrollMessageIntoView(String messageId) {
    final ChatThreadMessagesNotifier? n = widget.messageNotifier;
    final Set<String> cands = <String>{messageId};
    if (n != null) {
      cands.add(n.canonicalMessageId(messageId));
      final String? o = n.linkedMessageId(messageId);
      if (o != null) {
        cands.add(o);
      }
    }
    GlobalKey? k;
    for (final String id in cands) {
      k = _bubbleKeys[id];
      if (k != null) {
        break;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final BuildContext? ctx = k?.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          alignment: 0.32,
        );
      }
    });
  }

  void _onGroupMemberTap(
    BuildContext context, {
    required String messageId,
    required String peerUserId,
    required GroupChatSenderDisplay sender,
    required bool isDeleted,
  }) {
    if (widget.selectingMessages && !isDeleted) {
      widget.onToggleMessageSelection(messageId);
      return;
    }
    if (isDeleted) {
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext c) => DirectPeerProfileScreen(
          conversationId: widget.conversationId,
          peerUserId: peerUserId,
          title: sender.profileTitle,
        ),
      ),
    );
  }

  static Color _groupNickColor(String userId) {
    const List<Color> palette = <Color>[
      Color(0xFF55A99C),
      Color(0xFF5EA7DE),
      Color(0xFFD4A574),
      Color(0xFFBA8FDE),
      Color(0xFF7CB893),
      Color(0xFFE07B7B),
      Color(0xFF7EB6D4),
      Color(0xFFB5C76B),
    ];
    return palette[userId.hashCode.abs() % palette.length];
  }

  static String _initialForGroupAvatar(String label) {
    final String s = label.replaceAll('@', '').trim();
    if (s.isEmpty) {
      return '?';
    }
    return s[0].toUpperCase();
  }

  void _maybeReportRowsForForward(List<Map<String, dynamic>> rows) {
    final String sig = rows.isEmpty
        ? ''
        : '${rows.length}|${rows.first['id']}|${rows.last['id']}';
    if (sig == _rowsReportSig) {
      return;
    }
    _rowsReportSig = sig;
    widget.onMessagesSnapshot(rows);
  }

  String _dmReplyAuthorLabel(bool mine) {
    if (mine) {
      return 'Вы';
    }
    final String? p = widget.directPeerName?.trim();
    if (p != null && p.isNotEmpty) {
      return p;
    }
    return 'Собеседник';
  }

  Widget? _replyStripWidget(
    BuildContext context,
    Map<String, dynamic> m,
    bool outgoing,
  ) {
    final String? rid = m['reply_to_message_id']?.toString();
    if (rid == null || rid.isEmpty) {
      return null;
    }
    return _ReplyStripWithTarget(
      messageRow: m,
      targetMessageId: rid,
      outgoing: outgoing,
      onStripPressed: () {
        unawaited(_onReplyStripTap(context, rid));
      },
    );
  }

  List<Widget> _replyPreviewList(
    BuildContext context,
    Map<String, dynamic> m,
    bool outgoing,
  ) {
    final Widget? w = _replyStripWidget(context, m, outgoing);
    if (w == null) {
      return <Widget>[];
    }
    return <Widget>[w];
  }

  Future<void> _onReplyStripTap(
    BuildContext context,
    String targetMessageId,
  ) async {
    final ChatThreadMessagesNotifier? n = widget.messageNotifier;
    if (n == null) {
      return;
    }
    await n.loadUntilMessage(targetMessageId);
    if (!context.mounted) {
      return;
    }
    scrollMessageIntoView(targetMessageId);
    final GlobalKey? k = _bubbleKeys[targetMessageId];
    if (k?.currentContext == null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сообщение не найдено в ленте')),
      );
    }
  }

  Widget _wrapReplySlidable({
    required bool mine,
    required bool isDeleted,
    required Map<String, dynamic> m,
    required String replyAuthorLabel,
    required Widget child,
  }) {
    if (widget.selectingMessages || isDeleted) {
      return child;
    }
    if (chatMessageSnippetForReply(m).isEmpty) {
      return child;
    }
    void go() {
      widget.onReplyMessage(m, replyAuthorLabel);
    }

    return Slidable(
      key: ValueKey<String>('swipe_reply:${m['id']}'),
      startActionPane: !mine
          ? ActionPane(
              motion: const BehindMotion(),
              extentRatio: 0.24,
              children: <Widget>[
                SlidableAction(
                  onPressed: (_) => go(),
                  backgroundColor: kPrimaryBlue,
                  foregroundColor: Colors.white,
                  icon: Icons.reply_rounded,
                  label: 'Ответ',
                ),
              ],
            )
          : null,
      endActionPane: mine
          ? ActionPane(
              motion: const BehindMotion(),
              extentRatio: 0.24,
              children: <Widget>[
                SlidableAction(
                  onPressed: (_) => go(),
                  backgroundColor: kPrimaryBlue,
                  foregroundColor: Colors.white,
                  icon: Icons.reply_rounded,
                  label: 'Ответ',
                ),
              ],
            )
          : null,
      child: child,
    );
  }

  String _plainTextForShare(
    Map<String, dynamic> m,
    String? displayImageUrl,
    ChatFileMeta? fileMeta,
  ) {
    if (m['deleted_at'] != null) {
      return '';
    }
    if (displayImageUrl != null && displayImageUrl.isNotEmpty) {
      return displayImageUrl;
    }
    if (fileMeta != null) {
      return fileMeta.url;
    }
    return ((m['body'] as String?) ?? '').trim();
  }

  List<PopupMenuEntry<String>> _bubbleMenuEntries(
    Map<String, dynamic> m,
    String me, {
    required String? displayImageUrl,
    required ChatFileMeta? fileMeta,
  }) {
    final bool canDel = widget.canDeleteMessage(m, me);
    final String shareText = _plainTextForShare(m, displayImageUrl, fileMeta);
    final bool canShare = shareText.isNotEmpty;
    final bool canReply = chatMessageSnippetForReply(m).isNotEmpty;
    return <PopupMenuEntry<String>>[
      const PopupMenuItem<String>(
        value: 'show',
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.visibility_outlined),
          title: Text('Показать в чате'),
        ),
      ),
      if (canReply)
        const PopupMenuItem<String>(
          value: 'reply',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.reply_rounded),
            title: Text('Ответить'),
          ),
        ),
      if (canShare)
        const PopupMenuItem<String>(
          value: 'share',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.share_outlined),
            title: Text('Поделиться'),
          ),
        ),
      const PopupMenuItem<String>(
        value: 'forward',
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.forward_rounded),
          title: Text('Выбрать для пересылки'),
        ),
      ),
      if (canDel)
        const PopupMenuItem<String>(
          value: 'delete',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_outline, color: Color(0xFFC62828)),
            title: Text('Удалить', style: TextStyle(color: Color(0xFFC62828))),
          ),
        ),
    ];
  }

  Future<void> _applyBubbleMenuSelection(
    BuildContext menuContext,
    String value,
    Map<String, dynamic> m,
    String me, {
    required String? displayImageUrl,
    required ChatFileMeta? fileMeta,
    required String replyAuthorLabel,
  }) async {
    final String? mid = m['id']?.toString();
    if (value == 'show') {
      if (mid != null) {
        scrollMessageIntoView(mid);
      }
      return;
    }
    if (value == 'reply') {
      widget.onReplyMessage(m, replyAuthorLabel);
      return;
    }
    if (value == 'share') {
      final String t = _plainTextForShare(m, displayImageUrl, fileMeta);
      if (t.isEmpty) {
        return;
      }
      if (displayImageUrl != null &&
          displayImageUrl.isNotEmpty &&
          t == displayImageUrl) {
        await shareNetworkFileToDevice(
          context: menuContext,
          url: displayImageUrl,
          suggestedName: 'chat_image.jpg',
        );
      } else if (fileMeta != null && t == fileMeta.url) {
        await shareNetworkFileToDevice(
          context: menuContext,
          url: fileMeta.url,
          suggestedName: fileMeta.name,
        );
      } else {
        await Share.share(t);
      }
      return;
    }
    if (value == 'forward') {
      if (mid != null) {
        widget.onBeginForwardSelection(mid);
      }
      return;
    }
    if (value == 'delete' && mid != null) {
      widget.onDelete(mid);
    }
  }

  void _showBubbleActionsMenu(
    BuildContext anchorContext,
    Map<String, dynamic> m,
    String me, {
    required String? displayImageUrl,
    required ChatFileMeta? fileMeta,
    required String replyAuthorLabel,
  }) {
    if (m['deleted_at'] != null) {
      return;
    }
    final RenderBox? box = anchorContext.findRenderObject() as RenderBox?;
    if (box == null) {
      return;
    }
    final OverlayState overlayState = Overlay.of(anchorContext);
    final RenderBox overlay =
        overlayState.context.findRenderObject()! as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset.zero, ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    unawaited(
      showMenu<String>(
        context: anchorContext,
        position: position,
        color: Theme.of(anchorContext).brightness == Brightness.dark
            ? const Color(0xFF2C2C2E)
            : Theme.of(anchorContext).colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        items: _bubbleMenuEntries(
          m,
          me,
          displayImageUrl: displayImageUrl,
          fileMeta: fileMeta,
        ),
      ).then((String? v) {
        if (v == null || !anchorContext.mounted) {
          return;
        }
        unawaited(
          _applyBubbleMenuSelection(
            anchorContext,
            v,
            m,
            me,
            displayImageUrl: displayImageUrl,
            fileMeta: fileMeta,
            replyAuthorLabel: replyAuthorLabel,
          ),
        );
      }),
    );
  }

  void _openChatImage(
    BuildContext context,
    Map<String, dynamic> m,
    String me,
    String displayImageUrl, {
    required String replyAuthorLabel,
  }) {
    final String messageId = m['id']?.toString() ?? '';
    final bool canDel = widget.canDeleteMessage(m, me);
    final String sub = widget.timeLabel(m['created_at'] as String?);
    final bool allowDelete = canDel && messageId.isNotEmpty;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext c) => ChatFullImageViewerScreen(
          imageUrl: displayImageUrl,
          subtitle: sub.isEmpty ? null : sub,
          canDelete: allowDelete,
          onShowInChat: () {
            if (messageId.isNotEmpty) {
              scrollMessageIntoView(messageId);
            }
          },
          onReply: () => widget.onReplyMessage(m, replyAuthorLabel),
          onDelete: allowDelete ? () => widget.onDelete(messageId) : null,
        ),
      ),
    );
  }

  Widget _bubbleOverflowMenu({
    required BuildContext context,
    required Map<String, dynamic> m,
    required String me,
    required bool mine,
    required ColorScheme cs,
    required String? displayImageUrl,
    required ChatFileMeta? fileMeta,
    required String replyAuthorLabel,
  }) {
    return Material(
      color: Colors.transparent,
      child: Theme(
        data: Theme.of(context).copyWith(
          splashColor: (mine ? Colors.white : cs.primary).withValues(
            alpha: 0.12,
          ),
        ),
        child: PopupMenuButton<String>(
          padding: EdgeInsets.zero,
          menuPadding: const EdgeInsets.symmetric(vertical: 4),
          iconSize: 20,
          splashRadius: 22,
          tooltip: 'Действия',
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF2C2C2E)
              : cs.surfaceContainerHigh,
          surfaceTintColor: Colors.transparent,
          icon: Icon(
            Icons.more_vert_rounded,
            size: 20,
            color: mine
                ? Colors.white.withValues(alpha: 0.9)
                : cs.onSurfaceVariant,
          ),
          onSelected: (String v) => unawaited(
            _applyBubbleMenuSelection(
              context,
              v,
              m,
              me,
              displayImageUrl: displayImageUrl,
              fileMeta: fileMeta,
              replyAuthorLabel: replyAuthorLabel,
            ),
          ),
          itemBuilder: (BuildContext c) => _bubbleMenuEntries(
            m,
            me,
            displayImageUrl: displayImageUrl,
            fileMeta: fileMeta,
          ),
        ),
      ),
    );
  }

  Widget _bubbleImageBlock({
    required BuildContext context,
    required Map<String, dynamic> m,
    required String me,
    required String displayImageUrl,
    required ColorScheme cs,
    required bool outgoing,
    required String replyAuthorLabel,
  }) {
    return GestureDetector(
      onTap: () => _openChatImage(
        context,
        m,
        me,
        displayImageUrl,
        replyAuthorLabel: replyAuthorLabel,
      ),
      child: ChatImageBubble(imageUrl: displayImageUrl, isMe: outgoing),
    );
  }

  Widget _wrapPlaceShareBubbleTap({
    required BuildContext context,
    required ChatPlaceShareParsed? placeShare,
    required bool isDeleted,
    required bool selectingMessages,
    required Widget child,
  }) {
    if (placeShare == null || isDeleted || selectingMessages) {
      return child;
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => unawaited(_openSharedPlace(context, placeShare)),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.me == null) {
      return const Center(child: Text('Нет сессии'));
    }
    final String me = widget.me!;
    final ChatThreadMessagesNotifier? n = widget.messageNotifier;
    if (n == null) {
      return const Center(child: Text('Нет соединения'));
    }
    return ChangeNotifierProvider<ChatThreadMessagesNotifier>.value(
      value: n,
      child: Builder(
        builder: (BuildContext context) {
          final Object? err = context
              .select<ChatThreadMessagesNotifier, Object?>((nn) => nn.error);
          final bool init = context.select<ChatThreadMessagesNotifier, bool>(
            (nn) => nn.initialLoading,
          );
          if (err != null) {
            return Center(child: Text('Ошибка: $err'));
          }
          if (init) {
            return const Center(child: CircularProgressIndicator());
          }
          return Selector<ChatThreadMessagesNotifier, (int, bool)>(
            selector: (_, nn) => (nn.messageCount, nn.loadingOlder),
            builder: (BuildContext c, (int, bool) t, _) {
              final int count = t.$1;
              final bool loadingOlder = t.$2;
              if (count == 0) {
                final ColorScheme ecs = Theme.of(c).colorScheme;
                return Center(
                  child: Text(
                    'Пока нет сообщений',
                    style: TextStyle(color: ecs.onSurfaceVariant),
                  ),
                );
              }
              final ChatThreadMessagesNotifier nn = c
                  .read<ChatThreadMessagesNotifier>();
              _maybeReportRowsForForward(nn.orderedMessageRows);
              _maybeInitScrollToBottom();
              final String? firstId = nn.firstMessageId;
              final String? lastId = nn.lastMessageId;
              final String sig = '$count|$firstId|$lastId';
              if (sig != _dataSig) {
                _dataSig = sig;
                _scheduleOnStreamChanged();
              }
              if (widget.isGroup) {
                final Set<String> ids = <String>{};
                for (int j = 0; j < count; j++) {
                  final String id = nn.messageIdAtIndex(j);
                  final String? s = nn
                      .messageById(id)?['sender_id']
                      ?.toString();
                  if (s != null) {
                    ids.add(s);
                  }
                }
                ChatUserProfileCache.I.prefetch(ids);
              }
              final ColorScheme cs = Theme.of(c).colorScheme;
              final bool isDark = Theme.of(c).brightness == Brightness.dark;
              return ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                cacheExtent: 900,
                addRepaintBoundaries: false,
                itemCount: count + (loadingOlder ? 1 : 0),
                itemBuilder: (BuildContext context, int i) {
                  if (loadingOlder && i == 0) {
                    return const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    );
                  }
                  final int idx = loadingOlder ? i - 1 : i;
                  final String messageId = nn.messageIdAtIndex(idx);
                  return RepaintBoundary(
                    key: ValueKey<String>('chatMsg:$messageId'),
                    child: Selector<ChatThreadMessagesNotifier, int>(
                      shouldRebuild: (int a, int b) => a != b,
                      selector: (_, nnn) => nnn.messageVersion(messageId),
                      builder: (BuildContext context, int _, Widget? child) {
                        final Map<String, dynamic>? m = context
                            .read<ChatThreadMessagesNotifier>()
                            .messageById(messageId);
                        if (m == null) {
                          return const SizedBox.shrink();
                        }
                        final String? sid = m['sender_id']?.toString();
                        final bool mine = sid == me;
                        final bool isDeleted = m['deleted_at'] != null;
                        final String bodyRaw = (m['body'] as String?) ?? '';
                        final String? fwdLabel =
                            (m['forwarded_from_label'] as String?)?.trim();
                        final String? fwdUserId = m['forwarded_from_user_id']
                            ?.toString();
                        final String? imageUrl = !isDeleted
                            ? ChatService.imageUrlFromMessageBody(bodyRaw)
                            : null;
                        final ChatFileMeta? fileMeta = !isDeleted
                            ? ChatService.fileMetaFromMessageBody(bodyRaw)
                            : null;
                        final String? displayImageUrl =
                            imageUrl ??
                            (fileMeta != null && fileMeta.isImage
                                ? fileMeta.url
                                : null);
                        final ChatFileMeta? attachmentMeta =
                            fileMeta != null && !fileMeta.isImage
                            ? fileMeta
                            : null;
                        final ChatPlaceShareParsed? placeShare = !isDeleted
                            ? ChatService.parsePlaceShareBody(bodyRaw)
                            : null;
                        final String? voiceUrl = !isDeleted
                            ? ChatMessage.voicePlayUrlFromRow(m)
                            : null;
                        final int? voiceDurationMs = !isDeleted
                            ? ChatMessage.voiceDurationMsFromRow(m)
                            : null;
                        final String text = isDeleted
                            ? 'Сообщение удалено'
                            : voiceUrl != null
                            ? ''
                            : displayImageUrl != null
                            ? ''
                            : attachmentMeta != null
                            ? attachmentMeta.name
                            : placeShare != null
                            ? ''
                            : bodyRaw;
                        final DateTime? createdAt = _tryParse(
                          m['created_at'] as String?,
                        );
                        final bool incomingUnread =
                            !mine &&
                            !isDeleted &&
                            createdAt != null &&
                            widget.myReadAt != null &&
                            createdAt.isAfter(widget.myReadAt!);
                        final bool myReadByPeer =
                            mine && !isDeleted && createdAt != null
                            ? _peersReadMessage(
                                widget.otherReadByUser,
                                createdAt,
                              )
                            : false;
                        final String? deliveryStatus = m['delivery_status']
                            ?.toString();
                        final bool deliveredMark =
                            deliveryStatus == 'delivered' || myReadByPeer;
                        final Color incomingBubble = isDark
                            ? cs.surfaceContainerHigh
                            : Colors.white;
                        final Color incomingUnreadBubble = isDark
                            ? Color.alphaBlend(
                                kPrimaryBlue.withValues(alpha: 0.18),
                                cs.surfaceContainerHigh,
                              )
                            : const Color(0xFFF0F7FF);
                        final Color deletedBubble = isDark
                            ? cs.surfaceContainerLow
                            : const Color(0xFFE8E8ED);
                        final String? mid = m['id']?.toString();
                        final bool selected =
                            mid != null &&
                            widget.selectingMessages &&
                            widget.selectedMessageIds.contains(mid);

                        if (widget.isGroup &&
                            !mine &&
                            sid != null &&
                            mid != null) {
                          final String gMid = mid;
                          final String gSid = sid;
                          final GlobalKey groupBubbleKey = _bubbleKeys
                              .putIfAbsent(gMid, GlobalKey.new);
                          return KeyedSubtree(
                            key: groupBubbleKey,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: ValueListenableBuilder<Map<String, dynamic>?>(
                                valueListenable: ChatUserProfileCache.I
                                    .listenable(gSid),
                                builder: (BuildContext ctx, Map<String, dynamic>? row, _) {
                                  final GroupChatSenderDisplay sender =
                                      GroupChatSenderDisplay.fromRow(row);
                                  return GestureDetector(
                                    onTap:
                                        widget.selectingMessages && !isDeleted
                                        ? () => widget.onToggleMessageSelection(
                                            gMid,
                                          )
                                        : null,
                                    onLongPress:
                                        widget.selectingMessages || isDeleted
                                        ? null
                                        : () => _showBubbleActionsMenu(
                                            ctx,
                                            m,
                                            me,
                                            displayImageUrl: displayImageUrl,
                                            fileMeta: fileMeta,
                                            replyAuthorLabel:
                                                sender.bubbleLabel,
                                          ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        Material(
                                          color: Colors.transparent,
                                          clipBehavior: Clip.antiAlias,
                                          borderRadius: BorderRadius.circular(
                                            22,
                                          ),
                                          child: InkWell(
                                            onTap: () => _onGroupMemberTap(
                                              ctx,
                                              messageId: gMid,
                                              peerUserId: gSid,
                                              sender: sender,
                                              isDeleted: isDeleted,
                                            ),
                                            child: CircleAvatar(
                                              radius: 18,
                                              backgroundColor: kPrimaryBlue
                                                  .withValues(alpha: 0.22),
                                              child:
                                                  sender.avatarUrl != null &&
                                                      sender
                                                          .avatarUrl!
                                                          .isNotEmpty
                                                  ? CityNetworkImage.avatar(
                                                      context: ctx,
                                                      imageUrl:
                                                          sender.avatarUrl,
                                                      diameter: 36,
                                                    )
                                                  : Text(
                                                      _initialForGroupAvatar(
                                                        sender.bubbleLabel,
                                                      ),
                                                      style: const TextStyle(
                                                        fontSize: 15,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: kPrimaryBlue,
                                                      ),
                                                    ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        _wrapReplySlidable(
                                          mine: false,
                                          isDeleted: isDeleted,
                                          m: m,
                                          replyAuthorLabel: sender.bubbleLabel,
                                          child: ConstrainedBox(
                                            constraints: BoxConstraints(
                                              maxWidth:
                                                  MediaQuery.sizeOf(
                                                    context,
                                                  ).width *
                                                  0.78,
                                            ),
                                            child: Stack(
                                              clipBehavior: Clip.none,
                                              alignment: Alignment.topRight,
                                              children: <Widget>[
                                                Container(
                                                  margin:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 2,
                                                      ),
                                                  padding: EdgeInsets.fromLTRB(
                                                    12,
                                                    8,
                                                    (!widget.selectingMessages &&
                                                            !isDeleted)
                                                        ? 34
                                                        : 12,
                                                    8,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: isDeleted
                                                        ? deletedBubble
                                                        : (incomingUnread
                                                              ? incomingUnreadBubble
                                                              : incomingBubble),
                                                    border:
                                                        widget.selectingMessages &&
                                                            selected
                                                        ? Border.all(
                                                            color: kPrimaryBlue,
                                                            width: 2.5,
                                                          )
                                                        : incomingUnread
                                                        ? const Border(
                                                            left: BorderSide(
                                                              color:
                                                                  kPrimaryBlue,
                                                              width: 3,
                                                            ),
                                                          )
                                                        : null,
                                                    borderRadius:
                                                        const BorderRadius.only(
                                                          topLeft:
                                                              Radius.circular(
                                                                16,
                                                              ),
                                                          topRight:
                                                              Radius.circular(
                                                                16,
                                                              ),
                                                          bottomLeft:
                                                              Radius.circular(
                                                                4,
                                                              ),
                                                          bottomRight:
                                                              Radius.circular(
                                                                16,
                                                              ),
                                                        ),
                                                    boxShadow: <BoxShadow>[
                                                      BoxShadow(
                                                        color:
                                                            const Color(
                                                              0xFF0A0A0A,
                                                            ).withValues(
                                                              alpha: 0.04,
                                                            ),
                                                        blurRadius: 2,
                                                        offset: const Offset(
                                                          0,
                                                          1,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  child: _wrapPlaceShareBubbleTap(
                                                    context: ctx,
                                                    placeShare: placeShare,
                                                    isDeleted: isDeleted,
                                                    selectingMessages: widget
                                                        .selectingMessages,
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: <Widget>[
                                                        if (!isDeleted &&
                                                            fwdLabel != null &&
                                                            fwdLabel.isNotEmpty)
                                                          Padding(
                                                            padding:
                                                                const EdgeInsets.only(
                                                                  bottom: 8,
                                                                ),
                                                            child:
                                                                _ForwardedBubbleHeader(
                                                                  fromLabel:
                                                                      fwdLabel,
                                                                  fromUserId:
                                                                      fwdUserId,
                                                                  outgoing:
                                                                      false,
                                                                ),
                                                          ),
                                                        if (!isDeleted)
                                                          ..._replyPreviewList(
                                                            ctx,
                                                            m,
                                                            false,
                                                          ),
                                                        if (!isDeleted)
                                                          Material(
                                                            color: Colors
                                                                .transparent,
                                                            child: InkWell(
                                                              onTap: () =>
                                                                  _onGroupMemberTap(
                                                                    ctx,
                                                                    messageId:
                                                                        gMid,
                                                                    peerUserId:
                                                                        gSid,
                                                                    sender:
                                                                        sender,
                                                                    isDeleted:
                                                                        isDeleted,
                                                                  ),
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    6,
                                                                  ),
                                                              child: Align(
                                                                alignment: Alignment
                                                                    .centerLeft,
                                                                child: Padding(
                                                                  padding:
                                                                      const EdgeInsets.only(
                                                                        bottom:
                                                                            4,
                                                                      ),
                                                                  child: Text(
                                                                    sender
                                                                        .bubbleLabel,
                                                                    style: TextStyle(
                                                                      color:
                                                                          _groupNickColor(
                                                                            gSid,
                                                                          ),
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w600,
                                                                      fontSize:
                                                                          14,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        if (displayImageUrl !=
                                                                null &&
                                                            !isDeleted)
                                                          _bubbleImageBlock(
                                                            context: context,
                                                            m: m,
                                                            me: me,
                                                            displayImageUrl:
                                                                displayImageUrl,
                                                            cs: cs,
                                                            outgoing: false,
                                                            replyAuthorLabel:
                                                                sender
                                                                    .bubbleLabel,
                                                          )
                                                        else if (voiceUrl !=
                                                                null &&
                                                            !isDeleted)
                                                          ChatVoiceMessageBubble(
                                                            playUrl: voiceUrl,
                                                            durationMs:
                                                                voiceDurationMs,
                                                            outgoing: false,
                                                            incomingUnread:
                                                                incomingUnread,
                                                          )
                                                        else if (placeShare !=
                                                                null &&
                                                            !isDeleted)
                                                          ChatPlaceShareCard(
                                                            share: placeShare,
                                                            outgoing: false,
                                                            cs: cs,
                                                            incomingUnread:
                                                                incomingUnread,
                                                          )
                                                        else if (attachmentMeta !=
                                                                null &&
                                                            !isDeleted)
                                                          Row(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: <Widget>[
                                                              Icon(
                                                                attachmentMeta
                                                                        .isVideo
                                                                    ? Icons
                                                                          .play_circle_outline
                                                                    : Icons
                                                                          .insert_drive_file_outlined,
                                                                color: cs
                                                                    .onSurface,
                                                                size: 28,
                                                              ),
                                                              const SizedBox(
                                                                width: 8,
                                                              ),
                                                              ConstrainedBox(
                                                                constraints: BoxConstraints(
                                                                  maxWidth:
                                                                      MediaQuery.sizeOf(
                                                                        context,
                                                                      ).width *
                                                                      0.5,
                                                                ),
                                                                child: Text(
                                                                  attachmentMeta
                                                                      .name,
                                                                  maxLines: 3,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                  style: TextStyle(
                                                                    color: cs
                                                                        .onSurface,
                                                                    fontSize:
                                                                        15,
                                                                    fontWeight:
                                                                        incomingUnread
                                                                        ? FontWeight
                                                                              .w600
                                                                        : null,
                                                                    height:
                                                                        1.35,
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          )
                                                        else if (text
                                                            .isNotEmpty)
                                                          Text(
                                                            text,
                                                            textAlign:
                                                                TextAlign.left,
                                                            style: TextStyle(
                                                              color: isDeleted
                                                                  ? cs.onSurfaceVariant
                                                                  : cs.onSurface,
                                                              fontSize: 15,
                                                              fontWeight:
                                                                  incomingUnread
                                                                  ? FontWeight
                                                                        .w600
                                                                  : null,
                                                              fontStyle:
                                                                  isDeleted
                                                                  ? FontStyle
                                                                        .italic
                                                                  : null,
                                                              height: 1.35,
                                                            ),
                                                          ),
                                                        if (displayImageUrl !=
                                                                null &&
                                                            !isDeleted)
                                                          const SizedBox(
                                                            height: 4,
                                                          )
                                                        else
                                                          const SizedBox(
                                                            height: 2,
                                                          ),
                                                        Align(
                                                          alignment: Alignment
                                                              .centerRight,
                                                          child: Row(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: <Widget>[
                                                              Text(
                                                                widget.timeLabel(
                                                                  m['created_at']
                                                                      as String?,
                                                                ),
                                                                style: TextStyle(
                                                                  color: cs
                                                                      .onSurfaceVariant,
                                                                  fontSize: 11,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                                if (!widget.selectingMessages &&
                                                    !isDeleted)
                                                  Positioned(
                                                    right: 0,
                                                    top: 0,
                                                    child: _bubbleOverflowMenu(
                                                      context: ctx,
                                                      m: m,
                                                      me: me,
                                                      mine: false,
                                                      cs: cs,
                                                      displayImageUrl:
                                                          displayImageUrl,
                                                      fileMeta: fileMeta,
                                                      replyAuthorLabel:
                                                          sender.bubbleLabel,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          );
                        }

                        final GlobalKey? dmKey = mid != null
                            ? _bubbleKeys.putIfAbsent(mid, GlobalKey.new)
                            : null;
                        final String dmAuth = _dmReplyAuthorLabel(mine);
                        final Widget dmBubble = _wrapReplySlidable(
                          mine: mine,
                          isDeleted: isDeleted,
                          m: m,
                          replyAuthorLabel: dmAuth,
                          child: GestureDetector(
                            onTap:
                                !widget.selectingMessages ||
                                    isDeleted ||
                                    mid == null
                                ? null
                                : () => widget.onToggleMessageSelection(mid),
                            onLongPress: widget.selectingMessages || isDeleted
                                ? null
                                : () => _showBubbleActionsMenu(
                                    context,
                                    m,
                                    me,
                                    displayImageUrl: displayImageUrl,
                                    fileMeta: fileMeta,
                                    replyAuthorLabel: dmAuth,
                                  ),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.sizeOf(context).width * 0.82,
                              ),
                              child: Stack(
                                clipBehavior: Clip.none,
                                alignment: mine
                                    ? Alignment.topRight
                                    : Alignment.topLeft,
                                children: <Widget>[
                                  Container(
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 2,
                                    ),
                                    padding: EdgeInsets.fromLTRB(12, 8, 12, 8)
                                        .copyWith(
                                          right:
                                              (!widget.selectingMessages &&
                                                  !isDeleted)
                                              ? 34
                                              : 12,
                                        ),
                                    decoration: BoxDecoration(
                                      color: isDeleted
                                          ? deletedBubble
                                          : (mine
                                                ? kPrimaryBlue
                                                : (incomingUnread
                                                      ? incomingUnreadBubble
                                                      : incomingBubble)),
                                      border:
                                          widget.selectingMessages && selected
                                          ? Border.all(
                                              color: kPrimaryBlue,
                                              width: 2.5,
                                            )
                                          : incomingUnread
                                          ? const Border(
                                              left: BorderSide(
                                                color: kPrimaryBlue,
                                                width: 3,
                                              ),
                                            )
                                          : null,
                                      borderRadius: BorderRadius.only(
                                        topLeft: const Radius.circular(16),
                                        topRight: const Radius.circular(16),
                                        bottomLeft: Radius.circular(
                                          mine ? 16 : 4,
                                        ),
                                        bottomRight: Radius.circular(
                                          mine ? 4 : 16,
                                        ),
                                      ),
                                      boxShadow: <BoxShadow>[
                                        BoxShadow(
                                          color: const Color(
                                            0xFF0A0A0A,
                                          ).withValues(alpha: 0.04),
                                          blurRadius: 2,
                                          offset: const Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                    child: _wrapPlaceShareBubbleTap(
                                      context: context,
                                      placeShare: placeShare,
                                      isDeleted: isDeleted,
                                      selectingMessages:
                                          widget.selectingMessages,
                                      child: Column(
                                        crossAxisAlignment: mine
                                            ? CrossAxisAlignment.end
                                            : CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: <Widget>[
                                          if (!isDeleted &&
                                              fwdLabel != null &&
                                              fwdLabel.isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 8,
                                              ),
                                              child: Align(
                                                alignment: Alignment.centerLeft,
                                                child: _ForwardedBubbleHeader(
                                                  fromLabel: fwdLabel,
                                                  fromUserId: fwdUserId,
                                                  outgoing: mine,
                                                ),
                                              ),
                                            ),
                                          if (!isDeleted)
                                            ..._replyPreviewList(
                                              context,
                                              m,
                                              mine,
                                            ),
                                          if (displayImageUrl != null &&
                                              !isDeleted)
                                            _bubbleImageBlock(
                                              context: context,
                                              m: m,
                                              me: me,
                                              displayImageUrl: displayImageUrl,
                                              cs: cs,
                                              outgoing: mine,
                                              replyAuthorLabel: dmAuth,
                                            )
                                          else if (voiceUrl != null &&
                                              !isDeleted)
                                            ChatVoiceMessageBubble(
                                              playUrl: voiceUrl,
                                              durationMs: voiceDurationMs,
                                              outgoing: mine,
                                              incomingUnread: incomingUnread,
                                            )
                                          else if (placeShare != null &&
                                              !isDeleted)
                                            ChatPlaceShareCard(
                                              share: placeShare,
                                              outgoing: mine,
                                              cs: cs,
                                              incomingUnread: incomingUnread,
                                            )
                                          else if (attachmentMeta != null &&
                                              !isDeleted)
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: <Widget>[
                                                Icon(
                                                  attachmentMeta.isVideo
                                                      ? Icons
                                                            .play_circle_outline
                                                      : Icons
                                                            .insert_drive_file_outlined,
                                                  color: mine
                                                      ? Colors.white
                                                      : cs.onSurface,
                                                  size: 28,
                                                ),
                                                const SizedBox(width: 8),
                                                ConstrainedBox(
                                                  constraints: BoxConstraints(
                                                    maxWidth:
                                                        MediaQuery.sizeOf(
                                                          context,
                                                        ).width *
                                                        0.5,
                                                  ),
                                                  child: Text(
                                                    attachmentMeta.name,
                                                    maxLines: 3,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: mine
                                                          ? Colors.white
                                                          : cs.onSurface,
                                                      fontSize: 15,
                                                      fontWeight: incomingUnread
                                                          ? FontWeight.w600
                                                          : null,
                                                      height: 1.35,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            )
                                          else if (text.isNotEmpty)
                                            Text(
                                              text,
                                              style: TextStyle(
                                                color: isDeleted
                                                    ? cs.onSurfaceVariant
                                                    : (mine
                                                          ? Colors.white
                                                          : cs.onSurface),
                                                fontSize: 15,
                                                fontWeight: incomingUnread
                                                    ? FontWeight.w600
                                                    : null,
                                                fontStyle: isDeleted
                                                    ? FontStyle.italic
                                                    : null,
                                                height: 1.35,
                                              ),
                                            ),
                                          if (displayImageUrl != null &&
                                              !isDeleted)
                                            const SizedBox(height: 4)
                                          else
                                            const SizedBox(height: 2),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            mainAxisAlignment:
                                                MainAxisAlignment.end,
                                            children: <Widget>[
                                              if (mine &&
                                                  !isDeleted) ...<Widget>[
                                                Icon(
                                                  deliveredMark
                                                      ? Icons.done_all
                                                      : Icons.done,
                                                  size: 15,
                                                  color: deliveredMark
                                                      ? const Color(0xFFB3E0FF)
                                                      : Colors.white.withValues(
                                                          alpha: 0.7,
                                                        ),
                                                ),
                                                const SizedBox(width: 4),
                                              ],
                                              Text(
                                                widget.timeLabel(
                                                  m['created_at'] as String?,
                                                ),
                                                style: TextStyle(
                                                  color: mine
                                                      ? Colors.white.withValues(
                                                          alpha: 0.75,
                                                        )
                                                      : cs.onSurfaceVariant,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (!widget.selectingMessages && !isDeleted)
                                    Positioned(
                                      right: mine ? 0 : null,
                                      left: mine ? null : 0,
                                      top: 0,
                                      child: _bubbleOverflowMenu(
                                        context: context,
                                        m: m,
                                        me: me,
                                        mine: mine,
                                        cs: cs,
                                        displayImageUrl: displayImageUrl,
                                        fileMeta: fileMeta,
                                        replyAuthorLabel: dmAuth,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                        return Align(
                          alignment: mine
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: dmKey != null
                              ? KeyedSubtree(key: dmKey, child: dmBubble)
                              : dmBubble,
                        );
                      },
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// Reply line: подписка на [ChatThreadMessagesNotifier.messageVersion] целевого id
/// + однократная догрузка оригинала (reply_snippet — только кэш).
class _ReplyStripWithTarget extends StatefulWidget {
  const _ReplyStripWithTarget({
    required this.messageRow,
    required this.targetMessageId,
    required this.outgoing,
    required this.onStripPressed,
  });

  final Map<String, dynamic> messageRow;
  final String targetMessageId;
  final bool outgoing;
  final VoidCallback onStripPressed;

  @override
  State<_ReplyStripWithTarget> createState() => _ReplyStripWithTargetState();
}

class _ReplyStripWithTargetState extends State<_ReplyStripWithTarget> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final ChatThreadMessagesNotifier n = context
          .read<ChatThreadMessagesNotifier>();
      // ignore: discarded_futures
      n.ensureMessageLoadedForReply(widget.targetMessageId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Selector<ChatThreadMessagesNotifier, int>(
      selector: (_, ChatThreadMessagesNotifier n) =>
          n.messageVersion(widget.targetMessageId),
      builder: (BuildContext context, int _, Widget? child) {
        final Map<String, dynamic>? orig = context
            .read<ChatThreadMessagesNotifier>()
            .messageById(widget.targetMessageId);
        final ChatReplyStripData? data = ChatReplyStripData.fromMessageRow(
          widget.messageRow,
          original: orig,
        );
        if (data == null) {
          return const SizedBox.shrink();
        }
        return ChatMessageReplyStrip(
          data: data,
          outgoing: widget.outgoing,
          onPressed: widget.onStripPressed,
        );
      },
    );
  }
}

class _PendingForwardBanner extends StatelessWidget {
  const _PendingForwardBanner({required this.drafts, required this.onCancel});

  final List<ChatForwardDraft> drafts;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final ChatForwardDraft first = drafts.first;
    final String title = drafts.length == 1
        ? 'Переслать 1 сообщение'
        : 'Переслать ${drafts.length} сообщений';
    final String sub = drafts.length == 1
        ? '${first.originalSenderLabel}: ${first.previewSnippet}'
        : '${first.originalSenderLabel}: ${first.previewSnippet} — и ещё ${drafts.length - 1}…';

    return Material(
      color: cs.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 0, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(Icons.forward_rounded, color: kPrimaryBlue, size: 22),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurfaceVariant,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Отменить пересылку',
              onPressed: onCancel,
            ),
          ],
        ),
      ),
    );
  }
}

class _ForwardedBubbleHeader extends StatelessWidget {
  const _ForwardedBubbleHeader({
    required this.fromLabel,
    required this.outgoing,
    this.fromUserId,
  });

  final String fromLabel;
  final bool outgoing;
  final String? fromUserId;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Color barColor = outgoing
        ? Colors.white.withValues(alpha: 0.95)
        : kPrimaryBlue;
    final Color captionColor = outgoing
        ? Colors.white.withValues(alpha: 0.78)
        : cs.onSurfaceVariant;
    final Color nameColor = outgoing ? Colors.white : kPrimaryBlue;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 3,
          height: 40,
          decoration: BoxDecoration(
            color: barColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Переслано от',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.1,
                  color: captionColor,
                ),
              ),
              const SizedBox(height: 3),
              Row(
                children: <Widget>[
                  if (fromUserId != null && fromUserId!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChatForwardedTinyAvatar(
                        userId: fromUserId!,
                        outgoing: outgoing,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      fromLabel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: nameColor,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Future<void> _openSharedPlace(
  BuildContext context,
  ChatPlaceShareParsed share,
) async {
  String openId = (share.directPlaceId ?? '').trim();
  if (openId.isEmpty) {
    final ChatPlaceShareResolved? r = await ChatPlaceShareResolutionCache.I
        .futureFor(share);
    openId = (r?.placeId ?? '').trim();
  }
  if (!context.mounted || openId.isEmpty) {
    return;
  }
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (BuildContext c) => PlaceDetailScreen(placeId: openId),
    ),
  );
}

DateTime? _tryParse(String? iso) {
  if (iso == null || iso.isEmpty) {
    return null;
  }
  return DateTime.tryParse(iso);
}

/// Хотя бы один собеседник «дочитал» до [msgAt].
bool _peersReadMessage(Map<String, DateTime?> otherReadByUser, DateTime msgAt) {
  if (otherReadByUser.isEmpty) {
    return false;
  }
  for (final DateTime? t in otherReadByUser.values) {
    if (t != null && !t.isBefore(msgAt)) {
      return true;
    }
  }
  return false;
}
