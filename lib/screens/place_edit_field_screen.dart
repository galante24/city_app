import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_constants.dart';
import '../services/place_service.dart';
import '../utils/place_phone.dart';
import '../widgets/soft_tab_header.dart';
import '../widgets/weather_app_bar_action.dart';

class PlaceEditFieldScreen extends StatefulWidget {
  const PlaceEditFieldScreen({
    super.key,
    required this.placeId,
    required this.title,
    required this.column,
    required this.initialValue,
    required this.label,
    this.maxLines = 8,
  });

  final String placeId;
  final String title;
  final String column;
  final String initialValue;
  final String label;
  final int maxLines;

  @override
  State<PlaceEditFieldScreen> createState() => _PlaceEditFieldScreenState();
}

class _PlaceEditFieldScreenState extends State<PlaceEditFieldScreen> {
  late final TextEditingController _c;
  bool _saving = false;

  bool get _isPhone => widget.column == 'phone';

  @override
  void initState() {
    super.initState();
    if (_isPhone) {
      final String ten =
          PlacePhone.tenDigitNationalFromAny(widget.initialValue);
      _c = TextEditingController(text: PlacePhone.maskTen(ten));
    } else {
      _c = TextEditingController(text: widget.initialValue);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isPhone) {
      final String? stored = PlacePhone.toStoredOrEmpty(_c.text);
      if (stored == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Введите полный номер: +7 и 10 цифр мобильного телефона',
            ),
          ),
        );
        return;
      }
      setState(() => _saving = true);
      try {
        await PlaceService.updatePlace(widget.placeId, <String, dynamic>{
          'phone': stored,
        });
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } on Object catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка: $e')),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _saving = false);
        }
      }
      return;
    }

    setState(() => _saving = true);
    try {
      await PlaceService.updatePlace(widget.placeId, <String, dynamic>{
        widget.column: _c.text.trim(),
      });
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SoftTabHeader(
            leading: const SoftHeaderBackButton(),
            title: widget.title,
            trailing: const SoftHeaderWeatherWithAction(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                Text(
                  widget.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                if (_isPhone)
                  TextField(
                    controller: _c,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.done,
                    maxLines: 1,
                    inputFormatters: <TextInputFormatter>[
                      RuPhoneInputFormatter(),
                    ],
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: '+7 (___) ___-__-__',
                    ),
                  )
                else
                  TextField(
                    controller: _c,
                    maxLines: widget.maxLines,
                    minLines: 3,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: kPrimaryBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Сохранить'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
