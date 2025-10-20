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
import subprocess
import signal
import atexit
from collections import defaultdict
from auth_manager import AuthManager
from constants import (
    USER_TEXTURE_DIR, USER_DATA_DIR, PLACES_DIR, WORLD_ENVIRONMENT_FILE,
    VOICE_CHAT_SERVER_URL, VOICE_CHAT_SERVER_PORT, MAIN_SERVER_PORT,
    MAIN_SERVER_HOST, PLACE_SERVER_START_PORT, MAX_MESSAGE_SIZE, MAX_QUEUE_SIZE
)
from texture_manager import get_texture_filename, user_has_texture, send_texture_data, get_texture_path
from user_manager import (
    get_user_accessories, get_user_character_type, save_user_character_type,
    load_user_data, save_user_data
)

# Store connected clients and their data
clients = {}
next_id = 1
auth_manager = AuthManager()
# Replicated objects state: net_id -> {"transform": {...}}
objects = {}

# Place server management
place_servers = {}  # place_name -> {"port": int, "process": subprocess.Popen, "url": str}
next_place_port = PLACE_SERVER_START_PORT

# Ensure directories exist
os.makedirs(USER_TEXTURE_DIR, exist_ok=True)
os.makedirs(USER_DATA_DIR, exist_ok=True)
os.makedirs(PLACES_DIR, exist_ok=True)

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
voice_chat_server = VoiceChatServer(VOICE_CHAT_SERVER_PORT)

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

# Place server management functions
def get_place_scene_path(place_name):
    """Get the path to a place scene file"""
    return os.path.join(PLACES_DIR, f"{place_name}.tscn")

def place_scene_exists(place_name):
    """Check if a place scene file exists"""
    return os.path.exists(get_place_scene_path(place_name))

def read_place_scene(place_name):
    """Read a place scene file"""
    path = get_place_scene_path(place_name)
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as f:
            return f.read()
    return None

async def spawn_place_server(place_name):
    """Spawn a new place server for the given place"""
    global next_place_port
    
    if place_name in place_servers:
        print(f"Place server '{place_name}' already running")
        return place_servers[place_name]
    
    # Check if place scene exists
    if not place_scene_exists(place_name):
        print(f"Place scene '{place_name}' not found")
        return None
    
    # Assign a port
    port = next_place_port
    next_place_port += 1
    
    # Spawn the place server process
    try:
        process = subprocess.Popen(
            ["python", "place_server.py", place_name, str(port)],
            cwd=os.getcwd(),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        
        # Wait a moment for the server to start
        await asyncio.sleep(1)
        
        # Store the server info
        server_info = {
            "port": port,
            "process": process,
            "url": f"ws://127.0.0.1:{port}",
            "place_name": place_name
        }
        place_servers[place_name] = server_info
        
        print(f"Spawned place server '{place_name}' on port {port}")
        return server_info
    except Exception as e:
        print(f"Error spawning place server: {e}")
        return None

async def get_or_spawn_place_server(place_name):
    """Get existing place server or spawn a new one"""
    if place_name in place_servers:
        return place_servers[place_name]
    return await spawn_place_server(place_name)

def cleanup_place_servers():
    """Kill all spawned place server processes"""
    print("\nShutting down all place servers...")
    for place_name, server_info in place_servers.items():
        try:
            process = server_info["process"]
            print(f"  Terminating place server: {place_name} (port {server_info['port']})")
            process.terminate()
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()
        except Exception as e:
            print(f"  Error terminating place server {place_name}: {e}")
    print("All place servers stopped.")

# Register cleanup function
atexit.register(cleanup_place_servers)

async def handle_client(websocket):
    global next_id
    
    # Assign client ID
    client_id = next_id
    next_id += 1
    
    # Initial position (random within a small area, spawn 10 units up)
    position = {
        "x": random.uniform(-5, 5),
        "y": 10,
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
                        await send_texture_data(username, character_type, clients.values())
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
                
                # Get the texture path
                texture_path = get_texture_path(texture_name, target_character_type)
                
                if texture_path:
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
                    print(f"Sent {target_character_type} texture for {texture_name}")
                else:
                    # Texture not found
                    texture_filename = get_texture_filename(texture_name, target_character_type)
                    await websocket.send(json.dumps({
                        "type": "system_message",
                        "message": f"Texture {texture_filename} not found"
                    }))
                    print(f"Texture not found for {texture_name}")
            
            elif data["type"] == "transform_update":
                # Update client position and rotation
                clients[client_id]["position"] = data["position"]
                clients[client_id]["rotation"] = data["rotation"]
                
                # Store model rotation if provided
                model_rotation_y = data.get("model_rotation_y", None)
                
                # Store floor state if provided
                on_floor = data.get("on_floor", True)
                
                # Broadcast to all other clients
                for cid, client in clients.items():
                    if cid != client_id:
                        message = {
                            "type": "player_transform",
                            "player_id": client_id,
                            "position": data["position"],
                            "rotation": data["rotation"],
                            "on_floor": on_floor
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
                                    await send_texture_data(username, character_type, clients.values())
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
            
            elif data["type"] == "join_place":
                # Handle request to join a place
                place_name = data.get("place_name", "")
                
                if not place_name:
                    await websocket.send(json.dumps({
                        "type": "system_message",
                        "message": "Invalid place name"
                    }))
                    continue
                
                # Check if place exists
                if not place_scene_exists(place_name):
                    await websocket.send(json.dumps({
                        "type": "system_message",
                        "message": f"Place '{place_name}' does not exist"
                    }))
                    continue
                
                # Get or spawn the place server
                server_info = await get_or_spawn_place_server(place_name)
                
                if not server_info:
                    await websocket.send(json.dumps({
                        "type": "system_message",
                        "message": f"Failed to start place server for '{place_name}'"
                    }))
                    continue
                
                # Read the scene data
                scene_data = read_place_scene(place_name)
                
                if not scene_data:
                    await websocket.send(json.dumps({
                        "type": "system_message",
                        "message": f"Failed to load scene data for '{place_name}'"
                    }))
                    continue
                
                # Send place info to client
                await websocket.send(json.dumps({
                    "type": "place_info",
                    "place_name": place_name,
                    "server_url": server_info["url"],
                    "scene_data": scene_data
                }))
                
                print(f"Client {client_id} joining place '{place_name}' at {server_info['url']}")
            
            elif data["type"] == "list_places":
                # List available places
                places = []
                if os.path.exists(PLACES_DIR):
                    for filename in os.listdir(PLACES_DIR):
                        if filename.endswith(".tscn"):
                            place_name = filename[:-5]  # Remove .tscn extension
                            places.append(place_name)
                
                await websocket.send(json.dumps({
                    "type": "places_list",
                    "places": places
                }))
            
            elif data["type"] == "upload_place":
                # Handle place upload (requires authentication)
                if not clients[client_id]["authenticated"]:
                    await websocket.send(json.dumps({
                        "type": "system_message",
                        "message": "You must be logged in to upload places"
                    }))
                    continue
                
                username = clients[client_id]["username"]
                scene_data = data.get("scene_data", "")
                
                if not scene_data:
                    await websocket.send(json.dumps({
                        "type": "system_message",
                        "message": "No scene data provided"
                    }))
                    continue
                
                # Save the place scene file under the username
                place_path = os.path.join(PLACES_DIR, f"{username}.tscn")
                
                try:
                    with open(place_path, "w", encoding="utf-8") as f:
                        f.write(scene_data)
                    
                    print(f"User {username} uploaded their place: {place_path}")
                    
                    await websocket.send(json.dumps({
                        "type": "system_message",
                        "message": f"Successfully uploaded your place! Others can join with /join {username}"
                    }))
                except Exception as e:
                    print(f"Error saving place for {username}: {e}")
                    await websocket.send(json.dumps({
                        "type": "system_message",
                        "message": "Failed to upload place"
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
    game_server = websockets.serve(
        handle_client, 
        MAIN_SERVER_HOST, 
        MAIN_SERVER_PORT,
        max_size=MAX_MESSAGE_SIZE,
        max_queue=MAX_QUEUE_SIZE
    )
    voice_server = voice_chat_server.start_server()
    weather_task = weather_monitor()
    
    print("Starting unified server with:")
    print(f"- Game Server (Lobby) on ws://{MAIN_SERVER_HOST}:{MAIN_SERVER_PORT}")
    print(f"- Voice Chat Server on ws://{MAIN_SERVER_HOST}:{VOICE_CHAT_SERVER_PORT}")
    print(f"- Weather Monitor (checks {WORLD_ENVIRONMENT_FILE} every 5s)")
    print(f"- Place Servers will spawn dynamically on ports {PLACE_SERVER_START_PORT}+")
    
    # Run all services concurrently
    await asyncio.gather(
        game_server,
        voice_server,
        weather_task
    )

if __name__ == "__main__":
    asyncio.run(main())
