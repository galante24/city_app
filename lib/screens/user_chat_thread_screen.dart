import 'dart:async';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_constants.dart';
import '../config/supabase_ready.dart';
import '../models/conversation_list_item.dart';
import '../services/chat_download_share.dart';
import '../services/open_chat_tracker.dart';
import '../services/chat_service.dart';
import '../services/chat_unread_badge.dart';
import '../services/city_data_service.dart';
import 'direct_peer_profile_screen.dart';
import 'forward_conversation_picker_screen.dart';
import 'group_chat_info_screen.dart';

class UserChatThreadScreen extends StatefulWidget {
  const UserChatThreadScreen({
    super.key,
    required this.conversationId,
    required this.title,
    this.listItem,
    this.directPeerUserId,
  });

  final String conversationId;
  final String title;
  final ConversationListItem? listItem;

  /// Собеседник в личном чате, если экран открыт не из списка (например, из вакансии).
  final String? directPeerUserId;

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

  @override
  void initState() {
    super.initState();
    OpenChatTracker.setOpen(widget.conversationId);
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

  Future<void> _send() async {
    if (!supabaseAppReady) {
      return;
    }
    final String t = _input.text.trim();
    if (t.isEmpty || _sending) {
      return;
    }
    setState(() => _sending = true);
    try {
      await ChatService.sendMessage(widget.conversationId, t);
      _input.clear();
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
    final List<String> bodies = <String>[];
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
      bodies.add(raw);
    }
    if (bodies.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нечего пересылать')),
        );
      }
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
    try {
      await ChatService.forwardMessageBodies(target.id, bodies);
      _exitMessageSelection();
      unawaited(ChatUnreadBadge.refresh());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Переслано в «${target.title}»')),
        );
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось переслать: $e')),
        );
      }
    }
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
              conversationId: widget.conversationId,
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

class _MessagesList extends StatefulWidget {
  const _MessagesList({
    required this.conversationId,
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
  });

  final String conversationId;
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

  @override
  State<_MessagesList> createState() => _MessagesListState();
}

class _MessagesListState extends State<_MessagesList> {
  String? _dataSig;
  String? _rowsReportSig;

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

  void _showMessageActions(
    BuildContext sheetContext,
    Map<String, dynamic> m,
    String me, {
    required String? displayImageUrl,
    required ChatFileMeta? fileMeta,
  }) {
    final bool isDeleted = m['deleted_at'] != null;
    if (isDeleted) {
      return;
    }
    final bool canSave =
        (displayImageUrl != null && displayImageUrl.isNotEmpty) ||
        fileMeta != null;
    final bool canDel = widget.canDeleteMessage(m, me);
    showModalBottomSheet<void>(
      context: sheetContext,
      builder: (BuildContext bc) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.checklist_outlined),
                title: const Text('Выбрать для пересылки'),
                onTap: () {
                  Navigator.pop(bc);
                  widget.onBeginForwardSelection(m['id']!.toString());
                },
              ),
              if (canSave)
                ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('Скачать или поделиться'),
                  onTap: () {
                    Navigator.pop(bc);
                    final String url =
                        displayImageUrl ?? fileMeta?.url ?? '';
                    final String name = fileMeta?.name ??
                        (displayImageUrl != null ? 'image.jpg' : 'file');
                    if (url.isEmpty) {
                      return;
                    }
                    unawaited(
                      shareNetworkFileToDevice(
                        context: sheetContext,
                        url: url,
                        suggestedName: name,
                      ),
                    );
                  },
                ),
              if (canDel)
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline,
                    color: Color(0xFFC62828),
                  ),
                  title: const Text('Удалить сообщение'),
                  onTap: () {
                    Navigator.pop(bc);
                    widget.onDelete(m['id']!.toString());
                  },
                ),
            ],
          ),
        );
      },
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
            return Align(
              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
              child: GestureDetector(
                onTap: widget.selectingMessages && !isDeleted && mid != null
                    ? () => widget.onToggleMessageSelection(mid)
                    : null,
                onLongPress: widget.selectingMessages || isDeleted
                    ? null
                    : () => _showMessageActions(
                          context,
                          m,
                          me,
                          displayImageUrl: displayImageUrl,
                          fileMeta: fileMeta,
                        ),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * 0.82,
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
                        color: const Color(0xFF0A0A0A).withValues(alpha: 0.04),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (displayImageUrl != null && !isDeleted)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight:
                                  MediaQuery.sizeOf(context).height * 0.28,
                              maxWidth: MediaQuery.sizeOf(context).width * 0.7,
                            ),
                            child: Image.network(
                              displayImageUrl,
                              fit: BoxFit.cover,
                              loadingBuilder:
                                  (
                                    BuildContext _,
                                    Widget child,
                                    ImageChunkEvent? loadingProgress,
                                  ) {
                                    if (loadingProgress == null) {
                                      return child;
                                    }
                                    return const Padding(
                                      padding: EdgeInsets.all(24),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    );
                                  },
                              errorBuilder:
                                  (
                                    BuildContext context,
                                    Object error,
                                    StackTrace? st,
                                  ) => const Padding(
                                    padding: EdgeInsets.all(8),
                                    child: Text('не удалось загрузить фото'),
                                  ),
                            ),
                          ),
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
                            Flexible(
                              child: Text(
                                attachmentMeta.name,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: mine ? Colors.white : cs.onSurface,
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
                            fontWeight: incomingUnread ? FontWeight.w600 : null,
                            fontStyle: isDeleted ? FontStyle.italic : null,
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
              ),
            );
          },
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
