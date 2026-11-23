import { NormalizedTrackMetadata, AudioCandidateMatch } from '../../types/playlistImport';

/**
 * QUARANTINED — DO NOT RE-ENABLE WITHOUT A LEGAL AUDIT (Phase 0 item 5).
 *
 * spotDL (https://github.com/spotDL/spotify-downloader) is a Spotify-to-YouTube
 * downloader concept: it resolves a Spotify track, then fetches the matching
 * audio from YouTube (via yt-dlp) and writes an MP3/M4A file. That flow is
 * not lawful for commercial music:
 * - Downloading audio from YouTube violates YouTube's Terms of Service.
 * - Ripping commercial recordings violates Spotify's Terms of Service.
 * - Spotify streams themselves are protected with FairPlay/Widevine DRM;
 *   spotDL never downloads from Spotify directly.
 * The only clearly lawful uses would be Creative Commons, public domain, or
 * user-owned audio — which the app already covers through the Telegram Audio
 * Hub, local file import, and the Jamendo / Internet Archive / FMA open
 * catalogs, without any spotDL bridge.
 *
 * This file is kept (not deleted) so existing importers keep compiling, but
 * every public function is now a no-op that returns an explicit
 * "unavailable — under legal review" result and performs no network request.
 * The previous implementation (health probe + /api/match against a
 * user-hosted Python+FFmpeg microservice) was removed in full. Do not restore
 * it, and do not add a new download path for commercial recordings, until a
 * legal audit explicitly clears it.
 */

export const SPOTDL_BRIDGE_UNAVAILABLE_MESSAGE =
  'spotDL bridge is unavailable — under legal review. Downloading commercial tracks via spotDL/YouTube is not permitted; use the Telegram Audio Hub, local file import, or open catalogs instead.';

export interface SpotDLBridgeStatus {
  isConfigured: boolean;
  isOnline: boolean;
  version?: string;
  errorMessage?: string;
}

export async function checkSpotDLBridgeStatus(
  _bridgeUrl?: string
): Promise<SpotDLBridgeStatus> {
  return {
    isConfigured: false,
    isOnline: false,
    errorMessage: SPOTDL_BRIDGE_UNAVAILABLE_MESSAGE,
  };
}

/**
 * Quarantined: always reports no match. The X2 engine treats a null return as
 * a `no_match` provider attempt and continues with the remaining providers.
 */
export async function searchSpotDLBridge(
  _track: NormalizedTrackMetadata,
  _bridgeUrl?: string
): Promise<AudioCandidateMatch | null> {
  return null;
}
