"""
NPC Chat Manager — server-side LLM conversations with character cards.

Each NPC has ONE conversation history shared by all players. Player identity
is embedded as XML metadata in user messages, following LLM_Guidelines.txt:
  - Proper System/User/Assistant alternation for KV cache
  - XML metadata tags for player identity, time, and world state
  - No OpenAI tools parameter (prompt-based if needed later)
  - History never mutated after being sent (append-only, trim from front)

Character cards are stored on the server (npc_characters/) as JSON files.
Clients never see the system prompt.

Supports two backends:
  - "simple": direct llamacpp /v1/chat/completions call (default)
  - "agentic": route to AgenticBase API (when configured)
"""

import json
import os
import time
import aiohttp
import asyncio
from datetime import datetime
from npc_rag import NpcRagManager, RAG_ENABLED

# LLM provider: "local" or "openrouter"
LLM_PROVIDER = os.environ.get("LLM_PROVIDER", "local")

# Local LLM (llamacpp)
LLM_BASE_URL = os.environ.get("LLM_BASE_URL", "http://192.168.1.11:8082")
LLM_MODEL = os.environ.get("LLM_MODEL", "")

# OpenRouter
OPENROUTER_API_KEY = os.environ.get("OPENROUTER_API_KEY", "")
OPENROUTER_MODEL = os.environ.get("OPENROUTER_MODEL", "google/gemma-3-27b-it")

# AgenticBase endpoint (optional, for "agentic" backend NPCs)
AGENTIC_BASE_URL = os.environ.get("AGENTIC_BASE_URL", "http://127.0.0.1:5006")
AGENTIC_MESSAGE_ENDPOINT = f"{AGENTIC_BASE_URL}/api/agent/message"

# TTS
TTS_ENABLED = os.environ.get("TTS_ENABLED", "false").lower() == "true"
TTS_PROVIDER = os.environ.get("TTS_PROVIDER", "local")
TTS_BASE_URL = os.environ.get("TTS_BASE_URL", "http://127.0.0.1:8090")

# ElevenLabs
ELEVENLABS_API_KEY = os.environ.get("ELEVENLABS_API_KEY", "")
ELEVENLABS_VOICES = {}  # populated from env: ELEVENLABS_VOICE_{NAME}
for _k, _v in os.environ.items():
    if _k.startswith("ELEVENLABS_VOICE_") and _v:
        _name = _k.replace("ELEVENLABS_VOICE_", "").lower()
        ELEVENLABS_VOICES[_name] = _v

# Master toggle — set to False to disable all NPC chat LLM calls
NPC_CHAT_ENABLED = os.environ.get("NPC_CHAT_ENABLED", "true").lower() == "true"

# Block guests from talking to NPCs (requires login)
NPC_CHAT_REQUIRE_AUTH = os.environ.get("NPC_CHAT_REQUIRE_AUTH", "false").lower() == "true"

# Character cards directory
NPC_CHARACTERS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "npc_characters")

# Persistent chat history directory
NPC_CHAT_HISTORY_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "npc_chat_history")

# Max conversation history per NPC (to avoid context overflow)
MAX_HISTORY_ENTRIES = 40  # ~20 turns of user+assistant


def build_world_context(world_state: dict) -> str:
    """Build XML world context block from live server data."""
    parts = []

    t = world_state.get("time", "")
    if t:
        parts.append(f"<time>{t}</time>")

    weather = world_state.get("weather", "")
    if weather:
        parts.append(f"<weather>{weather}</weather>")

    online = world_state.get("online_players", [])
    if online:
        parts.append(f"<online_players>{', '.join(online)}</online_players>")

    player_count = world_state.get("player_count", 0)
    parts.append(f"<player_count>{player_count}</player_count>")

    nearby = world_state.get("nearby_players", [])
    if nearby:
        parts.append(f"<nearby_players>{', '.join(nearby)}</nearby_players>")

    npc_location = world_state.get("npc_location", "")
    if npc_location:
        parts.append(f"<my_location>{npc_location}</my_location>")

    schedule = world_state.get("npc_schedule", "")
    if schedule:
        parts.append(f"<my_schedule>{schedule}</my_schedule>")

    landmarks = world_state.get("landmarks", [])
    if landmarks:
        parts.append(f"<known_landmarks>{', '.join(landmarks)}</known_landmarks>")

    if not parts:
        return ""

    return "<world_state>\n" + "\n".join(parts) + "\n</world_state>"


class NpcConversation:
    """One conversation per NPC, shared across all players."""

    def __init__(self, npc_id: str, character_card: dict):
        self.npc_id = npc_id
        self.character_card = character_card
        self.base_system_prompt = character_card.get("system_prompt", "You are an NPC.")
        self.display_name = character_card.get("display_name", npc_id)
        self.backend = character_card.get("backend", "simple")
        self.history: list[dict] = []  # append-only, trimmed from front
        self.last_activity = time.time()
        self.generating = False

    def add_user_message(self, username: str, message: str) -> list[dict]:
        """Append a player message with XML metadata.
        Returns any trimmed messages for RAG archival."""
        now = datetime.now().strftime("%H:%M")
        content = (
            f"<metadata>\n"
            f"<speaker>{username}</speaker>\n"
            f"<time>{now}</time>\n"
            f"</metadata>\n"
            f"{message}"
        )

        # KV cache rule: must alternate user/assistant.
        if self.history and self.history[-1]["role"] == "user":
            self.history[-1]["content"] += "\n\n" + content
        else:
            self.history.append({"role": "user", "content": content})

        trimmed = self._trim_history()
        self.last_activity = time.time()
        return trimmed

    def add_assistant_message(self, message: str):
        self.history.append({"role": "assistant", "content": message})
        self.last_activity = time.time()

    def build_messages(self, world_state: dict = None,
                       rag_context: str = "") -> list[dict]:
        """Build the full message array for the LLM API call.
        World state and RAG context injected into system prompt dynamically."""
        system_content = self.base_system_prompt

        if world_state:
            world_ctx = build_world_context(world_state)
            if world_ctx:
                system_content += (
                    "\n\nBelow is the current state of the world. "
                    "Use this information naturally in conversation when relevant. "
                    "Do not dump it all at once.\n\n" + world_ctx
                )

        if rag_context:
            system_content += (
                "\n\nBelow are relevant excerpts from past conversations. "
                "Use them to maintain continuity and remember past interactions "
                "when relevant. Do not repeat them verbatim.\n\n" + rag_context
            )

        messages = [{"role": "system", "content": system_content}]
        messages.extend(self.history)
        return messages

    def _trim_history(self) -> list[dict]:
        """Trim oldest entries to stay within context limits.
        Returns the trimmed messages so they can be archived to RAG."""
        trimmed = []
        while len(self.history) > MAX_HISTORY_ENTRIES:
            if self.history[0]["role"] == "user":
                trimmed.append(self.history.pop(0))
                if self.history and self.history[0]["role"] == "assistant":
                    trimmed.append(self.history.pop(0))
            elif self.history[0]["role"] == "assistant":
                trimmed.append(self.history.pop(0))
        return trimmed

    def save(self):
        """Persist conversation history to disk."""
        os.makedirs(NPC_CHAT_HISTORY_DIR, exist_ok=True)
        path = os.path.join(NPC_CHAT_HISTORY_DIR, f"{self.npc_id}.json")
        try:
            with open(path, "w", encoding="utf-8") as f:
                json.dump(self.history, f, ensure_ascii=False, indent=2)
        except Exception as e:
            print(f"[NpcChat] Failed to save history for {self.npc_id}: {e}")

    def load(self):
        """Load conversation history from disk if it exists."""
        path = os.path.join(NPC_CHAT_HISTORY_DIR, f"{self.npc_id}.json")
        if not os.path.exists(path):
            return
        try:
            with open(path, "r", encoding="utf-8") as f:
                self.history = json.load(f)
            print(f"[NpcChat] Loaded {len(self.history)} history entries for {self.npc_id}")
        except Exception as e:
            print(f"[NpcChat] Failed to load history for {self.npc_id}: {e}")


class NpcChatManager:
    """Manages all NPC conversations and LLM calls."""

    def __init__(self):
        self.conversations: dict[str, NpcConversation] = {}
        self.character_cards: dict[str, dict] = {}
        self.rag = NpcRagManager()
        self._load_character_cards()

    def _load_character_cards(self):
        if not os.path.exists(NPC_CHARACTERS_DIR):
            os.makedirs(NPC_CHARACTERS_DIR, exist_ok=True)
            print(f"[NpcChat] Created character cards directory: {NPC_CHARACTERS_DIR}")
            return

        for filename in os.listdir(NPC_CHARACTERS_DIR):
            if not filename.endswith(".json"):
                continue
            filepath = os.path.join(NPC_CHARACTERS_DIR, filename)
            try:
                with open(filepath, "r", encoding="utf-8") as f:
                    card = json.load(f)
                npc_id = card.get("npc_id", filename.replace(".json", ""))
                self.character_cards[npc_id] = card
                backend = card.get("backend", "simple")
                print(f"[NpcChat] Loaded: {npc_id} ({card.get('display_name', npc_id)}) [{backend}]")
            except Exception as e:
                print(f"[NpcChat] Failed to load {filename}: {e}")

        print(f"[NpcChat] {len(self.character_cards)} character card(s) loaded")

    def get_conversation(self, npc_id: str) -> NpcConversation | None:
        if npc_id in self.conversations:
            return self.conversations[npc_id]
        if npc_id not in self.character_cards:
            return None
        conv = NpcConversation(npc_id, self.character_cards[npc_id])
        conv.load()
        self.conversations[npc_id] = conv
        return conv

    async def chat(self, npc_id: str, username: str, message: str,
                   world_state: dict = None) -> dict | None:
        """Send a player message to an NPC. Returns {"text": str, "audio": str|None}.
        Audio is base64 WAV if TTS is enabled and the NPC has a voice."""
        if not NPC_CHAT_ENABLED:
            return None

        conv = self.get_conversation(npc_id)
        if conv is None:
            return None

        if conv.generating:
            return None

        conv.generating = True
        trimmed = conv.add_user_message(username, message)

        # Archive trimmed messages to RAG so they can be retrieved later
        if trimmed and RAG_ENABLED:
            asyncio.ensure_future(self.rag.archive_trimmed_messages(conv.npc_id, trimmed))

        try:
            # Retrieve relevant past context via RAG
            rag_context = ""
            if RAG_ENABLED:
                rag_context = await self.rag.retrieve_context(conv.npc_id, message)

            if conv.backend == "agentic":
                response = await self._call_agentic(conv, username, message)
            else:
                response = await self._call_llm(conv, world_state, rag_context)

            if response:
                conv.add_assistant_message(response)
                conv.save()

                # Generate TTS if enabled and NPC has a voice configured
                audio_b64 = None
                if TTS_ENABLED and conv.character_card.get("voice"):
                    audio_b64 = await self._call_tts(
                        response,
                        conv.character_card["voice"],
                        conv.character_card.get("language", "English")
                    )

                return {"text": response, "audio": audio_b64}
            else:
                if conv.history and conv.history[-1]["role"] == "user":
                    conv.history.pop()
                return None
        except Exception as e:
            print(f"[NpcChat] Error for {npc_id}: {e}")
            if conv.history and conv.history[-1]["role"] == "user":
                conv.history.pop()
            return None
        finally:
            conv.generating = False

    async def _call_llm(self, conv: NpcConversation,
                        world_state: dict = None,
                        rag_context: str = "") -> str | None:
        """Route to local llamacpp or OpenRouter based on LLM_PROVIDER."""
        messages = conv.build_messages(world_state, rag_context)
        temperature = conv.character_card.get("temperature", 0.7)
        max_tokens = conv.character_card.get("max_tokens", 256)

        if LLM_PROVIDER == "openrouter" and OPENROUTER_API_KEY:
            return await self._llm_openrouter(messages, temperature, max_tokens)
        else:
            return await self._llm_local(messages, temperature, max_tokens)

    async def _llm_local(self, messages, temperature, max_tokens) -> str | None:
        endpoint = f"{LLM_BASE_URL}/v1/chat/completions"
        payload = {
            "messages": messages,
            "temperature": temperature,
            "max_tokens": max_tokens,
            "stream": False
        }
        if LLM_MODEL:
            payload["model"] = LLM_MODEL
        return await self._llm_request(endpoint, payload)

    async def _llm_openrouter(self, messages, temperature, max_tokens) -> str | None:
        payload = {
            "model": OPENROUTER_MODEL,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": max_tokens
        }
        headers = {
            "Authorization": f"Bearer {OPENROUTER_API_KEY}",
            "Content-Type": "application/json"
        }
        return await self._llm_request(
            "https://openrouter.ai/api/v1/chat/completions",
            payload, headers
        )

    async def _llm_request(self, endpoint, payload, headers=None) -> str | None:
        try:
            async with aiohttp.ClientSession() as session:
                async with session.post(
                    endpoint, json=payload, headers=headers,
                    timeout=aiohttp.ClientTimeout(total=30)
                ) as resp:
                    if resp.status != 200:
                        body = await resp.text()
                        print(f"[NpcChat] LLM returned {resp.status}: {body[:200]}")
                        return None
                    data = await resp.json()
                    choices = data.get("choices", [])
                    if choices:
                        return choices[0].get("message", {}).get("content", "").strip()
                    return None
        except asyncio.TimeoutError:
            print(f"[NpcChat] LLM timeout")
            return None
        except aiohttp.ClientError as e:
            print(f"[NpcChat] LLM connection error: {e}")
            return None

    async def _call_agentic(self, conv: NpcConversation,
                            username: str, message: str) -> str | None:
        """Agentic backend: route to AgenticBase API.
        AgenticBase handles its own memory, RAG, tools, etc."""
        payload = {
            "message": message,
            "user": username,
            # AgenticBase uses its own conversation management,
            # but we pass context so it knows this is an NPC
            "context": {
                "npc_id": conv.npc_id,
                "npc_name": conv.display_name,
                "character_prompt": conv.base_system_prompt
            }
        }

        try:
            async with aiohttp.ClientSession() as session:
                async with session.post(
                    AGENTIC_MESSAGE_ENDPOINT,
                    json=payload,
                    timeout=aiohttp.ClientTimeout(total=60)
                ) as resp:
                    if resp.status != 200:
                        body = await resp.text()
                        print(f"[NpcChat] AgenticBase returned {resp.status}: {body[:200]}")
                        return None
                    data = await resp.json()
                    return data.get("response", "").strip()
        except asyncio.TimeoutError:
            print(f"[NpcChat] AgenticBase timeout for {conv.npc_id}")
            return None
        except aiohttp.ClientError as e:
            print(f"[NpcChat] AgenticBase connection error: {e}")
            return None

    async def _call_tts(self, text: str, voice: str,
                        language: str = "English") -> str | None:
        """Route to local TTS or ElevenLabs based on TTS_PROVIDER."""
        if TTS_PROVIDER == "elevenlabs" and ELEVENLABS_API_KEY:
            return await self._tts_elevenlabs(text, voice)
        else:
            return await self._tts_local(text, voice, language)

    async def _tts_local(self, text: str, voice: str,
                         language: str) -> str | None:
        try:
            from local_services import generate_speech
            result = await generate_speech(text, voice, language)
            return result if result else None
        except ImportError:
            print("[NpcChat] local_services not available (missing mlx_audio?)")
            return None
        except Exception as e:
            print(f"[NpcChat] Local TTS error: {e}")
            return None

    async def _tts_elevenlabs(self, text: str, voice: str) -> str | None:
        voice_id = ELEVENLABS_VOICES.get(voice, "")
        if not voice_id:
            print(f"[NpcChat] No ElevenLabs voice ID for '{voice}'")
            return None
        try:
            import base64
            async with aiohttp.ClientSession() as session:
                async with session.post(
                    f"https://api.elevenlabs.io/v1/text-to-speech/{voice_id}",
                    json={"text": text, "model_id": "eleven_multilingual_v2"},
                    headers={
                        "xi-api-key": ELEVENLABS_API_KEY,
                        "Content-Type": "application/json",
                        "Accept": "audio/mpeg"
                    },
                    timeout=aiohttp.ClientTimeout(total=30)
                ) as resp:
                    if resp.status != 200:
                        body = await resp.text()
                        print(f"[NpcChat] ElevenLabs returned {resp.status}: {body[:200]}")
                        return None
                    audio_bytes = await resp.read()
                    return base64.b64encode(audio_bytes).decode()
        except Exception as e:
            print(f"[NpcChat] ElevenLabs error: {e}")
            return None

    def get_available_npcs(self) -> list[str]:
        return list(self.character_cards.keys())

    def reset_conversation(self, npc_id: str):
        if npc_id in self.conversations:
            self.conversations[npc_id].history.clear()
            self.conversations[npc_id].save()
            print(f"[NpcChat] Reset conversation for {npc_id}")
