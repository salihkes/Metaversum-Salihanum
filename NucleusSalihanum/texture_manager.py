#!/usr/bin/env python
"""
Texture management utilities for the Metaversum-Salihanum server.
"""

import os
import base64
import json
import io

# Try to import PIL for TGA to PNG conversion
try:
    from PIL import Image
    PIL_AVAILABLE = True
except ImportError:
    PIL_AVAILABLE = False
    print("Warning: Pillow not installed. TGA flag support will be disabled.")

# Supported flag file extensions (in order of preference)
FLAG_EXTENSIONS = ['.png', '.tga']

# Handle imports for both direct execution and package import
try:
    # Try relative import first (when running from NucleusSalihanum directory)
    from constants import USER_TEXTURE_DIR, FLAGS_DIR
except ImportError:
    # Fall back to absolute import (when imported as a package from outside)
    from NucleusSalihanum.constants import USER_TEXTURE_DIR, FLAGS_DIR


def get_texture_dir():
    """Get the absolute path to the texture directory.
    Resolves relative to NucleusSalihanum directory, not current working directory.
    """
    # If USER_TEXTURE_DIR is already absolute, use it as-is
    if os.path.isabs(USER_TEXTURE_DIR):
        return USER_TEXTURE_DIR
    
    # Get the directory where this file (texture_manager.py) is located
    # This will be NucleusSalihanum/ directory
    this_file_dir = os.path.dirname(os.path.abspath(__file__))
    
    # Resolve USER_TEXTURE_DIR relative to NucleusSalihanum directory
    texture_dir = os.path.join(this_file_dir, USER_TEXTURE_DIR)
    return os.path.normpath(texture_dir)


def get_flags_dir():
    """Get the absolute path to the flags directory.
    Resolves relative to NucleusSalihanum directory, not current working directory.
    """
    # If FLAGS_DIR is already absolute, use it as-is
    if os.path.isabs(FLAGS_DIR):
        return FLAGS_DIR
    
    # Get the directory where this file (texture_manager.py) is located
    this_file_dir = os.path.dirname(os.path.abspath(__file__))
    
    # Resolve FLAGS_DIR relative to NucleusSalihanum directory
    flags_dir = os.path.join(this_file_dir, FLAGS_DIR)
    return os.path.normpath(flags_dir)


def get_available_flags():
    """Get list of available flag codes.
    
    Returns:
        List of flag codes (e.g., ['TUR', 'TUR_republic', 'RUS', 'RUS_Republic'])
    """
    flags_dir = get_flags_dir()
    if not os.path.exists(flags_dir):
        return []
    
    flags = []
    seen_codes = set()  # Avoid duplicates if both .png and .tga exist
    for filename in os.listdir(flags_dir):
        for ext in FLAG_EXTENSIONS:
            if filename.lower().endswith(ext):
                # Remove extension to get flag code
                flag_code = filename[:-len(ext)]
                if flag_code.lower() not in seen_codes:
                    flags.append(flag_code)
                    seen_codes.add(flag_code.lower())
                break
    return flags


def get_flag_texture_path(flag_code):
    """Get the path to a flag texture file.
    
    Supports fallback: if TUR_republic doesn't exist, falls back to TUR.
    Supports both PNG and TGA formats (PNG preferred).
    
    Args:
        flag_code: The flag code (e.g., 'TUR', 'TUR_republic', 'RUS_Communist')
    
    Returns:
        Tuple of (path, actual_flag_code) if found, (None, None) if not found.
        actual_flag_code may differ from input if fallback was used.
    """
    flags_dir = get_flags_dir()
    if not os.path.exists(flags_dir):
        return None, None
    
    filenames = os.listdir(flags_dir)
    
    # Try exact match first (case-insensitive search), checking each extension in order
    for ext in FLAG_EXTENSIONS:
        for filename in filenames:
            if filename.lower() == f"{flag_code.lower()}{ext}":
                actual_code = filename[:-len(ext)]
                return os.path.join(flags_dir, filename), actual_code
    
    # If flag_code contains underscore (e.g., TUR_republic), try base code as fallback
    if '_' in flag_code:
        base_code = flag_code.split('_')[0]
        for ext in FLAG_EXTENSIONS:
            for filename in filenames:
                if filename.lower() == f"{base_code.lower()}{ext}":
                    actual_code = filename[:-len(ext)]
                    return os.path.join(flags_dir, filename), actual_code
    
    return None, None


def flag_exists(flag_code):
    """Check if a flag texture exists.
    
    Args:
        flag_code: The flag code to check (e.g., 'TUR', 'TUR_republic')
    
    Returns:
        True if flag exists (including fallback), False otherwise
    """
    path, _ = get_flag_texture_path(flag_code)
    return path is not None


def convert_tga_to_png_bytes(tga_path):
    """Convert a TGA file to PNG bytes.
    
    Args:
        tga_path: Path to the TGA file
    
    Returns:
        PNG image data as bytes, or None if conversion failed
    """
    if not PIL_AVAILABLE:
        print(f"Cannot convert TGA to PNG: Pillow not installed")
        return None
    
    try:
        with Image.open(tga_path) as img:
            # Convert to RGBA if necessary (TGA files may have alpha)
            if img.mode != 'RGBA':
                img = img.convert('RGBA')
            
            # Save to bytes buffer as PNG
            buffer = io.BytesIO()
            img.save(buffer, format='PNG')
            return buffer.getvalue()
    except Exception as e:
        print(f"Error converting TGA to PNG: {e}")
        return None


async def send_flag_texture_data(username, flag_code, target_clients):
    """Send flag texture data to specified clients for countryball_oneside morph.
    
    TGA files are automatically converted to PNG before sending.
    
    Args:
        username: The username of the player using this flag
        flag_code: The flag code (e.g., 'TUR', 'RUS_Communist')
        target_clients: Iterable of client dicts with 'websocket' key
    
    Returns:
        Tuple of (success: bool, actual_flag_code: str or None)
    """
    flag_path, actual_flag_code = get_flag_texture_path(flag_code)
    
    if flag_path and os.path.exists(flag_path):
        # Check if it's a TGA file that needs conversion
        if flag_path.lower().endswith('.tga'):
            png_data = convert_tga_to_png_bytes(flag_path)
            if png_data is None:
                print(f"Failed to convert TGA flag: {flag_path}")
                return False, None
            texture_data = base64.b64encode(png_data).decode('utf-8')
        else:
            # Read and encode the PNG texture file directly
            with open(flag_path, "rb") as f:
                texture_data = base64.b64encode(f.read()).decode('utf-8')
        
        # Send flag texture data to specified clients
        # Using character_type "countryball_oneside" to differentiate from regular countryball
        for client in target_clients:
            await client["websocket"].send(json.dumps({
                "type": "texture_data",
                "texture_name": username,
                "character_type": "countryball_oneside",
                "flag_code": actual_flag_code,
                "data": texture_data
            }))
        
        return True, actual_flag_code
    
    return False, None


def get_texture_filename(username, character_type):
    """Get the appropriate texture filename based on character type"""
    if character_type == "countryball":
        return f"{username}_countryball.png"
    else:
        return f"{username}.png"


def user_has_texture(username, character_type):
    """Check if user has a texture file for the specified character type"""
    texture_dir = get_texture_dir()
    # First check for user-specific texture
    texture_filename = get_texture_filename(username, character_type)
    texture_path = os.path.join(texture_dir, texture_filename)
    
    if os.path.exists(texture_path):
        return True
    
    # If no user-specific texture and it's a countryball, check for fallback
    if character_type == "countryball":
        fallback_path = os.path.join(texture_dir, "countryball.png")
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
    texture_dir = get_texture_dir()
    # First try user-specific texture
    texture_filename = get_texture_filename(username, character_type)
    texture_path = os.path.join(texture_dir, texture_filename)
    
    # If user-specific doesn't exist and it's countryball, try fallback
    if not os.path.exists(texture_path) and character_type == "countryball":
        texture_path = os.path.join(texture_dir, "countryball.png")
    
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
    texture_dir = get_texture_dir()
    texture_filename = get_texture_filename(username, character_type)
    texture_path = os.path.join(texture_dir, texture_filename)
    
    # If user-specific doesn't exist and it's countryball, try fallback
    if not os.path.exists(texture_path) and character_type == "countryball":
        fallback_path = os.path.join(texture_dir, "countryball.png")
        if os.path.exists(fallback_path):
            return fallback_path
    
    if os.path.exists(texture_path):
        return texture_path
    
    return None


def save_decal_texture(username, character_type, base64_data):
    """Save a decal texture from base64-encoded data
    
    Args:
        username: The username to save the texture for
        character_type: The character type (humanoid or countryball)
        base64_data: Base64-encoded image data (PNG format expected)
    
    Returns:
        Tuple of (success: bool, message: str, file_path: str or None)
    """
    try:
        # Validate character type
        if character_type not in ["humanoid", "countryball"]:
            return False, f"Invalid character type: {character_type}. Must be 'humanoid' or 'countryball'", None
        
        # Decode base64 data
        try:
            image_data = base64.b64decode(base64_data)
        except Exception as e:
            return False, f"Invalid base64 data: {str(e)}", None
        
        # Validate it's a reasonable size (max 5MB)
        if len(image_data) > 5 * 1024 * 1024:
            return False, "Image too large. Maximum size is 5MB", None
        
        # Get the absolute path to texture directory (relative to NucleusSalihanum)
        texture_dir = get_texture_dir()
        
        # Ensure directory exists
        os.makedirs(texture_dir, exist_ok=True)
        
        # Get the appropriate filename
        texture_filename = get_texture_filename(username, character_type)
        texture_path = os.path.join(texture_dir, texture_filename)
        
        # Save the image file
        with open(texture_path, "wb") as f:
            f.write(image_data)
        
        file_size_kb = len(image_data) / 1024
        print(f"Saved {character_type} decal for {username}: {texture_path} ({file_size_kb:.2f} KB)")
        
        return True, f"Successfully uploaded {character_type} decal ({file_size_kb:.1f} KB)", texture_path
        
    except Exception as e:
        error_msg = f"Error saving decal texture: {str(e)}"
        print(error_msg)
        return False, error_msg, None

