#!/usr/bin/env python

import asyncio
import websockets
import json
import subprocess
import threading
import time
import base64
import os
import platform
import argparse
from auth_manager import AuthManager

class VoiceMicrophoneClient:
    def __init__(self, username, password, room="default", server_url="ws://localhost:3246", **kwargs):
        """Initialize voice microphone client."""
        self.username = username
        self.password = password
        self.room = room
        self.server_url = server_url
        self.sample_rate = kwargs.get('sample_rate', 48000)
        self.channels = kwargs.get('channels', 2)
        self.audio_chunk_ms = kwargs.get('audio_chunk_ms', 40)
        self.running = False
        self.registered = False
        self.websocket = None
        self.audio_process = None
        self.auth_manager = AuthManager()
        
        # Audio capture settings
        self.bytes_per_chunk = int((self.sample_rate * self.channels * 2 * self.audio_chunk_ms) / 1000)
        
    async def authenticate(self):
        """Authenticate with the auth manager"""
        success, result = self.auth_manager.authenticate_user(self.username, self.password)
        if not success:
            print(f"Authentication failed: {result}")
            return False
        print(f"Authentication successful for {self.username}")
        return True
    
    async def keepalive_task(self):
        """Send periodic pings to keep connection alive"""
        while self.registered and hasattr(self, 'websocket'):
            try:
                await asyncio.sleep(30)  # Send ping every 30 seconds
                if self.registered and hasattr(self, 'websocket'):
                    ping_message = {
                        "type": "ping",
                        "timestamp": int(time.time() * 1000)
                    }
                    await self.websocket.send(json.dumps(ping_message))
                    print("Sent ping to voice server")
            except Exception as e:
                print(f"Error in keepalive: {e}")
                break

    async def connect_to_voice_server(self):
        """Connect to voice chat server"""
        try:
            print(f"Connecting to voice server: {self.server_url}")
            self.websocket = await websockets.connect(self.server_url)
            
            # Register with voice server
            registration = {
                "type": "register",
                "username": self.username,
                "room": self.room,
                "user_type": "streamer"  # This client streams microphone data
            }
            
            await self.websocket.send(json.dumps(registration))
            
            # Wait for confirmation
            response = await self.websocket.recv()
            response_data = json.loads(response)
            
            if response_data.get("type") == "registered":
                self.registered = True
                print(f"Successfully registered with voice server as {self.username}")
                
                # Start keepalive task
                asyncio.create_task(self.keepalive_task())
                return True
            else:
                print(f"Registration failed: {response_data}")
                return False
                
        except Exception as e:
            print(f"Failed to connect to voice server: {e}")
            return False

    async def send_audio_chunk(self, audio_data):
        """Send audio chunk to voice server"""
        if not self.registered or not hasattr(self, 'websocket'):
            return
            
        # Encode audio data as base64
        audio_base64 = base64.b64encode(audio_data).decode('utf-8')
        
        audio_message = {
            "type": "audio_chunk",
            "audio_data": audio_base64,
            "timestamp_ms": int(time.time() * 1000),
            "chunk_info": {
                "sample_rate": self.sample_rate,
                "channels": self.channels,
                "chunk_ms": self.audio_chunk_ms
            }
        }
        
        try:
            await self.websocket.send(json.dumps(audio_message))
        except Exception as e:
            print(f"Error sending audio chunk: {e}")

    def _setup_microphone_capture(self):
        """Set up microphone capture based on OS"""
        if platform.system() == "Windows":
            return self._setup_windows_microphone()
        elif platform.system() == "Darwin":  # macOS
            return self._setup_macos_microphone()
        else:  # Linux
            return self._setup_linux_microphone()
    
    def _setup_windows_microphone(self):
        """Set up microphone capture for Windows using DirectShow."""
        microphone_devices = [
            "audio=Mikrofon (3- AKG C44-USB Microphone)",
            "audio=Headset Microphone (Oculus Virtual Audio Device)",
            "audio=CABLE Output (VB-Audio Virtual Cable)",
            "audio=Microphone",
            "audio=Default"
        ]
        
        for device in microphone_devices:
            try:
                cmd = [
                    "ffmpeg", "-f", "dshow", "-i", device,
                    "-ar", str(self.sample_rate), "-ac", str(self.channels),
                    "-f", "s16le", "-acodec", "pcm_s16le", "-"
                ]
                
                self.audio_process = subprocess.Popen(
                    cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL
                )
                print(f"Started Windows microphone capture with device: {device}")
                return True
            except Exception as e:
                print(f"Failed to start Windows microphone with {device}: {e}")
                continue
        
        print("Failed to start any Windows microphone device")
        return False
    
    def _setup_macos_microphone(self):
        """Set up microphone capture for macOS using AVFoundation."""
        try:
            cmd = [
                "ffmpeg", "-f", "avfoundation", "-i", ":0",
                "-ar", str(self.sample_rate), "-ac", str(self.channels),
                "-f", "s16le", "-acodec", "pcm_s16le", "-"
            ]
            
            self.audio_process = subprocess.Popen(
                cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL
            )
            print("Started macOS microphone capture")
            return True
        except Exception as e:
            print(f"Failed to start macOS microphone: {e}")
            return False
    
    def _setup_linux_microphone(self):
        """Set up microphone capture for Linux using ALSA."""
        try:
            cmd = [
                "ffmpeg", "-f", "alsa", "-i", "default",
                "-ar", str(self.sample_rate), "-ac", str(self.channels),
                "-f", "s16le", "-acodec", "pcm_s16le", "-"
            ]
            
            self.audio_process = subprocess.Popen(
                cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL
            )
            print("Started Linux microphone capture")
            return True
        except Exception as e:
            print(f"Failed to start Linux microphone: {e}")
            return False

    async def start_websocket_server(self):
        """Handle WebSocket connection and audio streaming"""
        # First authenticate
        if not await self.authenticate():
            return
        
        # Connect to voice server
        if not await self.connect_to_voice_server():
            return
        
        # Start microphone capture
        if not self._setup_microphone_capture():
            print("Failed to set up microphone capture")
            return
        
        self.running = True
        print(f"Voice microphone client started for {self.username}")
        print("Press Ctrl+C to stop...")
        
        try:
            # Keep connection alive and process incoming messages
            await self.websocket.wait_closed()
        except KeyboardInterrupt:
            print("\nShutting down...")
        finally:
            await self.cleanup()

    async def audio_capture_loop(self):
        """Capture and send audio chunks"""
        while self.running and self.audio_process:
            try:
                # Read audio chunk
                audio_chunk = self.audio_process.stdout.read(self.bytes_per_chunk)
                if not audio_chunk:
                    break
                
                # Send to voice server
                await self.send_audio_chunk(audio_chunk)
                
                # Small delay to control chunk rate
                await asyncio.sleep(self.audio_chunk_ms / 1000.0)
                
            except Exception as e:
                print(f"Error in audio capture: {e}")
                break

    async def cleanup(self):
        """Clean up resources"""
        self.running = False
        self.registered = False
        
        if self.audio_process:
            self.audio_process.terminate()
            self.audio_process = None
            
        if hasattr(self, 'websocket'):
            await self.websocket.close()

    async def run(self):
        """Main run function"""
        # Start WebSocket connection
        websocket_task = asyncio.create_task(self.start_websocket_server())
        
        # Wait a moment for connection to establish
        await asyncio.sleep(1)
        
        # Start audio capture if connected
        if self.running and self.registered:
            audio_task = asyncio.create_task(self.audio_capture_loop())
            
            # Wait for either task to complete
            await asyncio.gather(websocket_task, audio_task, return_exceptions=True)
        else:
            await websocket_task

async def main():
    parser = argparse.ArgumentParser(description='Voice Microphone Client')
    parser.add_argument('--username', type=str, required=True, help='Username for authentication')
    parser.add_argument('--password', type=str, required=True, help='Password for authentication')
    parser.add_argument('--room', type=str, default='default', help='Room to join (default: default)')
    parser.add_argument('--server', type=str, default='ws://localhost:3246', help='Voice chat server URL')
    parser.add_argument('--sample-rate', type=int, default=48000, help='Audio sample rate (default: 48000)')
    parser.add_argument('--channels', type=int, default=2, help='Audio channels (default: 2)')
    parser.add_argument('--chunk-ms', type=int, default=40, help='Audio chunk size in ms (default: 40)')
    
    args = parser.parse_args()
    
    client = VoiceMicrophoneClient(
        username=args.username,
        password=args.password,
        room=args.room,
        server_url=args.server,
        sample_rate=args.sample_rate,
        channels=args.channels,
        audio_chunk_ms=args.chunk_ms
    )
    
    try:
        await client.run()
    except KeyboardInterrupt:
        print("\nShutting down...")
        await client.cleanup()

if __name__ == "__main__":
    asyncio.run(main())
