shader_type sky;

uniform vec3 sky_top_color : source_color = vec3(0.3, 0.405, 0.5);
uniform vec3 sky_horizon_color : source_color = vec3(0.647, 0.655, 0.67);
uniform float sky_curve : hint_range(0.0, 1.0) = 0.15;
uniform vec3 ground_bottom_color : source_color = vec3(0.2, 0.169, 0.133);
uniform vec3 ground_horizon_color : source_color = vec3(0.647, 0.655, 0.67);
uniform float ground_curve : hint_range(0.0, 1.0) = 0.02;

// Cloud parameters
uniform float cloud_density : hint_range(0.0, 1.0) = 0.5;
uniform float cloud_speed : hint_range(0.0, 10.0) = 2.0;
uniform float cloud_darkness : hint_range(0.0, 1.0) = 0.5;
uniform float cloud_scale : hint_range(1.0, 100.0) = 40.0;
uniform vec3 cloud_color : source_color = vec3(0.8, 0.8, 0.8);

// Noise functions
float hash(vec3 p) {
    p = fract(p * 0.3183099 + 0.1);
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
    vec3 p = floor(x);
    vec3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    
    return mix(mix(mix(hash(p + vec3(0, 0, 0)), 
                        hash(p + vec3(1, 0, 0)), f.x),
                   mix(hash(p + vec3(0, 1, 0)), 
                        hash(p + vec3(1, 1, 0)), f.x), f.y),
               mix(mix(hash(p + vec3(0, 0, 1)), 
                        hash(p + vec3(1, 0, 1)), f.x),
                   mix(hash(p + vec3(0, 1, 1)), 
                        hash(p + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    
    for (int i = 0; i < 5; i++) {
        value += amplitude * noise(p * frequency);
        amplitude *= 0.5;
        frequency *= 2.0;
    }
    
    return value;
}

void sky() {
    // Get the direction of the current pixel
    vec3 dir = EYEDIR;
    
    // Calculate sky and ground colors
    float sky_factor = clamp(dir.y, 0.0, 1.0);
    sky_factor = pow(sky_factor, sky_curve);
    vec3 sky_color = mix(sky_horizon_color, sky_top_color, sky_factor);
    
    float ground_factor = clamp(-dir.y, 0.0, 1.0);
    ground_factor = pow(ground_factor, ground_curve);
    vec3 ground_color = mix(ground_horizon_color, ground_bottom_color, ground_factor);
    
    // Combine sky and ground
    vec3 base_color = dir.y > 0.0 ? sky_color : ground_color;
    
    // Add clouds only to the sky part
    if (dir.y > 0.0) {
        // Cloud calculation
        float time = TIME * cloud_speed * 0.01;
        vec3 cloud_pos = vec3(dir.x * cloud_scale + time, dir.z * cloud_scale, dir.y * cloud_scale);
        float cloud_value = fbm(cloud_pos);
        
        // Apply cloud density and shape
        cloud_value = smoothstep(0.5 - cloud_density * 0.5, 0.6, cloud_value);
        
        // Mix clouds with sky
        vec3 cloud_final_color = mix(cloud_color, sky_color, cloud_darkness * (1.0 - dir.y));
        base_color = mix(base_color, cloud_final_color, cloud_value * (1.0 - ground_factor));
    }
    
    // Output the final color
    COLOR = base_color;
}