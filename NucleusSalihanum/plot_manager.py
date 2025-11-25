#!/usr/bin/env python
"""
Plot management system for Metaversum-Salihanum.
Handles plot boundaries, ownership, and object placement within plots.
"""

import os
import json
from constants import PLOTS_CONFIG_FILE, PLOTS_DATA_DIR


def load_plots_config():
    """Load plots configuration from JSON file
    
    Returns:
        Dictionary with plot configurations {plot_id: {owner, boundaries, ...}}
    """
    if not os.path.exists(PLOTS_CONFIG_FILE):
        # Create default configuration with example plots
        default_config = {
            "plots": [
                {
                    "plot_id": "plot_1",
                    "owner": "salih1",
                    "name": "Salih's Plot",
                    "boundaries": {
                        "min_x": -50.0,
                        "max_x": -30.0,
                        "min_y": 0.0,
                        "max_y": 50.0,
                        "min_z": -50.0,
                        "max_z": -30.0
                    }
                },
                {
                    "plot_id": "plot_2",
                    "owner": "tester",
                    "name": "Tester's Plot",
                    "boundaries": {
                        "min_x": 30.0,
                        "max_x": 50.0,
                        "min_y": 0.0,
                        "max_y": 50.0,
                        "min_z": -50.0,
                        "max_z": -30.0
                    }
                }
            ]
        }
        
        # Create the file with default configuration
        try:
            with open(PLOTS_CONFIG_FILE, "w") as f:
                json.dump(default_config, f, indent=2)
            print(f"Created default plots configuration: {PLOTS_CONFIG_FILE}")
        except Exception as e:
            print(f"Error creating plots config: {e}")
            return {}
    
    try:
        with open(PLOTS_CONFIG_FILE, "r") as f:
            config = json.load(f)
            # Convert list to dictionary keyed by plot_id
            plots_dict = {}
            for plot in config.get("plots", []):
                plots_dict[plot["plot_id"]] = plot
            return plots_dict
    except Exception as e:
        print(f"Error loading plots config: {e}")
        return {}


def get_plot_data_path(plot_id):
    """Get the path to a plot's data file"""
    return os.path.join(PLOTS_DATA_DIR, f"{plot_id}.json")


def load_plot_objects(plot_id):
    """Load objects placed in a specific plot
    
    Args:
        plot_id: The plot ID to load objects for
    
    Returns:
        Dictionary of objects {net_id: {transform, object_type, ...}}
    """
    plot_data_path = get_plot_data_path(plot_id)
    
    if not os.path.exists(plot_data_path):
        return {}
    
    try:
        with open(plot_data_path, "r") as f:
            return json.load(f)
    except Exception as e:
        print(f"Error loading plot objects for {plot_id}: {e}")
        return {}


def save_plot_objects(plot_id, objects):
    """Save objects placed in a specific plot
    
    Args:
        plot_id: The plot ID to save objects for
        objects: Dictionary of objects to save
    
    Returns:
        True if successful, False otherwise
    """
    plot_data_path = get_plot_data_path(plot_id)
    
    try:
        with open(plot_data_path, "w") as f:
            json.dump(objects, f, indent=2)
        return True
    except Exception as e:
        print(f"Error saving plot objects for {plot_id}: {e}")
        return False


def is_position_in_plot(position, boundaries):
    """Check if a position is within plot boundaries
    
    Args:
        position: Dictionary with x, y, z coordinates
        boundaries: Dictionary with min_x, max_x, min_y, max_y, min_z, max_z
    
    Returns:
        True if position is within boundaries, False otherwise
    """
    # Scale player position to world space (assuming world scale of 0.2)
    # Player positions are in game-space, boundaries are in world-space
    world_scale = 5.0  # Inverse of 0.2
    x = position["x"] * world_scale
    y = position["y"] * world_scale
    z = position["z"] * world_scale
    
    return (boundaries["min_x"] <= x <= boundaries["max_x"] and
            boundaries["min_y"] <= y <= boundaries["max_y"] and
            boundaries["min_z"] <= z <= boundaries["max_z"])


def get_user_plot(username, plots_config):
    """Get the plot owned by a specific user
    
    Args:
        username: The username to search for
        plots_config: Dictionary of all plots
    
    Returns:
        Tuple of (plot_id, plot_data) if found, (None, None) otherwise
    """
    for plot_id, plot_data in plots_config.items():
        if plot_data.get("owner", "").lower() == username.lower():
            return plot_id, plot_data
    return None, None


def get_plot_by_position(position, plots_config):
    """Find which plot (if any) contains a given position
    
    Args:
        position: Dictionary with x, y, z coordinates
        plots_config: Dictionary of all plots
    
    Returns:
        Tuple of (plot_id, plot_data) if found, (None, None) otherwise
    """
    for plot_id, plot_data in plots_config.items():
        boundaries = plot_data.get("boundaries", {})
        if is_position_in_plot(position, boundaries):
            return plot_id, plot_data
    return None, None


def can_user_place_object(username, position, plots_config):
    """Check if a user can place an object at a given position
    
    Args:
        username: The username attempting to place an object
        position: Dictionary with x, y, z coordinates
        plots_config: Dictionary of all plots
    
    Returns:
        Tuple of (can_place: bool, plot_id: str or None, reason: str)
    """
    # Find which plot this position is in
    plot_id, plot_data = get_plot_by_position(position, plots_config)
    
    if plot_id is None:
        # Position is not in any plot
        return False, None, "This position is not within any plot"
    
    # Check if user owns this plot
    plot_owner = plot_data.get("owner", "")
    if plot_owner.lower() != username.lower():
        return False, plot_id, f"This plot belongs to {plot_owner}"
    
    # User owns the plot and can place objects
    return True, plot_id, "OK"


def get_all_plot_objects(plots_config):
    """Load all objects from all plots
    
    Args:
        plots_config: Dictionary of all plots
    
    Returns:
        Dictionary mapping plot_id to objects dictionary
    """
    all_objects = {}
    for plot_id in plots_config.keys():
        all_objects[plot_id] = load_plot_objects(plot_id)
    return all_objects


def get_plot_info_for_client(plots_config):
    """Get plot information to send to clients
    
    Args:
        plots_config: Dictionary of all plots
    
    Returns:
        List of plot information dictionaries
    """
    plots_info = []
    for plot_id, plot_data in plots_config.items():
        plots_info.append({
            "plot_id": plot_id,
            "owner": plot_data.get("owner", ""),
            "name": plot_data.get("name", plot_id),
            "boundaries": plot_data.get("boundaries", {})
        })
    return plots_info

