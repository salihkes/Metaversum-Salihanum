#!/usr/bin/env python
"""
User data management utilities for the Metaversum-Salihanum server.
"""

import os
import json
from constants import USER_DATA_DIR, DEFAULT_CHARACTER_TYPE, MAP_COLOR_PALETTE, MAP_PLAYERS_OVERRIDE_FILE


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


# ── Province-map player-colour helpers ────────────────────────────────────

def _load_admin_overrides():
    """Load the optional admin override file for player map colours."""
    if not os.path.exists(MAP_PLAYERS_OVERRIDE_FILE):
        return {}
    try:
        with open(MAP_PLAYERS_OVERRIDE_FILE, "r") as f:
            return json.load(f)
    except Exception as e:
        print(f"Error reading map players override: {e}")
        return {}


def _collect_used_colors():
    """Scan all user data files and return the set of already-assigned map colours."""
    used = set()
    if not os.path.exists(USER_DATA_DIR):
        return used
    for filename in os.listdir(USER_DATA_DIR):
        if not filename.endswith(".json"):
            continue
        path = os.path.join(USER_DATA_DIR, filename)
        try:
            with open(path, "r") as f:
                data = json.load(f)
            color = data.get("map_color")
            if color:
                used.add(color.lower())
        except Exception:
            pass
    return used


def get_user_map_owner(username):
    """Get the player's map owner_id and colour.
    
    Resolution order:
      1. Admin override file  (map_players.json)
      2. Persisted user data  (user_data/{username}.json)
      3. None  (caller should auto-assign)
    
    Returns:
        {"owner_id": str, "color": str}  or  None
    """
    # 1. Admin override
    overrides = _load_admin_overrides()
    if username in overrides:
        entry = overrides[username]
        color = entry.get("color", "").lower()
        if color:
            user_data = load_user_data(username)
            owner_id = user_data.get("map_owner_id")
            # Ensure the override colour is persisted
            if user_data.get("map_color", "").lower() != color or not owner_id:
                owner_id = owner_id or f"owner_{username}"
                user_data["map_owner_id"] = owner_id
                user_data["map_color"] = color
                save_user_data(username, user_data)
            return {"owner_id": owner_id, "color": color}

    # 2. Existing user data
    user_data = load_user_data(username)
    owner_id = user_data.get("map_owner_id")
    color = user_data.get("map_color")
    if owner_id and color:
        return {"owner_id": owner_id, "color": color}

    return None


def assign_user_map_owner(username):
    """Auto-assign a colour from the palette and persist it.
    
    Picks the first palette colour not yet used by any other player.
    Falls back to a hash-derived colour if the palette is exhausted.
    
    Returns:
        {"owner_id": str, "color": str}
    """
    used = _collect_used_colors()
    color = None
    for c in MAP_COLOR_PALETTE:
        if c.lower() not in used:
            color = c
            break
    if not color:
        # Palette exhausted — derive from username hash
        h = hash(username) & 0xFFFFFF
        color = f"{h:06x}"

    owner_id = f"owner_{username}"
    user_data = load_user_data(username)
    user_data["map_owner_id"] = owner_id
    user_data["map_color"] = color
    save_user_data(username, user_data)
    print(f"[Map] Auto-assigned colour {color} to {username} (owner_id={owner_id})")
    return {"owner_id": owner_id, "color": color}
