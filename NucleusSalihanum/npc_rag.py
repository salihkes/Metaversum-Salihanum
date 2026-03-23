"""
NPC RAG — Retrieval-Augmented Generation for NPC conversations.

Embeds conversation chunks and retrieves relevant past context when needed.
Uses llamacpp's /v1/embeddings and /v1/rerank endpoints.

Storage: npc_rag_store/{npc_id}.json — array of {text, embedding, timestamp}
"""

import json
import os
import time
import aiohttp
import asyncio
import numpy as np
from datetime import datetime

# Embedding server (llamacpp with --embedding)
EMBEDDING_BASE_URL = os.environ.get("EMBEDDING_BASE_URL", "http://192.168.1.11:8081")
EMBEDDING_ENDPOINT = f"{EMBEDDING_BASE_URL}/v1/embeddings"
RERANK_ENDPOINT = f"{EMBEDDING_BASE_URL}/v1/rerank"

# Model names (required by llamacpp --models-dir router)
EMBEDDING_MODEL = os.environ.get("EMBEDDING_MODEL", "bge-m3-FP16")
RERANK_MODEL = os.environ.get("RERANK_MODEL", "bge-reranker-v2-m3-FP16")

# RAG toggle
RAG_ENABLED = os.environ.get("NPC_RAG_ENABLED", "false").lower() == "true"

# Storage
RAG_STORE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "npc_rag_store")

# Retrieval settings
TOP_K_EMBED = 10     # candidates from embedding search
TOP_K_RERANK = 3     # final results after reranking
CHUNK_MIN_LENGTH = 20  # don't embed very short messages


async def get_embedding(text: str) -> list[float] | None:
    """Get embedding vector for a text string."""
    try:
        async with aiohttp.ClientSession() as session:
            async with session.post(
                EMBEDDING_ENDPOINT,
                json={"input": text, "model": EMBEDDING_MODEL},
                timeout=aiohttp.ClientTimeout(total=15)
            ) as resp:
                if resp.status != 200:
                    print(f"[RAG] Embedding error: {resp.status}")
                    return None
                data = await resp.json()
                return data["data"][0]["embedding"]
    except Exception as e:
        print(f"[RAG] Embedding failed: {e}")
        return None


async def rerank(query: str, documents: list[str]) -> list[dict] | None:
    """Rerank documents by relevance to query. Returns sorted [{index, score}]."""
    if not documents:
        return []
    try:
        async with aiohttp.ClientSession() as session:
            async with session.post(
                RERANK_ENDPOINT,
                json={
                    "query": query,
                    "documents": documents,
                    "model": RERANK_MODEL,
                    "top_n": TOP_K_RERANK
                },
                timeout=aiohttp.ClientTimeout(total=15)
            ) as resp:
                if resp.status != 200:
                    print(f"[RAG] Rerank error: {resp.status}")
                    return None
                data = await resp.json()
                return data.get("results", [])
    except Exception as e:
        print(f"[RAG] Rerank failed: {e}")
        return None


def cosine_similarity(a: list[float], b: list[float]) -> float:
    a_np = np.array(a)
    b_np = np.array(b)
    dot = np.dot(a_np, b_np)
    norm = np.linalg.norm(a_np) * np.linalg.norm(b_np)
    if norm == 0:
        return 0.0
    return float(dot / norm)


class NpcRagStore:
    """Per-NPC vector store for conversation chunks."""

    def __init__(self, npc_id: str):
        self.npc_id = npc_id
        self.chunks: list[dict] = []  # [{text, embedding, timestamp}]
        self._load()

    def _store_path(self) -> str:
        return os.path.join(RAG_STORE_DIR, f"{self.npc_id}.json")

    def _load(self):
        path = self._store_path()
        if os.path.exists(path):
            try:
                with open(path, "r", encoding="utf-8") as f:
                    self.chunks = json.load(f)
                print(f"[RAG] Loaded {len(self.chunks)} chunks for {self.npc_id}")
            except Exception as e:
                print(f"[RAG] Failed to load store for {self.npc_id}: {e}")

    def _save(self):
        os.makedirs(RAG_STORE_DIR, exist_ok=True)
        path = self._store_path()
        try:
            with open(path, "w", encoding="utf-8") as f:
                json.dump(self.chunks, f, ensure_ascii=False)
        except Exception as e:
            print(f"[RAG] Failed to save store for {self.npc_id}: {e}")

    async def add_chunk(self, text: str):
        """Embed and store a conversation chunk."""
        if len(text) < CHUNK_MIN_LENGTH:
            return

        embedding = await get_embedding(text)
        if embedding is None:
            return

        self.chunks.append({
            "text": text,
            "embedding": embedding,
            "timestamp": time.time()
        })
        self._save()

    async def retrieve(self, query: str) -> list[str]:
        """Find relevant past conversation chunks for a query.
        Uses embedding similarity then reranking."""
        if not self.chunks:
            return []

        # Step 1: embed the query
        query_emb = await get_embedding(query)
        if query_emb is None:
            return []

        # Step 2: cosine similarity to find top-K candidates
        scored = []
        for i, chunk in enumerate(self.chunks):
            sim = cosine_similarity(query_emb, chunk["embedding"])
            scored.append((i, sim))

        scored.sort(key=lambda x: x[1], reverse=True)
        candidates = scored[:TOP_K_EMBED]

        if not candidates:
            return []

        candidate_texts = [self.chunks[i]["text"] for i, _ in candidates]

        # Step 3: rerank for precision
        reranked = await rerank(query, candidate_texts)
        if reranked:
            results = []
            for item in reranked:
                idx = item.get("index", 0)
                if idx < len(candidate_texts):
                    results.append(candidate_texts[idx])
            return results

        # Fallback: return top embedding matches without reranking
        return candidate_texts[:TOP_K_RERANK]


# World knowledge documents directory
WORLD_KNOWLEDGE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "npc_world_knowledge")


class NpcRagManager:
    """Manages RAG stores for all NPCs."""

    def __init__(self):
        self.stores: dict[str, NpcRagStore] = {}
        self._world_knowledge_indexed = False

    def get_store(self, npc_id: str) -> NpcRagStore:
        if npc_id not in self.stores:
            self.stores[npc_id] = NpcRagStore(npc_id)
        return self.stores[npc_id]

    async def archive_trimmed_messages(self, npc_id: str, messages: list[dict]):
        """When conversation history is trimmed, embed the trimmed messages
        so they can be retrieved later."""
        if not RAG_ENABLED:
            return
        store = self.get_store(npc_id)
        # Combine user+assistant pairs into chunks
        chunk_text = ""
        for msg in messages:
            role = msg.get("role", "")
            content = msg.get("content", "")
            chunk_text += f"[{role}] {content}\n"
            # Save each complete exchange as a chunk
            if role == "assistant" and chunk_text:
                await store.add_chunk(chunk_text.strip())
                chunk_text = ""
        # Save any remaining text
        if chunk_text.strip():
            await store.add_chunk(chunk_text.strip())

    async def index_world_knowledge(self):
        """Index all .txt files in npc_world_knowledge/ into a shared 'world' store.
        Called once on first RAG query."""
        if self._world_knowledge_indexed or not RAG_ENABLED:
            return
        self._world_knowledge_indexed = True

        if not os.path.exists(WORLD_KNOWLEDGE_DIR):
            return

        store = self.get_store("_world_knowledge")
        if store.chunks:  # already indexed
            print(f"[RAG] World knowledge already has {len(store.chunks)} chunks")
            return

        for filename in os.listdir(WORLD_KNOWLEDGE_DIR):
            if not filename.endswith(".txt"):
                continue
            filepath = os.path.join(WORLD_KNOWLEDGE_DIR, filename)
            try:
                with open(filepath, "r", encoding="utf-8") as f:
                    text = f.read()
                # Split into paragraphs
                paragraphs = [p.strip() for p in text.split("\n\n") if p.strip()]
                for para in paragraphs:
                    if len(para) >= CHUNK_MIN_LENGTH:
                        await store.add_chunk(para)
                print(f"[RAG] Indexed {len(paragraphs)} chunks from {filename}")
            except Exception as e:
                print(f"[RAG] Failed to index {filename}: {e}")

        print(f"[RAG] World knowledge: {len(store.chunks)} total chunks")

    async def retrieve_context(self, npc_id: str, query: str) -> str:
        """Retrieve relevant context from:
          1. NPC's own past conversations (personal memory)
          2. NPC-specific knowledge (npc_world_knowledge/{npc_id}_*.txt)
          3. Shared world knowledge (npc_world_knowledge/*.txt)
        Returns formatted XML string for injection into system prompt."""
        if not RAG_ENABLED:
            return ""

        # Index world knowledge on first call
        await self.index_world_knowledge()

        parts = []

        # 1. NPC's conversation memory
        conv_store = self.get_store(npc_id)
        conv_results = await conv_store.retrieve(query)
        if conv_results:
            memory_parts = []
            for i, text in enumerate(conv_results):
                memory_parts.append(f"<memory_{i+1}>\n{text}\n</memory_{i+1}>")
            parts.append("<past_conversations>\n" + "\n".join(memory_parts) + "\n</past_conversations>")

        # 2. NPC-specific knowledge (if store exists)
        npc_knowledge_store = self.get_store(f"_knowledge_{npc_id}")
        if not npc_knowledge_store.chunks:
            await self._index_npc_knowledge(npc_id, npc_knowledge_store)
        npc_knowledge = await npc_knowledge_store.retrieve(query)
        if npc_knowledge:
            k_parts = [f"<fact>{text}</fact>" for text in npc_knowledge]
            parts.append("<personal_knowledge>\n" + "\n".join(k_parts) + "\n</personal_knowledge>")

        # 3. Shared world knowledge
        world_store = self.get_store("_world_knowledge")
        world_results = await world_store.retrieve(query)
        if world_results:
            w_parts = [f"<fact>{text}</fact>" for text in world_results]
            parts.append("<world_knowledge>\n" + "\n".join(w_parts) + "\n</world_knowledge>")

        if not parts:
            return ""
        return "\n".join(parts)

    async def _index_npc_knowledge(self, npc_id: str, store: NpcRagStore):
        """Index NPC-specific knowledge files (e.g. NPC_Guard_duties.txt)."""
        if not os.path.exists(WORLD_KNOWLEDGE_DIR):
            return
        prefix = f"{npc_id}_"
        for filename in os.listdir(WORLD_KNOWLEDGE_DIR):
            if not filename.startswith(prefix) or not filename.endswith(".txt"):
                continue
            filepath = os.path.join(WORLD_KNOWLEDGE_DIR, filename)
            try:
                with open(filepath, "r", encoding="utf-8") as f:
                    text = f.read()
                paragraphs = [p.strip() for p in text.split("\n\n") if p.strip()]
                for para in paragraphs:
                    if len(para) >= CHUNK_MIN_LENGTH:
                        await store.add_chunk(para)
                print(f"[RAG] Indexed {len(paragraphs)} personal knowledge chunks for {npc_id}")
            except Exception as e:
                print(f"[RAG] Failed to index {filename}: {e}")
