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

