shader_type spatial;
render_mode cull_disabled;

// Data textures — filter_nearest preserves exact ID values
uniform sampler2D index_map : filter_nearest, repeat_disable;
uniform sampler2D color_lookup : filter_nearest, repeat_disable;   // controller colour (occupier if occupied, else owner)
uniform sampler2D owner_lookup : filter_nearest, repeat_disable;   // always the sovereign owner colour

// Map dimensions in pixels
uniform vec2 map_size = vec2(1024.0, 512.0);

// Province borders
uniform bool show_borders = true;
uniform vec4 border_color : source_color = vec4(0.0, 0.0, 0.0, 0.6);

// Occupation stripes — width in map pixels
uniform float stripe_width = 8.0;

// Hover / selection highlights
uniform vec2 hover_id = vec2(-1.0, -1.0);
uniform vec4 hover_tint : source_color = vec4(1.0, 1.0, 1.0, 0.25);
uniform vec2 selected_id = vec2(-1.0, -1.0);
uniform vec4 selected_tint : source_color = vec4(1.0, 1.0, 1.0, 0.35);

// ── Sphere mode ─────────────────────────────────────────────────────────
uniform bool sphere_mode = false;
uniform float polar_cutoff = 0.12;           // fraction of V-space to letterbox
uniform vec4 ocean_color : source_color = vec4(0.18, 0.32, 0.52, 1.0);
// Minimum visibility on the night side (0 = fully dark, 1 = fully lit).
uniform float night_emission : hint_range(0.0, 1.0) = 0.1;

bool is_different(vec2 a, vec2 b) {
	return distance(a, b) > 0.002;
}

bool matches_id(vec2 pixel_id, vec2 target_id) {
	return target_id.x >= 0.0 && distance(pixel_id, target_id) < 0.002;
}

// Wrap U for sphere mode so the longitude seam (U=0/1) doesn't produce
// false borders.  V is left untouched (latitude doesn't wrap).
vec2 wrap_uv_sphere(vec2 uv_in) {
	return vec2(fract(uv_in.x), uv_in.y);
}

void fragment() {
	vec3 final_col;

	// ── Polar letterbox (sphere only) ───────────────────────────────────
	bool is_polar = sphere_mode && (UV.y < polar_cutoff || UV.y > 1.0 - polar_cutoff);

	if (is_polar) {
		final_col = ocean_color.rgb;
	} else {
		// In sphere mode, remap V so the ENTIRE province texture fits in the
		// non-polar band.  This ADDS ocean at the poles instead of cutting provinces.
		// Raw UV.y  0.12 .. 0.88  →  texture V  0 .. 1
		vec2 prov_uv = UV;
		if (sphere_mode) {
			float band = 1.0 - 2.0 * polar_cutoff;
			prov_uv.y = (UV.y - polar_cutoff) / band;
		}

		vec2 pid = texture(index_map, prov_uv).rg;

		vec3 ctrl_col  = texture(color_lookup, pid).rgb;  // controller (occupier or owner)
		vec3 owner_col = texture(owner_lookup, pid).rgb;   // sovereign owner

		final_col = ctrl_col;

		// ── Occupation stripes ──────────────────────────────────────────
		// When controller ≠ owner the province is occupied.
		// Draw thin diagonal stripes of the owner's colour over the occupier base.
		if (distance(ctrl_col, owner_col) > 0.01) {
			float diag    = prov_uv.x * map_size.x - prov_uv.y * map_size.y;
			float pattern = fract(diag / stripe_width);
			float stripe  = step(0.65, pattern);           // 35 % owner stripe, 65 % occupier
			final_col = mix(ctrl_col, owner_col, stripe);
		}

		// ── Borders ─────────────────────────────────────────────────────
		if (show_borders) {
			vec2 ps = 1.0 / map_size;

			vec2 uv_r = prov_uv + vec2(ps.x, 0.0);
			vec2 uv_l = prov_uv - vec2(ps.x, 0.0);
			vec2 uv_u = prov_uv - vec2(0.0, ps.y);
			vec2 uv_d = prov_uv + vec2(0.0, ps.y);

			// In sphere mode, wrap U so borders across the longitude seam are correct
			if (sphere_mode) {
				uv_r = wrap_uv_sphere(uv_r);
				uv_l = wrap_uv_sphere(uv_l);
				uv_u = wrap_uv_sphere(uv_u);
				uv_d = wrap_uv_sphere(uv_d);
			}

			vec2 id_r = texture(index_map, uv_r).rg;
			vec2 id_l = texture(index_map, uv_l).rg;
			vec2 id_u = texture(index_map, uv_u).rg;
			vec2 id_d = texture(index_map, uv_d).rg;

			if (is_different(pid, id_r) || is_different(pid, id_l) ||
				is_different(pid, id_u) || is_different(pid, id_d)) {
				final_col = mix(final_col, border_color.rgb, border_color.a);
			}
		}

		// ── Highlights ──────────────────────────────────────────────────
		if (matches_id(pid, hover_id)) {
			final_col = mix(final_col, hover_tint.rgb, hover_tint.a);
		}
		if (matches_id(pid, selected_id)) {
			final_col = mix(final_col, selected_tint.rgb, selected_tint.a);
		}
	}

	ALBEDO = final_col;
	// Emit a fraction of the colour so provinces stay readable on the night side.
	EMISSION = final_col * night_emission;
}
