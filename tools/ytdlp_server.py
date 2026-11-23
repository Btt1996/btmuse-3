#!/usr/bin/env python3
"""Btt Music 2.00 — reference yt-dlp bridge server.

REFERENCE IMPLEMENTATION ONLY. This file is not part of the app and
is never bundled into the iOS binary. It is the server half of the
optional "Self-hosted bridge" in the Flutter app's YouTube import
sheet (see flutter_app/lib/features/x2/youtube_bridge_service.dart).

How it fits together:
  - The Btt Music iOS app CANNOT run yt-dlp (it is a Python pipeline)
    and must not extract YouTube streams itself.
  - YOU run this server on hardware you control, with your own
    network, and paste its base URL into the app's YouTube import
    sheet. With no bridge URL configured the app does nothing at all.
  - The app POSTs a YouTube URL to /extract; the server downloads
    audio-only with yt-dlp and returns a download_url the phone can
    fetch. The app then imports that audio through the same X2
    validation as any authorized download (content-type, magic bytes,
    size, duration plausibility, SHA-256 dedup).

Contract (implemented by the app in YoutubeBridgeService):
    GET  /health
    200:   {"ok": true, "service": "btmu-ytdlp-bridge"}
    POST /extract
    Body:  {"url": "https://youtube.com/watch?v=..."}
    200:   {"title": "...", "download_url": "https://.../files/<name>.m4a"}
    400:   {"detail": "not a URL"}            (bad request body)
    502:   {"detail": "extraction failed: ..."} (yt-dlp failed)
    other: any non-200 is reported to the user as a server error.

The download_url is built from the request's own base URL and served
from the ./bridge-files directory (or $BTMU_BRIDGE_DIR) via /files, so
it is fetchable by the phone as long as the server is reachable from
it (same LAN, or publicly reachable behind HTTPS).

Run it:
    pip install fastapi uvicorn yt-dlp
    uvicorn ytdlp_server:app --host 0.0.0.0 --port 8000

Then in Btt Music: Import Center -> YouTube -> set the server base URL
(e.g. http://192.168.1.10:8000) and use "Test connection" before
importing anything.

No YouTube Terms of Service claims are made here, and none should be
inferred from this file existing. Responsibilities you keep as the host
operator:
    - Respect YouTube's Terms of Service and applicable law.
    - Only extract content you have the right to download.
    - Keep yt-dlp updated (pip install -U yt-dlp).
    - Secure the server if it is publicly reachable (HTTPS +
      a token / allowlist of your own; the app sends no credentials).
    - The files in the bridge directory accumulate; clean them up.
"""

import os
import pathlib

import yt_dlp
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

OUT_DIR = pathlib.Path(os.environ.get("BTMU_BRIDGE_DIR", "./bridge-files")).resolve()
OUT_DIR.mkdir(parents=True, exist_ok=True)

app = FastAPI(title="Btt Music yt-dlp bridge")
app.mount("/files", StaticFiles(directory=OUT_DIR), name="files")


class ExtractRequest(BaseModel):
    url: str


@app.get("/health")
def health():
    return {"ok": True, "service": "btmu-ytdlp-bridge"}


@app.post("/extract")
def extract(req: ExtractRequest, request: Request):
    url = req.url.strip()
    if not url.startswith(("http://", "https://")):
        raise HTTPException(status_code=400, detail="not a URL")

    options = {
        # Audio only, no video stream, best quality, m4a container.
        "format": "bestaudio[ext=m4a]/bestaudio/best",
        "outtmpl": str(OUT_DIR / "%(title).80s.%(ext)s"),
        "noplaylist": True,
        "quiet": True,
        "no_warnings": True,
    }
    try:
        with yt_dlp.YoutubeDL(options) as ydl:
            info = ydl.extract_info(url, download=True)
            file_path = pathlib.Path(ydl.prepare_filename(info))
    except Exception as exc:  # surfaced to the app as a server error
        return JSONResponse(status_code=502, content={"detail": f"extraction failed: {exc}"})

    if not file_path.exists():
        return JSONResponse(status_code=502, content={"detail": "no file produced"})

    return {
        "title": info.get("title") or file_path.stem,
        "download_url": f"{request.base_url}files/{file_path.name}",
    }
