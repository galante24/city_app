import 'dart:async';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_constants.dart';
import '../config/supabase_ready.dart';
import '../utils/image_cache_extent.dart';
import '../models/chat_forward_draft.dart';
import '../models/conversation_list_item.dart';
import '../services/chat_download_share.dart';
import '../services/open_chat_tracker.dart';
import '../services/chat_service.dart';
import '../services/chat_unread_badge.dart';
import '../services/city_data_service.dart';
import 'chat_full_image_viewer_screen.dart';
import 'direct_peer_profile_screen.dart';
import 'forward_conversation_picker_screen.dart';
import 'group_chat_info_screen.dart';

(int, int) _bubbleImageCachePx(BuildContext context) {
  final Size sz = MediaQuery.sizeOf(context);
  return (
    imageCacheExtentPx(context, sz.width * 0.7),
    imageCacheExtentPx(context, sz.height * 0.28),
  );
}

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
  bool _showEmoji = false;
  String _headerTitle = '';
  bool? _isGroup;
  bool? _isOpen;
  String? _myRole;
  String? _peerUserId;
  String? _peerAvatarUrl;
  Timer? _readDebounce;

  /// Курсор «прочитано до» (для стиля входящих + галочек исходящих).
  DateTime? _myReadCursor;
  Map<String, DateTime?> _otherReadByUser = <String, DateTime?>{};

  bool _selectingMessages = false;
  final Set<String> _selectedMessageIds = <String>{};

  /// Актуальная лента (для порядка пересылки); обновляется из [ _MessagesList ] без setState.
  List<Map<String, dynamic>> _messageRowsForForward =
      <Map<String, dynamic>>[];

  List<ChatForwardDraft>? _pendingForwardDrafts;

  /// Цитата для ответа (префикс к тексту при отправке).
  String? _replySnippet;

  final GlobalKey<_MessagesListState> _messagesListKey =
      GlobalKey<_MessagesListState>();

  @override
  void initState() {
    super.initState();
    OpenChatTracker.setOpen(widget.conversationId);
    if (widget.initialForwardDraft != null &&
        widget.initialForwardDraft!.isNotEmpty) {
      _pendingForwardDrafts =
          List<ChatForwardDraft>.from(widget.initialForwardDraft!);
    }
    _headerTitle = widget.title;
    _isGroup = widget.listItem?.isGroup;
    _isOpen = widget.listItem?.isOpen;
    _myRole = widget.listItem?.myRole;
    _loadMeta();
    unawaited(_bootstrapReadState());
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

  void _toggleEmoji() {
    if (_showEmoji) {
      setState(() => _showEmoji = false);
    } else {
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => _showEmoji = true);
    }
  }

  Future<void> _attachImage() async {
    if (_sending || _sendingImage) {
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
      await ChatService.sendImageMessage(widget.conversationId, url);
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
    if (_sending || _sendingImage || _sendingFile) {
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
    final String displayName =
        pf.name.isNotEmpty ? pf.name : (xf.name.isNotEmpty ? xf.name : 'file');
    setState(() => _sendingFile = true);
    try {
      final String url = await CityDataService.uploadChatAttachment(xf);
      await ChatService.sendFileMessage(
        widget.conversationId,
        ChatFileMeta(
          url: url,
          name: displayName,
          mime: _mimeFromFileName(displayName),
        ),
      );
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

  String _snippetFromMessageRow(Map<String, dynamic> m) {
    if (m['deleted_at'] != null) {
      return '';
    }
    final String bodyRaw = (m['body'] as String?) ?? '';
    final String? imageUrl = ChatService.imageUrlFromMessageBody(bodyRaw);
    final ChatFileMeta? fileMeta = ChatService.fileMetaFromMessageBody(bodyRaw);
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return '[Фото]';
    }
    if (fileMeta != null) {
      return fileMeta.isImage ? '[Фото]' : fileMeta.name;
    }
    final String t = bodyRaw.trim();
    if (t.length > 160) {
      return '${t.substring(0, 157)}…';
    }
    return t;
  }

  void _beginReplyTo(Map<String, dynamic> m) {
    final String s = _snippetFromMessageRow(m);
    if (s.isEmpty) {
      return;
    }
    setState(() => _replySnippet = s);
    _inputFocus.requestFocus();
  }

  Future<void> _send() async {
    if (!supabaseAppReady || _sending) {
      return;
    }
    final String t = _input.text.trim();
    final bool hasForward = _pendingForwardDrafts != null &&
        _pendingForwardDrafts!.isNotEmpty;
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
          setState(() => _pendingForwardDrafts = null);
        }
        unawaited(ChatUnreadBadge.refresh());
      }
      if (t.isNotEmpty) {
        String body = t;
        final String? q = _replySnippet?.trim();
        if (q != null && q.isNotEmpty) {
          body = '«$q»\n\n$t';
        }
        await ChatService.sendMessage(widget.conversationId, body);
        _input.clear();
        if (mounted) {
          setState(() => _replySnippet = null);
        }
        unawaited(ChatUnreadBadge.refresh());
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

  Future<String> _displayLabelForUserId(String userId) async {
    final Map<String, dynamic>? row =
        await CityDataService.fetchProfileRow(userId);
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
    final bool deleted = m['deleted_at'] != null;
    if (deleted) {
      return false;
    }
    if (sid == me) {
      return true;
    }
    if (_isGroup == true) {
      return _myRole == 'owner' || _myRole == 'moderator';
    }
    return false;
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нечего пересылать')),
        );
      }
      return;
    }
    if (!mounted) {
      return;
    }
    final ConversationListItem? target =
        await Navigator.of(context).push<ConversationListItem>(
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
      return const Scaffold(body: Center(child: Text('Supabase не настроен')));
    }
    final String? me = Supabase.instance.client.auth.currentUser?.id;
    final bool isGroup = _isGroup == true;
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;
    final Color chatBg =
        isDark ? theme.scaffoldBackgroundColor : const Color(0xFFF0F2F5);
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
                              backgroundColor:
                                  kPrimaryBlue.withValues(alpha: 0.2),
                              backgroundImage: _peerAvatarUrl != null
                                  ? NetworkImage(_peerAvatarUrl!)
                                  : null,
                              child: _peerAvatarUrl == null
                                  ? Text(
                                      _headerTitle.isNotEmpty
                                          ? _headerTitle[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                        color: kPrimaryBlue,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    )
                                  : null,
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
              onPressed:
                  _selectedMessageIds.isEmpty ? null : () => _forwardSelected(),
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
          Expanded(
            child: _MessagesList(
              key: _messagesListKey,
              conversationId: widget.conversationId,
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
              onReply: _beginReplyTo,
            ),
          ),
          if (!_selectingMessages &&
              _replySnippet != null &&
              _replySnippet!.isNotEmpty)
            Material(
              color: cs.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 0, 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child:
                          Icon(Icons.reply_rounded, color: kPrimaryBlue, size: 22),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Ответ',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _replySnippet!,
                            maxLines: 3,
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
                      tooltip: 'Отменить ответ',
                      onPressed: () => setState(() => _replySnippet = null),
                    ),
                  ],
                ),
              ),
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
                    enabled: !_sendingImage && !_sendingFile,
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
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 16,
                      ),
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
                  const SizedBox(width: 2),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
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

class _GroupSenderUi {
  const _GroupSenderUi({
    required this.profileTitle,
    required this.bubbleLabel,
    this.avatarUrl,
  });

  final String profileTitle;
  final String bubbleLabel;
  final String? avatarUrl;
}

class _MessagesList extends StatefulWidget {
  const _MessagesList({
    super.key,
    required this.conversationId,
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
    required this.onReply,
  });

  final String conversationId;
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
  final void Function(Map<String, dynamic> row) onReply;

  @override
  State<_MessagesList> createState() => _MessagesListState();
}

class _MessagesListState extends State<_MessagesList> {
  String? _dataSig;
  String? _rowsReportSig;
  final Map<String, GlobalKey> _bubbleKeys = <String, GlobalKey>{};
  final Map<String, Future<_GroupSenderUi>> _groupSenderFutures =
      <String, Future<_GroupSenderUi>>{};

  /// Прокрутить ленту так, чтобы сообщение [messageId] оказалось в зоне видимости.
  void scrollMessageIntoView(String messageId) {
    final GlobalKey? k = _bubbleKeys[messageId];
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

  Future<_GroupSenderUi> _groupSenderUi(String userId) {
    return _groupSenderFutures.putIfAbsent(
      userId,
      () => _fetchGroupSenderUi(userId),
    );
  }

  Future<_GroupSenderUi> _fetchGroupSenderUi(String userId) async {
    final Map<String, dynamic>? row =
        await CityDataService.fetchProfileRow(userId);
    final String? uname = (row?['username'] as String?)?.trim();
    final String fn = (row?['first_name'] as String?)?.trim() ?? '';
    final String ln = (row?['last_name'] as String?)?.trim() ?? '';
    final String full = ('$fn $ln').trim();
    final String profileTitle = full.isNotEmpty
        ? full
        : (uname != null && uname.isNotEmpty ? '@$uname' : 'Участник');
    final String bubbleLabel = (uname != null && uname.isNotEmpty)
        ? '@$uname'
        : (full.isNotEmpty ? full : 'Участник');
    final String? av = (row?['avatar_url'] as String?)?.trim();
    return _GroupSenderUi(
      profileTitle: profileTitle,
      bubbleLabel: bubbleLabel,
      avatarUrl: (av != null && av.isNotEmpty) ? av : null,
    );
  }

  void _onGroupMemberTap(
    BuildContext context, {
    required String messageId,
    required String peerUserId,
    required _GroupSenderUi sender,
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

  String _replySnippetFor(Map<String, dynamic> m) {
    if (m['deleted_at'] != null) {
      return '';
    }
    final String bodyRaw = (m['body'] as String?) ?? '';
    final String? imageUrl = ChatService.imageUrlFromMessageBody(bodyRaw);
    final ChatFileMeta? fileMeta = ChatService.fileMetaFromMessageBody(bodyRaw);
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return '[Фото]';
    }
    if (fileMeta != null) {
      return fileMeta.isImage ? '[Фото]' : fileMeta.name;
    }
    final String t = bodyRaw.trim();
    if (t.length > 160) {
      return '${t.substring(0, 157)}…';
    }
    return t;
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
    final String shareText =
        _plainTextForShare(m, displayImageUrl, fileMeta);
    final bool canShare = shareText.isNotEmpty;
    final bool canReply = _replySnippetFor(m).isNotEmpty;
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
  }) async {
    final String? mid = m['id']?.toString();
    if (value == 'show') {
      if (mid != null) {
        scrollMessageIntoView(mid);
      }
      return;
    }
    if (value == 'reply') {
      widget.onReply(m);
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
        box.localToGlobal(
          box.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
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
          ),
        );
      }),
    );
  }

  void _openChatImage(
    BuildContext context,
    Map<String, dynamic> m,
    String me,
    String displayImageUrl,
  ) {
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
          onReply: () => widget.onReply(m),
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
  }) {
    final Size mq = MediaQuery.sizeOf(context);
    return GestureDetector(
      onTap: () => _openChatImage(context, m, me, displayImageUrl),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: mq.height * 0.28,
            maxWidth: mq.width * 0.58,
          ),
          child: Builder(
            builder: (BuildContext imgCtx) {
              final (int iw, int ih) = _bubbleImageCachePx(imgCtx);
              return Image.network(
                displayImageUrl,
                fit: BoxFit.contain,
                cacheWidth: iw,
                cacheHeight: ih,
                loadingBuilder: (
                  BuildContext _,
                  Widget child,
                  ImageChunkEvent? loadingProgress,
                ) {
                  if (loadingProgress == null) {
                    return child;
                  }
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  );
                },
                errorBuilder: (
                  BuildContext context,
                  Object error,
                  StackTrace? st,
                ) =>
                    const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('не удалось загрузить фото'),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.me == null) {
      return const Center(child: Text('Нет сессии'));
    }
    final String me = widget.me!;
    final Stream<List<Map<String, dynamic>>>? stream =
        ChatService.watchMessages(widget.conversationId);
    if (stream == null) {
      return const Center(child: Text('Нет соединения'));
    }
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: (BuildContext c, AsyncSnapshot<List<Map<String, dynamic>>> s) {
        if (s.hasError) {
          return Center(child: Text('Ошибка: ${s.error}'));
        }
        if (!s.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final List<Map<String, dynamic>> raw =
            s.data ?? <Map<String, dynamic>>[];
        final List<Map<String, dynamic>> rows =
            ChatService.dedupeChatMessagesById(raw);
        _maybeReportRowsForForward(rows);
        final String sig = rows.isEmpty
            ? '0'
            : '${rows.length}:${rows.last['id']}:${rows.first['id']}';
        if (sig != _dataSig) {
          _dataSig = sig;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.onStreamChanged();
          });
        }
        if (rows.isEmpty) {
          final ColorScheme ecs = Theme.of(context).colorScheme;
          return Center(
            child: Text(
              'Пока нет сообщений',
              style: TextStyle(color: ecs.onSurfaceVariant),
            ),
          );
        }
        final ColorScheme cs = Theme.of(context).colorScheme;
        final bool isDark = Theme.of(context).brightness == Brightness.dark;
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: rows.length,
          itemBuilder: (BuildContext context, int i) {
            final Map<String, dynamic> m = rows[i];
            final String? sid = m['sender_id']?.toString();
            final bool mine = sid == me;
            final bool isDeleted = m['deleted_at'] != null;
            final String bodyRaw = (m['body'] as String?) ?? '';
            final String? fwdLabel =
                (m['forwarded_from_label'] as String?)?.trim();
            final String? fwdUserId =
                m['forwarded_from_user_id']?.toString();
            final String? imageUrl = !isDeleted
                ? ChatService.imageUrlFromMessageBody(bodyRaw)
                : null;
            final ChatFileMeta? fileMeta = !isDeleted
                ? ChatService.fileMetaFromMessageBody(bodyRaw)
                : null;
            final String? displayImageUrl = imageUrl ??
                (fileMeta != null && fileMeta.isImage ? fileMeta.url : null);
            final ChatFileMeta? attachmentMeta =
                fileMeta != null && !fileMeta.isImage ? fileMeta : null;
            final String text = isDeleted
                ? 'Сообщение удалено'
                : displayImageUrl != null
                    ? ''
                    : attachmentMeta != null
                        ? attachmentMeta.name
                        : bodyRaw;
            final DateTime? createdAt = _tryParse(m['created_at'] as String?);
            final bool incomingUnread =
                !mine &&
                !isDeleted &&
                createdAt != null &&
                widget.myReadAt != null &&
                createdAt.isAfter(widget.myReadAt!);
            final bool myReadByPeer = mine && !isDeleted && createdAt != null
                ? _peersReadMessage(widget.otherReadByUser, createdAt)
                : false;
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
            final bool selected = mid != null &&
                widget.selectingMessages &&
                widget.selectedMessageIds.contains(mid);

            if (widget.isGroup && !mine && sid != null && mid != null) {
              final String gMid = mid;
              final String gSid = sid;
              final GlobalKey groupBubbleKey =
                  _bubbleKeys.putIfAbsent(gMid, GlobalKey.new);
              return KeyedSubtree(
                key: groupBubbleKey,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FutureBuilder<_GroupSenderUi>(
                    future: _groupSenderUi(gSid),
                    builder:
                        (BuildContext ctx, AsyncSnapshot<_GroupSenderUi> snap) {
                      final _GroupSenderUi sender = snap.hasData
                          ? snap.data!
                          : const _GroupSenderUi(
                              profileTitle: 'Участник',
                              bubbleLabel: '…',
                            );
                      return GestureDetector(
                        onTap: widget.selectingMessages && !isDeleted
                            ? () => widget.onToggleMessageSelection(gMid)
                            : null,
                        onLongPress: widget.selectingMessages || isDeleted
                            ? null
                            : () => _showBubbleActionsMenu(
                                  ctx,
                                  m,
                                  me,
                                  displayImageUrl: displayImageUrl,
                                  fileMeta: fileMeta,
                                ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Material(
                              color: Colors.transparent,
                              clipBehavior: Clip.antiAlias,
                              borderRadius: BorderRadius.circular(22),
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
                                  backgroundColor:
                                      kPrimaryBlue.withValues(alpha: 0.22),
                                  backgroundImage: sender.avatarUrl != null
                                      ? NetworkImage(sender.avatarUrl!)
                                      : null,
                                  child: sender.avatarUrl == null
                                      ? Text(
                                          _initialForGroupAvatar(
                                            sender.bubbleLabel,
                                          ),
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: kPrimaryBlue,
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.sizeOf(context).width * 0.78,
                              ),
                              child: IntrinsicWidth(
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  alignment: Alignment.topRight,
                                  children: <Widget>[
                                    Container(
                                      margin: const EdgeInsets.symmetric(
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
                                        borderRadius: const BorderRadius.only(
                                          topLeft: Radius.circular(16),
                                          topRight: Radius.circular(16),
                                          bottomLeft: Radius.circular(4),
                                          bottomRight: Radius.circular(16),
                                        ),
                                        boxShadow: <BoxShadow>[
                                          BoxShadow(
                                            color: const Color(0xFF0A0A0A)
                                                .withValues(alpha: 0.04),
                                            blurRadius: 2,
                                            offset: const Offset(0, 1),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: <Widget>[
                                  if (!isDeleted &&
                                      fwdLabel != null &&
                                      fwdLabel.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 8,
                                      ),
                                      child: _ForwardedBubbleHeader(
                                        fromLabel: fwdLabel,
                                        fromUserId: fwdUserId,
                                        outgoing: false,
                                      ),
                                    ),
                                  if (!isDeleted)
                                    Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () => _onGroupMemberTap(
                                          ctx,
                                          messageId: gMid,
                                          peerUserId: gSid,
                                          sender: sender,
                                          isDeleted: isDeleted,
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 4,
                                            ),
                                            child: Text(
                                              sender.bubbleLabel,
                                              style: TextStyle(
                                                color: _groupNickColor(gSid),
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (displayImageUrl != null && !isDeleted)
                                    _bubbleImageBlock(
                                      context: context,
                                      m: m,
                                      me: me,
                                      displayImageUrl: displayImageUrl,
                                      cs: cs,
                                      outgoing: false,
                                    )
                                  else if (attachmentMeta != null &&
                                      !isDeleted)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        Icon(
                                          attachmentMeta.isVideo
                                              ? Icons.play_circle_outline
                                              : Icons
                                                  .insert_drive_file_outlined,
                                          color: cs.onSurface,
                                          size: 28,
                                        ),
                                        const SizedBox(width: 8),
                                        ConstrainedBox(
                                          constraints: BoxConstraints(
                                            maxWidth: MediaQuery.sizeOf(
                                                  context,
                                                ).width *
                                                0.5,
                                          ),
                                          child: Text(
                                            attachmentMeta.name,
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: cs.onSurface,
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
                                      textAlign: TextAlign.left,
                                      style: TextStyle(
                                        color: isDeleted
                                            ? cs.onSurfaceVariant
                                            : cs.onSurface,
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
                                  if (displayImageUrl != null && !isDeleted)
                                    const SizedBox(height: 4)
                                  else
                                    const SizedBox(height: 2),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        Text(
                                          widget.timeLabel(
                                            m['created_at'] as String?,
                                          ),
                                          style: TextStyle(
                                            color: cs.onSurfaceVariant,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                                    ),
                                    if (!widget.selectingMessages && !isDeleted)
                                      Positioned(
                                        right: 0,
                                        top: 0,
                                        child: _bubbleOverflowMenu(
                                          context: ctx,
                                          m: m,
                                          me: me,
                                          mine: false,
                                          cs: cs,
                                          displayImageUrl: displayImageUrl,
                                          fileMeta: fileMeta,
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

            final GlobalKey? dmKey =
                mid != null ? _bubbleKeys.putIfAbsent(mid, GlobalKey.new) : null;
            final Widget dmBubble = GestureDetector(
              onTap: !widget.selectingMessages || isDeleted || mid == null
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
                      ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.82,
                ),
                child: IntrinsicWidth(
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: mine ? Alignment.topRight : Alignment.topLeft,
                    children: <Widget>[
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        padding: EdgeInsets.fromLTRB(
                          12,
                          8,
                          12,
                          8,
                        ).copyWith(
                          right: (!widget.selectingMessages && !isDeleted)
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
                          border: widget.selectingMessages && selected
                              ? Border.all(color: kPrimaryBlue, width: 2.5)
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
                            bottomLeft: Radius.circular(mine ? 16 : 4),
                            bottomRight: Radius.circular(mine ? 4 : 16),
                          ),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: const Color(0xFF0A0A0A)
                                  .withValues(alpha: 0.04),
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
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
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: _ForwardedBubbleHeader(
                                    fromLabel: fwdLabel,
                                    fromUserId: fwdUserId,
                                    outgoing: mine,
                                  ),
                                ),
                              ),
                            if (displayImageUrl != null && !isDeleted)
                              _bubbleImageBlock(
                                context: context,
                                m: m,
                                me: me,
                                displayImageUrl: displayImageUrl,
                                cs: cs,
                                outgoing: mine,
                              )
                            else if (attachmentMeta != null && !isDeleted)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Icon(
                                    attachmentMeta.isVideo
                                        ? Icons.play_circle_outline
                                        : Icons.insert_drive_file_outlined,
                                    color: mine ? Colors.white : cs.onSurface,
                                    size: 28,
                                  ),
                                  const SizedBox(width: 8),
                                  ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: MediaQuery.sizeOf(context)
                                              .width *
                                          0.5,
                                    ),
                                    child: Text(
                                      attachmentMeta.name,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color:
                                            mine ? Colors.white : cs.onSurface,
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
                            if (displayImageUrl != null && !isDeleted)
                              const SizedBox(height: 4)
                            else
                              const SizedBox(height: 2),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: <Widget>[
                                if (mine && !isDeleted) ...<Widget>[
                                  Icon(
                                    myReadByPeer ? Icons.done_all : Icons.done,
                                    size: 15,
                                    color: myReadByPeer
                                        ? const Color(0xFFB3E0FF)
                                        : Colors.white.withValues(alpha: 0.7),
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Text(
                                  widget.timeLabel(m['created_at'] as String?),
                                  style: TextStyle(
                                    color: mine
                                        ? Colors.white.withValues(alpha: 0.75)
                                        : cs.onSurfaceVariant,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ],
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
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
            return Align(
              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
              child: dmKey != null
                  ? KeyedSubtree(key: dmKey, child: dmBubble)
                  : dmBubble,
            );
          },
        );
      },
    );
  }
}

class _PendingForwardBanner extends StatelessWidget {
  const _PendingForwardBanner({
    required this.drafts,
    required this.onCancel,
  });

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
    final Color barColor =
        outgoing ? Colors.white.withValues(alpha: 0.95) : kPrimaryBlue;
    final Color captionColor = outgoing
        ? Colors.white.withValues(alpha: 0.78)
        : cs.onSurfaceVariant;
    final Color nameColor =
        outgoing ? Colors.white : kPrimaryBlue;

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
                      child: _ForwardedTinyAvatar(
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

class _ForwardedTinyAvatar extends StatelessWidget {
  const _ForwardedTinyAvatar({
    required this.userId,
    required this.outgoing,
  });

  final String userId;
  final bool outgoing;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: CityDataService.fetchProfileRow(userId),
      builder: (BuildContext context, AsyncSnapshot<Map<String, dynamic>?> s) {
        final String? url =
            (s.data?['avatar_url'] as String?)?.trim();
        final String fn =
            (s.data?['first_name'] as String?)?.trim() ?? '';
        final String un =
            (s.data?['username'] as String?)?.trim() ?? '';
        final String letter = (fn.isNotEmpty
                ? fn[0]
                : (un.isNotEmpty ? un.replaceAll('@', '')[0] : '?'))
            .toUpperCase();
        return CircleAvatar(
          radius: 11,
          backgroundColor: outgoing
              ? Colors.white.withValues(alpha: 0.25)
              : kPrimaryBlue.withValues(alpha: 0.2),
          backgroundImage:
              url != null && url.isNotEmpty ? NetworkImage(url) : null,
          child: url == null || url.isEmpty
              ? Text(
                  letter,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: outgoing ? Colors.white : kPrimaryBlue,
                  ),
                )
              : null,
        );
      },
    );
  }
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
