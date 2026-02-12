shader_type spatial;
render_mode unshaded;

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

bool is_different(vec2 a, vec2 b) {
	return distance(a, b) > 0.002;
}

bool matches_id(vec2 pixel_id, vec2 target_id) {
	return target_id.x >= 0.0 && distance(pixel_id, target_id) < 0.002;
}

void fragment() {
	vec2 pid = texture(index_map, UV).rg;

	vec3 ctrl_col  = texture(color_lookup, pid).rgb;  // controller (occupier or owner)
	vec3 owner_col = texture(owner_lookup, pid).rgb;   // sovereign owner

	vec3 final_col = ctrl_col;

	// ── Occupation stripes ──────────────────────────────────────────────
	// When controller ≠ owner the province is occupied.
	// Draw thin diagonal stripes of the owner's colour over the occupier base.
	if (distance(ctrl_col, owner_col) > 0.01) {
		float diag    = UV.x * map_size.x - UV.y * map_size.y;
		float pattern = fract(diag / stripe_width);
		float stripe  = step(0.65, pattern);           // 35 % owner stripe, 65 % occupier
		final_col = mix(ctrl_col, owner_col, stripe);
	}

	// ── Borders ─────────────────────────────────────────────────────────
	if (show_borders) {
		vec2 ps = 1.0 / map_size;

		vec2 id_r = texture(index_map, UV + vec2(ps.x, 0.0)).rg;
		vec2 id_l = texture(index_map, UV - vec2(ps.x, 0.0)).rg;
		vec2 id_u = texture(index_map, UV - vec2(0.0, ps.y)).rg;
		vec2 id_d = texture(index_map, UV + vec2(0.0, ps.y)).rg;

		if (is_different(pid, id_r) || is_different(pid, id_l) ||
			is_different(pid, id_u) || is_different(pid, id_d)) {
			final_col = mix(final_col, border_color.rgb, border_color.a);
		}
	}

	// ── Highlights ──────────────────────────────────────────────────────
	if (matches_id(pid, hover_id)) {
		final_col = mix(final_col, hover_tint.rgb, hover_tint.a);
	}
	if (matches_id(pid, selected_id)) {
		final_col = mix(final_col, selected_tint.rgb, selected_tint.a);
	}

	ALBEDO = final_col;
}
