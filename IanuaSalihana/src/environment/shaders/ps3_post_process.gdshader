shader_type canvas_item;

// PS3/Console Era Post-Processing Shader
// Implements GTA 4-style visual effects for that distinctive console look

// Main effect controls
uniform bool enable_effects = true;
uniform float effect_intensity : hint_range(0.0, 1.0) = 1.0;
uniform bool vr_mode = false;

// Color grading parameters
uniform float sepia_strength : hint_range(0.0, 1.0) = 0.3;
uniform float warmth : hint_range(0.0, 1.0) = 0.4;
uniform float vintage_contrast : hint_range(0.5, 2.0) = 1.3;
uniform float desaturation : hint_range(0.0, 1.0) = 0.3;

// Film grain and noise
uniform float film_grain_strength : hint_range(0.0, 0.5) = 0.15;
uniform float noise_size : hint_range(1.0, 10.0) = 3.0;

// Chromatic aberration
uniform float chromatic_aberration : hint_range(0.0, 5.0) = 0.8;

// Bloom simulation (fake bloom for lower-end systems)
uniform bool fake_bloom = false;
uniform float bloom_threshold : hint_range(0.0, 2.0) = 1.0;
uniform float bloom_intensity : hint_range(0.0, 3.0) = 1.5;

// Depth of field simulation
uniform bool enable_dof = false;
uniform float dof_blur_size : hint_range(0.0, 10.0) = 2.0;
uniform float dof_focus_distance : hint_range(0.0, 1.0) = 0.5;
uniform float dof_focus_range : hint_range(0.1, 1.0) = 0.3;

// Vignette effect
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.2;
uniform float vignette_size : hint_range(0.1, 2.0) = 0.8;

// Time for animated effects
uniform float time_factor : hint_range(0.1, 5.0) = 1.0;

varying vec2 screen_uv;

vec3 rgb_to_hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv_to_rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

float random(vec2 uv) {
    return fract(sin(dot(uv.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

float noise(vec2 uv) {
    vec2 i = floor(uv);
    vec2 f = fract(uv);

    float a = random(i);
    float b = random(i + vec2(1.0, 0.0));
    float c = random(i + vec2(0.0, 1.0));
    float d = random(i + vec2(1.0, 1.0));

    vec2 u = f * f * (3.0 - 2.0 * f);

    return mix(a, b, u.x) +
            (c - a) * u.y * (1.0 - u.x) +
            (d - b) * u.x * u.y;
}

vec3 apply_sepia(vec3 color, float strength) {
    vec3 sepia_color = vec3(
        dot(color, vec3(0.393, 0.769, 0.189)),
        dot(color, vec3(0.349, 0.686, 0.168)),
        dot(color, vec3(0.272, 0.534, 0.131))
    );
    return mix(color, sepia_color, strength);
}

vec3 apply_warmth(vec3 color, float warmth_amount) {
    // Shift color temperature towards warmer tones
    vec3 warm_color = color;
    warm_color.r *= 1.0 + warmth_amount * 0.2;
    warm_color.g *= 1.0 + warmth_amount * 0.1;
    warm_color.b *= 1.0 - warmth_amount * 0.15;
    return warm_color;
}

vec3 apply_contrast_saturation(vec3 color, float contrast, float saturation) {
    // Apply contrast
    color = mix(vec3(0.5), color, contrast);

    // Apply saturation
    float luminance = dot(color, vec3(0.299, 0.587, 0.114));
    color = mix(vec3(luminance), color, saturation);

    return color;
}

vec3 apply_chromatic_aberration(sampler2D tex, vec2 uv, float strength) {
    if (vr_mode) {
        strength *= 0.3; // Reduce for VR comfort
    }

    vec2 offset = (uv - 0.5) * strength * 0.01;

    float r = texture(tex, uv + offset).r;
    float g = texture(tex, uv).g;
    float b = texture(tex, uv - offset).b;

    return vec3(r, g, b);
}

float apply_vignette(vec2 uv, float strength, float size) {
    vec2 center = uv - 0.5;
    float dist = length(center);
    float vignette = 1.0 - smoothstep(size * 0.5, size, dist);
    return mix(1.0, vignette, strength);
}

vec3 apply_fake_bloom(vec3 color, float threshold, float intensity) {
    // Simple fake bloom by brightening bright areas
    float brightness = dot(color, vec3(0.299, 0.587, 0.114));
    if (brightness > threshold) {
        float bloom_factor = (brightness - threshold) * intensity;
        color += color * bloom_factor;
    }
    return color;
}

void vertex() {
    screen_uv = UV;
}

void fragment() {
    vec2 uv = UV;
    vec3 color = texture(TEXTURE, uv).rgb;

    // Apply chromatic aberration first
    if (enable_effects && chromatic_aberration > 0.0) {
        color = apply_chromatic_aberration(TEXTURE, uv, chromatic_aberration * effect_intensity);
    }

    // Apply fake bloom if enabled
    if (enable_effects && fake_bloom) {
        color = apply_fake_bloom(color, bloom_threshold, bloom_intensity * effect_intensity);
    }

    // Apply PS3/GTA 4 color grading
    if (enable_effects) {
        color = apply_sepia(color, sepia_strength * effect_intensity);
        color = apply_warmth(color, warmth * effect_intensity);
        color = apply_contrast_saturation(color,
            mix(1.0, vintage_contrast, effect_intensity),
            mix(1.0, 1.0 - desaturation, effect_intensity)
        );
    }

    // Add film grain
    if (enable_effects && film_grain_strength > 0.0) {
        float time_seed = TIME * time_factor;
        float grain = noise(uv * noise_size + time_seed) * 2.0 - 1.0;
        grain *= film_grain_strength * effect_intensity;

        // Reduce grain in VR mode
        if (vr_mode) {
            grain *= 0.5;
        }

        color += grain;
    }

    // Apply vignette
    if (enable_effects && vignette_strength > 0.0) {
        float vignette = apply_vignette(uv, vignette_strength * effect_intensity, vignette_size);
        color *= vignette;
    }

    // Clamp final color
    color = clamp(color, 0.0, 1.0);

    COLOR = vec4(color, texture(TEXTURE, uv).a);
}