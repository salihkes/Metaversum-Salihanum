#!/usr/bin/env python
"""
User data management utilities for the Metaversum-Salihanum server.
"""

import os
import json
from constants import USER_DATA_DIR, DEFAULT_CHARACTER_TYPE


def get_user_data_path(username):
    """Get the path to a user's data file"""
    return os.path.join(USER_DATA_DIR, f"{username}.json")


def load_user_data(username):
    """Load user data from file
    
    Args:
        username: The username to load data for
    
    Returns:
        Dictionary with user data, or empty dict if file doesn't exist
    """
    user_data_path = get_user_data_path(username)
    
    if not os.path.exists(user_data_path):
        return {}
    
    try:
        with open(user_data_path, "r") as f:
            return json.load(f)
    except Exception as e:
        print(f"Error reading user data for {username}: {e}")
        return {}


def save_user_data(username, user_data):
    """Save user data to file
    
    Args:
        username: The username to save data for
        user_data: Dictionary with user data to save
    
    Returns:
        True if successful, False otherwise
    """
    user_data_path = get_user_data_path(username)
    
    try:
        with open(user_data_path, "w") as f:
            json.dump(user_data, f, indent=2)
        return True
    except Exception as e:
        print(f"Error saving user data for {username}: {e}")
        return False


def get_user_accessories(username):
    """Get list of equipped accessories for a user
    
    Args:
        username: The username to get accessories for
    
    Returns:
        List of accessory names (empty list if none)
    """
    user_data = load_user_data(username)
    return user_data.get("equipped_accessories", [])


def get_user_character_type(username):
    """Get character type for a user
    
    Args:
        username: The username to get character type for
    
    Returns:
        Character type string (default: DEFAULT_CHARACTER_TYPE from constants)
    """
    user_data = load_user_data(username)
    return user_data.get("character_type", DEFAULT_CHARACTER_TYPE)


def save_user_character_type(username, character_type):
    """Save character type for a user
    
    Args:
        username: The username to save character type for
        character_type: The character type to save
    
    Returns:
        True if successful, False otherwise
    """
    user_data = load_user_data(username)
    user_data["character_type"] = character_type
    return save_user_data(username, user_data)


def update_user_accessories(username, accessories):
    """Update equipped accessories for a user
    
    Args:
        username: The username to update accessories for
        accessories: List of accessory names to equip
    
    Returns:
        True if successful, False otherwise
    """
    user_data = load_user_data(username)
    user_data["equipped_accessories"] = accessories
    return save_user_data(username, user_data)


def get_user_monsters(username):
    """Get list of monsters owned by a user
    
    Args:
        username: The username to get monsters for
    
    Returns:
        List of monster dicts: [{"species": str, "texture": str}, ...]
    """
    user_data = load_user_data(username)
    return user_data.get("monsters", [])


def set_user_monsters(username, monsters):
    """Set the list of monsters owned by a user
    
    Args:
        username: The username to set monsters for
        monsters: List of monster dicts: [{"species": str, "texture": str}, ...]
    
    Returns:
        True if successful, False otherwise
    """
    user_data = load_user_data(username)
    user_data["monsters"] = monsters
    return save_user_data(username, user_data)


def add_user_monster(username, species, texture=""):
    """Add a monster to a user's collection
    
    Args:
        username: The username to add monster to
        species: The monster species (e.g., "countryball")
        texture: Optional texture name for countryball monsters
    
    Returns:
        True if successful, False otherwise
    """
    user_data = load_user_data(username)
    if "monsters" not in user_data:
        user_data["monsters"] = []
    
    user_data["monsters"].append({
        "species": species,
        "texture": texture
    })
    
    return save_user_data(username, user_data)
