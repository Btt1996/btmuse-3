import 'dart:io';

import 'package:dio/dio.dart';

/// Update checking for the Flutter app (Phase 6, item 27).
///
/// Flutter had no update checking at all (zero hits in `flutter_app/lib`);
/// the React web app checks its own served `version.json` via
/// `src/hooks/useAppUpdate.ts`, which does not apply here — the Flutter
/// app is an iOS build, not a served PWA. This service asks GitHub for
/// the latest release of this repo instead:
///
///   GET https://api.github.com/repos/Btt1996/btmuse-3.0/releases/latest
///
/// Honest limits, stated where the UI repeats them:
/// * iOS cannot self-update. There is no install button and never will
///   be one here — an available update means "sideload the new unsigned
///   IPA from the release page". The service returns the release URL so
///   the UI can show/copy it; `url_launcher` is NOT a dependency, so the
///   UI copies the link instead of opening a browser.
/// * A release is never invented. GitHub answers 404 on
///   `/releases/latest` when a repo has no releases, and that maps to
///   [UpdateCheckStatus.noReleases], not to "up to date".
/// * Version comparison is numeric per segment (`2.00` == `2.0.0`;
///   `v` prefix stripped). Pre-release suffixes are ignored for the
///   comparison — a `2.0.1-beta` tag still counts as newer than `2.00`.
/// * No auth token is sent. Unauthenticated GitHub API calls are
///   rate-limited per IP; a 403 therefore surfaces as an error naming
///   the rate limit instead of a fake "up to date".
class UpdateService {
  /// Display version shown in Settings ("Version 2.00") and in the Home
  /// header badge. Must stay in step with `pubspec.yaml` (`2.0.0+30`)
  /// and `settings_screen.dart`.
  static const String currentVersion = '2.00';

  static const String releasesApiUrl =
      'https://api.github.com/repos/Btt1996/btmuse-3.0/releases/latest';

  /// Human-facing releases page, shown/copied by the UI when an update
  /// is available. Never fetched by this service.
  static const String releasesPageUrl =
      'https://github.com/Btt1996/btmuse-3.0/releases';

  final Dio _dio;

  UpdateService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 10),
              ),
            ) {
    // Headers are this service's contract with the GitHub API, so they
    // are applied even when a Dio is injected (tests inject a stubbed
    // Dio and still prove the headers are sent).
    _dio.options.headers['Accept'] = 'application/vnd.github+json';
    _dio.options.headers['User-Agent'] = 'BttMusic/2.00 (iOS; Flutter)';
  }

  /// One update check against the GitHub releases API. Never throws:
  /// every failure mode is a [UpdateCheckResult] with a status and a
  /// human-readable message.
  Future<UpdateCheckResult> checkForUpdates() async {
    try {
      final res = await _dio.getUri(Uri.parse(releasesApiUrl));
      final status = res.statusCode ?? 0;
      if (status == 404) return _noReleases();
      if (status == 403) {
        return _error(
          'GitHub refused the check (HTTP 403 — API rate limit). '
          'Try again later.',
        );
      }
      if (status != 200) {
        return _error('GitHub returned HTTP $status. Try again later.');
      }
      final data = res.data;
      if (data is! Map<String, dynamic>) {
        return _error('GitHub returned an unexpected response. Try again later.');
      }
      return UpdateCheckResult.fromReleaseJson(data);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 404) return _noReleases();
      if (status == 403) {
        return _error(
          'GitHub refused the check (HTTP 403 — API rate limit). '
          'Try again later.',
        );
      }
      if (status != null) {
        return _error('GitHub returned HTTP $status. Try again later.');
      }
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.error is SocketException) {
        return UpdateCheckResult(
          status: UpdateCheckStatus.offline,
          currentVersion: currentVersion,
          errorMessage:
              'You appear to be offline. Connect to the internet to check for updates.',
          checkedAt: DateTime.now(),
        );
      }
      return _error(
        'Could not check for updates: ${e.message ?? e.error ?? e.type}',
      );
    } on FormatException catch (e) {
      return _error('Could not read the GitHub response: ${e.message}');
    } catch (e) {
      return _error('Could not check for updates: $e');
    }
  }

  UpdateCheckResult _noReleases() => UpdateCheckResult(
        status: UpdateCheckStatus.noReleases,
        currentVersion: currentVersion,
        errorMessage:
            'No releases have been published for Btt Music 2.00 yet. '
            'You are running $currentVersion.',
        checkedAt: DateTime.now(),
      );

  UpdateCheckResult _error(String message) => UpdateCheckResult(
        status: UpdateCheckStatus.error,
        currentVersion: currentVersion,
        errorMessage: message,
        checkedAt: DateTime.now(),
      );

  /// Numeric per-segment comparison, same rule as the React
  /// `useAppUpdate` comparator: returns > 0 if [a] is newer than [b],
  /// < 0 if older, 0 if equal. A leading `v` is stripped, missing
  /// segments count as 0 (`2.00` == `2.0.0`), non-numeric suffixes on a
  /// segment are ignored (`2.0.1-beta` > `2.00`).
  static int compareVersions(String a, String b) {
    List<int> parts(String v) => v
        .trim()
        .replaceFirst(RegExp(r'^v'), '')
        .split('.')
        .map((s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
    final pa = parts(a);
    final pb = parts(b);
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final na = i < pa.length ? pa[i] : 0;
      final nb = i < pb.length ? pb[i] : 0;
      if (na > nb) return 1;
      if (na < nb) return -1;
    }
    return 0;
  }
}

enum UpdateCheckStatus {
  upToDate,
  updateAvailable,
  offline,
  error,
  noReleases,
}

class UpdateCheckResult {
  final UpdateCheckStatus status;
  final String currentVersion;

  /// Release tag as published, e.g. `v2.0.1`. Null unless a release was
  /// found (up-to-date and update-available both carry it).
  final String? latestTag;

  /// Release title (`name` field), if the release has one.
  final String? releaseName;

  /// Release notes (`body` field), if the release has any.
  final String? releaseNotes;

  /// Link to the release page (`html_url`), if the release has one.
  final String? releaseUrl;

  /// Human-readable explanation for the offline / error / noReleases
  /// statuses. Null for up-to-date / update-available.
  final String? errorMessage;

  final DateTime checkedAt;

  const UpdateCheckResult({
    required this.status,
    required this.currentVersion,
    this.latestTag,
    this.releaseName,
    this.releaseNotes,
    this.releaseUrl,
    this.errorMessage,
    required this.checkedAt,
  });

  bool get isUpdateAvailable => status == UpdateCheckStatus.updateAvailable;

  /// Parses one `GET /releases/latest` response body. Throws
  /// [FormatException] when the body has no usable `tag_name` — the
  /// caller turns that into an error result, never into an invented
  /// "up to date".
  factory UpdateCheckResult.fromReleaseJson(Map<String, dynamic> json) {
    final tag = json['tag_name'];
    if (tag is! String || tag.trim().isEmpty) {
      throw const FormatException(
        'GitHub release response has no tag_name.',
      );
    }
    final name = json['name'];
    final body = json['body'];
    final htmlUrl = json['html_url'];
    final latestTag = tag.trim();
    final isNewer =
        UpdateService.compareVersions(latestTag, UpdateService.currentVersion) > 0;
    return UpdateCheckResult(
      status: isNewer
          ? UpdateCheckStatus.updateAvailable
          : UpdateCheckStatus.upToDate,
      currentVersion: UpdateService.currentVersion,
      latestTag: latestTag,
      releaseName: name is String && name.trim().isNotEmpty ? name.trim() : null,
      releaseNotes:
          body is String && body.trim().isNotEmpty ? body.trim() : null,
      releaseUrl:
          htmlUrl is String && htmlUrl.trim().isNotEmpty ? htmlUrl.trim() : null,
      checkedAt: DateTime.now(),
    );
  }
}
