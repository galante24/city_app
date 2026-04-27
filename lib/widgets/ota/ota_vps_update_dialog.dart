import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app_constants.dart';
import '../../services/ota/ota_models.dart';
import '../../services/ota/vps_ota_service.dart';

/// Диалог «Доступно обновление» + загрузка + установщик.
Future<void> showOtaVpsUpdateDialog(
  BuildContext context, {
  required String localLabel,
  required int localBuildCode,
  required OtaUpdateManifest manifest,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: OtaForcePolicy.from(
      m: manifest,
      localCode: localBuildCode,
    ).laterOk,
    builder: (BuildContext context) {
      return _OtaVpsUpdateBody(
        localLabel: localLabel,
        localBuildCode: localBuildCode,
        manifest: manifest,
      );
    },
  );
}

class _OtaVpsUpdateBody extends StatefulWidget {
  const _OtaVpsUpdateBody({
    required this.localLabel,
    required this.localBuildCode,
    required this.manifest,
  });

  final String localLabel;
  final int localBuildCode;
  final OtaUpdateManifest manifest;

  @override
  State<_OtaVpsUpdateBody> createState() => _OtaVpsUpdateBodyState();
}

class _OtaVpsUpdateBodyState extends State<_OtaVpsUpdateBody> {
  bool _downloading = false;
  String? _error;
  double? _fraction;
  String _phase = '';

  OtaForcePolicy get _force => OtaForcePolicy.from(
        m: widget.manifest,
        localCode: widget.localBuildCode,
      );

  Future<void> _onUpdate() async {
    setState(() {
      _downloading = true;
      _error = null;
    });
    try {
      await VpsOtaService.downloadVerifyAndOpen(
        manifest: widget.manifest,
        onProgress: (double? f, String status) {
          if (mounted) {
            setState(() {
              _fraction = f;
              _phase = status;
            });
          }
        },
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on OtaException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _downloading = false;
        });
      }
    } catch (e, st) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('OTA download: $e\n$st');
      }
      if (mounted) {
        setState(() {
          _error =
              'Не удалось загрузить или установить обновление. Повторите позже.';
          _downloading = false;
        });
      }
    }
  }

  Future<void> _openSettings() async {
    await openAppSettings();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData t = Theme.of(context);
    final OtaForcePolicy f = _force;
    return PopScope(
      canPop: f.laterOk && !_downloading,
      child: AlertDialog(
        title: const Text('Доступно обновление'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Выпущена новая версия: ${widget.manifest.version} '
                '(сборка ${widget.manifest.versionCode}).\n\n'
                'Ваша версия: ${widget.localLabel}.\n\n'
                '${f.laterOk ? "Рекомендуется обновить приложение." : "Для работы требуется обновить приложение."}',
                style: t.textTheme.bodyMedium,
              ),
              if (widget.manifest.sha256Hex == null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  'В манифесте не задана контрольная сумма; после загрузки целостность не проверяется (кроме проверки подписи ОС).',
                  style: t.textTheme.bodySmall?.copyWith(
                    color: kAppTextSecondary,
                  ),
                ),
              ],
              if (_downloading) ...<Widget>[
                const SizedBox(height: 16),
                if (_fraction != null)
                  LinearProgressIndicator(
                    value: _fraction!,
                    backgroundColor: kAppScaffoldBg,
                    color: kPrimaryBlue,
                  )
                else
                  const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(
                  _phase.isNotEmpty ? _phase : 'Загрузка…',
                  textAlign: TextAlign.center,
                  style: t.textTheme.bodySmall,
                ),
              ],
              if (_error != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: t.textTheme.bodySmall?.copyWith(
                    color: t.colorScheme.error,
                  ),
                ),
                if (_error!.toLowerCase().contains('установк') ||
                    _error!.toLowerCase().contains('unknown') ||
                    _error!.toLowerCase().contains('пакет')) ...<Widget>[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _openSettings,
                    child: const Text('Настройки приложения'),
                  ),
                ],
              ],
            ],
          ),
        ),
        actions: <Widget>[
          if (f.laterOk)
            TextButton(
              onPressed: _downloading
                  ? null
                  : () {
                      Navigator.of(context).pop();
                    },
              child: const Text('Позже'),
            ),
          FilledButton(
            onPressed: _downloading ? null : _onUpdate,
            style: FilledButton.styleFrom(
              backgroundColor: kPrimaryBlue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Обновить'),
          ),
        ],
      ),
    );
  }
}
