import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_constants.dart';
import '../config/supabase_ready.dart';
import '../schedule/lesosibirsk_bus_widgets.dart';
import '../services/city_data_service.dart';
import '../widgets/clean_screen_header.dart';
import '../widgets/weather_app_bar_action.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  StreamSubscription<AuthState>? _authSub;
  Stream<List<Map<String, dynamic>>>? _ferryStream;

  @override
  void initState() {
    super.initState();
    if (supabaseAppReady) {
      _ferryStream = CityDataService.watchFerrySchedule();
      _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((
        AuthState data,
      ) {
        if (data.event == AuthChangeEvent.signedIn ||
            data.event == AuthChangeEvent.signedOut) {
          if (mounted) {
            setState(() {});
          }
        }
      });
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
                    ScaffoldMessenger.of(
                      dialogContext,
                    ).showSnackBar(SnackBar(content: Text('Сохранение: $e')));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Статус обновлён')));
    }
  }

  Widget _ferryStrip({
    required FerryStatusRow? ferry,
    required bool loading,
    required bool isAdmin,
  }) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final String text = ferry == null
        ? (loading
              ? 'Загрузка статуса парома...'
              : 'Расписание парома пока не настроено. Обратитесь к администратору.')
        : ferry.statusText;
    final String? timeLine = ferry?.timeText;
    final bool run = ferry == null || ferry.isRunning;
    return Material(
      color: Theme.of(context).colorScheme.surface,
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
                  Text(
                    'Паром',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    text,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  if (timeLine != null && timeLine.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        timeLine,
                        style: TextStyle(
                          fontSize: 14,
                          color: cs.onSurfaceVariant,
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
    if (!supabaseAppReady || _ferryStream == null) {
      return Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            CleanFloatingHeader(
              title: 'Расписание',
              trailing: SoftHeaderWeatherWithAction(
                action: Icon(
                  Icons.directions_bus_filled_rounded,
                  size: 28,
                  color: cleanHeaderIconColor(context),
                ),
              ),
            ),
            const Expanded(child: Center(child: Text('Supabase не подключён'))),
          ],
        ),
      );
    }
    final bool isAdmin = CityDataService.isCurrentUserAdminSync();

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _ferryStream!,
      builder:
          (BuildContext c, AsyncSnapshot<List<Map<String, dynamic>>> fSnap) {
            final bool fWait =
                fSnap.connectionState == ConnectionState.waiting &&
                !fSnap.hasData;
            final FerryStatusRow? ferry =
                fSnap.data != null && fSnap.data!.isNotEmpty
                ? CityDataService.ferryFromScheduleRow(fSnap.data!.first)
                : null;

            return Scaffold(
              extendBodyBehindAppBar: true,
              backgroundColor: Colors.transparent,
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  CleanFloatingHeader(
                    title: 'Расписание',
                    trailing: SoftHeaderWeatherWithAction(
                      action: Icon(
                        Icons.directions_bus_filled_rounded,
                        size: 28,
                        color: cleanHeaderIconColor(context),
                      ),
                    ),
                  ),
                  if (fWait) const LinearProgressIndicator(minHeight: 2),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                      children: <Widget>[
                        Card(
                          color: Theme.of(c).colorScheme.surface,
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
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 8),
                          child: Text(
                            'Автобусы',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                        const LesosibirskBusesSection(),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
    );
  }
}
