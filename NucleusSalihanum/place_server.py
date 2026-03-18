#!/usr/bin/env python

import asyncio
import json
import websockets
import random
import sys
import os
import base64
from collections import defaultdict
from constants import USER_TEXTURE_DIR, USER_DATA_DIR, MAX_MESSAGE_SIZE, MAX_QUEUE_SIZE, DEFAULT_CHARACTER_TYPE, CLIENT_KEY

# See main.py for full documentation on SECURE_HANDSHAKE.
SECURE_HANDSHAKE = getattr(__import__('constants'), 'SECURE_HANDSHAKE', True)
from texture_manager import get_texture_filename, user_has_texture, send_texture_data, get_texture_path
from user_manager import get_user_accessories, get_user_character_type, save_user_character_type

# Store connected clients and their data
clients = {}
next_id = 1
objects = {}

# Place configuration
PLACE_NAME = "default"
PORT = 8766

class PlaceServer:
    def __init__(self, place_name, port):
        self.place_name = place_name
        self.port = port
        self.clients = clients
        self.next_id = 1
        self.objects = objects
        
    async def _admit_client(self, client_id, websocket):
        """Execute the full join flow for a place server client."""
        position = {
            "x": random.uniform(-5, 5),
            "y": 10,
            "z": random.uniform(-5, 5)
        }
        rotation = {"x": 0, "y": 0, "z": 0}

        self.clients[client_id] = {
            "websocket": websocket,
            "username": f"Guest{client_id}",
            "authenticated": False,
            "position": position,
            "rotation": rotation,
            "texture": None,
            "character_type": DEFAULT_CHARACTER_TYPE,
            "key_validated": True,
        }

        await websocket.send(json.dumps({
            "type": "connected",
            "client_id": client_id,
            "username": self.clients[client_id]["username"],
            "authenticated": False,
            "character_type": self.clients[client_id]["character_type"],
            "place_name": self.place_name
        }))

        # Send list of existing players
        players_list = []
        for existing_id, existing_client in self.clients.items():
            if existing_id != client_id:
                players_list.append({
                    "id": existing_id,
                    "username": existing_client["username"],
                    "position": existing_client["position"],
                    "rotation": existing_client["rotation"],
                    "texture": existing_client["texture"],
                    "accessories": existing_client.get("accessories", []),
                    "character_type": existing_client.get("character_type", DEFAULT_CHARACTER_TYPE)
                })

        await websocket.send(json.dumps({
            "type": "player_list",
            "players": players_list
        }))

        # Send texture and accessories data for all existing players
        for existing_id, existing_client in self.clients.items():
            if existing_id != client_id:
                texture = existing_client.get("texture")
                character_type = existing_client.get("character_type", DEFAULT_CHARACTER_TYPE)
                accessories = existing_client.get("accessories", [])
                username = existing_client.get("username")

                if texture:
                    texture_path = get_texture_path(texture, character_type)
                    if texture_path:
                        with open(texture_path, "rb") as f:
                            texture_data = base64.b64encode(f.read()).decode('utf-8')
                        await websocket.send(json.dumps({
                            "type": "texture_data",
                            "texture_name": texture,
                            "character_type": character_type,
                            "data": texture_data
                        }))

                await websocket.send(json.dumps({
                    "type": "accessories_data",
                    "player_id": existing_id,
                    "username": username,
                    "accessories": accessories
                }))

        # Send existing replicated objects
        for net_id, obj in self.objects.items():
            await websocket.send(json.dumps({
                "type": "object_spawn",
                "net_id": net_id,
                "transform": obj.get("transform", {})
            }))

        # Notify existing clients about new player
        for existing_id, existing_client in self.clients.items():
            if existing_id != client_id:
                await existing_client["websocket"].send(json.dumps({
                    "type": "player_joined",
                    "player_id": client_id,
                    "username": self.clients[client_id]["username"],
                    "position": self.clients[client_id]["position"],
                    "rotation": self.clients[client_id]["rotation"],
                    "texture": self.clients[client_id]["texture"],
                    "accessories": self.clients[client_id].get("accessories", []),
                    "character_type": self.clients[client_id]["character_type"]
                }))

        print(f"[Admit] Place client {client_id} admitted as {self.clients[client_id]['username']}")

    async def handle_client(self, websocket):
        client_id = self.next_id
        self.next_id += 1

        kick_task = None

        if SECURE_HANDSHAKE:
            # SECURE MODE: hold in limbo until valid key arrives
            print(f"[Security] Place connection from limbo client (pending ID {client_id}), waiting for key...")
            admitted = False
            first_data = None

            async def _kick_limbo():
                await asyncio.sleep(15)
                if not admitted:
                    print(f"[Security] Place limbo client {client_id} sent no valid key within 15s, disconnecting")
                    await websocket.close(4002, "Timeout")
            kick_task = asyncio.ensure_future(_kick_limbo())

            try:
                async for raw_message in websocket:
                    try:
                        data = json.loads(raw_message)
                    except json.JSONDecodeError:
                        continue
                    if data.get("ck") != CLIENT_KEY:
                        print(f"[Security] Invalid/missing client key from place limbo client {client_id}, disconnecting")
                        await websocket.close(4001, "Invalid client")
                        return
                    admitted = True
                    kick_task.cancel()
                    first_data = data
                    break
            except websockets.exceptions.ConnectionClosed:
                if kick_task and not kick_task.done():
                    kick_task.cancel()
                return

            if not admitted:
                if kick_task and not kick_task.done():
                    kick_task.cancel()
                return

            await self._admit_client(client_id, websocket)
            _first_messages = [first_data] if first_data else []

        else:
            # LEGACY MODE: immediate admission
            await self._admit_client(client_id, websocket)

            async def _kick_unvalidated():
                await asyncio.sleep(15)
                if client_id in self.clients and not self.clients[client_id].get("key_validated"):
                    print(f"[Security] Place client {client_id} sent no valid client key within 15s, disconnecting")
                    await websocket.close(4002, "Timeout")
            kick_task = asyncio.ensure_future(_kick_unvalidated())
            _first_messages = []

        try:
            async def _process(data):
                if data.get("ck") != CLIENT_KEY:
                    print(f"[Security] Invalid/missing client key from place client {client_id}, disconnecting")
                    await websocket.close(4001, "Invalid client")
                    return False
                if not self.clients[client_id].get("key_validated"):
                    self.clients[client_id]["key_validated"] = True
                    if kick_task and not kick_task.done():
                        kick_task.cancel()
                return True

            async def _message_stream():
                for queued in _first_messages:
                    yield json.dumps(queued)
                async for raw in websocket:
                    yield raw

            async for message in _message_stream():
                data = json.loads(message)
                if not await _process(data):
                    return
                
                # Handle identity transfer from lobby
                if data["type"] == "set_identity":
                    username = data.get("username", f"Guest{client_id}")
                    texture = data.get("texture", None)
                    character_type = data.get("character_type", DEFAULT_CHARACTER_TYPE)
                    accessories = data.get("accessories", [])
                    
                    # Update client with identity from lobby
                    self.clients[client_id]["username"] = username
                    self.clients[client_id]["texture"] = texture
                    self.clients[client_id]["character_type"] = character_type
                    self.clients[client_id]["accessories"] = accessories
                    self.clients[client_id]["authenticated"] = True
                    
                    print(f"Client {client_id} identity set: {username} ({character_type})")
                    
                    # Notify all other clients about the updated player info
                    for existing_id, existing_client in self.clients.items():
                        if existing_id != client_id:
                            await existing_client["websocket"].send(json.dumps({
                                "type": "player_identity_update",
                                "player_id": client_id,
                                "username": username,
                                "texture": texture,
                                "character_type": character_type,
                                "accessories": accessories
                            }))
                    
                    # Send texture data to ALL clients (including the one that just set identity)
                    if texture:
                        # Use helper function to send texture data
                        success = await send_texture_data(texture, character_type, self.clients.values())
                        if success:
                            print(f"Broadcasted texture for {username}")
                    
                    # ALWAYS send accessories data to ALL clients (even if empty list)
                    for cid, client in self.clients.items():
                        await client["websocket"].send(json.dumps({
                            "type": "accessories_data",
                            "player_id": client_id,
                            "username": username,
                            "accessories": accessories
                        }))
                    print(f"Broadcasted accessories for {username}: {accessories}")
                    
                    # Send character type to ALL clients (including the one that just joined)
                    for cid, client in self.clients.items():
                        await client["websocket"].send(json.dumps({
                            "type": "character_transform",
                            "player_id": client_id,
                            "username": username,
                            "character_type": character_type
                        }))
                    print(f"Broadcasted character type for {username}: {character_type}")
                    
                    # Send confirmation that identity was set successfully
                    await websocket.send(json.dumps({
                        "type": "system_message",
                        "message": f"Identity set: {username} ({character_type})"
                    }))
                
                elif data["type"] == "transform_update":
                    # Update client position and rotation
                    self.clients[client_id]["position"] = data["position"]
                    self.clients[client_id]["rotation"] = data["rotation"]
                    
                    model_rotation_y = data.get("model_rotation_y", None)
                    on_floor = data.get("on_floor", True)
                    
                    # Broadcast to all other clients
                    for cid, client in self.clients.items():
                        if cid != client_id:
                            message_data = {
                                "type": "player_transform",
                                "player_id": client_id,
                                "position": data["position"],
                                "rotation": data["rotation"],
                                "on_floor": on_floor
                            }
                            
                            if model_rotation_y is not None:
                                message_data["model_rotation_y"] = model_rotation_y
                                
                            await client["websocket"].send(json.dumps(message_data))
                
                elif data["type"] == "login" or data["type"] == "register":
                    # Place servers don't support authentication
                    await websocket.send(json.dumps({
                        "type": "system_message",
                        "message": "You cannot login/register in a place. Please return to the lobby to authenticate."
                    }))
                    
                    # Send a fake response to unblock the UI
                    response_type = "login_response" if data["type"] == "login" else "register_response"
                    await websocket.send(json.dumps({
                        "type": response_type,
                        "success": False,
                        "message": "Authentication not available in places. Return to lobby."
                    }))
                
                elif data["type"] == "chat_message":
                    message = data["message"]
                    
                    # Check if it's a character transformation command
                    if message.startswith("/transform "):
                        parts = message.split(" ")
                        if len(parts) >= 2:
                            character_type = parts[1].lower()
                            if character_type in ["humanoid", "countryball"]:
                                # Update client's character type
                                old_character_type = self.clients[client_id]["character_type"]
                                self.clients[client_id]["character_type"] = character_type
                                
                                # Save to user data if authenticated
                                username = self.clients[client_id]["username"]
                                if self.clients[client_id].get("authenticated", False):
                                    save_user_character_type(username, character_type)
                                    
                                    # Check if user has texture for new character type
                                    has_texture = user_has_texture(username, character_type)
                                    
                                    if has_texture:
                                        self.clients[client_id]["texture"] = username
                                        # Send new texture to all clients
                                        await send_texture_data(username, character_type, self.clients.values())
                                        print(f"Sent {character_type} texture for {username} after transformation")
                                    else:
                                        self.clients[client_id]["texture"] = None
                                        print(f"No {character_type} texture found for {username} after transformation")
                                
                                # Broadcast transformation to all clients
                                for cid, client in self.clients.items():
                                    await client["websocket"].send(json.dumps({
                                        "type": "character_transform",
                                        "player_id": client_id,
                                        "username": username,
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
                    for cid, client in self.clients.items():
                        await client["websocket"].send(json.dumps({
                            "type": "chat_message",
                            "player_id": client_id,
                            "username": self.clients[client_id]["username"],
                            "message": message
                        }))
                
                elif data["type"] == "get_texture":
                    # Client is requesting a texture
                    texture_name = data.get("texture_name", "")
                    
                    if not texture_name:
                        continue
                    
                    # Determine character type for this texture
                    target_character_type = DEFAULT_CHARACTER_TYPE  # Default
                    for cid, client_data in self.clients.items():
                        if client_data["username"] == texture_name:
                            target_character_type = client_data.get("character_type", DEFAULT_CHARACTER_TYPE)
                            break
                    
                    # Get the texture path using helper function
                    texture_path = get_texture_path(texture_name, target_character_type)
                    
                    if texture_path:
                        # Read and encode the texture file
                        with open(texture_path, "rb") as f:
                            texture_data = base64.b64encode(f.read()).decode('utf-8')
                        
                        # Send texture data to the requesting client
                        await websocket.send(json.dumps({
                            "type": "texture_data",
                            "texture_name": texture_name,
                            "character_type": target_character_type,
                            "data": texture_data
                        }))
                        print(f"Sent texture for {texture_name}")
                    else:
                        texture_filename = get_texture_filename(texture_name, target_character_type)
                        print(f"Texture not found: {texture_filename}")
                
                elif data["type"] == "get_players":
                    # Send list of existing players
                    players_list = []
                    for existing_id, existing_client in self.clients.items():
                        if existing_id != client_id:
                            players_list.append({
                                "id": existing_id,
                                "username": existing_client["username"],
                                "position": existing_client["position"],
                                "rotation": existing_client["rotation"],
                                "texture": existing_client["texture"],
                                "accessories": existing_client.get("accessories", []),
                                "character_type": existing_client.get("character_type", DEFAULT_CHARACTER_TYPE)
                            })
                            
                    await websocket.send(json.dumps({
                        "type": "player_list",
                        "players": players_list
                    }))
                
                elif data["type"] == "object_grab":
                    net_id = str(data.get("net_id"))
                    xf = data.get("transform", {})
                    self.objects[net_id] = {"transform": xf}
                    # Broadcast to everyone
                    for cid, client in self.clients.items():
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
                    self.objects[net_id] = {"transform": xf}
                    # Broadcast to everyone
                    for cid, client in self.clients.items():
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
                    self.objects[net_id] = {"transform": xf}
                    # Broadcast to everyone except sender
                    for cid, client in self.clients.items():
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
            if kick_task and not kick_task.done():
                kick_task.cancel()
            # Remove client
            if client_id in self.clients:
                username = self.clients[client_id]["username"]
                del self.clients[client_id]
                
                # Notify all clients about player leaving
                for cid, client in self.clients.items():
                    await client["websocket"].send(json.dumps({
                        "type": "player_left",
                        "player_id": client_id
                    }))
                    
                    await client["websocket"].send(json.dumps({
                        "type": "system_message",
                        "message": f"{username} has left the place"
                    }))
    
    async def start_server(self):
        print(f"Starting Place Server '{self.place_name}' on port {self.port}")
        
        async with websockets.serve(
            self.handle_client, 
            "0.0.0.0", 
            self.port, 
            max_size=MAX_MESSAGE_SIZE, 
            max_queue=MAX_QUEUE_SIZE
        ):
            print(f"Place Server '{self.place_name}' listening on ws://0.0.0.0:{self.port}")
            await asyncio.Future()  # Run forever

async def main():
    # Get place name and port from command line arguments
    place_name = sys.argv[1] if len(sys.argv) > 1 else "default"
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 8766
    
    server = PlaceServer(place_name, port)
    await server.start_server()

if __name__ == "__main__":
    asyncio.run(main())

