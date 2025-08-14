# Metaversum-Salihanum

A personal metaverse foundation built with Godot Engine (4) and Python, featuring dual character morphs, VR support, and real-time voice chat.

## 🌟 Origin Story

The passion and grounds for myself (salih1, known as salihkes on Github) on creating a personal digital space (now coined as a metaverse) originate in December of 2009 with the discovery that it was indeed possible to create your own experiences within the ROBLOX platform that I had joined september of the same year. Having built multiple experiences with immersive worlds with lore behind them, most noticably Polandball Roleplay, I couldnt just top there. I wanted to build my digital space where people could just enter in any method, let it be a standard computer, or a virtual reality glass. ROBLOX provided all these, despite having discovred Godot by 2020-2021, I continued with the platform.

This changed, in 2024. First of all; ROBLOX got banned in Turkey in August 2024 (due to child safety concerns by the Turkish government),
My violent overthrowal and exile from varios Discord ROBLOX communities from 2020 ranging to 2024 didnt help with my situation either (This README will not focus on who is right nor self-defense)

It was time; I had already made various Godot Projects before such as OpenPolandballRoleplay (https://github.com/salihkes/OpenPolandballRoleplay) before. But now; It was time to act as if there was an existential crisis. I had literally no digital representation.

This projects aims to not only fix that by providing a ground/base to build upon, but potentionally help you the reader (if you aren't salih1/salihkes) as well.
My goal is simple; Finish the project, release the game on a dedicated website, release the entire code under AGPL v3 on Github.

**Target Release Date**: I am planning to release this project to the public on September 19, 2025 (16th anniversary of me joining ROBLOX) as the day is pretty significant to me.

This project will not just let my digital presence flourish where I and my community upholds each other, rather than repeating many of the mistakes I did in Polandball Roleplay.

No, I want this project to help you potentionally achieve this as well, with same quality. This is one of many reasons for why I am opting for open-sourcing the code, humanity/the people must uphold and raise&nurture each other.


## 🎮 Features

### Dual Character System
- **Humanoid Morph**: Traditional avatar with support for numereous accessories, this is identical to the traditional ROBLOX humanoid including animations
- **Countryball Morph**: Spherical character with emotions and outline effects, and a flag as a base. This is very similar to ROBLOX Countryball games and has animations of its own
- **Dynamic Transformation**: Switch between morphs using `/transform humanoid` or `/transform countryball`. This setting is persistent and is remembered across sessions unless you change back
- **Custom Textures**: User-specific textures for both character types, so you have the freedom of creative expression

### Immersive Experience
- **Full VR Support**: Complete OpenXR integration. This project was built to support both traditional and virtual reality modes. I am still trying to figure out Microphone in Godot though (see relevant section)
- **Spatial Voice Chat**: 3D positional audio with real-time microphone streaming and room-based voice rooms. This is achieved by a Python script until I figure out how Godot handles this
- **Live TV Streaming**: PVM (Professional Video Monitor) system for streaming live content via Python scripts
- **Real-time Multiplayer**: Dual WebSocket architecture with live player synchronization
- **Custom Accessories**: Wearable items system (Antlers, HeadType2) with dynamic attachment
- **Dynamic Environment**: Custom sky shaders, water effects, atmospheric lighting, adjustable graphics depending on your device (you can manually override it if you want to), and day/night cycles (this can be disabled)

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


### Security & Privacy
- SHA256 password hashing with UUID-based salt
- Local JSON user database with secure credential storage
- Room-based voice chat isolation
- Private repository design (escaping platform dependency)

## 🌐 Future Vision

This foundation supports expansion into:
- Additional character morphs beyond humanoid/countryball
- Enhanced VR interactions and physics systems
- More sophisticated world-building and content creation tools
- Extended social features and private spaces

---