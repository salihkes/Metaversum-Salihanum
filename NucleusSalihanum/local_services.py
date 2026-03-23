"""
Local ML services (TTS + STT) that run inside the game server process.
Models are lazy-loaded on first use. Blocking inference runs in a thread
pool so it doesn't block the async event loop.

These are only used when TTS_PROVIDER=local or STT_PROVIDER=local.
Cloud providers (ElevenLabs, OpenAI) go through aiohttp in npc_chat_manager.
"""

import os
import io
import json
import base64
import asyncio
import tempfile
from concurrent.futures import ThreadPoolExecutor

_executor = ThreadPoolExecutor(max_workers=2)

# ════════════════════════════════════════════════════════════════════
#  STT (faster-whisper)
# ════════════════════════════════════════════════════════════════════

_stt_model = None

STT_MODEL_SIZE = os.environ.get("STT_MODEL_SIZE", "large-v3")
STT_DEVICE = os.environ.get("STT_DEVICE", "auto")
STT_COMPUTE_TYPE = os.environ.get("STT_COMPUTE_TYPE", "int8")


def _get_stt_model():
    global _stt_model
    if _stt_model is None:
        print("[STT] Loading faster-whisper model: %s..." % STT_MODEL_SIZE)
        from faster_whisper import WhisperModel
        _stt_model = WhisperModel(STT_MODEL_SIZE, device=STT_DEVICE,
                                  compute_type=STT_COMPUTE_TYPE)
        print("[STT] Model loaded")
    return _stt_model


def _transcribe_sync(wav_bytes: bytes) -> str:
    """Blocking transcription — runs in thread pool."""
    model = _get_stt_model()

    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        f.write(wav_bytes)
        tmp_path = f.name

    try:
        segments, info = model.transcribe(tmp_path, beam_size=5, language="en")
        text = " ".join(seg.text.strip() for seg in segments)
        print(f"[STT] Result: '{text}' (lang={info.language})")
        return text.strip()
    finally:
        os.unlink(tmp_path)


async def transcribe_audio(audio_b64: str) -> str:
    """Async wrapper — runs STT in thread pool."""
    wav_bytes = base64.b64decode(audio_b64)
    print(f"[STT] Transcribing {len(wav_bytes)} bytes...")
    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(_executor, _transcribe_sync, wav_bytes)


# ════════════════════════════════════════════════════════════════════
#  TTS (Qwen3-TTS via mlx_audio)
# ════════════════════════════════════════════════════════════════════

_tts_model = None

TTS_MODEL_PATH = os.environ.get(
    "TTS_MODEL",
    "/Users/salihkeskin/Documents/Qwen3TTS/OSX/Qwen3-TTS-12Hz-1.7B-Base-bf16"
)
NPC_VOICES_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "npc_voices")


def _get_tts_model():
    global _tts_model
    if _tts_model is None:
        print("[TTS] Loading Qwen3-TTS model...")
        from mlx_audio.tts.utils import load_model
        _tts_model = load_model(TTS_MODEL_PATH)
        print(f"[TTS] Model loaded: {TTS_MODEL_PATH}")
    return _tts_model


def _generate_speech_sync(text: str, ref_voice: str, language: str) -> str:
    """Blocking TTS — runs in thread pool. Returns base64 WAV."""
    import numpy as np
    import wave

    model = _get_tts_model()

    ref_audio_path = os.path.join(NPC_VOICES_DIR, f"{ref_voice}.wav")
    if not os.path.exists(ref_audio_path):
        for f in os.listdir(NPC_VOICES_DIR):
            if f.endswith(".wav"):
                ref_audio_path = os.path.join(NPC_VOICES_DIR, f)
                break
        else:
            print(f"[TTS] No reference voice for '{ref_voice}'")
            return ""

    ref_text_path = ref_audio_path.replace(".wav", ".txt")
    ref_text = ""
    if os.path.exists(ref_text_path):
        with open(ref_text_path, "r") as f:
            ref_text = f.read().strip()

    print(f"[TTS] Generating: '{text[:50]}...' voice={ref_voice} lang={language}")
    results = list(model.generate(
        text=text,
        ref_audio=ref_audio_path,
        ref_text=ref_text,
        language=language,
    ))

    if not results:
        return ""

    result = results[0]
    audio = np.array(result.audio, dtype=np.float32).flatten()
    audio = np.clip(audio, -1.0, 1.0)
    sample_rate = result.sample_rate
    samples_int16 = (audio * 32767).astype(np.int16)

    buf = io.BytesIO()
    with wave.open(buf, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        wf.writeframes(samples_int16.tobytes())

    wav_bytes = buf.getvalue()
    print(f"[TTS] Done: {len(wav_bytes)} bytes")
    return base64.b64encode(wav_bytes).decode()


async def generate_speech(text: str, ref_voice: str,
                          language: str = "English") -> str:
    """Async wrapper — runs TTS in thread pool. Returns base64 WAV."""
    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(
        _executor, _generate_speech_sync, text, ref_voice, language
    )
