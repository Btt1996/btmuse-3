import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:btmu/app/providers/app_providers.dart';
import 'package:btmu/app/theme/btt_theme.dart';
import 'package:btmu/app/widgets/btt_logo_mark.dart';
import 'package:btmu/core/config/x2_config.dart';
import 'package:btmu/features/audio_settings/audio_settings_screen.dart';
import 'package:btmu/features/downloads/download_history_screen.dart';
import 'package:btmu/features/telegram/telegram_screen.dart';
import 'package:btmu/features/x2/clients/x2_connectivity_tester.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final TextEditingController _backendCtrl = TextEditingController();
  final TextEditingController _pipedCtrl = TextEditingController();
  final TextEditingController _invidiousCtrl = TextEditingController();
  final TextEditingController _authTokenCtrl = TextEditingController();

  bool _testingConnectivity = false;
  X2ConnectivityReport? _connectivityReport;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = ref.read(credentialsStoreProvider);
    _backendCtrl.text = await store.getBackendUrl();
    _pipedCtrl.text = await store.getPipedUrlsCsv();
    _invidiousCtrl.text = await store.getInvidiousUrlsCsv();
    _authTokenCtrl.text = (await store.getBackendAuthToken()) ?? '';
    if (mounted) setState(() {});
  }

  Future<void> _saveX2Configuration() async {
    final store = ref.read(credentialsStoreProvider);
    await store.setBackendUrl(_backendCtrl.text);
    await store.setPipedUrlsCsv(_pipedCtrl.text);
    await store.setInvidiousUrlsCsv(_invidiousCtrl.text);
    await store.setBackendAuthToken(_authTokenCtrl.text);

    final updated = X2Config(
      backendUrl: X2Config.normalizeSingleUrl(_backendCtrl.text),
      pipedInstances: X2Config.parseUrlList(_pipedCtrl.text),
      invidiousInstances: X2Config.parseUrlList(_invidiousCtrl.text),
    );
    ref.read(x2ConfigProvider.notifier).state = updated;
    ref.read(apiClientProvider).backendAuthToken = _authTokenCtrl.text.trim();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            updated.isBackendConfigured
                ? 'X2 configuration saved securely.'
                : 'X2 instance configuration saved. X2_BACKEND_URL remains unset (not configured).',
          ),
        ),
      );
    }
  }

  Future<void> _runConnectivityTest() async {
    await _saveX2Configuration();
    setState(() => _testingConnectivity = true);
    try {
      final report = await ref.read(x2ConnectivityTesterProvider).runDiagnostics();
      if (mounted) {
        setState(() => _connectivityReport = report);
      }
    } finally {
      if (mounted) setState(() => _testingConnectivity = false);
    }
  }

  @override
  void dispose() {
    _backendCtrl.dispose();
    _pipedCtrl.dispose();
    _invidiousCtrl.dispose();
    _authTokenCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(storageStatsProvider).valueOrNull;
    final x2Config = ref.watch(x2ConfigProvider);
    final mb = stats == null ? '0.0' : (stats.totalBytes / (1024 * 1024)).toStringAsFixed(1);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: BttColors.bgCard,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: BttColors.borderSubtle),
            ),
            child: Row(
              children: [
                const BttLogoMark(size: 54),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Btt Music (BTmu)', style: Theme.of(context).textTheme.titleLarge),
                      Text(
                        'Version 3.0.0 · com.ahmed.btmu',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      Text(
                        'Developer: Ahmed Taboubi',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            tileColor: BttColors.bgCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            leading: const Icon(Icons.graphic_eq_rounded, color: BttColors.goldAccent),
            title: const Text('Audio Engine & Extreme Boost (300%)'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AudioSettingsScreen()),
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            tileColor: BttColors.bgCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            leading: const Icon(Icons.send_rounded, color: BttColors.greenAccent),
            title: const Text('Telegram Bot Sync'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const TelegramScreen()),
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            tileColor: BttColors.bgCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            leading: const Icon(Icons.downloading_rounded, color: BttColors.cyanAccent),
            title: const Text('Download Queue & History'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const DownloadHistoryScreen()),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  'X2 Backend & Multi-Provider Config',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: x2Config.isBackendConfigured
                      ? BttColors.greenAccent.withValues(alpha: 0.16)
                      : BttColors.warning.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  x2Config.isBackendConfigured ? 'Backend Set' : 'Backend Not Configured',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: x2Config.isBackendConfigured ? BttColors.greenAccent : BttColors.warning,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Audius, Telegram Sync, Direct/RSS URLs, X1 Local Matching, and YouTube/SoundCloud oEmbed work standalone with ZERO keys. Configure optional endpoints below:',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _backendCtrl,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'X2_BACKEND_URL (Deployed Btt Music Server)',
              hintText: 'Leave empty if not deployed (never invented)',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _pipedCtrl,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'PIPED_API_URL (Comma-separated failover URLs)',
              hintText: 'https://pipedapi.example.com,https://piped2.example.com',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _invidiousCtrl,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'INVIDIOUS_API_URL (Comma-separated failover URLs)',
              hintText: 'https://invidious.example.com',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _authTokenCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Optional Backend Auth Token (X-BTT-AUTH, Keychain)',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _saveX2Configuration,
                  child: const Text('Save X2 Config'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _testingConnectivity ? null : _runConnectivityTest,
                  icon: _testingConnectivity
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.network_check_rounded),
                  label: const Text('Test Connectivity'),
                ),
              ),
            ],
          ),
          if (_connectivityReport != null) ...[
            const SizedBox(height: 12),
            _DiagnosticsCard(report: _connectivityReport!),
          ],
          const SizedBox(height: 20),
          ListTile(
            tileColor: BttColors.bgCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            leading: const Icon(Icons.sd_storage_rounded, color: BttColors.textSecondary),
            title: const Text('Offline Storage Footprint'),
            subtitle: Text('${stats?.trackCount ?? 0} tracks · $mb MB stored in App Documents'),
          ),
        ],
      ),
    );
  }
}

class _DiagnosticsCard extends StatelessWidget {
  final X2ConnectivityReport report;

  const _DiagnosticsCard({required this.report});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BttColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BttColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Live Connectivity Report', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _statusRow(
            label: 'X2_BACKEND_URL',
            ok: report.backendConfigured && report.backendReachable,
            detail: report.backendMessage,
          ),
          const SizedBox(height: 6),
          _statusRow(
            label: 'Audius Direct (Zero-Key)',
            ok: report.audiusReachable,
            detail: report.audiusMessage,
          ),
          if (report.pipedProbes.isEmpty) ...[
            const SizedBox(height: 6),
            _statusRow(
              label: 'PIPED_API_URL',
              ok: false,
              detail: 'No Piped instances configured.',
            ),
          ] else
            ...report.pipedProbes.map(
              (p) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _statusRow(
                  label: 'Piped (${Uri.tryParse(p.instanceUrl)?.host ?? p.instanceUrl})',
                  ok: p.available,
                  detail: p.available ? 'Healthy (${p.latencyMs}ms)' : (p.error ?? 'Unavailable'),
                ),
              ),
            ),
          if (report.invidiousProbes.isEmpty) ...[
            const SizedBox(height: 6),
            _statusRow(
              label: 'INVIDIOUS_API_URL',
              ok: false,
              detail: 'No Invidious instances configured.',
            ),
          ] else
            ...report.invidiousProbes.map(
              (p) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _statusRow(
                  label: 'Invidious (${Uri.tryParse(p.instanceUrl)?.host ?? p.instanceUrl})',
                  ok: p.available,
                  detail: p.available ? 'Healthy (${p.latencyMs}ms)' : (p.error ?? 'Unavailable'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusRow({
    required String label,
    required bool ok,
    required String detail,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
          size: 16,
          color: ok ? BttColors.greenAccent : BttColors.warning,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$label: $detail',
            style: const TextStyle(fontSize: 12, color: BttColors.textSecondary),
          ),
        ),
      ],
    );
  }
}
