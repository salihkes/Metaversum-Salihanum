#!/usr/bin/env python
"""
Shared constants for the Metaversum-Salihanum server.
"""

# Default character/morph type for new players
# Valid options: "humanoid", "countryball", "countryball_oneside"
DEFAULT_CHARACTER_TYPE = "humanoid"

# Directory for user textures
USER_TEXTURE_DIR = "user_textures"

# Directory for country flag textures (for countryball oneside morph)
FLAGS_DIR = "Flags"

# Directory for user data
USER_DATA_DIR = "user_data"

# Directory for place scenes
PLACES_DIR = "places"

# Directory for plot data
PLOTS_DATA_DIR = "plots_data"

# Plots configuration file
PLOTS_CONFIG_FILE = "plots.json"

# World environment config
WORLD_ENVIRONMENT_FILE = "world_environment.json"

# Province map state file (replicated map JSON)
MAP_STATE_FILE = "map_state.json"

# Province map: fixed colour palette auto-assigned to players on first login.
# 16 visually distinct colours; admin can override per-user in MAP_PLAYERS_OVERRIDE_FILE.
MAP_COLOR_PALETTE = [
    "c0392b", "2980b9", "27ae60", "f39c12", "8e44ad",
    "1abc9c", "d35400", "2c3e50", "e74c3c", "3498db",
    "2ecc71", "e67e22", "9b59b6", "16a085", "f1c40f",
    "34495e",
]

# Optional JSON file: {"username": {"color": "hex"}} — admin overrides for player colours.
MAP_PLAYERS_OVERRIDE_FILE = "map_players.json"

# Peace-treaty negotiation timeout (seconds).
TREATY_TIMEOUT_SECONDS = 30

# When True, players can only occupy provinces belonging to players who are
# currently online.  Set to False to allow occupying anyone's land at any time.
MAP_REQUIRE_ONLINE_TO_OCCUPY = True

# External domain (Cloudflare proxied - use wss:// for WebSocket, https:// for HTTP)
EXTERNAL_DOMAIN = "project.skeskin.com"

# Cloudflare HTTP ports (no SSL required on origin): 80, 8080, 8880, 2052, 2082, 2086, 2095
# With Flexible SSL: Cloudflare serves wss:// to clients, connects via ws:// to origin

# Voice chat server configuration
VOICE_CHAT_SERVER_PORT = 8443  # Cloudflare HTTPS port (requires SSL on origin)
VOICE_CHAT_SERVER_URL = f"wss://{EXTERNAL_DOMAIN}:{VOICE_CHAT_SERVER_PORT}"

# Main server configuration (game server)
MAIN_SERVER_PORT = 2053  # Cloudflare HTTPS port (requires SSL on origin)
MAIN_SERVER_HOST = "0.0.0.0"  # Internal bind address
MAIN_SERVER_URL = f"wss://{EXTERNAL_DOMAIN}:{MAIN_SERVER_PORT}"

# Place server configuration
PLACE_SERVER_START_PORT = 2086  # Cloudflare HTTP port

# WebSocket configuration
MAX_MESSAGE_SIZE = 10_000_000  # 10MB max message size
MAX_QUEUE_SIZE = None  # No queue size limit

# Web-to-Game SSO Configuration
# This secret is used to sign authentication tokens between the website and game server
# IMPORTANT: Change this in production!
SSO_SECRET_KEY = "pbrp-sso-secret-change-in-production-12345"
SSO_TOKEN_EXPIRY_SECONDS = 60  # Tokens expire after 60 seconds

# Client validation key – embedded in the Godot binary, checked on every message.
# Prevents connections from modified / third-party clients.
# The current system is not optimal, but this is the only method that works with web exports.
# There are much better methods if you do not require web exports.
CLIENT_KEY = "salihionica-2026"

# PCK dynamic content delivery configuration
# Place .pck files in this directory and register them in the manifest
PCK_PACKAGES_DIR = "pck_packages"
PCK_MANIFEST_FILE = "pck_manifest.json"
PCK_HTTP_SERVER_PORT = 8080  # Cloudflare HTTP port (no SSL required on origin)

