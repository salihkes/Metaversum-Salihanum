// Web-compatible volumetric cloud shader — no DEPTH_TEXTURE.
// Derived from volumetric_clouds.gdshader.
// Replaces depth-buffer occlusion with analytical ray-planet intersection
// so it works on WebGL / HTML5 builds.

shader_type spatial;
// depth_test_disabled is intentionally NOT used on web.
// Instead we write a custom DEPTH so the GPU's hardware depth test
// correctly hides clouds behind scene objects (characters, buildings).
// depth_draw_never prevents the cloud depth from polluting the buffer
// for later transparent passes (atmosphere).
render_mode blend_mix, depth_draw_never, unshaded, cull_disabled;

// Cloud shell geometry (local planet units, set by script)
uniform float cloud_inner_radius = 66.0;
uniform float cloud_outer_radius = 76.0;

// Planet surface radius for analytical occlusion (set by switcher script)
uniform float planet_surface_radius = 62.0;

// Appearance
uniform float cloud_density : hint_range(0.0, 5.0) = 1.5;
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.45;
uniform float cloud_speed : hint_range(0.0, 0.5) = 0.02;
uniform float cloud_scale : hint_range(0.5, 20.0) = 4.0;
uniform vec3 cloud_bright_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shadow_color : source_color = vec3(0.3, 0.35, 0.5);
uniform float light_absorption : hint_range(0.0, 4.0) = 1.0;

// Sun direction in world space (set every frame by script)
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);

// Quality — lowered defaults for web performance
uniform int march_steps : hint_range(4, 48) = 12;
uniform int light_steps : hint_range(1, 8) = 2;

// ---------------------------------------------------------------------------
// Ray-sphere intersection  (sphere at origin, radius r)
// Returns (t_enter, t_exit).  vec2(-1) on miss.
// ---------------------------------------------------------------------------
vec2 ray_sphere(vec3 ro, vec3 rd, float max_t, float r) {
	float a = dot(rd, rd);
	float b = 2.0 * dot(rd, ro);
	float c = dot(ro, ro) - r * r;
	float d = b * b - 4.0 * a * c;
	if (d < 0.0) return vec2(-1.0);
	float s = sqrt(d);
	return vec2(
		max((-b - s) / (2.0 * a), 0.0),
		min((-b + s) / (2.0 * a), max_t)
	);
}

// ---------------------------------------------------------------------------
// 3-D value noise
// ---------------------------------------------------------------------------
float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3d(vec3 x) {
	vec3 p = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash3(p),               hash3(p + vec3(1,0,0)), f.x),
		    mix(hash3(p + vec3(0,1,0)),  hash3(p + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash3(p + vec3(0,0,1)), hash3(p + vec3(1,0,1)), f.x),
		    mix(hash3(p + vec3(0,1,1)), hash3(p + vec3(1,1,1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise3d(p);
		p = p * 2.01 + vec3(0.17, 0.31, 0.09);
		a *= 0.5;
	}
	return v;
}

// ---------------------------------------------------------------------------
// Cloud density at a planet-centred position (local units)
// ---------------------------------------------------------------------------
float sample_cloud(vec3 pos, float anim) {
	float r = length(pos);
	if (r < cloud_inner_radius || r > cloud_outer_radius) return 0.0;

	float h = (r - cloud_inner_radius) / (cloud_outer_radius - cloud_inner_radius);
	float h_profile = smoothstep(0.0, 0.15, h) * smoothstep(1.0, 0.4, h);

	vec3 dir = normalize(pos);
	vec3 wind = vec3(anim, 0.0, anim * 0.6);
	float n = fbm(dir * cloud_scale + wind);

	return smoothstep(cloud_coverage, cloud_coverage + 0.25, n) * h_profile * cloud_density;
}

// ---------------------------------------------------------------------------
// Henyey-Greenstein phase function
// ---------------------------------------------------------------------------
float phase_hg(float cos_t, float g) {
	float g2 = g * g;
	return (1.0 - g2) / (4.0 * PI * pow(1.0 + g2 - 2.0 * g * cos_t, 1.5));
}

// ---------------------------------------------------------------------------
// Fragment — proper world-to-local ray march (web-safe, no depth texture)
// ---------------------------------------------------------------------------
void fragment() {
	// Godot requires DEPTH to be set in ALL non-discard branches when any
	// branch writes it.  Default to the box-mesh interpolated depth.
	DEPTH = FRAGCOORD.z;

	// Parent-chain uniform scale (e.g. workspace 0.2)
	float ws = length(MODEL_MATRIX[0].xyz);
	vec3 planet_w = MODEL_MATRIX[3].xyz;            // planet centre, world space

	// Camera position in local (planet-centred) units
	vec3 cam = (INV_VIEW_MATRIX[3].xyz - planet_w) / ws;

	// Ray direction: VIEW points frag->camera; negate for camera->scene.
	vec3 rd = normalize(mat3(INV_VIEW_MATRIX) * (-VIEW));

	// Sun direction (already world-space, same as local for uniform scale)
	vec3 sd = normalize(sun_direction);

	// -------------------------------------------------------------------
	// WEB FIX: analytical planet-surface occlusion instead of depth buffer.
	// Uses closest-approach test so it works when the camera is ON/near
	// the planet surface (where simple ray_sphere entry > 0 fails).
	// -------------------------------------------------------------------
	float far_limit = cloud_outer_radius * 4.0;

	// t_closest = parameter where the ray comes nearest to the planet centre.
	// Positive means the closest point is AHEAD (ray heading inward).
	float t_closest = -dot(cam, rd) / dot(rd, rd);
	float max_t;

	if (t_closest > 0.0) {
		// Ray heading toward the planet — check if it enters the planet zone.
		float r_min = length(cam + rd * t_closest);
		if (r_min < planet_surface_radius) {
			// Ray passes through the planet interior.
			vec2 ph = ray_sphere(cam, rd, far_limit, planet_surface_radius);
			if (ph.x > 0.001) {
				// Camera clearly outside planet sphere — stop at near surface
				max_t = ph.x;
			} else {
				// Camera ON or inside the planet sphere and ray heading inward
				// → the planet surface is right in front, block this ray.
				max_t = 0.0;
			}
		} else {
			// Ray passes above the planet — no occlusion needed
			max_t = far_limit;
		}
	} else {
		// Closest approach is behind the camera — ray heading away from planet.
		// Clouds between us and space are fine; no far-side problem.
		max_t = far_limit;
	}

	// Intersect outer cloud shell
	vec2 hit = ray_sphere(cam, rd, max_t, cloud_outer_radius);
	if (hit.x < 0.0 || hit.y < 0.0) discard;
	float t0 = hit.x;
	float t1 = min(hit.y, max_t);
	if (t0 >= t1) discard;

	// Phase function (forward + back scatter blend)
	float ct = dot(rd, sd);
	float phase = mix(phase_hg(ct, 0.3), phase_hg(ct, -0.3), 0.35);

	// Ray-march through the cloud shell
	float anim = TIME * cloud_speed;
	float dt   = (t1 - t0) / float(march_steps);
	float trans = 1.0;
	vec3  light = vec3(0.0);
	float t_first_cloud = -1.0;          // nearest cloud hit (for DEPTH)

	for (int i = 0; i < march_steps; i++) {
		if (trans < 0.01) break;

		float t = t0 + (float(i) + 0.5) * dt;
		vec3  p = cam + rd * t;                       // planet-centred local pos
		float d = sample_cloud(p, anim);
		if (d < 0.001) continue;

		// Record the nearest cloud sample for depth output
		if (t_first_cloud < 0.0) t_first_cloud = t;

		// Light march toward the sun
		float light_od = 0.0;
		float ls = (cloud_outer_radius - cloud_inner_radius) / float(light_steps);
		for (int j = 1; j <= light_steps; j++) {
			light_od += sample_cloud(p + sd * ls * float(j), anim) * ls;
		}

		float sun_atten = exp(-light_od * light_absorption);
		vec3  S  = mix(cloud_shadow_color, cloud_bright_color, sun_atten) * phase;

		// Beer-Lambert integration
		float ext = d * dt;
		float tr  = exp(-ext);
		light += S * trans * (1.0 - tr);
		trans *= tr;
	}

	float alpha = 1.0 - trans;
	if (alpha < 0.003) discard;

	// Write depth at the nearest cloud sample so the GPU depth test
	// correctly hides clouds behind scene objects (countryball, buildings).
	float t_depth = t_first_cloud > 0.0 ? t_first_cloud : t0;
	vec3  cloud_world_pos = planet_w + (cam + rd * t_depth) * ws;
	vec4  cloud_clip = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(cloud_world_pos, 1.0));
	DEPTH = cloud_clip.z / cloud_clip.w;

	ALBEDO = light / max(alpha, 0.001);
	ALPHA  = clamp(alpha, 0.0, 1.0);
}
