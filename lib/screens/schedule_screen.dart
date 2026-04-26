import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_constants.dart';
import '../config/supabase_ready.dart';
import '../schedule/lesosibirsk_bus_widgets.dart';
import '../services/city_data_service.dart';
import '../widgets/soft_tab_header.dart';

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
    if (!supabaseAppReady || _ferryStream == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F5F7),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SoftTabHeader(
              title: 'Расписание',
              trailing: Icon(
                Icons.directions_bus_filled_rounded,
                size: 28,
                color: kSoftHeaderActionIconColor,
              ),
            ),
            const Expanded(
              child: Center(child: Text('Supabase не подключён')),
            ),
          ],
        ),
      );
    }
    final bool isAdmin = CityDataService.isCurrentUserAdminSync();

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _ferryStream!,
      builder: (BuildContext c, AsyncSnapshot<List<Map<String, dynamic>>> fSnap) {
        final bool fWait =
            fSnap.connectionState == ConnectionState.waiting && !fSnap.hasData;
        final FerryStatusRow? ferry = fSnap.data != null && fSnap.data!.isNotEmpty
            ? CityDataService.ferryFromScheduleRow(fSnap.data!.first)
            : null;

        return Scaffold(
          backgroundColor: const Color(0xFFF5F5F7),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SoftTabHeader(
                title: 'Расписание',
                trailing: Icon(
                  Icons.directions_bus_filled_rounded,
                  size: 28,
                  color: kSoftHeaderActionIconColor,
                ),
              ),
              if (fWait) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                  children: <Widget>[
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
