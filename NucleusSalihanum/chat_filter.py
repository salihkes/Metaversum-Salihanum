#!/usr/bin/env python
"""
Chat Filter Module for Metaversum-Salihanum
Simple profanity filter with future LLM support planned
"""

import json
import os
import re
from typing import Tuple, List, Optional

# Filter configuration file
FILTER_CONFIG_FILE = "filter_config.json"
BAD_WORDS_FILE = "bad_words.json"

class ChatFilter:
    def __init__(self):
        self.bad_words: set = set()
        self.bad_patterns: List[re.Pattern] = []
        self.replacement_char = "*"
        self.enabled = True
        self.log_filtered = True  # Log when messages are filtered
        
        self._load_config()
        self._load_bad_words()
    
    def _load_config(self):
        """Load filter configuration"""
        if os.path.exists(FILTER_CONFIG_FILE):
            try:
                with open(FILTER_CONFIG_FILE, 'r', encoding='utf-8') as f:
                    config = json.load(f)
                    self.enabled = config.get('enabled', True)
                    self.replacement_char = config.get('replacement_char', '*')
                    self.log_filtered = config.get('log_filtered', True)
            except Exception as e:
                print(f"Error loading filter config: {e}")
    
    def _load_bad_words(self):
        """Load bad words from JSON file"""
        if os.path.exists(BAD_WORDS_FILE):
            try:
                with open(BAD_WORDS_FILE, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                    
                    # Support both list and object format
                    if isinstance(data, list):
                        self.bad_words = set(word.lower() for word in data)
                    elif isinstance(data, dict):
                        # Format: {"words": [...], "patterns": [...]}
                        self.bad_words = set(word.lower() for word in data.get('words', []))
                        for pattern in data.get('patterns', []):
                            try:
                                self.bad_patterns.append(re.compile(pattern, re.IGNORECASE))
                            except re.error as e:
                                print(f"Invalid regex pattern '{pattern}': {e}")
                    
                    print(f"Loaded {len(self.bad_words)} bad words, {len(self.bad_patterns)} patterns")
            except Exception as e:
                print(f"Error loading bad words: {e}")
        else:
            # Create default bad words file
            self._create_default_bad_words()
    
    def _create_default_bad_words(self):
        """Create a default bad words file with common examples"""
        default_data = {
            "words": [
                # Add your bad words here
                # This is intentionally minimal - populate from a dataset
            ],
            "patterns": [
                # Regex patterns for more complex matching
                # e.g., "n+[i1]+g+[e3]+r+",  # catches variations
            ],
            "_comment": "Add bad words to 'words' array. Use 'patterns' for regex matching."
        }
        
        try:
            with open(BAD_WORDS_FILE, 'w', encoding='utf-8') as f:
                json.dump(default_data, f, indent=2)
            print(f"Created default {BAD_WORDS_FILE} - please populate with bad words")
        except Exception as e:
            print(f"Error creating default bad words file: {e}")
    
    def _normalize_text(self, text: str) -> str:
        """Normalize text for comparison (handle leetspeak, etc.)"""
        # Basic leetspeak substitutions
        substitutions = {
            '0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's',
            '7': 't', '8': 'b', '@': 'a', '$': 's', '!': 'i',
        }
        normalized = text.lower()
        for char, replacement in substitutions.items():
            normalized = normalized.replace(char, replacement)
        return normalized
    
    def contains_bad_word(self, message: str) -> Tuple[bool, Optional[str]]:
        """
        Check if message contains bad words
        Returns: (contains_bad_word, matched_word_or_pattern)
        """
        if not self.enabled:
            return False, None
        
        # Normalize the message
        normalized = self._normalize_text(message)
        words = re.findall(r'\b\w+\b', normalized)
        
        # Check individual words
        for word in words:
            if word in self.bad_words:
                return True, word
        
        # Check patterns
        for pattern in self.bad_patterns:
            match = pattern.search(normalized)
            if match:
                return True, f"pattern:{pattern.pattern}"
        
        return False, None
    
    def censor_message(self, message: str) -> str:
        """
        Censor bad words in a message
        Returns the censored message
        """
        if not self.enabled:
            return message
        
        censored = message
        normalized = self._normalize_text(message)
        
        # Find and censor bad words
        for word in self.bad_words:
            # Case-insensitive replacement
            pattern = re.compile(re.escape(word), re.IGNORECASE)
            censored = pattern.sub(self.replacement_char * len(word), censored)
        
        # Apply pattern censoring
        for pattern in self.bad_patterns:
            def replace_match(match):
                return self.replacement_char * len(match.group())
            censored = pattern.sub(replace_match, censored)
        
        return censored
    
    def filter_message(self, message: str, username: str = "Unknown") -> Tuple[bool, str, Optional[str]]:
        """
        Filter a chat message
        Returns: (allowed, processed_message, reason_if_blocked)
        
        Modes:
        - Block: Return original message blocked
        - Censor: Return censored message
        """
        if not self.enabled:
            return True, message, None
        
        has_bad_word, matched = self.contains_bad_word(message)
        
        if has_bad_word:
            if self.log_filtered:
                print(f"[FILTER] User '{username}': possible TOS violation")
            
            # Option 1: Block entirely
            # return False, "", f"Message blocked: inappropriate content"
            
            # Option 2: Censor and allow (current behavior)
            censored = self.censor_message(message)
            return True, censored, None
        
        return True, message, None
    
    def reload(self):
        """Reload filter configuration and word lists"""
        self.bad_words = set()
        self.bad_patterns = []
        self._load_config()
        self._load_bad_words()
        print("Chat filter reloaded")
    
    # Future LLM integration placeholder
    async def filter_with_llm(self, message: str, context: Optional[List[str]] = None) -> Tuple[bool, str, Optional[str]]:
        """
        Future: Filter message using LLM (llama.cpp)
        This is a placeholder for future implementation
        """
        # TODO: Implement llama.cpp integration
        # For now, fall back to simple filter
        return self.filter_message(message)


# Global filter instance
chat_filter = ChatFilter()


def filter_chat_message(message: str, username: str = "Unknown") -> Tuple[bool, str, Optional[str]]:
    """Convenience function to filter a chat message"""
    return chat_filter.filter_message(message, username)


def reload_filter():
    """Reload the chat filter"""
    chat_filter.reload()

