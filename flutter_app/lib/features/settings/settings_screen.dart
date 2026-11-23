import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:btmu/app/btt_page_route.dart';
import 'package:btmu/app/providers/app_providers.dart';
import 'package:btmu/app/theme/btt_theme.dart';
import 'package:btmu/app/widgets/btt_logo_mark.dart';
import 'package:btmu/core/config/x2_config.dart';
import 'package:btmu/core/services/update_service.dart';
import 'package:btmu/features/audio_settings/audio_settings_screen.dart';
import 'package:btmu/features/backup/backup_screen.dart';
import 'package:btmu/features/downloads/download_history_screen.dart';
import 'package:btmu/features/storage/storage_dashboard.dart';
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
  final TextEditingController _jamendoCtrl = TextEditingController();

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
    _jamendoCtrl.text = await store.getJamendoClientId();
    if (mounted) setState(() {});
  }

  Future<void> _saveX2Configuration() async {
    final store = ref.read(credentialsStoreProvider);
    await store.setBackendUrl(_backendCtrl.text);
    await store.setPipedUrlsCsv(_pipedCtrl.text);
    await store.setInvidiousUrlsCsv(_invidiousCtrl.text);
    await store.setBackendAuthToken(_authTokenCtrl.text);
    await store.setJamendoClientId(_jamendoCtrl.text);

    final updated = X2Config(
      backendUrl: X2Config.normalizeSingleUrl(_backendCtrl.text),
      pipedInstances: X2Config.parseUrlList(_pipedCtrl.text),
      invidiousInstances: X2Config.parseUrlList(_invidiousCtrl.text),
      jamendoClientId: _jamendoCtrl.text.trim(),
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
    _jamendoCtrl.dispose();
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
                      Text('Btmus by Taboubi Ahmed', style: Theme.of(context).textTheme.titleLarge),
                      Text(
                        'Version 2.00 · com.ahmed.btmu',
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
          // Phase 6, item 27 — update-check card. Flutter had no update
          // checking; this card checks GitHub releases via UpdateService.
          // Honest copy throughout: iOS cannot self-update, so an
          // available update is a sideload-the-new-IPA pointer, never a
          // fake install button. Nothing else on this screen changed.
          const _UpdateCheckCard(),
          const SizedBox(height: 16),
          ListTile(
            tileColor: BttColors.bgCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            leading: const Icon(Icons.graphic_eq_rounded, color: BttColors.accentViolet),
            title: const Text('Audio Engine & Extreme Boost (300%)'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              BttPageRoute<void>(builder: (_) => const AudioSettingsScreen()),
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            tileColor: BttColors.bgCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            leading: const Icon(Icons.send_rounded, color: BttColors.accentMagenta),
            title: const Text('Telegram Bot Sync'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              BttPageRoute<void>(builder: (_) => const TelegramScreen()),
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            tileColor: BttColors.bgCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            leading: const Icon(Icons.downloading_rounded, color: BttColors.accentPink),
            title: const Text('Download Queue & History'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              BttPageRoute<void>(builder: (_) => const DownloadHistoryScreen()),
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            tileColor: BttColors.bgCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            leading: const Icon(Icons.backup_rounded, color: BttColors.accentViolet),
            title: const Text('Backup & Restore'),
            subtitle: const Text('Export your library as JSON or restore from a backup'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              BttPageRoute<void>(builder: (_) => const BackupScreen()),
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
                      ? BttColors.success.withValues(alpha: 0.16)
                      : BttColors.warning.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  x2Config.isBackendConfigured ? 'Backend Set' : 'Backend Not Configured',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: x2Config.isBackendConfigured ? BttColors.success : BttColors.warning,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Audius, Internet Archive, Telegram Sync, Direct/RSS URLs, X1 Local Matching, and YouTube/SoundCloud oEmbed work standalone with ZERO keys. Spotify playlist tracklists need the deployed backend below; single Spotify track links resolve via oEmbed, and SoundCloud works by pasting a track URL (no keyword search, no client ID). Jamendo keyword search needs its own client ID below — without it, Jamendo stays off and everything else keeps working. Configure optional endpoints below:',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _backendCtrl,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'X2_BACKEND_URL (Deployed Btmus Server)',
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
          const SizedBox(height: 10),
          TextField(
            controller: _jamendoCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Jamendo client ID (optional, Keychain)',
              hintText: 'From devportal.jamendo.com — only needed for Jamendo search',
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
          // Storage dashboard entry point: the previously static
          // "Offline Storage Footprint" tile is now tappable and opens
          // StorageDashboardScreen (per-source usage + duplicate scan
          // with confirmed-only cleanup). No other tile changed.
          ListTile(
            tileColor: BttColors.bgCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            leading: const Icon(Icons.sd_storage_rounded, color: BttColors.textSecondary),
            title: const Text('Offline Storage Footprint'),
            subtitle: Text(
              '${stats?.trackCount ?? 0} tracks · $mb MB stored in App Documents'
              '${(stats?.duplicateGroupsCount ?? 0) > 0 ? ' · ${stats!.duplicateGroupsCount} duplicate group(s) — tap to review' : ' · tap for breakdown & duplicates'}',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              BttPageRoute<void>(builder: (_) => const StorageDashboardScreen()),
            ),
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
          const SizedBox(height: 6),
          _statusRow(
            label: 'Internet Archive (Zero-Key)',
            ok: report.archiveOrgReachable,
            detail: report.archiveOrgMessage,
          ),
          const SizedBox(height: 6),
          _statusRow(
            label: 'Jamendo',
            ok: report.jamendoReachable,
            detail: report.jamendoMessage,
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
          color: ok ? BttColors.success : BttColors.warning,
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

/// Update-check card (Phase 6, item 27). Checks GitHub releases for
/// Btt Music 2.00 via [UpdateService] and renders every state honestly:
///
/// * up-to-date — current version is the latest release.
/// * update available — latest tag + release notes + the sideload truth:
///   iOS cannot self-update, so the card shows the release link (copy
///   button; `url_launcher` is NOT a dependency) and says to sideload
///   the new unsigned IPA. There is no install button.
/// * offline / error — the reason, with a retry.
/// * no releases yet — GitHub has no releases for the repo; the card
///   says so instead of claiming "up to date".
///
/// The service instance is local: no new provider was added (the
/// providers file is outside this item's scope); a coordinator can move
/// it to a provider later without changing this card's behaviour.
class _UpdateCheckCard extends StatefulWidget {
  const _UpdateCheckCard();

  @override
  State<_UpdateCheckCard> createState() => _UpdateCheckCardState();
}

class _UpdateCheckCardState extends State<_UpdateCheckCard> {
  final UpdateService _service = UpdateService();
  UpdateCheckResult? _result;
  bool _checking = false;

  Future<void> _check() async {
    setState(() => _checking = true);
    try {
      final result = await _service.checkForUpdates();
      if (mounted) setState(() => _result = result);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _copyReleaseLink(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Release link copied.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BttColors.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: BttColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.system_update_rounded, color: BttColors.accentViolet),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'App Updates',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: BttColors.bgCardHighlight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Current ${UpdateService.currentVersion}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_checking) ...[
            const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text('Checking GitHub releases…'),
              ],
            ),
          ] else if (result == null) ...[
            Text(
              'Check whether a newer Btt Music release is published on GitHub.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ] else
            _statusBody(context, result),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _checking ? null : _check,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(
                    result == null ? 'Check for Updates' : 'Check Again',
                  ),
                ),
              ),
              if (result?.status == UpdateCheckStatus.updateAvailable &&
                  result?.releaseUrl != null) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _copyReleaseLink(result!.releaseUrl!),
                    icon: const Icon(Icons.link_rounded, size: 18),
                    label: const Text('Copy Release Link'),
                  ),
                ),
              ],
            ],
          ),
          if (result != null) ...[
            const SizedBox(height: 8),
            Text(
              'Last checked ${_formatCheckedAt(result.checkedAt)}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusBody(BuildContext context, UpdateCheckResult result) {
    switch (result.status) {
      case UpdateCheckStatus.upToDate:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.check_circle_rounded, size: 18, color: BttColors.success),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'You’re up to date — ${result.latestTag ?? result.currentVersion} '
                'is the latest release on GitHub.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        );
      case UpdateCheckStatus.updateAvailable:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.new_releases_rounded, size: 18, color: BttColors.accentPink),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Update available: ${result.latestTag}'
                    '${result.releaseName != null ? ' — ${result.releaseName}' : ''}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'iOS cannot self-update — there is no in-app install. '
              'Sideload the new unsigned IPA from the release page, '
              'the same way this build was installed.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (result.releaseNotes != null) ...[
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 160),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: BttColors.bgCardHighlight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    result.releaseNotes!,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontSize: 12.5),
                  ),
                ),
              ),
            ],
            if (result.releaseUrl != null) ...[
              const SizedBox(height: 8),
              SelectableText(
                result.releaseUrl!,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ],
        );
      case UpdateCheckStatus.offline:
      case UpdateCheckStatus.error:
      case UpdateCheckStatus.noReleases:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded, size: 18, color: BttColors.warning),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                result.errorMessage ?? 'Could not check for updates.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        );
    }
  }

  String _formatCheckedAt(DateTime at) {
    String two(int n) => n.toString().padLeft(2, '0');
    final local = at.toLocal();
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
