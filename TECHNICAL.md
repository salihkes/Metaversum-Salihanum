# Metaversum-Salihanum - Technical Documentation

This document covers the technical details, setup instructions, architecture, and complete feature list for developers and self-hosters.

## Table of Contents
- [Architecture Overview](#architecture-overview)
- [Complete Feature List](#complete-feature-list)
- [Chat Commands Reference](#chat-commands-reference)
- [Prerequisites](#prerequisites)
- [Setup & Running](#setup--running)
- [Project Structure](#project-structure)
- [Media Broadcasting System](#media-broadcasting-system)
- [Remote Play / Pixel Streaming](#remote-play--pixel-streaming)

---

## Architecture Overview

### Tech Stack
- **Game Client**: Godot Engine 4 with GDScript
- **Backend Server**: Python with WebSockets
- **Web Frontend**: Flask with HTML templates
- **VR Runtime**: OpenXR

### Server Architecture
The backend uses a dual WebSocket system plus HTTP content delivery:
- **Port 8765**: Game server (authentication, player data, textures, chat, game logic)
- **Port 3246**: Voice chat server (real-time audio with room-based distribution)
- **Port 443 (Frontend)**: Web interface + PCK file delivery via `/pck/` route

### Communication Flow
```
Web Frontend (Flask) ←→ User Browser
        ↓ SSO Token
        ↓ PCK Downloads (https://domain/pck/*.pck)
Godot Client ←→ Game Server (8765) ←→ Database/Files
Godot Client ←→ Voice Server (3246) ←→ Other Clients
```

### Province Map Network Protocol
On login, the server auto-assigns a unique colour to the player and injects them into the map state. Province changes are replicated via debounced full-state sync.

| Message | Direction | Purpose |
|---------|-----------|---------|
| `map_state` | Server → Client | Initial full map state on connect |
| `map_full_update` | Both | Full state sync after changes (debounced on client) |
| `map_request_state` | Client → Server | Re-request current state |
| `map_player_owner` | Server → Client | Assign player's owner ID + colour on login |
| `treaty_propose` | Client → Server | Propose peace treaty to target player |
| `treaty_pending` | Server → Proposer | Confirm proposal was created |
| `treaty_incoming` | Server → Target | Notify target of incoming proposal (with countdown) |
| `treaty_respond` | Client → Server | Accept or reject a treaty |
| `treaty_resolved` | Server → Both | Treaty outcome (accepted/rejected/expired) |

---

## Complete Feature List

### Character System
| Feature | Description |
|---------|-------------|
| Humanoid Avatar | Traditional avatar with customizable accessories |
| Countryball | Spherical character with flag textures |
| Countryball (One-sided) | For real country flags without special UV mapping |
| Character Transformation | Switch between types with `/transform` |
| Custom Textures | Upload PNG decals via web interface (max 5MB) |
| Accessories System | Equip and persist accessories per character |
| Emotions | Happy, sad, serious, neutral expressions for countryballs |
| Persistence | Character type, textures, and accessories saved per user |

### World & Environment
| Feature | Description |
|---------|-------------|
| Spherical Planets | Authentic planetary gravity affecting players and objects |
| Multiple Planets | Different explorable planets |
| Day/Night Cycle | Dynamic time of day (can be disabled) |
| Weather System | Rain effects and dynamic weather |
| Water Effects | Realistic water rendering |
| Custom Sky Shaders | Atmospheric sky rendering |
| Adjustable Graphics | Performance settings based on device capability |
| Checkpoints | Spawn points throughout the world |

### Multiplayer & Social
| Feature | Description |
|---------|-------------|
| Real-time Sync | Live player position, rotation, and appearance |
| Voice Chat | 3D positional audio with room support |
| Text Chat | In-game chat with profanity filter |
| Join/Leave Notifications | See when players connect/disconnect |
| Player List | Request list of online players |

### Plot & Property System
| Feature | Description |
|---------|-------------|
| Plot Ownership | Own land with defined 3D boundaries |
| Object Placement | Place objects within your plot |
| Object Removal | Remove objects from your plot |
| Position Updates | Move objects within boundaries |
| Persistence | Plot objects saved to JSON files |
| Server Validation | Position checks ensure plot boundary enforcement |
| Teleport to Plot | Teleport directly to your plot by name |

### Dynamic Content Delivery (PCK System)
| Feature | Description |
|---------|-------------|
| Server Manifest | `pck_manifest.json` defines available packages with version strings |
| Delta Downloads | Only packages with version mismatches or missing files are downloaded |
| HTTP Delivery | PCK files served via the Flask Frontend (`/pck/` route) through Cloudflare |
| Auto-Loading | Downloaded `.pck` files are loaded with `ProjectSettings.load_resource_pack()` |
| Scene Instantiation | Each package can define a `scene_path` that is automatically instantiated into the workspace |
| Baseplate Removal | The default baseplate is removed when a map pack loads, acting as fallback when no map is available |
| Loading Screen | Displays download progress matching the project's Loading.tscn style |
| Local Caching | Client caches downloaded packages and versions at `user://pck_manifest.json` |
| Obsolete Cleanup | Packages removed from the server manifest are deleted from clients |

### Places System (Unused / Not Enabled by Default)

> **Note**: The Places system is currently unused in Metaversum-Salihanum. The lobby serves as the main game world. This infrastructure is included for future use or for projects based on this codebase that want ROBLOX-style separate "places" (alternative dimensions/universes).

| Feature | Description |
|---------|-------------|
| User-Created Places | Upload custom spaces (`.tscn` files) |
| Place Listing | View available places with `/places` |
| Join Places | Enter user-created spaces with `/join` |
| Return to Lobby | Exit places with `/lobby` |
| Scene Transfer | Complete scene data sent to clients |
| Checkpoint Spawns | Places can define custom spawn points |

### Province Map (Territory Gameplay)
| Feature | Description |
|---------|-------------|
| Province Map | Paintable world map rendered as a 3D plane with per-pixel province detection |
| Auto-Assigned Colours | Each player receives a unique colour from a 16-colour palette on first login, persisted in user data |
| Admin Colour Override | Admins can override player colours via `map_players.json` (`{"username": {"color": "hex"}}`) |
| Click-to-Claim | Click an unowned province to claim it as your own |
| Click-to-Occupy | Click another player's province to occupy it (your colour overlays theirs) |
| Click-to-Defend | Click your own occupied province to remove the occupier |
| Click-to-Unclaim | Click your own unoccupied province to release it |
| Peace Treaties | Shift+Click to propose a two-sided treaty; target player gets Accept/Reject popup with 30s countdown |
| Treaty Transfers | Accepted treaties transfer all mutually occupied provinces to their respective occupiers |
| Full-State Replication | Map state (owners + provinces) replicated to all clients with debounced full-state sync |
| Server Persistence | Map state saved to `map_state.json` on every change |
| Treaty Expiry | Server-side periodic cleanup expires unanswered treaty proposals after 30 seconds |

### Monster/Creature System
| Feature | Description |
|---------|-------------|
| Monster Spawning | Spawn creatures in the world |
| Monster Ownership | Own and collect multiple monsters |
| Persistence | Monsters saved per user account |
| Replication | Monsters sync across all clients |

### Building Tools (Offline Studio)
| Tool | Key | Description |
|------|-----|-------------|
| Move | 1 | Drag objects with 3D axis gizmos |
| Rotate | 2 | Rotate around any axis with ring gizmos |
| Resize | 3 | Scale on any axis with handles |
| Material | 4 | Apply materials and properties |
| New Part | 5 | Create new objects |
| Color | 6 | Paint with 39 ROBLOX-style colors |
| Group | 7 | Organize objects into groups |

| Shortcut | Action |
|----------|--------|
| Ctrl+C | Copy |
| Ctrl+V | Paste |
| Ctrl+X | Cut |
| Ctrl+D | Duplicate |
| Ctrl+A | Select All |
| Ctrl+Z | Undo |
| Ctrl+Y / Ctrl+Shift+Z | Redo |
| Ctrl+E | Export to OBJ |
| Delete | Remove selected |

| Feature | Description |
|---------|-------------|
| Multi-select | Box selection and Shift-click |
| Grid Snapping | Configurable snap increments |
| Object Locking | Prevent accidental modification |
| Local Save/Load | `/save` and `/load` commands |
| OBJ Export | Industry-standard format with MTL |
| Upload Places | `/upload` to share your creation (Places system unused) |

### VR Features
| Feature | Description |
|---------|-------------|
| OpenXR Integration | Full VR headset support |
| Controller Grabbing | Left/right hand grip to grab objects |
| VR Movement | Controller-based locomotion |
| VR Menu | Right menu button toggle |
| VR Jump | A button on right controller |

### Web Interface
| Feature | Description |
|---------|-------------|
| Login/Register | Account management |
| Guest Mode | Play without account (configurable) |
| SSO Authentication | Seamless web-to-game login |
| Texture Upload | Upload character decals (PNG, max 5MB) |
| Settings Page | Character customization options |
| Game Launcher | Launch game in browser |

### Moderation
| Feature | Description |
|---------|-------------|
| Profanity Filter | Censors bad words with asterisks |
| Leetspeak Detection | Handles character substitutions |
| Regex Patterns | Custom filter rules |
| Hot Reload | `/reloadfilter` without restart |
| Word Lists | Configurable blocked terms |

---

## Chat Commands Reference

### Authentication (Lobby Only)
| Command | Description |
|---------|-------------|
| `/register <user> <pass>` | Create new account |
| `/login <user> <pass>` | Log in to existing account |
| `/logout` | Log out of current session |

### Connection
| Command | Description |
|---------|-------------|
| `/connect` | Connect to server |
| `/disconnect` | Disconnect from server |
| `/help` | Show available commands |

### Character
| Command | Description |
|---------|-------------|
| `/transform humanoid` | Transform to humanoid |
| `/transform countryball` | Transform to countryball |
| `/countryball <flag>` | Transform with specific flag (e.g., `TUR`, `RUS_Republic`) |
| `/happy` | Set happy emotion |
| `/sad` | Set sad emotion |
| `/serious` | Set serious emotion |
| `/neutral` | Set neutral emotion |

### Navigation
| Command | Description |
|---------|-------------|
| `/teleport <dest>` | Teleport to location (asia, europe, parliament, or plot name) |
| `/myplot` or `/plot` | View your plot info |

### Places (Unused System)
| Command | Description |
|---------|-------------|
| `/places` | List available places |
| `/join <name>` | Join a place |
| `/lobby` | Return to main lobby |
| `/upload` | Upload current workspace as place |

### Studio (Offline)
| Command | Description |
|---------|-------------|
| `/save` | Save workspace locally |
| `/load` | Load saved workspace |

### Admin
| Command | Description |
|---------|-------------|
| `/reloadfilter` | Reload chat filter configuration |

---

## Prerequisites

### Required
- **Godot Engine 4.x** - Game client
- **Python 3.8+** - Backend server
- **FFmpeg** - Audio/video processing (must be in PATH)

### Recommended: Use Miniconda

We recommend using [Miniconda](https://docs.conda.io/en/latest/miniconda.html) to manage Python environments. This keeps dependencies isolated and avoids conflicts with your system Python.

```bash
# Create a new environment
conda create -n metaversum python=3.11
conda activate metaversum

# Install FFmpeg via conda (optional, or install system-wide)
conda install -c conda-forge ffmpeg
```

### Platform-Specific
- **Windows**: VB-Audio Virtual Cable (for desktop audio capture)
- **macOS**: Screen Recording permissions in System Preferences

---

## Setup & Running

### 1. Start the Backend Server
```bash
cd NucleusSalihanum
pip install -r requirements.txt
python main.py
```

This starts:
- Game Server: `ws://127.0.0.1:8765`
- Voice Server: `ws://127.0.0.1:3246`

### 2. Start the Web Frontend (Optional)
```bash
cd Frontend
pip install -r requirements.txt
python app.py
```

Access at: `http://127.0.0.1:5000`

### 3. Launch the Game Client
1. Open `IanuaSalihana/project.godot` in Godot Engine 4
2. Run the project (F5)
3. VR headset auto-detected if connected

### 4. Add Dynamic Content Packages (Optional)

The game can download map and asset packages on-the-fly so the base game stays small. Packages are `.pck` files exported from Godot.

**Creating a package:**
1. In Godot, export a PCK: **Project > Export > Export PCK/ZIP**
2. Place the `.pck` file in `NucleusSalihanum/pck_packages/`
3. Register it in `NucleusSalihanum/pck_manifest.json`:

```json
{
    "packages": {
        "MyMap": {
            "version": "1.00",
            "filename": "MyMap.pck",
            "scene_path": "res://src/dynamic/mymap/assets.tscn",
            "description": "My map assets"
        }
    }
}
```

**Updating a package:** Replace the `.pck` file and bump the `version` string. Clients with the old version will automatically re-download only the updated package.

**Removing a package:** Delete its entry from the manifest. Clients will remove the cached file and unload the scene.

### 5. Media Streaming (Optional)
```bash
cd NucleusSalihanum/TV

# Stream a video file
python macOSVariant.py --video /path/to/video.mp4 --port 3245

# Stream desktop
python macOSVariant.py --desktop --width 1280 --height 720

# Rebroadcast a live stream
python macOSVariant.py --vlc-url "https://example.com/live.m3u8"

# With letterboxing (preserves aspect ratio)
python macOSVariant.py --video movie.mp4 --letterbox
```

---

## Project Structure

```
Metaversum-Salihanum/
├── NucleusSalihanum/          # Python Backend
│   ├── main.py                # Main server (game + voice)
│   ├── auth_manager.py        # Authentication & user data
│   ├── user_manager.py        # User session management
│   ├── plot_manager.py        # Plot ownership & objects
│   ├── place_server.py        # Places system
│   ├── texture_manager.py     # Texture handling
│   ├── chat_filter.py         # Profanity filtering
│   ├── constants.py           # Server configuration
│   ├── pck_server.py          # PCK manifest utilities
│   ├── pck_manifest.json      # Defines available PCK packages & versions
│   ├── pck_packages/          # PCK files served to clients
│   ├── map_state.json         # Province map state (owners + provinces, auto-saved)
│   ├── map_players.json       # (Optional) Admin colour overrides per player
│   └── TV/                    # Media streaming utilities
│       └── macOSVariant.py    # Cross-platform TV streamer
│
├── Frontend/                  # Flask Web Interface
│   ├── app.py                 # Web server + PCK file delivery (/pck/ route)
│   └── templates/             # HTML templates
│       ├── home.html
│       ├── login.html
│       ├── play.html
│       └── settings.html
│
├── IanuaSalihana/             # Godot Game Client
│   ├── project.godot          # Godot project file
│   └── src/
│       ├── networking/        # WebSocket clients
│       │   ├── network_controller.gd  # Main networking
│       │   ├── pck_manager.gd         # PCK download, versioning & loading
│       │   └── texture_manager.gd     # Texture handling
│       ├── dynamic/           # Scenes loaded from PCK packages
│       ├── character/         # Humanoid system
│       ├── countryball/       # Countryball system
│       ├── paintablemap/      # Province map system
│       │   ├── scenes/map_3d.tscn       # Map scene (3D plane + UI)
│       │   ├── scripts/province_map.gd  # Core map: province detection, owners, shaders
│       │   ├── scripts/main.gd          # Gameplay: click-to-claim, treaty UI
│       │   ├── scripts/map_network.gd   # Network bridge: debounced state sync, treaty routing
│       │   └── assets/                  # Province texture + data
│       ├── scenes/            # World scenes
│       │   ├── workspace.tscn       # Standard world (with fallback baseplate)
│       │   └── planetworkspace.tscn # Spherical planet world
│       └── ui/                # Chat & interface
│
└── Extra/                     # Additional Utilities
    ├── pixel_streaming_server/  # Remote play via browser
    │   ├── server.py            # Local streaming server
    │   ├── local_streamer.py    # Remote server streamer
    │   ├── vds_server.py        # Video distribution server
    │   └── static/templates/    # Web client
    └── voice_microphone_client.py  # Standalone voice client
```

---

## Media Broadcasting System

Four distinct streaming modes for in-world displays:

| Mode | Use Case |
|------|----------|
| Video Playback | Stream pre-recorded video files |
| Desktop Broadcasting | Real-time screen + audio capture |
| Live Stream Ingestion | Rebroadcast HLS/M3U8 streams |
| Universal Streaming | VLC-based fallback for any URL |

### Technical Features
- Cross-platform capture (Windows GDI, macOS AVFoundation)
- Letterboxing/pillarboxing with aspect ratio preservation
- Multiple audio source fallbacks
- Real-time JPEG encoding with adaptive quality
- Thread-safe WebSocket broadcasting
- Synchronized audio/video at 48kHz stereo PCM

---

## Remote Play / Pixel Streaming

Stream the game to any web browser for remote play.

### Components
| File | Purpose |
|------|---------|
| `server.py` | Local streaming server |
| `local_streamer.py` | Stream to remote VDS |
| `vds_server.py` | Video distribution middleware |
| `client.js` | Web client controls |

### Features
- Real-time game window streaming
- Mouse, keyboard, and touch input forwarding
- Passphrase-protected access
- Pointer lock for first-person controls
- Mobile/tablet touch support

### Usage
```bash
cd Extra/pixel_streaming_server
python server.py
```

Access at: `http://localhost:8080`

---

## License

This project is licensed under the [GNU Affero General Public License v3.0](LICENSE).

See main [README.md](README.md) for the philosophy behind this choice.
