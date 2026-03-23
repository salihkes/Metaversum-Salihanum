"""
Minimal STT HTTP server wrapping faster-whisper.

Run separately:  python stt_server.py
Endpoint:        POST /stt
Payload:         {"audio": "<base64 WAV>"}
Response:        {"text": "transcribed text", "language": "en"}
"""

import os
import json
import base64
import io
import tempfile

from http.server import HTTPServer, BaseHTTPRequestHandler

_model = None

STT_HOST = os.environ.get("STT_HOST", "0.0.0.0")
STT_PORT = int(os.environ.get("STT_PORT", "8091"))
STT_MODEL_SIZE = os.environ.get("STT_MODEL_SIZE", "large-v3")
STT_DEVICE = os.environ.get("STT_DEVICE", "auto")
STT_COMPUTE_TYPE = os.environ.get("STT_COMPUTE_TYPE", "int8")


def get_model():
    global _model
    if _model is None:
        print(f"[STT] Loading faster-whisper model: {STT_MODEL_SIZE}...")
        from faster_whisper import WhisperModel
        _model = WhisperModel(STT_MODEL_SIZE, device=STT_DEVICE,
                              compute_type=STT_COMPUTE_TYPE)
        print(f"[STT] Model loaded")
    return _model


def transcribe(wav_bytes: bytes) -> dict:
    """Transcribe WAV audio bytes. Returns {"text": str, "language": str}."""
    model = get_model()

    # Write to temp file (faster-whisper needs a file path)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        f.write(wav_bytes)
        tmp_path = f.name

    # Save a debug copy
    debug_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "stt_debug_last.wav")
    import shutil
    shutil.copy2(tmp_path, debug_path)
    print(f"[STT] Debug WAV saved to: {debug_path}")

    try:
        segments, info = model.transcribe(tmp_path, beam_size=5, language="en")
        text = " ".join(seg.text.strip() for seg in segments)
        return {"text": text.strip(), "language": info.language}
    finally:
        os.unlink(tmp_path)


class STTHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != "/stt":
            self.send_error(404)
            return

        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)

        try:
            data = json.loads(body)
            audio_b64 = data.get("audio", "")

            if not audio_b64:
                self.send_error(400, "Missing 'audio'")
                return

            wav_bytes = base64.b64decode(audio_b64)
            print(f"[STT] Transcribing {len(wav_bytes)} bytes...")

            result = transcribe(wav_bytes)

            response = json.dumps(result)
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(response.encode())
            print(f"[STT] Result: '{result['text']}' (lang={result['language']})")

        except Exception as e:
            print(f"[STT] Error: {e}")
            self.send_error(500, str(e))

    def log_message(self, format, *args):
        pass


if __name__ == "__main__":
    print(f"[STT] Starting server on {STT_HOST}:{STT_PORT}")
    server = HTTPServer((STT_HOST, STT_PORT), STTHandler)
    server.serve_forever()
