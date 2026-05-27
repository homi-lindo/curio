import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lume_core/domain/app_snapshot.dart';
import 'package:lume_core/sync/sync_adapter.dart';

import '../../services/appearance_settings_store.dart';
import '../../services/alarm_settings_store.dart';
import '../../services/local_sync_sidecar.dart';
import '../../services/sync_settings_store.dart';
import '../../theme/curio_theme.dart';
import '../task_view_helpers.dart';
import '../widgets/metric_line.dart';
import '../widgets/page_frame.dart';
import '../widgets/section_header.dart';
import '../widgets/status_pill.dart';
import '../widgets/surface.dart';

final class SyncView extends StatelessWidget {
  const SyncView({
    super.key,
    required this.busy,
    required this.deviceId,
    required this.controller,
    required this.tokenController,
    required this.settings,
    required this.appearance,
    required this.alarmSettings,
    required this.alarmPlaying,
    required this.sidecarSupported,
    required this.sidecarState,
    required this.lastResult,
    required this.snapshot,
    required this.onSave,
    required this.onAppearanceChanged,
    required this.onAlarmSettingsChanged,
    required this.onPickAlarmAudio,
    required this.onClearAlarmAudio,
    required this.onTestAlarmAudio,
    required this.onStopAlarmAudio,
    required this.onExportCalendarIcs,
    required this.onImportCalendarIcs,
    required this.onSync,
    required this.onCopyBackup,
    required this.onRestoreBackup,
    required this.onStartSidecar,
    required this.onStopSidecar,
  });

  final bool busy;
  final String deviceId;
  final TextEditingController controller;
  final TextEditingController tokenController;
  final SyncSettings settings;
  final AppearanceSettings appearance;
  final AlarmSettings alarmSettings;
  final bool alarmPlaying;
  final bool sidecarSupported;
  final LocalSyncSidecarState? sidecarState;
  final SyncResult? lastResult;
  final AppSnapshot snapshot;
  final VoidCallback onSave;
  final ValueChanged<AppearanceSettings> onAppearanceChanged;
  final ValueChanged<AlarmSettings> onAlarmSettingsChanged;
  final VoidCallback onPickAlarmAudio;
  final VoidCallback onClearAlarmAudio;
  final VoidCallback onTestAlarmAudio;
  final VoidCallback onStopAlarmAudio;
  final VoidCallback onExportCalendarIcs;
  final VoidCallback onImportCalendarIcs;
  final VoidCallback onSync;
  final VoidCallback onCopyBackup;
  final VoidCallback onRestoreBackup;
  final VoidCallback onStartSidecar;
  final VoidCallback onStopSidecar;

  @override
  Widget build(BuildContext context) {
    final result = lastResult;
    final lastSyncedAt = settings.lastSyncedAtUtc;
    final sidecarRunning = sidecarState != null;
    final serverHint = kDebugMode
        ? 'http://192.168.0.10:8787'
        : 'https://sync.seu-dominio.com';

    return PageFrame(
      title: 'Sync',
      subtitle: sidecarRunning
          ? 'Servidor local Windows ativo'
          : settings.serverUrl.isEmpty
          ? 'Offline'
          : settings.authToken.isEmpty
          ? 'Token necessário'
          : 'Self-hosted protegido',
      trailing: StatusPill(
        icon: Icons.devices_outlined,
        label: '${snapshot.deletedRecords.length} tombstone(s)',
      ),
      child: Column(
        children: <Widget>[
          _AppearancePanel(
            settings: appearance,
            onChanged: onAppearanceChanged,
          ),
          const SizedBox(height: 14),
          _AlarmPanel(
            settings: alarmSettings,
            playing: alarmPlaying,
            busy: busy,
            onChanged: onAlarmSettingsChanged,
            onPickAudio: onPickAlarmAudio,
            onClearAudio: onClearAlarmAudio,
            onTestAudio: onTestAlarmAudio,
            onStopAudio: onStopAlarmAudio,
          ),
          const SizedBox(height: 14),
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.dns_outlined),
                    labelText: 'Servidor',
                    hintText: serverHint,
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => onSave(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tokenController,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.key_outlined),
                    labelText: 'Token',
                    hintText: 'mesmo token do servidor',
                  ),
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => onSave(),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: busy ? null : onSync,
                      icon: const Icon(Icons.sync_outlined),
                      label: const Text('Sincronizar'),
                    ),
                    OutlinedButton.icon(
                      onPressed: busy ? null : onSave,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Salvar sync'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const SectionHeader(
                  icon: Icons.backup_outlined,
                  title: 'Backup manual TXT',
                ),
                const SizedBox(height: 12),
                Text(
                  'Gera um TXT legível por dia, com bloco de restauração '
                  'para notas e notificações.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: busy ? null : onCopyBackup,
                      icon: const Icon(Icons.copy_all_outlined),
                      label: const Text('Copiar TXT'),
                    ),
                    OutlinedButton.icon(
                      onPressed: busy ? null : onRestoreBackup,
                      icon: const Icon(Icons.restore_page_outlined),
                      label: const Text('Restaurar TXT'),
                    ),
                    OutlinedButton.icon(
                      onPressed: busy ? null : onExportCalendarIcs,
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: const Text('Exportar .ics'),
                    ),
                    OutlinedButton.icon(
                      onPressed: busy ? null : onImportCalendarIcs,
                      icon: const Icon(Icons.event_repeat_outlined),
                      label: const Text('Importar .ics'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                MetricLine('Notas incluídas', snapshot.notes.length.toString()),
                MetricLine(
                  'Notificações incluídas',
                  snapshot.scheduledNotifications.length.toString(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const SectionHeader(
                  icon: Icons.cloud_download_outlined,
                  title: 'Kit self-hosted',
                ),
                const SizedBox(height: 12),
                Text(
                  'Docker/Compose pronto para publicar no GitHub Release.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                const MetricLine('Guia', 'docs/self-hosted-sync.md'),
                const MetricLine('Pacote', 'build/self-hosted'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (sidecarSupported) ...<Widget>[
            Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SectionHeader(
                    icon: Icons.power_outlined,
                    title: 'Servidor local opcional',
                    action: OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : sidecarRunning
                          ? onStopSidecar
                          : onStartSidecar,
                      icon: Icon(
                        sidecarRunning
                            ? Icons.stop_circle_outlined
                            : Icons.power_settings_new_outlined,
                      ),
                      label: Text(sidecarRunning ? 'Parar' : 'Iniciar'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Atalho de teste no Windows: inicia a API de sync dentro do app, sem Docker.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  MetricLine('Servidor', sidecarRunning ? 'Ativo' : 'Parado'),
                  if (sidecarRunning) ...<Widget>[
                    MetricLine('Local', sidecarState!.localUrl),
                    MetricLine(
                      'LAN',
                      '${sidecarState!.host}:${sidecarState!.port}',
                    ),
                    MetricLine(
                      'Iniciado',
                      formatLocalDateTime(sidecarState!.startedAtUtc),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const SectionHeader(icon: Icons.hub_outlined, title: 'Estado'),
                const SizedBox(height: 12),
                MetricLine('Device', deviceId),
                MetricLine('Notas', snapshot.notes.length.toString()),
                MetricLine(
                  'Notificações',
                  snapshot.scheduledNotifications.length.toString(),
                ),
                MetricLine(
                  'Exclusões',
                  snapshot.deletedRecords.length.toString(),
                ),
                MetricLine(
                  'Proteção',
                  settings.authToken.isEmpty
                      ? 'Token necessário'
                      : 'Token ativo',
                ),
                MetricLine(
                  'Último',
                  lastSyncedAt == null
                      ? 'Nunca'
                      : formatLocalDateTime(lastSyncedAt),
                ),
                if (settings.lastMessage != null)
                  MetricLine('Status', settings.lastMessage!),
              ],
            ),
          ),
          if (result != null) ...<Widget>[
            const SizedBox(height: 14),
            Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const SectionHeader(
                    icon: Icons.receipt_long_outlined,
                    title: 'Última troca',
                  ),
                  const SizedBox(height: 12),
                  MetricLine('Push', result.pushedRecords.toString()),
                  MetricLine('Pull', result.pulledRecords.toString()),
                  MetricLine('Tombstones', result.tombstones.toString()),
                  MetricLine('Fim', formatLocalDateTime(result.finishedAtUtc)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

final class _AppearancePanel extends StatelessWidget {
  const _AppearancePanel({required this.settings, required this.onChanged});

  final AppearanceSettings settings;
  final ValueChanged<AppearanceSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionHeader(icon: Icons.palette_outlined, title: 'Aparência'),
          const SizedBox(height: 14),
          _SegmentedControlRow<ThemeMode>(
            label: 'Modo',
            segments: const <ButtonSegment<ThemeMode>>[
              ButtonSegment<ThemeMode>(
                value: ThemeMode.system,
                icon: Icon(Icons.brightness_auto_outlined),
                label: Text('Sistema'),
              ),
              ButtonSegment<ThemeMode>(
                value: ThemeMode.light,
                icon: Icon(Icons.light_mode_outlined),
                label: Text('Claro'),
              ),
              ButtonSegment<ThemeMode>(
                value: ThemeMode.dark,
                icon: Icon(Icons.dark_mode_outlined),
                label: Text('Escuro'),
              ),
            ],
            selected: settings.themeMode,
            onChanged: (themeMode) {
              onChanged(settings.copyWith(themeMode: themeMode));
            },
          ),
          const SizedBox(height: 12),
          _SegmentedControlRow<CurioThemeProfile>(
            label: 'Tema',
            segments: const <ButtonSegment<CurioThemeProfile>>[
              ButtonSegment<CurioThemeProfile>(
                value: CurioThemeProfile.aurora,
                icon: Icon(Icons.wb_twilight_outlined),
                label: Text('Aurora'),
              ),
              ButtonSegment<CurioThemeProfile>(
                value: CurioThemeProfile.slate,
                icon: Icon(Icons.terminal_outlined),
                label: Text('Slate'),
              ),
              ButtonSegment<CurioThemeProfile>(
                value: CurioThemeProfile.lumen,
                icon: Icon(Icons.auto_awesome_outlined),
                label: Text('Lumen'),
              ),
            ],
            selected: settings.themeProfile,
            onChanged: (themeProfile) {
              onChanged(settings.copyWith(themeProfile: themeProfile));
            },
          ),
        ],
      ),
    );
  }
}

final class _AlarmPanel extends StatelessWidget {
  const _AlarmPanel({
    required this.settings,
    required this.playing,
    required this.busy,
    required this.onChanged,
    required this.onPickAudio,
    required this.onClearAudio,
    required this.onTestAudio,
    required this.onStopAudio,
  });

  final AlarmSettings settings;
  final bool playing;
  final bool busy;
  final ValueChanged<AlarmSettings> onChanged;
  final VoidCallback onPickAudio;
  final VoidCallback onClearAudio;
  final VoidCallback onTestAudio;
  final VoidCallback onStopAudio;

  @override
  Widget build(BuildContext context) {
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(
            icon: Icons.alarm_on_outlined,
            title: 'Alarmes',
            action: playing
                ? FilledButton.tonalIcon(
                    onPressed: busy ? null : onStopAudio,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Parar som'),
                  )
                : null,
          ),
          const SizedBox(height: 14),
          _SegmentedControlRow<AlarmSoundSource>(
            label: 'Áudio',
            segments: const <ButtonSegment<AlarmSoundSource>>[
              ButtonSegment<AlarmSoundSource>(
                value: AlarmSoundSource.system,
                icon: Icon(Icons.volume_up_outlined),
                label: Text('Sistema'),
              ),
              ButtonSegment<AlarmSoundSource>(
                value: AlarmSoundSource.custom,
                icon: Icon(Icons.library_music_outlined),
                label: Text('Arquivo'),
              ),
            ],
            selected: settings.soundSource,
            onChanged: (source) =>
                onChanged(settings.copyWith(soundSource: source)),
          ),
          const SizedBox(height: 12),
          MetricLine('Atual', settings.label),
          MetricLine('Formatos', alarmAudioExtensionsLabel),
          const SizedBox(height: 12),
          Text(
            'O toque contínuo funciona enquanto o Curió está aberto ou iniciado '
            'com o Windows. Se o app estiver fechado, fica valendo o alarme do sistema.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              FilledButton.tonalIcon(
                onPressed: busy ? null : onPickAudio,
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Escolher áudio'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : onTestAudio,
                icon: const Icon(Icons.play_arrow_outlined),
                label: const Text('Testar'),
              ),
              OutlinedButton.icon(
                onPressed: busy || !settings.hasCustomAudio
                    ? null
                    : onClearAudio,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remover áudio'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

final class _SegmentedControlRow<T> extends StatelessWidget {
  const _SegmentedControlRow({
    required this.label,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final List<ButtonSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 560;
        final control = SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<T>(
            showSelectedIcon: false,
            segments: segments,
            selected: <T>{selected},
            onSelectionChanged: (values) => onChanged(values.single),
          ),
        );

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              control,
            ],
          );
        }

        return Row(
          children: <Widget>[
            SizedBox(
              width: 92,
              child: Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            Expanded(child: control),
          ],
        );
      },
    );
  }
}
