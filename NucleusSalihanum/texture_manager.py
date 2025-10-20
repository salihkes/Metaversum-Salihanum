#!/usr/bin/env python
"""
Texture management utilities for the Metaversum-Salihanum server.
"""

import os
import base64
import json
from constants import USER_TEXTURE_DIR


def get_texture_filename(username, character_type):
    """Get the appropriate texture filename based on character type"""
    if character_type == "countryball":
        return f"{username}_countryball.png"
    else:
        return f"{username}.png"


def user_has_texture(username, character_type):
    """Check if user has a texture file for the specified character type"""
    # First check for user-specific texture
    texture_filename = get_texture_filename(username, character_type)
    texture_path = os.path.join(USER_TEXTURE_DIR, texture_filename)
    
    if os.path.exists(texture_path):
        return True
    
    # If no user-specific texture and it's a countryball, check for fallback
    if character_type == "countryball":
        fallback_path = os.path.join(USER_TEXTURE_DIR, "countryball.png")
        return os.path.exists(fallback_path)
    
    return False


async def send_texture_data(username, character_type, target_clients):
    """Send texture data to specified clients
    
    Args:
        username: The username associated with the texture
        character_type: The character type (humanoid or countryball)
        target_clients: Iterable of client dicts with 'websocket' key (required)
    
    Returns:
        True if texture was found and sent, False otherwise
    """
    # First try user-specific texture
    texture_filename = get_texture_filename(username, character_type)
    texture_path = os.path.join(USER_TEXTURE_DIR, texture_filename)
    
    # If user-specific doesn't exist and it's countryball, try fallback
    if not os.path.exists(texture_path) and character_type == "countryball":
        texture_path = os.path.join(USER_TEXTURE_DIR, "countryball.png")
    
    if os.path.exists(texture_path):
        # Read and encode the texture file
        with open(texture_path, "rb") as f:
            texture_data = base64.b64encode(f.read()).decode('utf-8')
        
        # Send texture data to specified clients with correct character type
        for client in target_clients:
            await client["websocket"].send(json.dumps({
                "type": "texture_data",
                "texture_name": username,  # Keep username as texture_name for client compatibility
                "character_type": character_type,  # This should match the actual character type
                "data": texture_data
            }))
        
        return True
    return False


def get_texture_path(username, character_type):
    """Get the full path to a user's texture file
    
    Args:
        username: The username associated with the texture
        character_type: The character type (humanoid or countryball)
    
    Returns:
        Path to the texture file, or fallback path for countryball, or None if not found
    """
    texture_filename = get_texture_filename(username, character_type)
    texture_path = os.path.join(USER_TEXTURE_DIR, texture_filename)
    
    # If user-specific doesn't exist and it's countryball, try fallback
    if not os.path.exists(texture_path) and character_type == "countryball":
        fallback_path = os.path.join(USER_TEXTURE_DIR, "countryball.png")
        if os.path.exists(fallback_path):
            return fallback_path
    
    if os.path.exists(texture_path):
        return texture_path
    
    return None

