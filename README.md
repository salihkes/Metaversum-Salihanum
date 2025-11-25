# Metaversum-Salihanum

A personal metaverse foundation built with Godot Engine (4) and Python, featuring dual character morphs, VR support, and physics-based gameplay on a spherical planet with legacy flat workspace support.

## 🌟 Origin Story

The passion and grounds for myself (salih1, known as salihkes on Github) on creating a personal digital space (now coined as a metaverse) originate in December of 2009 with the discovery that it was indeed possible to create your own experiences within the ROBLOX platform that I had joined september of the same year. Having built multiple experiences with immersive worlds with lore behind them, most noticably Polandball Roleplay, I couldnt just top there. I wanted to build my digital space where people could just enter in any method, let it be a standard computer, or a virtual reality glass. ROBLOX provided all these, despite having discovred Godot by 2020-2021, I continued with the platform.

This changed, in 2024. First of all; ROBLOX got banned in Turkey in August 2024 (due to child safety concerns by the Turkish government),
My violent overthrowal and exile from varios Discord ROBLOX communities from 2020 ranging to 2024 didnt help with my situation either (This README will not focus on who is right nor self-defense)

It was time; I had already made various Godot Projects before such as OpenPolandballRoleplay (https://github.com/salihkes/OpenPolandballRoleplay) before. But now; It was time to act as if there was an existential crisis. I had literally no digital representation.

This projects aims to not only fix that by providing a ground/base to build upon, but potentionally help you the reader (if you aren't salih1/salihkes) as well.
My goal is simple; Finish the project, release the game on a dedicated website, release the entire code under AGPL v3 on Github.

**Target Release Date**: I was planning to release this project to the public on September 19, 2025 (16th anniversary of me joining ROBLOX) as the day was pretty significant to me. But the day has passed and currently the new release date is unknown.

This project will not just let my digital presence flourish where I and my community upholds each other, rather than repeating many of the mistakes I did in Polandball Roleplay.

No, I want this project to help you potentionally achieve this as well, with same quality. This is one of many reasons for why I am opting for open-sourcing the code, humanity/the people must uphold and raise&nurture each other.


## 🎮 Features

### Dual Character System
- **Humanoid Morph**: Traditional avatar with support for numereous accessories, this is identical to the traditional ROBLOX humanoid including animations
- **Countryball Morph**: Spherical character with emotions and outline effects, and a flag as a base. This is very similar to ROBLOX Countryball games and has animations of its own
- **Dynamic Transformation**: Switch between morphs using `/transform humanoid` or `/transform countryball`. This setting is persistent and is remembered across sessions unless you change back
- **Custom Textures**: User-specific textures for both character types, so you have the freedom of creative expression

### Immersive Experience
- **Spherical Planet Gameplay**: The entire game world takes place on a realistic spherical planet with authentic planetary gravity mechanics that affect movement and physics
- **Full VR Support**: Complete OpenXR integration. This project was built to support both traditional and virtual reality modes
- **Spatial Voice Chat**: 3D positional audio with real-time microphone streaming and room-based voice rooms. This was achieved by a seperate Python script until recently, now it is built in and works on both VR and Desktop.
- **Live Media Streaming**: A system for streaming content, whether it be live or pre-defined, via Python scripts.
- **Real-time Multiplayer**: Dual WebSocket architecture with live player synchronization
- **Custom Accessories**: Wearable items system (Antlers, HeadType2) with dynamic attachment
- **Dynamic Environment**: Custom sky shaders, water effects, atmospheric lighting, adjustable graphics depending on your device (you can manually override it if you want to), and day/night cycles (this can be disabled)
- **Plot System**: As this is a personal Metaverse, you should be able to own personal property to express yourself, hence there is a plot system and furniture decoration system.

#### Plot & Property System
- **User-owned plot boundaries**: 3D spatial boundaries with owner-based permissions
- **Persistent object placement**: Objects placed in plots are saved to per-plot JSON files
- **Server-side validation**: Position checks ensure users can only place objects in their own plots
- **Teleportation system**: `/teleport <location>` or `/teleport <your plot name>` (Also works for Public Property and Locations)
- **Plot metadata tracking**: Boundaries, owner, object count, creation date

### Media Broadcasting System
A in-world media streaming infrastructure with **four distinct modes**:
- **Video Playback**: Stream pre-recorded video files with synchronized audio
- **Desktop Broadcasting**: Real-time screen + audio capture (Windows/macOS)
- **Live Stream Ingestion**: Rebroadcast HLS/M3U8 streams
- **Universal Streaming**: VLC-based fallback for maximum URL compatibility

**Features:**
- Cross-platform capture (Windows GDI, macOS AVFoundation)
- Letterboxing/pillarboxing with aspect ratio preservation
- Multiple audio source fallbacks (VB-Audio Virtual Cable, Stereo Mix, etc.)
- Real-time JPEG encoding with adaptive quality
- Thread-safe WebSocket broadcasting to multiple viewers
- Synchronized audio/video with 48kHz stereo PCM

**Use cases:**
- Shared movie nights in VR
- Live event viewing parties (sports, concerts, etc.)
- Desktop sharing/presentations
- In-world video displays and screens

### Build Tools (Offline Studio Mode)
A complete ROBLOX Studio-inspired building system that works entirely offline, allowing creative freedom without platform dependency. Please note that as its offline, multiplayer capacities are not ENABLED. If you somehow create a server of the scene playerworkpace.tscn, other players wont see your builds. This is intentional, but may be changed in the future if a building game is desired rather than a metaverse:

- **Selection System**: 
  - Single and multi-object selection with box selection support
  - Shift-click to add/remove from selection
  - Group and individual part selection modes
  - Lock objects to prevent accidental modification
- **Transformation Tools**:
  - **Move Tool**: Drag objects with 3D axis gizmos (RGB arrows for X/Y/Z) or natural click-and-drag
  - **Resize Tool**: Scale objects on any axis with visual handles and configurable grid snapping
  - **Rotate Tool**: Rotate objects around any axis with torus ring gizmos
- **Appearance Tools**:
  - **Color Tool**: Paint mode with ROBLOX-style color palette (39 predefined colors)
  - **Material Tool**: Apply different materials and properties to objects
- **Creation & Organization**:
  - **New Part Tool**: Create new objects directly in the workspace
  - **Group Tool**: Organize multiple objects into groups for easier management
- **Quality of Life**:
  - Grid snapping with customizable increments for precise building
  - Delete key support for quick object removal
  - Undo/redo system for mistake-proof editing
  - Real-time visual gizmos that follow selected objects
  - Should not work (as its not designed for) with VR mode.
- **Export System**:
  - **OBJ Exporter** (Ctrl+E): Export your entire workspace to industry-standard OBJ format
  - Preserves materials, colors, and textures with automatic MTL file generation
  - Smart texture deduplication to optimize export file size
  - Exports to timestamped files for version tracking
  - Full preservation of transformations and mesh data
  - Compatible with Blender (Tested with Blender 3.6)
  - Requires a special script for mixing in textures and Colors. This is also an issue with ROBLOX OBJ exports which this game imitates.

All build tools function completely offline, requiring no internet connection or external server—true creative independence. This was my main complaint about ROBLOX Studio btw.

#### Dynamic Place Servers (Infrastructure Ready)
While currently unused, the codebase includes full support for ROBLOX-style "Places":
- **Dynamic subprocess spawning**: Place servers spin up on-demand with auto-assigned ports
- **Identity persistence**: Username, texture, character type, and accessories transfer across server switches
- **Scene data transfer**: Complete scene files (`.tscn`) sent to clients for loading
- **Checkpoint spawn system**: Places can define spawn points for players
- **Graceful cleanup**: Automatic termination of place servers on shutdown

### Technical Architecture
- **Godot Engine 4 Frontend**: 3D world rendering with spherical planet physics, OpenXR VR integration, spatial audio
- **Python Backend**: Unified server with concurrent game logic and voice chat servers
- **Dual WebSocket System**: 
  - Port 8765: Game logic, authentication, textures, chat
  - Port 3246: Dedicated voice chat with room-based audio distribution
- **Cross-Platform Audio**: FFmpeg-based microphone capture (Windows/macOS/Linux)
- **Physics Engine**: Custom planetary gravity system for authentic spherical world gameplay
- **Modular Design**: Separate systems for characters, environment, networking, planetary physics, and media

## 🚀 Quick Start

### Prerequisites
- Godot Engine 4.x
- Python 3.8+
- FFmpeg (for microphone capture)
- Required Python packages: `websockets`, `pydub`

### Running the Server
```bash
cd NucleusSalihanum
python main.py
```

This starts both servers:
- **Game Server**: `ws://127.0.0.1:8765` (player data, textures, chat)
- **Voice Chat Server**: `ws://127.0.0.1:3246` (real-time audio)

### For TV/Media Streaming (Optional)
Additional dependencies for broadcasting features:
pip install opencv-python numpy av pydub websockets**Platform-specific requirements:**
- **Windows**: VB-Audio Virtual Cable (for desktop audio capture)
- **macOS**: Screen Recording permissions in System Preferences
- **FFmpeg**: Must be in PATH for all streaming modes

#### Running a TV Stream
# Stream a video file
cd NucleusSalihanum/TV
python macOSVariant.py --video /path/to/video.mp4 --port 3245

# Stream your desktop
python macOSVariant.py --desktop --width 1280 --height 720

# Rebroadcast a Twitch/YouTube stream
python macOSVariant.py --vlc-url "https://twitch.tv/stream_url"

# Rebroadcast HLS/M3U8 (direct method)
python macOSVariant.py --m3u8-url "https://example.com/stream.m3u8"**Letterboxing mode** (preserves aspect ratio):
python macOSVariant.py --video movie.mp4 --letterbox

### Launching the Game
1. Open `IanuaSalihana/project.godot` in Godot Engine
2. Run the project (VR headset optional - auto-detects)
3. Use in-game commands:
   - `/register USERNAME PASSWORD` - Create account
   - `/login USERNAME PASSWORD` - Authenticate
   - `/transform countryball` or `/transform humanoid` - Morph characters
   - `/help` - Show all available commands

## 🏗️ Architecture

### Backend (`NucleusSalihanum/`)
- **`main.py`**: Unified server with game logic and voice chat
- **`auth_manager.py`**: User authentication and data management
- **`texture_server.py`**: *(Legacy - functionality moved to main.py)*
- **`TV/`**: Media streaming utilities for enhanced features

### Frontend (`IanuaSalihana/`)
- **`src/networking/`**: WebSocket clients and texture management
- **`src/character/`**: Humanoid character with accessories system
- **`src/countryball/`**: Countryball character with emotions and effects
- **`src/planet/`**: Planetary gravity and physics systems
- **`src/ui/`**: Chat interface and user interaction

### Why Open Source?
This project is AGPL v3 because I believe:
- Digital spaces should be owned by their communities, not corporations
- Platform bans shouldn't erase years of creative work
- Others deserve the chance to build their own digital homes
- Knowledge should be shared, not hoarded

If this project helps you build your own metaverse, that's the entire point.
---