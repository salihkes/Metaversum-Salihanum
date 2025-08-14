# Metaversum-Salihanum

A personal metaverse foundation built with Godot Engine (4) and Python, featuring dual character morphs, VR support, and real-time voice chat.

## 🌟 Origin Story

This project was born out of necessity and creative freedom. After ROBLOX got banned in Turkey in August 2024 (due to child safety concerns by the Turkish government) and before that, following some community dramas that led to my exile from the ROBLOX Countryballs community, I decided to build my own virtual space. Rather than depend on external platforms that can disappear overnight, I created a foundation for a personal metaverse where I have complete control over the experience. I was imagining this since 2020, and now, I have done it.

## 🎮 Features

### Dual Character System
- **Humanoid Morph**: Traditional avatar with accessories (Antlers, HeadType2, etc.)
- **Countryball Morph**: Spherical character with emotions and outline effects
- **Dynamic Transformation**: Switch between morphs using `/transform humanoid` or `/transform countryball`
- **Custom Textures**: User-specific textures for both character types

### Immersive Experience
- **Full VR Support**: Complete OpenXR integration with Quest Pro controller models and spatial tracking
- **Spatial Voice Chat**: 3D positional audio with real-time microphone streaming and room-based voice rooms
- **Live TV Streaming**: PVM (Professional Video Monitor) system for streaming live content via Python scripts
- **Real-time Multiplayer**: Dual WebSocket architecture with live player synchronization
- **Custom Accessories**: Wearable items system (Antlers, HeadType2) with dynamic attachment
- **Dynamic Environment**: Custom sky shaders, water effects, atmospheric lighting, and day/night cycles

### Media & Streaming
- **PVM System**: Professional Video Monitor for live TV/media streaming within the metaverse
- **RetroArch Integration**: Support for retro gaming content streaming 
- **Multi-format Support**: DirectMedia, Desktop capture, M3U8 streams, VLC integration
- **Real-time Audio**: 48kHz/16-bit spatial audio with low-latency streaming

### Technical Architecture
- **Godot Engine 4 Frontend**: 3D world rendering, OpenXR VR integration, spatial audio
- **Python Backend**: Unified server with concurrent game logic and voice chat servers
- **Dual WebSocket System**: 
  - Port 8765: Game logic, authentication, textures, chat
  - Port 3246: Dedicated voice chat with room-based audio distribution
- **Cross-Platform Audio**: FFmpeg-based microphone capture (Windows/macOS/Linux)
- **Modular Design**: Separate systems for characters, environment, networking, and media

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

### For Voice Chat Users
Before entering the game, run the microphone client:
```bash
cd NucleusSalihanum
python voice_microphone_client.py --username YOUR_USERNAME --password YOUR_PASSWORD --room default
```

### For Live TV Streaming (Optional)
Stream content to in-world PVM displays:
```bash
cd NucleusSalihanum/TV
python macOSVariant.py --video-path /path/to/content.mp4  # Multiple streaming options available
```

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
- **`src/world/`**: 3D environment, shaders, and world assets
- **`src/ui/`**: Chat interface and user interaction

### Character Morphs

#### Humanoid System
- Base model with texture mapping
- Accessory attachment system (Antlers, HeadType2)
- Standard 3D movement and animations
- Custom user textures support

#### Countryball System  
- **Base.obj**: Core spherical model
- **Emotions.obj**: Facial expression variations
- **Outline.obj**: Visual emphasis effects
- Country-specific texture mapping
- Physics-based movement

## 🎭 Personal Touch

This isn't just a technical project - it's a creative sanctuary. The dual character system represents different aspects of online identity:
- **Humanoid**: Traditional self-representation
- **Countryball**: Playful, community-oriented identity (honoring the community I once belonged to)

The VR integration and spatial voice chat create an intimate, immersive space for personal use and close friends.

## 🏗️ System Components

### Character Systems
- **Humanoid**: Traditional 3D avatar with accessory attachment points
- **Countryball**: Physics-based spherical character with emotional expressions
  - `Base.obj`: Core sphere geometry
  - `Emotions.obj`: Facial expression variations  
  - `Outline.obj`: Visual emphasis effects
- **Dynamic Morphing**: Runtime transformation between character types
- **Texture Management**: Base64-encoded custom textures via WebSocket

### Environment & Visual Effects
- **Custom Sky System**: Dynamic sky shaders with day/night transitions
- **Water Simulation**: Animated water surfaces with custom materials
- **Professional Lighting**: Directional lighting with atmospheric effects

### Media Integration
- **PVM (Professional Video Monitor)**: In-world TV screens for live content
- **RetroArch Viewer**: Retro gaming content streaming to 3D displays
- **Multi-source Streaming**: Desktop capture, media files, live streams
- **3D Spatial Media**: Positioned audio/video sources in the world

## 🔧 Development Notes

### Voice Chat Architecture
The voice chat system uses a sophisticated dual-WebSocket approach:
1. **Game Connection** (8765): Player data, positions, textures, authentication
2. **Voice Connection** (3246): Dedicated real-time audio with room management
3. **External Microphone Client**: Solves Godot microphone capture limitations via FFmpeg

### VR Implementation
- **OpenXR Integration**: Full VR support with comprehensive controller mapping
- **Quest Pro Models**: Accurate 3D controller representations
- **Spatial Interaction**: VR-optimized movement and interaction systems
- **Comfort Features**: VR-specific shader adjustments and movement options

### Asset Management Strategy
- ✅ **Essential preservation**: VR controllers, character models, world assets, game sounds
- ❌ **Intelligent exclusion**: Auto-generated files, large development assets
- 🎯 **Selective tracking**: Critical functionality while maintaining lean repo

### Security & Privacy
- SHA256 password hashing with UUID-based salt
- Local JSON user database with secure credential storage
- Room-based voice chat isolation
- Private repository design (escaping platform dependency)

## 🎯 Advanced Features Discovered

### Sophisticated VR System
- **Complete OpenXR Action Mapping**: Full controller binding system with 22+ actions
- **Multi-VR Platform Support**: Quest, Vive, and other OpenXR-compatible headsets
- **Spatial Audio**: True 3D positional voice chat with distance attenuation
- **VR Comfort Options**: Shader intensity reduction for VR mode comfort

### Unique Media Integration
- **In-World TV Displays**: Real 3D objects that can stream live content
- **RetroArch Integration**: Classic gaming content viewable in the metaverse
- **Professional Streaming**: Multiple input sources (desktop, files, URLs, VLC)
- **Synchronized Audio/Video**: Frame-accurate streaming with spatial positioning

### Character Depth
- **Emotional Countryball System**: Separate geometry for different facial expressions
- **Accessory Physics**: Dynamic attachment system for wearable items
- **Texture Hot-Swapping**: Real-time character appearance changes
- **Dual Morph Architecture**: Seamless switching between completely different character types

### Network Architecture Excellence
- **Concurrent Server Design**: Game logic and voice chat in unified Python process
- **Room-Based Voice**: Isolated audio channels for different spaces
- **Authentication Integration**: Secure login before voice chat access
- **Ping/Keepalive System**: Robust connection management with automatic cleanup

## 🌐 Future Vision

This foundation supports expansion into:
- Additional character morphs beyond humanoid/countryball
- Enhanced VR interactions and physics systems
- More sophisticated world-building and content creation tools
- Extended social features and private spaces

---

*"When existing platforms fail us, we build our own worlds. When communities exile us, we create better ones."*

## 📝 License

Private project - not intended for public distribution.  
Born from the necessity of platform independence and creative freedom.