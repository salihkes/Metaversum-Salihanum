"""
Minimal TTS HTTP server wrapping Qwen3-TTS via MLX.

Run separately:  python tts_server.py
Endpoint:        POST /tts
Payload:         {"text": "...", "language": "English", "ref_voice": "guard"}
Response:        {"audio": "<base64 wav>", "sample_rate": 24000}

Reference voices are stored in npc_voices/{name}.wav
"""

import os
import json
import base64
import io
import numpy as np
from http.server import HTTPServer, BaseHTTPRequestHandler

# Lazy-load model on first request
_model = None
_voices_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "npc_voices")

TTS_HOST = os.environ.get("TTS_HOST", "0.0.0.0")
TTS_PORT = int(os.environ.get("TTS_PORT", "8090"))


def get_model():
    global _model
    if _model is None:
        print("[TTS] Loading Qwen3-TTS model...")
        from mlx_audio.tts.utils import load_model
        model_name = os.environ.get("TTS_MODEL", "/Users/salihkeskin/Documents/Qwen3TTS/OSX/Qwen3-TTS-12Hz-1.7B-Base-bf16")
        _model = load_model(model_name)
        print(f"[TTS] Model loaded: {model_name}")
    return _model


def generate_speech(text: str, ref_voice: str = "default",
                    language: str = "English") -> tuple[bytes, int]:
    """Generate speech audio, return (wav_bytes, sample_rate)."""
    model = get_model()

    # Find reference audio
    ref_audio_path = os.path.join(_voices_dir, f"{ref_voice}.wav")
    if not os.path.exists(ref_audio_path):
        # Fallback to any available voice
        for f in os.listdir(_voices_dir):
            if f.endswith(".wav"):
                ref_audio_path = os.path.join(_voices_dir, f)
                break
        else:
            raise FileNotFoundError(f"No reference voice found for '{ref_voice}'")

    # Load reference text if available (for better voice cloning)
    ref_text_path = ref_audio_path.replace(".wav", ".txt")
    ref_text = ""
    if os.path.exists(ref_text_path):
        with open(ref_text_path, "r") as f:
            ref_text = f.read().strip()

    results = list(model.generate(
        text=text,
        ref_audio=ref_audio_path,
        ref_text=ref_text,
        language=language,
    ))

    if not results:
        raise RuntimeError("TTS generated no output")

    result = results[0]
    audio = np.array(result.audio, dtype=np.float32).flatten()
    audio = np.clip(audio, -1.0, 1.0)
    sample_rate = result.sample_rate

    # Encode as WAV in memory
    samples_int16 = (audio * 32767).astype(np.int16)
    buf = io.BytesIO()
    import wave
    with wave.open(buf, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        wf.writeframes(samples_int16.tobytes())

    return buf.getvalue(), sample_rate


class TTSHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != "/tts":
            self.send_error(404)
            return

        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)

        try:
            data = json.loads(body)
            text = data.get("text", "")
            ref_voice = data.get("ref_voice", "default")
            language = data.get("language", "English")

            if not text:
                self.send_error(400, "Missing 'text'")
                return

            print(f"[TTS] Generating: '{text[:50]}...' voice={ref_voice} lang={language}")
            wav_bytes, sample_rate = generate_speech(text, ref_voice, language)

            response = json.dumps({
                "audio": base64.b64encode(wav_bytes).decode(),
                "sample_rate": sample_rate
            })

            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(response.encode())
            print(f"[TTS] Done: {len(wav_bytes)} bytes")

        except Exception as e:
            print(f"[TTS] Error: {e}")
            self.send_error(500, str(e))

    def log_message(self, format, *args):
        pass  # Suppress default access logs


if __name__ == "__main__":
    os.makedirs(_voices_dir, exist_ok=True)
    print(f"[TTS] Voice directory: {_voices_dir}")
    print(f"[TTS] Starting server on {TTS_HOST}:{TTS_PORT}")
    server = HTTPServer((TTS_HOST, TTS_PORT), TTSHandler)
    server.serve_forever()
