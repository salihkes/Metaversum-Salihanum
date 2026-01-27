import time
import base64
import hmac
import hashlib
import os
from flask import Flask, render_template, request, redirect, url_for, session, send_from_directory,  jsonify

app = Flask(__name__)
app.secret_key = "change_this_to_a_random_secret_key"

# MUST MATCH the key in main.py
SSO_SECRET_KEY = "pbrp-sso-secret-change-in-production-12345"
SSO_TOKEN_EXPIRY_SECONDS = 60

# Simple in-memory user data
USERS = {
    "salih1": "654321"
}

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
        username = request.form.get("username", "")
        password = request.form.get("password", "")
        
        if USERS.get(username) == password:
            session['user'] = username
            return redirect(url_for("blank"))
            
        return render_template("login.html", error="Invalid credentials", username=username)

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