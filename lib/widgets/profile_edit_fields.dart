import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_constants.dart';
import '../services/chat_service.dart';
import '../services/city_data_service.dart';
import '../utils/phone_normalize.dart';
import 'settings_tablet_card.dart';

class NickBlock extends StatelessWidget {
  const NickBlock({
    super.key,
    required this.username,
    required this.userId,
    required this.profileReload,
    required this.initialForEdit,
    required this.onSaved,
  });

  final String username;
  final String userId;
  final int profileReload;
  final String? initialForEdit;
  final VoidCallback onSaved;

  Future<void> _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Скопировано в буфер')));
    }
  }

  Future<void> _share(String text) async {
    await Share.share('Мой ник в чате: $text', subject: 'Ник');
  }

  @override
  Widget build(BuildContext context) {
    final String at = username.isEmpty ? '—' : '@$username';
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Color sub = cs.onSurfaceVariant;
    final Color val = cs.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LayoutBuilder(
          builder: (BuildContext c, BoxConstraints b) {
            final bool narrow = b.maxWidth < 420;
            final Widget valueRow = Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (username.isNotEmpty) ...<Widget>[
                  IconButton(
                    tooltip: 'Скопировать',
                    onPressed: () => _copy(c, '@$username'),
                    icon: const Icon(
                      Icons.copy_outlined,
                      size: 22,
                      color: kPrimaryBlue,
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 40,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Поделиться',
                    onPressed: () => _share('@$username'),
                    icon: const Icon(
                      Icons.share_outlined,
                      size: 22,
                      color: kPrimaryBlue,
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 40,
                    ),
                  ),
                ],
              ],
            );
            final Widget nik = SelectableText(
              at,
              maxLines: 1,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: val,
              ),
            );
            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Ник в чате',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: sub,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Латиница, цифры и _; 3–32 символа. Виден всем в чатах.',
                    style: TextStyle(fontSize: 12, color: sub, height: 1.2),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Expanded(child: nik),
                      valueRow,
                    ],
                  ),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Ник в чате',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: sub,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Латиница, цифры и _; 3–32 символа. Виден всем в чатах.',
                        style: TextStyle(fontSize: 12, color: sub, height: 1.2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      Flexible(child: nik),
                      IconButton(
                        tooltip: 'Скопировать',
                        onPressed: username.isEmpty
                            ? null
                            : () => _copy(context, '@$username'),
                        icon: const Icon(
                          Icons.copy_outlined,
                          size: 22,
                          color: kPrimaryBlue,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      IconButton(
                        tooltip: 'Поделиться',
                        onPressed: username.isEmpty
                            ? null
                            : () => _share('@$username'),
                        icon: const Icon(
                          Icons.share_outlined,
                          size: 22,
                          color: kPrimaryBlue,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        Text(
          'Изменить ник',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: sub,
          ),
        ),
        const SizedBox(height: 6),
        ProfileUsername(
          key: ValueKey<String>(
            '${initialForEdit ?? ''}_${userId}_$profileReload',
          ),
          initial: initialForEdit,
          onSaved: onSaved,
        ),
      ],
    );
  }
}

/// Короткий текст «О себе» в [profiles.about] — виден собеседнику в профиле личного чата.
class AboutBlock extends StatelessWidget {
  const AboutBlock({
    super.key,
    required this.initialAbout,
    required this.onSaved,
  });

  final String? initialAbout;
  final VoidCallback onSaved;

  Future<void> _edit(BuildContext context) async {
    final TextEditingController controller = TextEditingController(
      text: (initialAbout ?? '').trim(),
    );
    try {
      final bool? ok = await showDialog<bool>(
        context: context,
        builder: (BuildContext ctx) {
          final double maxH = MediaQuery.sizeOf(ctx).height * 0.72;
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(ctx).bottom,
            ),
            child: AlertDialog(
              title: const Text('О себе'),
              content: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 520, maxHeight: maxH),
                child: SingleChildScrollView(
                  child: TextField(
                    controller: controller,
                    minLines: 4,
                    maxLines: 10,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      hintText: 'Коротко о себе — видно в профиле в чатах',
                      alignLabelWithHint: true,
                      contentPadding: EdgeInsets.all(16),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Отмена'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Сохранить'),
                ),
              ],
            ),
          );
        },
      );
      if (ok != true || !context.mounted) {
        return;
      }
      await CityDataService.setMyAbout(controller.text);
      onSaved();
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(CityDataService.messageForAboutSaveFailure(e)),
          ),
        );
      }
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Color sub = cs.onSurfaceVariant;
    final String display = (initialAbout ?? '').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'О себе',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: sub,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Текст показывается в карточке профиля при личной переписке.',
          style: TextStyle(fontSize: 12, color: sub, height: 1.2),
        ),
        const SizedBox(height: 10),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            display.isEmpty ? 'Не заполнено' : display,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: display.isEmpty ? sub : cs.onSurface,
              fontSize: 16,
              height: 1.35,
            ),
          ),
          trailing: IconButton(
            tooltip: 'Изменить',
            onPressed: () => _edit(context),
            icon: const Icon(Icons.edit_outlined, color: kPrimaryBlue),
          ),
        ),
      ],
    );
  }
}

class PhoneBlock extends StatelessWidget {
  const PhoneBlock({
    super.key,
    required this.phoneDisplay,
    required this.userId,
    required this.profileReload,
    required this.initialForEdit,
    required this.onSaved,
  });

  final String phoneDisplay;
  final String userId;
  final int profileReload;
  final String? initialForEdit;
  final VoidCallback onSaved;

  Future<void> _copy(BuildContext context, String text) async {
    if (text.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Номер скопирован')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final String display = phoneDisplay.isEmpty ? 'не указан' : phoneDisplay;
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Color sub = cs.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LayoutBuilder(
          builder: (BuildContext c, BoxConstraints b) {
            final bool narrow = b.maxWidth < 420;
            final TextStyle valueStyle = TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: phoneDisplay.isEmpty ? cs.onSurfaceVariant : cs.onSurface,
            );
            final Widget phone = SelectableText(
              display,
              maxLines: 1,
              style: valueStyle,
            );
            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Телефон',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: sub,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Виден только вам. В списке чатов и у других не показывается.',
                    style: TextStyle(fontSize: 12, color: sub, height: 1.2),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Expanded(child: phone),
                      if (phoneDisplay.isNotEmpty)
                        IconButton(
                          tooltip: 'Скопировать',
                          onPressed: () => _copy(c, phoneDisplay),
                          icon: const Icon(
                            Icons.copy_outlined,
                            size: 22,
                            color: kPrimaryBlue,
                          ),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 40,
                            minHeight: 40,
                          ),
                        ),
                    ],
                  ),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Телефон',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: sub,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Виден только вам. В списке чатов и у других не показывается.',
                        style: TextStyle(fontSize: 12, color: sub, height: 1.2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      Flexible(
                        child: SelectableText(
                          display,
                          maxLines: 1,
                          textAlign: TextAlign.end,
                          style: valueStyle,
                        ),
                      ),
                      if (phoneDisplay.isNotEmpty)
                        IconButton(
                          tooltip: 'Скопировать',
                          onPressed: () => _copy(context, phoneDisplay),
                          icon: const Icon(
                            Icons.copy_outlined,
                            size: 22,
                            color: kPrimaryBlue,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        Text(
          'Изменить номер',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: sub,
          ),
        ),
        const SizedBox(height: 6),
        ProfilePhoneE164(
          key: ValueKey<String>(
            'ph_${initialForEdit ?? ''}_$userId$profileReload',
          ),
          initial: initialForEdit,
          onSaved: onSaved,
        ),
      ],
    );
  }
}

class ProfileUsername extends StatefulWidget {
  const ProfileUsername({super.key, this.initial, required this.onSaved});

  final String? initial;
  final VoidCallback onSaved;

  @override
  State<ProfileUsername> createState() => _ProfileUsernameState();
}

class _ProfileUsernameState extends State<ProfileUsername> {
  late TextEditingController _c;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(
      text: widget.initial == null || widget.initial!.isEmpty
          ? ''
          : (widget.initial!.startsWith('@')
                ? widget.initial!
                : '@${widget.initial!}'),
    );
  }

  @override
  void didUpdateWidget(covariant ProfileUsername oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initial != oldWidget.initial) {
      final String want = widget.initial == null || widget.initial!.isEmpty
          ? ''
          : (widget.initial!.startsWith('@')
                ? widget.initial!
                : '@${widget.initial!}');
      if (want != _c.text) {
        _c.text = want;
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String _normalizedInput() {
    String s = _c.text.trim();
    if (s.startsWith('@')) {
      s = s.substring(1);
    }
    return s;
  }

  Future<void> _save() async {
    final String s = _normalizedInput();
    if (s.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() => _saving = true);
      try {
        await ChatService.setMyUsername(null);
        if (mounted) {
          widget.onSaved();
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Ник сброшен')));
        }
      } on PostgrestException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                e.message.isNotEmpty ? e.message : 'Ошибка сохранения ника',
              ),
            ),
          );
        }
      } on Object {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Не удалось сохранить ник. Проверьте сеть и SQL-миграции.',
              ),
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _saving = false);
        }
      }
      return;
    }
    if (!RegExp(r'^[a-z0-9_]{3,32}$').hasMatch(s)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Ник: 3–32 символа, латиница, цифры, подчёркивание _',
            ),
          ),
        );
      }
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _saving = true);
    try {
      await ChatService.setMyUsername(s);
      if (mounted) {
        widget.onSaved();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Ник сохранён')));
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        final String m = e.message;
        final bool taken =
            m.toLowerCase().contains('taken') ||
            m.toLowerCase().contains('username');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              m.isNotEmpty
                  ? (taken ? 'Ник занят, выберите другой' : m)
                  : 'Ошибка сохранения',
            ),
          ),
        );
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось сохранить ник')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  InputDecoration _deco(BuildContext context, String hint) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    if (SettingsTabletFieldScope.borderlessFields(context)) {
      return InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: cs.onSurfaceVariant),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      );
    }
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: cs.onSurfaceVariant),
      filled: true,
      fillColor: isDark ? cs.surfaceContainerHigh : const Color(0xFFF2F2F7),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isDark
              ? cs.outline.withValues(alpha: 0.45)
              : const Color(0xFFE5E5EA),
          width: 1,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kPrimaryBlue, width: 1.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: _c,
            textCapitalization: TextCapitalization.none,
            autocorrect: false,
            keyboardType: TextInputType.text,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: cs.onSurface,
            ),
            decoration: _deco(context, '@nickname'),
            onSubmitted: (_) => _save(),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Сохранить'),
        ),
      ],
    );
  }
}

class ProfilePhoneE164 extends StatefulWidget {
  const ProfilePhoneE164({super.key, this.initial, required this.onSaved});

  final String? initial;
  final VoidCallback onSaved;

  @override
  State<ProfilePhoneE164> createState() => _ProfilePhoneE164State();
}

class _ProfilePhoneE164State extends State<ProfilePhoneE164> {
  late TextEditingController _c;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.initial ?? '');
  }

  @override
  void didUpdateWidget(covariant ProfilePhoneE164 oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initial != oldWidget.initial) {
      _c.text = widget.initial ?? '';
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final String? n = normalizePhoneToE164Ru(_c.text);
    if (n == null && _c.text.trim().isNotEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Введите номер, например +79991234567')),
        );
      }
      return;
    }
    setState(() => _saving = true);
    try {
      await ChatService.setMyPhoneE164(n);
      if (mounted) {
        widget.onSaved();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Телефон сохранён')));
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.message.isNotEmpty
                  ? e.message
                  : 'Не удалось сохранить телефон. Выполните миграцию 009 (RLS) в Supabase.',
            ),
          ),
        );
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Не удалось сохранить. Проверьте сеть и права RLS (миграция 009).',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  InputDecoration _deco(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    if (SettingsTabletFieldScope.borderlessFields(context)) {
      return InputDecoration(
        hintText: '+79991234567',
        hintStyle: TextStyle(color: cs.onSurfaceVariant),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      );
    }
    return InputDecoration(
      hintText: '+79991234567',
      filled: true,
      fillColor: isDark ? cs.surfaceContainerHigh : const Color(0xFFF2F2F7),
      hintStyle: TextStyle(color: cs.onSurfaceVariant),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isDark
              ? cs.outline.withValues(alpha: 0.45)
              : const Color(0xFFE5E5EA),
          width: 1,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kPrimaryBlue, width: 1.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: _c,
            keyboardType: TextInputType.phone,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: cs.onSurface,
            ),
            decoration: _deco(context),
            onSubmitted: (_) => _save(),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Сохранить'),
        ),
      ],
    );
  }
}

class ProfileBirthDate extends StatefulWidget {
  const ProfileBirthDate({super.key, this.initialIso, required this.onSaved});

  final String? initialIso;
  final VoidCallback onSaved;

  @override
  State<ProfileBirthDate> createState() => _ProfileBirthDateState();
}

class _ProfileBirthDateState extends State<ProfileBirthDate> {
  DateTime? _date;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _date = _parseInitial(widget.initialIso);
  }

  @override
  void didUpdateWidget(covariant ProfileBirthDate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialIso != oldWidget.initialIso) {
      _date = _parseInitial(widget.initialIso);
    }
  }

  static DateTime? _parseInitial(String? iso) {
    if (iso == null || iso.isEmpty) {
      return null;
    }
    final String s = iso.length >= 10 ? iso.substring(0, 10) : iso;
    try {
      final List<String> p = s.split('-');
      if (p.length == 3) {
        return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
      }
    } on Object {
      return null;
    }
    return null;
  }

  String _label() {
    if (_date == null) {
      return 'Не выбрана';
    }
    return '${_date!.day.toString().padLeft(2, '0')}.'
        '${_date!.month.toString().padLeft(2, '0')}.'
        '${_date!.year}';
  }

  Future<void> _pick() async {
    final DateTime now = DateTime.now();
    final DateTime? d = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime(now.year - 20, 1, 1),
      firstDate: DateTime(1920, 1, 1),
      lastDate: now,
    );
    if (d != null && mounted) {
      setState(() => _date = d);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await CityDataService.setMyBirthDate(_date);
      if (mounted) {
        widget.onSaved();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Дата рождения сохранена')),
        );
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.message.isNotEmpty
                  ? e.message
                  : 'Нет столбца birth_date — выполните миграцию 009 в Supabase.',
            ),
          ),
        );
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось сохранить дату')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _clear() async {
    setState(() => _date = null);
    setState(() => _saving = true);
    try {
      await CityDataService.setMyBirthDate(null);
      if (mounted) {
        widget.onSaved();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Дата сброшена')));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Не удалось сбросить')));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool inTablet = SettingsTabletFieldScope.borderlessFields(context);
    final Color tileBg = inTablet
        ? Colors.transparent
        : (isDark ? cs.surfaceContainerHigh : const Color(0xFFF2F2F7));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: Material(
                color: tileBg,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: _saving ? null : _pick,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 20,
                          color: cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _label(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            softWrap: true,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_date != null) ...<Widget>[
              const SizedBox(width: 6),
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.secondaryContainer,
                ),
                onPressed: _saving ? null : _clear,
                icon: const Icon(Icons.clear, size: 20),
                tooltip: 'Сбросить',
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Сохранить'),
          ),
        ),
      ],
    );
  }
}
