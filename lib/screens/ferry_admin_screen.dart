import 'package:flutter/material.dart';

import '../services/city_data_service.dart';

class FerryAdminScreen extends StatefulWidget {
  const FerryAdminScreen({super.key});

  @override
  State<FerryAdminScreen> createState() => _FerryAdminScreenState();
}

class _FerryAdminScreenState extends State<FerryAdminScreen> {
  final _textController = TextEditingController();
  final _timeController = TextEditingController();
  bool _running = true;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  FerryStatusRow? _row;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final FerryStatusRow? row = await CityDataService.fetchFerryStatus();
    if (mounted) {
      setState(() {
        _loading = false;
        _row = row;
        if (row != null) {
          _textController.text = row.statusText;
          _timeController.text = row.timeText ?? '';
          _running = row.isRunning;
        }
      });
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _timeController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_row == null) {
        throw StateError('Нет записи в schedules');
      }
      await CityDataService.updateFerryStatus(
        statusText: _textController.text.trim(),
        isRunning: _running,
        timeText: _timeController.text,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Расписание парома обновлено')),
        );
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
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
      appBar: AppBar(
        title: const Text('Паром — расписание'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: <Widget>[
                const Text(
                  'Текст для блока на главной и индикатор движения',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _textController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Статус (например, ходит по расписанию / задержка)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _timeController,
                  decoration: const InputDecoration(
                    labelText: 'Время (подпись, например ближайший рейс)',
                    border: OutlineInputBorder(),
                    hintText: '12:00 — 12:20',
                  ),
                ),
                const SizedBox(height: 20),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('По расписанию (зелёный индикатор)'),
                  subtitle: const Text('Выключите, если движение остановлено'),
                  value: _running,
                  onChanged: (v) {
                    setState(() => _running = v);
                  },
                ),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: const TextStyle(color: Color(0xFFC62828)),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Сохранить'),
                ),
              ],
            ),
    );
  }
}
