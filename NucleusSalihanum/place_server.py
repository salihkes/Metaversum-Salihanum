#!/usr/bin/env python

import asyncio
import json
import websockets
import random
import sys
import os
from collections import defaultdict

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
        
    async def handle_client(self, websocket):
        client_id = self.next_id
        self.next_id += 1
        
        # Initial position
        position = {
            "x": random.uniform(-5, 5),
            "y": 0,
            "z": random.uniform(-5, 5)
        }
        rotation = {"x": 0, "y": 0, "z": 0}
        
        # Store client data
        self.clients[client_id] = {
            "websocket": websocket,
            "username": f"Guest{client_id}",
            "authenticated": False,
            "position": position,
            "rotation": rotation,
            "texture": None,
            "character_type": "humanoid"
        }
        
        # Send connected message
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
                    "character_type": existing_client.get("character_type", "humanoid")
                })
                
        await websocket.send(json.dumps({
            "type": "player_list",
            "players": players_list
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
        
        try:
            async for message in websocket:
                data = json.loads(message)
                
                if data["type"] == "transform_update":
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
                
                elif data["type"] == "chat_message":
                    message = data["message"]
                    
                    # Broadcast to all clients
                    for cid, client in self.clients.items():
                        await client["websocket"].send(json.dumps({
                            "type": "chat_message",
                            "player_id": client_id,
                            "username": self.clients[client_id]["username"],
                            "message": message
                        }))
                
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
                                "character_type": existing_client.get("character_type", "humanoid")
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
        
        async with websockets.serve(self.handle_client, "0.0.0.0", self.port, max_size=10_000_000, max_queue=None):
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

