const video = document.getElementById('stream');
let pc = null;
let dc = null;

async function start() {
    try {
        pc = new RTCPeerConnection();
        
        dc = pc.createDataChannel('input');
        dc.onopen = () => {
            console.log('Connected. Click to capture mouse.');
        };
        dc.onmessage = (e) => console.log('Server:', e.data);


        pc.ontrack = (evt) => {
            if (evt.track.kind === 'video') {
                const [stream] = evt.streams;
                if (stream) {
                    video.srcObject = stream;
                    // Safari (especially on iOS / recent versions) may block autoplay
                    // even for muted WebRTC streams unless play() is called explicitly.
                    const playPromise = video.play();
                    if (playPromise !== undefined) {
                        playPromise.catch((err) => {
                            console.warn('Video autoplay was blocked, will start on user gesture.', err);
                        });
                    }
                }
            }
        };

        // Add transceiver to ensure video m-line is present in offer
        pc.addTransceiver('video', { direction: 'recvonly' });

        const offer = await pc.createOffer();
        await pc.setLocalDescription(offer);

        const response = await fetch('/offer', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                sdp: pc.localDescription.sdp,
                type: pc.localDescription.type
            })
        });

        const answer = await response.json();
        await pc.setRemoteDescription(answer);
    } catch (e) {
        console.error('Error connecting: ' + e);
    }
}

// Input Handling
function send(data) {
    if (dc && dc.readyState === 'open') {
        dc.send(JSON.stringify(data));
    }
}

// Mouse Locking
const requestPointerLock = async () => {
    if (document.pointerLockElement !== video) {
        try {
            await video.requestPointerLock();
        } catch (e) {
            console.error(e);
        }
    }
};

// --- INPUT HANDLING ---

// POINTER LOCK + Start video on user gesture (helps Safari autoplay policy)
video.addEventListener('click', async () => {
    try {
        if (video.paused) {
            await video.play();
        }
    } catch (e) {
        console.error('Error starting video playback on click:', e);
    }
    requestPointerLock();
});

document.addEventListener('pointerlockchange', () => {
    if (document.pointerLockElement === video) {
        send({ type: 'mouse_mode', captured: true });
    } else {
        send({ type: 'mouse_mode', captured: false });
    }
});

// MOUSE (Desktop)
document.addEventListener('mousemove', (e) => {
    if (document.pointerLockElement !== video) return;

    const SCALE = 1.0; // reduce sensitivity for remote play
    send({
        type: 'mouse_motion',
        x: e.clientX,
        y: e.clientY,
        dx: e.movementX * SCALE,
        dy: e.movementY * SCALE,
    });
});

document.addEventListener('mousedown', (e) => {
    if (document.pointerLockElement !== video) return;
    send({ type: 'mouse_button', button_index: e.button + 1, pressed: true, x: e.clientX, y: e.clientY });
});

document.addEventListener('mouseup', (e) => {
    if (document.pointerLockElement !== video) return;
    send({ type: 'mouse_button', button_index: e.button + 1, pressed: false, x: e.clientX, y: e.clientY });
});

document.addEventListener('wheel', (e) => {
    if (document.pointerLockElement !== video) return;
    send({ type: 'wheel', delta_y: e.deltaY, x: e.clientX, y: e.clientY });
});

// KEYBOARD (Desktop + Bluetooth Keyboards on Mobile)
// Note: On mobile, keydown events might only fire for input fields or have restrictions.
// We attach to 'window' to catch everything possible.
window.addEventListener('keydown', (e) => {
    // Allow keys if pointer locked OR if we are on touch device (implicit capture logic)
    // Checking for touch capability is tricky, but usually if pointerLockElement is null on desktop we ignore.
    // But on iPad with keyboard, pointerLock might not be active.
    
    // Send key regardless of lock status if it looks like a game key (WASD, etc)
    // or strictly enforce lock/touch active state.
    
    // Basic check: If pointer is locked OR we've touched recently (mobile mode)
    // Let's just ALWAYS send keys if the user has interacted with the page at least once?
    // Safer: Send keys if active.
    
    // On iPad, pointerLockElement will be null. We need a flag for "Mobile Input Active".
    send({ type: 'key', code: e.code, key: e.key, pressed: true });
});

window.addEventListener('keyup', (e) => {
    send({ type: 'key', code: e.code, key: e.key, pressed: false });
});

// TOUCH (Mobile / Tablet)
let lastTouchX = 0;
let lastTouchY = 0;

// Handle touch start - behaves like Mouse Down + Enable Capture
video.addEventListener('touchstart', (e) => {
    if (e.touches.length > 0) {
         const touch = e.touches[0];
         lastTouchX = touch.clientX;
         lastTouchY = touch.clientY;
         
         // Enable "captured" mode so camera_controller allows rotation
         send({ type: 'mouse_mode', captured: true });
         
         // Send click down (Left Mouse Button)
         send({ type: 'mouse_button', button_index: 1, pressed: true, x: touch.clientX, y: touch.clientY });
    }
}, { passive: false });

// Handle touch move - behaves like Mouse Move (Look)
video.addEventListener('touchmove', (e) => {
    // Prevent scrolling
    e.preventDefault();
    if (e.touches.length > 0) {
        const touch = e.touches[0];
        const dx = touch.clientX - lastTouchX;
        const dy = touch.clientY - lastTouchY;
        
        lastTouchX = touch.clientX;
        lastTouchY = touch.clientY;

        send({ 
            type: 'mouse_motion', 
            x: touch.clientX, 
            y: touch.clientY,
            dx: dx, 
            dy: dy 
        });
    }
}, { passive: false });

// Handle touch end - behaves like Mouse Up + Disable Capture
video.addEventListener('touchend', (e) => {
     // Release click
     send({ type: 'mouse_button', button_index: 1, pressed: false, x: 0, y: 0 });
     
     // Note: On a shooter game, you might NOT want to disable capture immediately 
     // if you want to keep using the keyboard? 
     // But for camera look, dragging stops here.
     // Let's disable capture to stop potential drifting.
     send({ type: 'mouse_mode', captured: false });
}, { passive: false });

start();
