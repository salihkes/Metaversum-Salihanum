import time
import base64
import hmac
import hashlib
import os
import sys
from flask import Flask, render_template, request, redirect, url_for, session, send_from_directory,  jsonify

# Add parent directory to path to import from NucleusSalihanum
parent_dir = os.path.join(os.path.dirname(__file__), '..')
sys.path.insert(0, parent_dir)

from NucleusSalihanum.auth_manager import AuthManager
from NucleusSalihanum.constants import SSO_SECRET_KEY, SSO_TOKEN_EXPIRY_SECONDS

app = Flask(__name__)
app.secret_key = "change_this_to_a_random_secret_key"

# Initialize AuthManager with the correct path to the database file
db_path = os.path.join(parent_dir, 'NucleusSalihanum', 'user_database.json')
auth_manager = AuthManager(db_path=db_path)

def generate_sso_token(username):
    timestamp = str(int(time.time()))
    message = f"{username}:{timestamp}"
    signature = hmac.new(
        SSO_SECRET_KEY.encode(), 
        message.encode(), 
        hashlib.sha256
    ).hexdigest()
    token_data = f"{username}:{timestamp}:{signature}"
    return base64.b64encode(token_data.encode()).decode()

@app.route("/", methods=["GET"])
def index():
    return redirect(url_for("login"))

@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        action = request.form.get("action", "login")  # Check if it's login or register
        
        if action == "register":
            # Handle registration
            username = request.form.get("username", "").strip()
            password = request.form.get("password", "")
            confirm_password = request.form.get("confirm_password", "")
            
            if not username or not password:
                return render_template("login.html", error="Username and password are required", username=username)
            
            if password != confirm_password:
                return render_template("login.html", error="Passwords do not match", username=username)
            
            # Register the user (won't overwrite existing accounts)
            success, message = auth_manager.register_user(username, password)
            
            if success:
                # Auto-login after successful registration
                session['user'] = username
                return redirect(url_for("blank"))
            else:
                return render_template("login.html", error=message, username=username)
        
        else:
            # Handle login
            username = request.form.get("username", "").strip()
            password = request.form.get("password", "")
            
            if not username or not password:
                return render_template("login.html", error="Username and password are required", username=username)
            
            # Authenticate using AuthManager from NucleusSalihanum
            success, result = auth_manager.authenticate_user(username, password)
            
            if success:
                session['user'] = username
                return redirect(url_for("blank"))
            
            # Provide more specific error message
            error_msg = result if isinstance(result, str) else "Invalid credentials"
            return render_template("login.html", error=error_msg, username=username)
    
    # GET request - show login form
    return render_template("login.html")

@app.route("/api/game-token", methods=["GET"])
def get_game_token():
    """
    API Endpoint for the game to fetch SSO token via AJAX/Fetch.
    This is required if the window.PBRP_SSO variables aren't read correctly
    or if the game requests a fresh token.
    """
    if 'user' not in session:
        return jsonify({
            "success": False, 
            "message": "User not authenticated"
        }), 401
    
    username = session['user']
    token = generate_sso_token(username)
    
    return jsonify({
        "success": True,
        "username": username,
        "token": token
    })

@app.route("/blank")
def blank():
    if 'user' not in session:
        return redirect(url_for("login"))
    
    username = session['user']
    sso_token = generate_sso_token(username)
    
    # 3. UPDATE THE URL GENERATION
    # We point directly to index.html to ensure relative paths work correctly
    game_url = url_for('serve_game_file', filename='index.html')
    
    return render_template("blank.html", 
                         username=username, 
                         sso_token=sso_token,
                         game_url=game_url)

@app.route("/game/<path:filename>")
def serve_game_file(filename):
    """Serves any file requested from the static/game directory (js, wasm, pck)"""
    return send_from_directory(os.path.join(app.static_folder, 'game'), filename)

# 2. KEEP THE ROOT GAME ROUTE (Redirects or serves index)
@app.route("/game/")
def serve_game_index():
    """Serves the index.html when opening /game/"""
    return serve_game_file('index.html')

@app.route("/logout")
def logout():
    session.pop('user', None)
    return redirect(url_for("login"))

# Godot 4 requires these headers for SharedArrayBuffer support
@app.after_request
def add_header(response):
    response.headers['Cross-Origin-Opener-Policy'] = 'same-origin'
    response.headers['Cross-Origin-Embedder-Policy'] = 'require-corp'
    return response

if __name__ == "__main__":
    app.run(debug=True, host='0.0.0.0', port=80)