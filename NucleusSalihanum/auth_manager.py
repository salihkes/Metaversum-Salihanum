import json
import os
import hashlib
import uuid

class AuthManager:
    def __init__(self, db_path="user_database.json"):
        self.db_path = db_path
        self.users = {}
        self._last_modified = 0  # Track file modification time
        self.load_database()
    
    def _get_file_mtime(self):
        """Get file modification time"""
        try:
            return os.path.getmtime(self.db_path)
        except OSError:
            return 0
    
    def _check_reload(self):
        """Check if database file was modified externally and reload if needed"""
        current_mtime = self._get_file_mtime()
        if current_mtime > self._last_modified:
            print(f"[AuthManager] Database file changed, reloading...")
            self.load_database()
    
    def load_database(self):
        """Load the user database from JSON file"""
        if os.path.exists(self.db_path):
            try:
                with open(self.db_path, 'r') as f:
                    self.users = json.load(f)
                self._last_modified = self._get_file_mtime()
                print(f"[AuthManager] Loaded {len(self.users)} users from database")
            except json.JSONDecodeError:
                print(f"[AuthManager] Error loading database, creating new one")
                self.users = {}
        else:
            self.users = {}
            self.save_database()
    
    def save_database(self):
        """Save the user database to JSON file"""
        with open(self.db_path, 'w') as f:
            json.dump(self.users, f, indent=4)
    
    def hash_password(self, password, salt=None):
        """Hash a password with optional salt"""
        if salt is None:
            salt = uuid.uuid4().hex
        
        hashed = hashlib.sha256((password + salt).encode()).hexdigest()
        return {"hash": hashed, "salt": salt}
    
    def register_user(self, username, password):
        """Register a new user"""
        # Reload database if modified externally (e.g., by web server)
        self._check_reload()
        
        # Check if username already exists
        if username.lower() in [u.lower() for u in self.users.keys()]:
            return False, "Username already exists"
        
        # Hash the password with a salt
        password_data = self.hash_password(password)
        
        # Store the user
        self.users[username] = {
            "password_hash": password_data["hash"],
            "salt": password_data["salt"],
            "display_name": username,
            "created_at": str(uuid.uuid1())  # Use timestamp as creation date
        }
        
        # Save the database
        self.save_database()
        return True, "User registered successfully"
    
    def authenticate_user(self, username, password):
        """Authenticate a user"""
        # Reload database if modified externally (e.g., by web server)
        self._check_reload()
        
        # Check if username exists
        if username not in self.users:
            return False, "Invalid username or password"
        
        # Get the stored password hash and salt
        user_data = self.users[username]
        salt = user_data["salt"]
        stored_hash = user_data["password_hash"]
        
        # Hash the provided password with the stored salt
        password_data = self.hash_password(password, salt)
        
        # Compare the hashes
        if password_data["hash"] == stored_hash:
            return True, user_data
        else:
            return False, "Invalid username or password"
    
    def get_user_data(self, username):
        """Get user data without sensitive information"""
        # Reload database if modified externally
        self._check_reload()
        
        if username in self.users:
            user_data = self.users[username].copy()
            # Remove sensitive data
            if "password_hash" in user_data:
                del user_data["password_hash"]
            if "salt" in user_data:
                del user_data["salt"]
            return user_data
        return None 