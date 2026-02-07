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

# Load .env: prefer Frontend/.env, then project root
_frontend_dir = os.path.dirname(os.path.abspath(__file__))
_env_file = os.path.join(_frontend_dir, '.env')
if not os.path.exists(_env_file):
    _env_file = os.path.join(parent_dir, '.env')
if os.path.exists(_env_file):
    with open(_env_file, 'r') as f:
        for line in f:
            if '=' in line and not line.strip().startswith('#'):
                k, v = line.strip().split('=', 1)
                os.environ.setdefault(k.strip(), v.strip())

def _env_bool(name: str, default: bool = True) -> bool:
    raw = os.environ.get(name, '').strip().strip('"\'').lower()
    if raw in ('', '0', 'false', 'no'): return False
    if raw in ('1', 'true', 'yes'): return True
    return default

ENABLE_GUEST = _env_bool('ENABLE_GUEST', True)
ENABLE_REGISTRATION = _env_bool('ENABLE_REGISTRATION', True)

from NucleusSalihanum.auth_manager import AuthManager
from NucleusSalihanum.constants import SSO_SECRET_KEY, SSO_TOKEN_EXPIRY_SECONDS, PCK_PACKAGES_DIR
from NucleusSalihanum.texture_manager import save_decal_texture

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
    if 'user' in session:
        return redirect(url_for("home"))
    return redirect(url_for("login"))

@app.route("/login", methods=["GET", "POST"])
def login():
    # If already logged in, go to home
    if 'user' in session:
        return redirect(url_for("home"))
    
    if request.method == "POST":
        action = request.form.get("action", "login")  # Check if it's login or register
        
        if action == "register":
            if not ENABLE_REGISTRATION:
                return render_template("login.html", error="Registration is disabled.", username=request.form.get("username", "").strip(), enable_guest=ENABLE_GUEST, enable_registration=ENABLE_REGISTRATION)
            # Handle registration
            username = request.form.get("username", "").strip()
            password = request.form.get("password", "")
            confirm_password = request.form.get("confirm_password", "")
            
            if not username or not password:
                return render_template("login.html", error="Username and password are required", username=username, enable_guest=ENABLE_GUEST, enable_registration=ENABLE_REGISTRATION)
            
            if password != confirm_password:
                return render_template("login.html", error="Passwords do not match", username=username, enable_guest=ENABLE_GUEST, enable_registration=ENABLE_REGISTRATION)
            
            # Register the user (won't overwrite existing accounts)
            success, message = auth_manager.register_user(username, password)
            
            if success:
                # Auto-login after successful registration
                session['user'] = username
                return redirect(url_for("home"))
            else:
                return render_template("login.html", error=message, username=username, enable_guest=ENABLE_GUEST, enable_registration=ENABLE_REGISTRATION)
        
        else:
            # Handle login
            username = request.form.get("username", "").strip()
            password = request.form.get("password", "")
            
            if not username or not password:
                return render_template("login.html", error="Username and password are required", username=username, enable_guest=ENABLE_GUEST, enable_registration=ENABLE_REGISTRATION)
            
            # Authenticate using AuthManager from NucleusSalihanum
            success, result = auth_manager.authenticate_user(username, password)
            
            if success:
                session['user'] = username
                return redirect(url_for("home"))
            
            # Provide more specific error message
            error_msg = result if isinstance(result, str) else "Invalid credentials"
            return render_template("login.html", error=error_msg, username=username, enable_guest=ENABLE_GUEST, enable_registration=ENABLE_REGISTRATION)
    
    # GET request - show login form
    return render_template("login.html", enable_guest=ENABLE_GUEST, enable_registration=ENABLE_REGISTRATION)

@app.route("/home")
def home():
    if 'user' not in session:
        return redirect(url_for("login"))
    
    username = session['user']
    message = request.args.get('message', None)
    return render_template("home.html", username=username, message=message)

@app.route("/settings")
def settings_page():
    if 'user' not in session:
        return redirect(url_for("login"))
    
    username = session['user']
    return render_template("settings.html", username=username)

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

@app.route("/play-as-guest")
def play_as_guest():
    """Enter game as guest; game handles guest logic."""
    if not ENABLE_GUEST:
        return redirect(url_for("login"))
    # Serve game directly without any session - game handles guest mode
    game_url = url_for('serve_game_file', filename='index.html')
    return render_template("play.html", username="", sso_token="", game_url=game_url)


@app.route("/play")
def play_game():
    """Game client page"""
    if 'user' not in session:
        return redirect(url_for("login"))
    
    username = session['user']
    sso_token = generate_sso_token(username)
    game_url = url_for('serve_game_file', filename='index.html')
    
    return render_template("play.html", 
                         username=username, 
                         sso_token=sso_token,
                         game_url=game_url)

@app.route("/upload-decal")
def upload_decal_page():
    """Redirect to settings page"""
    return redirect(url_for("settings_page"))

@app.route("/game/<path:filename>")
def serve_game_file(filename):
    """Serves any file requested from the static/game directory (js, wasm, pck)"""
    return send_from_directory(os.path.join(app.static_folder, 'game'), filename)

# 2. KEEP THE ROOT GAME ROUTE (Redirects or serves index)
@app.route("/game/")
def serve_game_index():
    """Serves the index.html when opening /game/"""
    return serve_game_file('index.html')

# ── PCK dynamic content delivery ─────────────────────────────────────────────
# Serves .pck files from NucleusSalihanum/pck_packages/ so the Godot client
# can download them at https://project.skeskin.com/pck/<filename>.pck
_pck_dir = os.path.join(parent_dir, 'NucleusSalihanum', PCK_PACKAGES_DIR)

@app.route("/pck/<path:filename>")
def serve_pck_file(filename):
    """Serve a .pck resource pack file for the game client to download."""
    # Only allow .pck files (security)
    if not filename.endswith('.pck'):
        return "Forbidden", 403
    response = send_from_directory(_pck_dir, filename)
    response.headers['Content-Type'] = 'application/octet-stream'
    response.headers['Cross-Origin-Resource-Policy'] = 'same-origin'
    return response

@app.route("/logout")
def logout():
    session.pop('user', None)
    return redirect(url_for("login"))

@app.route("/api/upload-decal", methods=["POST"])
def upload_decal():
    """
    API Endpoint for uploading countryball or humanoid decals.
    Accepts multipart/form-data with 'file' and 'character_type' fields.
    """
    if 'user' not in session:
        return jsonify({
            "success": False,
            "message": "User not authenticated"
        }), 401
    
    username = session['user']
    
    # Check if file is present
    if 'file' not in request.files:
        return jsonify({
            "success": False,
            "message": "No file provided"
        }), 400
    
    file = request.files['file']
    character_type = request.form.get('character_type', 'humanoid').lower()
    
    # Validate character type
    if character_type not in ['humanoid', 'countryball']:
        return jsonify({
            "success": False,
            "message": "Invalid character_type. Must be 'humanoid' or 'countryball'"
        }), 400
    
    # Check if file is empty
    if file.filename == '':
        return jsonify({
            "success": False,
            "message": "No file selected"
        }), 400
    
    # Validate file extension (should be PNG)
    if not file.filename.lower().endswith('.png'):
        return jsonify({
            "success": False,
            "message": "Only PNG files are supported"
        }), 400
    
    try:
        # Read file data
        file_data = file.read()
        
        # Validate file size (max 5MB)
        if len(file_data) > 5 * 1024 * 1024:
            return jsonify({
                "success": False,
                "message": "File too large. Maximum size is 5MB"
            }), 400
        
        # Encode to base64
        base64_data = base64.b64encode(file_data).decode('utf-8')
        
        # Save the decal using the texture manager
        success, message, file_path = save_decal_texture(username, character_type, base64_data)
        
        if success:
            return jsonify({
                "success": True,
                "message": message,
                "character_type": character_type,
                "file_path": file_path
            })
        else:
            return jsonify({
                "success": False,
                "message": message
            }), 500
            
    except Exception as e:
        return jsonify({
            "success": False,
            "message": f"Error processing file: {str(e)}"
        }), 500

# Godot 4 requires these headers for SharedArrayBuffer support
@app.after_request
def add_header(response):
    response.headers['Cross-Origin-Opener-Policy'] = 'same-origin'
    response.headers['Cross-Origin-Embedder-Policy'] = 'require-corp'
    return response

if __name__ == "__main__":
    app.run(debug=True, host='0.0.0.0', port=80)