import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_constants.dart';
import '../config/supabase_ready.dart';
import '../services/city_data_service.dart';

const Color _kPanelBg = Color(0xFFFFFFFF);
const Color _kTextSecondary = Color(0xFF6C6C70);
const Color _kTextPrimary = Color(0xFF1C1C1E);

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  StreamSubscription<AuthState>? _authSub;
  Stream<List<Map<String, dynamic>>>? _ferryStream;
  Stream<List<Map<String, dynamic>>>? _busStream;

  @override
  void initState() {
    super.initState();
    if (supabaseAppReady) {
      _ferryStream = CityDataService.watchFerrySchedule();
      _busStream = CityDataService.watchBusSchedules();
      _authSub = Supabase.instance.client.auth.onAuthStateChange.listen(
        (AuthState data) {
          if (data.event == AuthChangeEvent.signedIn ||
              data.event == AuthChangeEvent.signedOut) {
            if (mounted) {
              setState(() {});
            }
          }
        },
      );
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _showFerryEditDialog(FerryStatusRow ferry) async {
    final statusController = TextEditingController(text: ferry.statusText);
    final timeController = TextEditingController(text: ferry.timeText ?? '');
    if (!context.mounted) {
      return;
    }
    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Паром'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: statusController,
                  decoration: const InputDecoration(
                    labelText: 'Статус',
                    border: OutlineInputBorder(),
                  ),
                  minLines: 1,
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: timeController,
                  decoration: const InputDecoration(
                    labelText: 'Время',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () async {
                if (!CityDataService.isCurrentUserAdminSync()) {
                  return;
                }
                if (statusController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('Введите статус')),
                  );
                  return;
                }
                try {
                  await CityDataService.updateFerryStatus(
                    statusText: statusController.text.trim(),
                    isRunning: ferry.isRunning,
                    timeText: timeController.text,
                  );
                } on Object catch (e) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(content: Text('Сохранение: $e')),
                    );
                  }
                  return;
                }
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop(true);
                }
              },
              child: const Text('Сохранить'),
            ),
          ],
        );
      },
    );
    statusController.dispose();
    timeController.dispose();
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Статус обновлён')),
      );
    }
  }

  List<String> _parseTimesField(String raw) {
    return raw
        .split(RegExp(r'[\n,;]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  Future<void> _showBusDialog({BusScheduleRow? row}) async {
    final routeC = TextEditingController(text: row?.routeNumber ?? '');
    final destC = TextEditingController(text: row?.destination ?? '');
    final timesC = TextEditingController(
      text: row == null
          ? ''
          : row.departureTimes.join(', '),
    );
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: Text(row == null ? 'Новый маршрут' : 'Редактирование маршрута'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: routeC,
                  decoration: const InputDecoration(
                    labelText: 'Номер маршрута',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: destC,
                  decoration: const InputDecoration(
                    labelText: 'Направление',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: timesC,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Время отправлений',
                    border: OutlineInputBorder(),
                    hintText: '08:00, 10:00, 12:00',
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                if (routeC.text.trim().isEmpty || destC.text.trim().isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Заполните маршрут и направление')),
                  );
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Сохранить'),
            ),
          ],
        );
      },
    );
    if (ok != true || !context.mounted) {
      routeC.dispose();
      destC.dispose();
      timesC.dispose();
      return;
    }
    if (!CityDataService.isCurrentUserAdminSync()) {
      routeC.dispose();
      destC.dispose();
      timesC.dispose();
      return;
    }
    final List<String> times = _parseTimesField(timesC.text);
    try {
      if (row == null) {
        await CityDataService.insertBusSchedule(
          routeNumber: routeC.text.trim(),
          destination: destC.text.trim(),
          departureTimes: times,
        );
      } else {
        await CityDataService.updateBusSchedule(
          id: row.id,
          routeNumber: routeC.text.trim(),
          destination: destC.text.trim(),
          departureTimes: times,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Сохранено')),
        );
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
    routeC.dispose();
    destC.dispose();
    timesC.dispose();
  }

  Future<void> _confirmDelete(BusScheduleRow row) async {
    final bool? y = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Удалить маршрут?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Нет'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Да'),
          ),
        ],
      ),
    );
    if (y != true) {
      return;
    }
    try {
      await CityDataService.deleteBusSchedule(row.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Удалено')),
        );
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }

  Widget _ferryStrip({
    required FerryStatusRow? ferry,
    required bool loading,
    required bool isAdmin,
  }) {
    final String text = ferry == null
        ? (loading
            ? 'Загрузка статуса парома...'
            : 'Расписание парома пока не настроено. Обратитесь к администратору.')
        : ferry.statusText;
    final String? timeLine = ferry?.timeText;
    final bool run = ferry == null || ferry.isRunning;
    return Material(
      color: _kPanelBg,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              run ? Icons.directions_boat_filled : Icons.portable_wifi_off,
              color: run ? const Color(0xFF2ECC71) : Colors.orange[800]!,
              size: 30,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Text(
                    'Паром',
                    style: TextStyle(
                      fontSize: 12,
                      color: _kTextSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    text,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _kTextPrimary,
                    ),
                  ),
                  if (timeLine != null && timeLine.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        timeLine,
                        style: const TextStyle(
                          fontSize: 14,
                          color: _kTextSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (isAdmin && ferry != null)
              IconButton(
                onPressed: () => unawaited(_showFerryEditDialog(ferry)),
                icon: const Icon(Icons.edit, color: kPrimaryBlue),
                tooltip: 'Карандаш',
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!supabaseAppReady || _ferryStream == null || _busStream == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Расписание')),
        body: const Center(
          child: Text('Supabase не подключён'),
        ),
      );
    }
    final bool isAdmin = CityDataService.isCurrentUserAdminSync();

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _ferryStream!,
      builder: (BuildContext c, AsyncSnapshot<List<Map<String, dynamic>>> fSnap) {
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _busStream!,
          builder: (BuildContext c, AsyncSnapshot<List<Map<String, dynamic>>> bSnap) {
            final bool fWait = fSnap.connectionState == ConnectionState.waiting &&
                !fSnap.hasData;
            final FerryStatusRow? ferry = fSnap.data != null && fSnap.data!.isNotEmpty
                ? CityDataService.ferryFromScheduleRow(fSnap.data!.first)
                : null;
            final List<BusScheduleRow> buses = (bSnap.data ?? <Map<String, dynamic>>[])
                .map(BusScheduleRow.fromMap)
                .whereType<BusScheduleRow>()
                .toList();
            final bool bWait = bSnap.connectionState == ConnectionState.waiting &&
                !bSnap.hasData;

            return Scaffold(
              backgroundColor: const Color(0xFFF2F2F7),
              appBar: AppBar(
                title: const Text('Расписание'),
                backgroundColor: kPrimaryBlue,
                foregroundColor: Colors.white,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
              ),
              floatingActionButton: isAdmin
                  ? FloatingActionButton(
                      onPressed: () => unawaited(_showBusDialog()),
                      backgroundColor: kPrimaryBlue,
                      foregroundColor: Colors.white,
                      child: const Icon(Icons.add),
                    )
                  : null,
              body: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                children: <Widget>[
                  if (fWait)
                    const LinearProgressIndicator(minHeight: 2),
                  Card(
                    color: _kPanelBg,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: _ferryStrip(
                      ferry: ferry,
                      loading: fWait,
                      isAdmin: isAdmin,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 8),
                    child: Text(
                      'Автобусы',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _kTextPrimary,
                      ),
                    ),
                  ),
                  if (bWait)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (buses.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'Нет маршрутов. Админ может добавить кнопкой +.',
                        ),
                      ),
                    )
                  else
                    ...buses.map(
                      (BusScheduleRow b) => Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              CircleAvatar(
                                backgroundColor: kPrimaryBlue.withValues(alpha: 0.12),
                                child: Text(
                                  b.routeNumber.isNotEmpty
                                      ? b.routeNumber
                                      : '?',
                                  style: const TextStyle(
                                    color: kPrimaryBlue,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      b.destination,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: _kTextPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: b.departureTimes
                                          .map(
                                            (t) => Chip(
                                              label: Text(t),
                                              visualDensity: VisualDensity.compact,
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize.shrinkWrap,
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  ],
                                ),
                              ),
                              if (isAdmin)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    IconButton(
                                      onPressed: () => unawaited(
                                        _showBusDialog(row: b),
                                      ),
                                      icon: const Icon(Icons.edit, color: kPrimaryBlue),
                                      tooltip: 'Изменить',
                                    ),
                                    IconButton(
                                      onPressed: () => unawaited(
                                        _confirmDelete(b),
                                      ),
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: Color(0xFFC62828),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
