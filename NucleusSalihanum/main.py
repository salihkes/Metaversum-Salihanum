#!/usr/bin/env python

import asyncio
import json
import websockets
import uuid
import random
import os
import base64
import threading
import time
from collections import defaultdict
from auth_manager import AuthManager

# Store connected clients and their data
clients = {}
next_id = 1
auth_manager = AuthManager()
# Replicated objects state: net_id -> {"transform": {...}}
objects = {}


# Directory for user textures
USER_TEXTURE_DIR = "user_textures"

# Directory for user data
USER_DATA_DIR = "user_data"

# World environment config
WORLD_ENVIRONMENT_FILE = "world_environment.json"

# Ensure the user texture directory exists
os.makedirs(USER_TEXTURE_DIR, exist_ok=True)

# Ensure directories exist
os.makedirs(USER_DATA_DIR, exist_ok=True)

# Voice chat server configuration
VOICE_CHAT_SERVER_URL = "ws://0.0.0.0:3246"

# Integrated Voice Chat Server
class VoiceChatServer:
    def __init__(self, port=3246):
        self.port = port
        self.clients = {}  # websocket -> client_info
        self.rooms = defaultdict(set)  # room_id -> set of websockets
        self.ping_interval = 3  # Send ping every 3 seconds
        self.ping_tasks = {}  # websocket -> ping task
        
    async def start_ping_task(self, websocket):
        """Start periodic ping for a client"""
        async def ping_loop():
            try:
                while websocket in self.clients:
                    await asyncio.sleep(self.ping_interval)
                    if websocket in self.clients:
                        try:
                            await websocket.send(json.dumps({"type": "ping"}))
                        except websockets.exceptions.ConnectionClosed:
                            break
                        except Exception as e:
                            print(f"Error sending ping: {e}")
                            break
            except asyncio.CancelledError:
                pass
        
        task = asyncio.create_task(ping_loop())
        self.ping_tasks[websocket] = task
        return task
    
    async def register_client(self, websocket, client_info):
        """Register a new client"""
        self.clients[websocket] = client_info
        room_id = client_info.get('room', 'default')
        self.rooms[room_id].add(websocket)
        
        # Start ping task for this client
        await self.start_ping_task(websocket)
        
        print(f"Voice client registered: {client_info['username']} in room '{room_id}' ({len(self.clients)} total)")
        
        # Notify room about new user
        await self.broadcast_to_room(room_id, {
            "type": "user_joined",
            "username": client_info['username'],
            "timestamp": int(time.time() * 1000)
        }, exclude=websocket)
    
    async def unregister_client(self, websocket):
        """Unregister a client"""
        if websocket in self.clients:
            client_info = self.clients[websocket]
            room_id = client_info.get('room', 'default')
            
            # Cancel ping task
            if websocket in self.ping_tasks:
                self.ping_tasks[websocket].cancel()
                del self.ping_tasks[websocket]
            
            # Remove from room and clients
            self.rooms[room_id].discard(websocket)
            del self.clients[websocket]
            
            print(f"Voice client unregistered: {client_info['username']} from room '{room_id}' ({len(self.clients)} remaining)")
            
            # Notify room about user leaving
            await self.broadcast_to_room(room_id, {
                "type": "user_left", 
                "username": client_info['username'],
                "timestamp": int(time.time() * 1000)
            })
    
    async def broadcast_to_room(self, room_id, message, exclude=None):
        """Broadcast message to all clients in a room"""
        if room_id not in self.rooms:
            return
            
        room_clients = self.rooms[room_id].copy()
        if exclude:
            room_clients.discard(exclude)
            
        if not room_clients:
            return
            
        message_json = json.dumps(message)
        disconnected = set()
        
        # Send to all clients in room
        for client_ws in room_clients:
            try:
                await client_ws.send(message_json)
            except websockets.exceptions.ConnectionClosed:
                disconnected.add(client_ws)
            except Exception as e:
                print(f"Error sending to voice client: {e}")
                disconnected.add(client_ws)
        
        # Clean up disconnected clients
        for ws in disconnected:
            await self.unregister_client(ws)
    
    async def handle_audio_chunk(self, websocket, data):
        """Handle incoming audio chunk and redistribute"""
        if websocket not in self.clients:
            return
            
        client_info = self.clients[websocket]
        room_id = client_info.get('room', 'default')
        
        # Add sender info to the audio chunk
        audio_message = {
            "type": "audio_chunk",
            "username": client_info['username'],
            "audio_data": data['audio_data'],
            "timestamp_ms": data.get('timestamp_ms', int(time.time() * 1000)),
            "chunk_info": data.get('chunk_info', {})
        }
        
        # Broadcast to all clients in room (including sender for echo/monitoring)
        await self.broadcast_to_room(room_id, audio_message)
    
    async def handle_client(self, websocket):
        """Handle individual client connection"""
        client_info = None
        try:
            # Wait for registration message
            registration_msg = await websocket.recv()
            registration_data = json.loads(registration_msg)
            
            if registration_data.get('type') != 'register':
                await websocket.send(json.dumps({"type": "error", "message": "First message must be registration"}))
                return
            
            client_info = {
                'username': registration_data.get('username', 'Anonymous'),
                'room': registration_data.get('room', 'default'),
                'user_type': registration_data.get('user_type', 'player')  # 'player' or 'streamer'
            }
            
            await self.register_client(websocket, client_info)
            
            # Send confirmation
            await websocket.send(json.dumps({
                "type": "registered",
                "username": client_info['username'],
                "room": client_info['room']
            }))
            
            # Handle messages
            async for message in websocket:
                try:
                    data = json.loads(message)
                    
                    if data.get('type') == 'audio_chunk':
                        await self.handle_audio_chunk(websocket, data)
                    elif data.get('type') == 'ping':
                        await websocket.send(json.dumps({"type": "pong"}))
                    elif data.get('type') == 'pong':
                        # Client responded to our ping - connection is alive
                        pass
                    else:
                        print(f"Unknown voice message type: {data.get('type')}")
                        
                except json.JSONDecodeError:
                    print("Received invalid JSON from voice client")
                except Exception as e:
                    print(f"Error handling voice message: {e}")
                    
        except websockets.exceptions.ConnectionClosed:
            pass
        except Exception as e:
            print(f"Error in voice client handler: {e}")
        finally:
            if client_info:
                await self.unregister_client(websocket)

    async def start_server(self):
        """Start the voice chat server"""
        print(f"Starting Voice Chat Server on port {self.port}")
        
        async with websockets.serve(self.handle_client, "0.0.0.0", self.port):
            print(f"Voice Chat Server listening on ws://0.0.0.0:{self.port}")
            await asyncio.Future()  # Run forever

# Global voice chat server instance
voice_chat_server = VoiceChatServer(3246)

# Function to get texture filename based on character type
def get_texture_filename(username, character_type):
    """Get the appropriate texture filename based on character type"""
    if character_type == "countryball":
        return f"{username}_countryball.png"
    else:
        return f"{username}.png"

# Function to check if user has texture for specific character type
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

# Function to send texture data for a user
async def send_texture_data(username, character_type, target_clients=None):
    """Send texture data to specified clients (or all clients if None)"""
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
        
        # Determine which clients to send to
        if target_clients is None:
            target_clients = clients.values()
        
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

# Function to get user accessories
def get_user_accessories(username):
    # Path to user's data file
    user_data_path = os.path.join(USER_DATA_DIR, f"{username}.json")
    
    # Default empty accessories if file doesn't exist
    if not os.path.exists(user_data_path):
        return []
    
    # Read and return accessories
    try:
        with open(user_data_path, "r") as f:
            user_data = json.load(f)
            return user_data.get("equipped_accessories", [])
    except Exception as e:
        print(f"Error reading accessories for {username}: {e}")
        return []

# Function to get user character type
def get_user_character_type(username):
    # Path to user's data file
    user_data_path = os.path.join(USER_DATA_DIR, f"{username}.json")
    
    # Default to humanoid if file doesn't exist
    if not os.path.exists(user_data_path):
        return "humanoid"
    
    # Read and return character type
    try:
        with open(user_data_path, "r") as f:
            user_data = json.load(f)
            return user_data.get("character_type", "humanoid")
    except Exception as e:
        print(f"Error reading character type for {username}: {e}")
        return "humanoid"

# Function to save user character type
def save_user_character_type(username, character_type):
    user_data_path = os.path.join(USER_DATA_DIR, f"{username}.json")
    
    # Load existing data or create new
    user_data = {}
    if os.path.exists(user_data_path):
        try:
            with open(user_data_path, "r") as f:
                user_data = json.load(f)
        except Exception as e:
            print(f"Error reading user data for {username}: {e}")
    
    # Update character type
    user_data["character_type"] = character_type
    
    # Save back to file
    try:
        with open(user_data_path, "w") as f:
            json.dump(user_data, f, indent=2)
        return True
    except Exception as e:
        print(f"Error saving character type for {username}: {e}")
        return False

# Function to read world environment configuration
def get_world_environment():
    """Read the world environment configuration from JSON file"""
    if not os.path.exists(WORLD_ENVIRONMENT_FILE):
        # Default environment
        return {"weather": {"type": "clear"}}
    
    try:
        with open(WORLD_ENVIRONMENT_FILE, "r") as f:
            return json.load(f)
    except Exception as e:
        print(f"Error reading world environment: {e}")
        return {"weather": {"type": "clear"}}

# Function to broadcast weather updates to all clients  
async def broadcast_weather_update():
    """Send current weather state to all connected clients"""
    world_env = get_world_environment()
    weather_data = world_env.get("weather", {"type": "clear"})
    
    print(f"Broadcasting weather update: {weather_data}")
    
    # Send to all connected clients
    for client_id, client in clients.items():
        try:
            await client["websocket"].send(json.dumps({
                "type": "weather_update",
                "weather": weather_data
            }))
        except Exception as e:
            print(f"Error sending weather update to client {client_id}: {e}")

async def handle_client(websocket):
    global next_id
    
    # Assign client ID
    client_id = next_id
    next_id += 1
    
    # Initial position (random within a small area)
    position = {
        "x": random.uniform(-5, 5),
        "y": 0,
        "z": random.uniform(-5, 5)
    }
    rotation = {"x": 0, "y": 0, "z": 0}
    
    # Store client data (initially not authenticated)
    clients[client_id] = {
        "websocket": websocket,
        "username": f"Guest{client_id}",
        "authenticated": False,
        "position": position,
        "rotation": rotation,
        "texture": None,  # Will be set when authenticated
        "character_type": "humanoid"  # Default character type
    }
    
    # Send connected message to client with voice chat server info
    await websocket.send(json.dumps({
        "type": "connected",
        "client_id": client_id,
        "username": clients[client_id]["username"],
        "authenticated": False,
        "character_type": clients[client_id]["character_type"],
        "voice_chat_server": VOICE_CHAT_SERVER_URL
    }))
    
    # Send list of existing players to the new client
    players_list = []
    for existing_id, existing_client in clients.items():
        if existing_id != client_id:  # Don't include the new client
            players_list.append({
                "id": existing_id,
                "username": existing_client["username"],
                "position": existing_client["position"],
                "rotation": existing_client["rotation"],
                "texture": existing_client["texture"],
                "accessories": existing_client.get("accessories", []),
                "character_type": existing_client.get("character_type", "humanoid")
            })
            
    await websocket.send(json.dumps({
        "type": "player_list",
        "players": players_list
    }))

    # Send existing replicated objects to the new client
    for net_id, obj in objects.items():
        await websocket.send(json.dumps({
            "type": "object_spawn",
            "net_id": net_id,
            "transform": obj.get("transform", {})
        }))
    
    # Send current weather state to the new client
    world_env = get_world_environment()
    weather_data = world_env.get("weather", {"type": "clear"})
    await websocket.send(json.dumps({
        "type": "weather_update",
        "weather": weather_data
    }))

    # Notify existing clients about new player
    for existing_id, existing_client in clients.items():
        if existing_id != client_id:  # Don't send to the new client
            await existing_client["websocket"].send(json.dumps({
                "type": "player_joined",
                "player_id": client_id,
                "username": clients[client_id]["username"],
                "position": clients[client_id]["position"],
                "rotation": clients[client_id]["rotation"],
                "texture": clients[client_id]["texture"],
                "accessories": clients[client_id].get("accessories", []),
                "character_type": clients[client_id]["character_type"]
            }))
    
    try:
        async for message in websocket:
            data = json.loads(message)
            
            # Remove voice chat message handling - these will go to the voice server
            # Keep all other message types (register, login, transform_update, chat_message, etc.)
            
            # Handle authentication requests
            if data["type"] == "register":
                username = data["username"]
                password = data["password"]
                
                success, message = auth_manager.register_user(username, password)
                
                await websocket.send(json.dumps({
                    "type": "register_response",
                    "success": success,
                    "message": message
                }))
            
            elif data["type"] == "login":
                username = data["username"]
                password = data["password"]
                
                success, result = auth_manager.authenticate_user(username, password)
                
                if success:
                    # Update client data with authenticated user
                    old_username = clients[client_id]["username"]
                    clients[client_id]["username"] = username
                    clients[client_id]["authenticated"] = True
                    clients[client_id]["display_name"] = result["display_name"]
                    
                    # Get user's accessories
                    accessories = get_user_accessories(username)
                    clients[client_id]["accessories"] = accessories
                    print(f"User {username} has accessories: {accessories}")  # Debug print
                    
                    # Get user's character type
                    character_type = get_user_character_type(username)
                    clients[client_id]["character_type"] = character_type
                    print(f"User {username} has character type: {character_type}")  # Debug print
                    
                    # First notify all clients about the name change
                    for cid, client in clients.items():
                        await client["websocket"].send(json.dumps({
                            "type": "system_message",
                            "message": f"{old_username} is now known as {username}"
                        }))
                    
                    # THEN check if user has a custom texture for their character type and send it AFTER the username change
                    has_texture = user_has_texture(username, character_type)
                    
                    # Set texture name for client
                    if has_texture:
                        clients[client_id]["texture"] = username
                        
                        # Send texture data to ALL clients using character-type-specific filename
                        await send_texture_data(username, character_type)
                        print(f"Sent {character_type} texture for {username}")
                    else:
                        clients[client_id]["texture"] = None
                        print(f"No {character_type} texture found for {username}")
                    
                    # Send accessories information to ALL clients - even if empty list
                    print(f"Sending accessories to all clients: {accessories}")  # Debug print
                    for cid, client in clients.items():
                        await client["websocket"].send(json.dumps({
                            "type": "accessories_data",
                            "player_id": client_id,  # Add player_id for easier matching
                            "username": username,
                            "accessories": accessories
                        }))
                    
                    # Send character type information to ALL clients
                    print(f"Sending character type to all clients: {character_type}")  # Debug print
                    for cid, client in clients.items():
                        await client["websocket"].send(json.dumps({
                            "type": "character_transform",
                            "player_id": client_id,
                            "username": username,
                            "character_type": character_type
                        }))
                
                await websocket.send(json.dumps({
                    "type": "login_response",
                    "success": success,
                    "message": "Login successful" if success else result
                }))
            
            elif data["type"] == "get_texture":
                # Client is requesting a specific texture
                texture_name = data["texture_name"]
                
                # Find the client with this username to get their character type
                target_character_type = "humanoid"  # Default
                for cid, client_data in clients.items():
                    if client_data["username"] == texture_name:
                        target_character_type = client_data.get("character_type", "humanoid")
                        break
                
                # Get the appropriate texture filename
                texture_filename = get_texture_filename(texture_name, target_character_type)
                texture_path = os.path.join(USER_TEXTURE_DIR, texture_filename)
                
                # If user-specific doesn't exist and it's countryball, try fallback
                if not os.path.exists(texture_path) and target_character_type == "countryball":
                    texture_path = os.path.join(USER_TEXTURE_DIR, "countryball.png")
                    texture_filename = "countryball.png"
                
                if os.path.exists(texture_path):
                    # Read and encode the texture file
                    with open(texture_path, "rb") as f:
                        texture_data = base64.b64encode(f.read()).decode('utf-8')
                    
                    # Send texture data to the client with correct character type
                    await websocket.send(json.dumps({
                        "type": "texture_data",
                        "texture_name": texture_name,
                        "character_type": target_character_type,  # Send the correct character type
                        "data": texture_data
                    }))
                    print(f"Sent {target_character_type} texture {texture_filename} for {texture_name}")
                else:
                    # Texture not found
                    await websocket.send(json.dumps({
                        "type": "system_message",
                        "message": f"Texture {texture_filename} not found"
                    }))
                    print(f"Texture {texture_filename} not found for {texture_name}")
            
            elif data["type"] == "transform_update":
                # Update client position and rotation
                clients[client_id]["position"] = data["position"]
                clients[client_id]["rotation"] = data["rotation"]
                
                # Store model rotation if provided
                model_rotation_y = data.get("model_rotation_y", None)
                
                # Broadcast to all other clients
                for cid, client in clients.items():
                    if cid != client_id:
                        message = {
                            "type": "player_transform",
                            "player_id": client_id,
                            "position": data["position"],
                            "rotation": data["rotation"]
                        }
                        
                        # Add model rotation if provided
                        if model_rotation_y is not None:
                            message["model_rotation_y"] = model_rotation_y
                            
                        await client["websocket"].send(json.dumps(message))
            
            elif data["type"] == "chat_message":
                # Get the message
                message = data["message"]
                
                # Check if it's a character transformation command
                if message.startswith("/transform "):
                    parts = message.split(" ")
                    if len(parts) >= 2:
                        character_type = parts[1].lower()
                        if character_type in ["humanoid", "countryball"]:
                            # Get old character type for texture handling
                            old_character_type = clients[client_id]["character_type"]
                            
                            # Update client's character type
                            clients[client_id]["character_type"] = character_type
                            
                            # Save to user data if authenticated
                            if clients[client_id]["authenticated"]:
                                username = clients[client_id]["username"]
                                save_user_character_type(username, character_type)
                                
                                # Check if user has texture for new character type
                                has_texture = user_has_texture(username, character_type)
                                
                                if has_texture:
                                    clients[client_id]["texture"] = username
                                    # Send new texture to all clients with character type info
                                    await send_texture_data(username, character_type)
                                    print(f"Sent {character_type} texture for {username} after transformation")
                                else:
                                    clients[client_id]["texture"] = None
                                    print(f"No {character_type} texture found for {username} after transformation")
                            
                            # Broadcast transformation to all clients
                            for cid, client in clients.items():
                                await client["websocket"].send(json.dumps({
                                    "type": "character_transform",
                                    "player_id": client_id,
                                    "username": clients[client_id]["username"],
                                    "character_type": character_type
                                }))
                            
                            # Send confirmation to the user
                            await websocket.send(json.dumps({
                                "type": "system_message",
                                "message": f"Transformed to {character_type}"
                            }))
                            continue
                        else:
                            await websocket.send(json.dumps({
                                "type": "system_message",
                                "message": "Invalid character type. Use 'humanoid' or 'countryball'"
                            }))
                            continue
                
                # Check if it's any other command
                if message.startswith("/"):
                    # Handle other commands on the client side
                    continue
                
                # Broadcast to all clients
                for cid, client in clients.items():
                    await client["websocket"].send(json.dumps({
                        "type": "chat_message",
                        "player_id": client_id,
                        "username": clients[client_id]["username"],
                        "message": message
                    }))
            
            elif data["type"] == "get_players":
                # Send list of existing players to the requesting client
                players_list = []
                for existing_id, existing_client in clients.items():
                    if existing_id != client_id:  # Don't include the requesting client
                        players_list.append({
                            "id": existing_id,
                            "username": existing_client["username"],
                            "position": existing_client["position"],
                            "rotation": existing_client["rotation"],
                            "texture": existing_client["texture"],
                            "accessories": existing_client.get("accessories", []),
                            "character_type": existing_client.get("character_type", "humanoid")
                        })
                        
                await websocket.send(json.dumps({
                    "type": "player_list",
                    "players": players_list
                }))

            elif data["type"] == "object_grab":
                net_id = str(data.get("net_id"))
                xf = data.get("transform", {})
                objects[net_id] = {"transform": xf}
                # Broadcast spawn/update to everyone
                for cid, client in clients.items():
                    await client["websocket"].send(json.dumps({
                        "type": "object_spawn",
                        "net_id": net_id,
                        "transform": xf,
                        "seq": data.get("seq", 0),
                        "authority": client_id
                    }))

            elif data["type"] == "object_release":
                net_id = str(data.get("net_id"))
                xf = data.get("transform", {})
                vel = data.get("velocity", {"x": 0, "y": 0, "z": 0})
                objects[net_id] = {"transform": xf}
                # Broadcast update to everyone
                for cid, client in clients.items():
                    await client["websocket"].send(json.dumps({
                        "type": "object_update",
                        "net_id": net_id,
                        "node_path": data.get("node_path", None),
                        "transform": xf,
                        "velocity": vel,
                        "seq": data.get("seq", 0),
                        "authority": client_id
                    }))

            elif data["type"] == "object_update":
                net_id = str(data.get("net_id"))
                xf = data.get("transform", {})
                objects[net_id] = {"transform": xf}
                # Broadcast update to everyone except sender
                for cid, client in clients.items():
                    if cid == client_id:
                        continue
                    await client["websocket"].send(json.dumps({
                        "type": "object_update",
                        "net_id": net_id,
                        "node_path": data.get("node_path", None),
                        "transform": xf,
                        "seq": data.get("seq", 0),
                        "authority": client_id
                    }))
    
    except websockets.exceptions.ConnectionClosed:
        pass
    finally:
        # Remove client
        if client_id in clients:
            username = clients[client_id]["username"]
            del clients[client_id]
            
            # Notify all clients about player leaving
            for cid, client in clients.items():
                await client["websocket"].send(json.dumps({
                    "type": "player_left",
                    "player_id": client_id
                }))
                
                await client["websocket"].send(json.dumps({
                    "type": "system_message",
                    "message": f"{username} has left the server"
                }))

async def weather_monitor():
    """Monitor world_environment.json for changes and broadcast updates"""
    last_weather = None
    
    while True:
        try:
            current_env = get_world_environment()
            current_weather = current_env.get("weather", {"type": "clear"})
            
            # Check if weather has changed
            if current_weather != last_weather:
                print(f"Weather changed from {last_weather} to {current_weather}")
                await broadcast_weather_update()
                last_weather = current_weather
            
            # Check every 5 seconds
            await asyncio.sleep(5)
        except Exception as e:
            print(f"Error in weather monitor: {e}")
            await asyncio.sleep(5)

async def main():
    # Start all servers and monitors concurrently
    game_server = websockets.serve(handle_client, "0.0.0.0", 8765)
    voice_server = voice_chat_server.start_server()
    weather_task = weather_monitor()
    
    print("Starting unified server with:")
    print("- Game Server on ws://0.0.0.0:8765")
    print("- Voice Chat Server on ws://0.0.0.0:3246")
    print("- Weather Monitor (checks world_environment.json every 5s)")
    
    # Run all services concurrently
    await asyncio.gather(
        game_server,
        voice_server,
        weather_task
    )

if __name__ == "__main__":
    asyncio.run(main())
