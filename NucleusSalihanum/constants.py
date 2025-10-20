#!/usr/bin/env python
"""
Shared constants for the Metaversum-Salihanum server.
"""

# Directory for user textures
USER_TEXTURE_DIR = "user_textures"

# Directory for user data
USER_DATA_DIR = "user_data"

# Directory for place scenes
PLACES_DIR = "places"

# World environment config
WORLD_ENVIRONMENT_FILE = "world_environment.json"

# Voice chat server configuration
VOICE_CHAT_SERVER_URL = "ws://0.0.0.0:3246"
VOICE_CHAT_SERVER_PORT = 3246

# Main server configuration
MAIN_SERVER_PORT = 8765
MAIN_SERVER_HOST = "0.0.0.0"

# Place server configuration
PLACE_SERVER_START_PORT = 8766

# WebSocket configuration
MAX_MESSAGE_SIZE = 10_000_000  # 10MB max message size
MAX_QUEUE_SIZE = None  # No queue size limit

