shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, unshaded;

uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_disable;
uniform sampler2D albedo_texture_2 : source_color, filter_nearest, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float use_secondary_texture : hint_range(0.0, 1.0) = 0.0;
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.2;

uniform float time_sec = 0.0;
uniform vec2 wind_direction = vec2(1.0, 0.3);
uniform float wind_strength : hint_range(0.0, 2.0) = 0.35;
uniform float wind_speed : hint_range(0.1, 8.0) = 2.2;
uniform float turbulence_strength : hint_range(0.0, 2.0) = 0.25;

uniform vec3 player_world_pos = vec3(0.0, -1000.0, 0.0);
uniform float interaction_radius : hint_range(0.1, 10.0) = 2.0;
uniform float interaction_strength : hint_range(0.0, 2.0) = 0.45;

uniform vec3 gust_world_pos = vec3(0.0, -1000.0, 0.0);
uniform float gust_radius : hint_range(0.1, 20.0) = 3.0;
uniform float gust_strength : hint_range(0.0, 3.0) = 0.0;

varying float v_variant;

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float blade_weight = clamp(1.0 - UV.y, 0.0, 1.0);
	float bend = blade_weight * blade_weight;
	v_variant = INSTANCE_CUSTOM.r;
	float phase = INSTANCE_CUSTOM.g * 6.28318530718;

	vec2 wind_dir = normalize(wind_direction + vec2(0.0001, 0.0001));
	float wave_a = sin(world_pos.x * 1.35 + time_sec * wind_speed + phase);
	float wave_b = cos(world_pos.z * 1.05 - time_sec * wind_speed * 0.83 + phase * 0.75);
	float turbulence = sin((world_pos.x + world_pos.z) * 2.5 + time_sec * 3.7 + phase * 1.35);
	float wind_wave = (wave_a + wave_b) * 0.5 + turbulence * turbulence_strength;
	vec2 offset_xz = wind_dir * wind_wave * wind_strength;

	vec2 from_player = world_pos.xz - player_world_pos.xz;
	float player_dist = length(from_player);
	if (player_dist > 0.0001) {
		float player_influence = smoothstep(interaction_radius, 0.0, player_dist);
		offset_xz += normalize(from_player) * (interaction_strength * player_influence);
	}

	vec2 from_gust = world_pos.xz - gust_world_pos.xz;
	float gust_dist = length(from_gust);
	if (gust_dist > 0.0001) {
		float gust_influence = smoothstep(gust_radius, 0.0, gust_dist);
		offset_xz += normalize(from_gust) * (gust_strength * gust_influence);
	}

	float random_strength = mix(0.8, 1.2, v_variant);
	VERTEX.x += offset_xz.x * bend * random_strength;
	VERTEX.z += offset_xz.y * bend * random_strength;
	VERTEX.y += abs(wind_wave) * 0.03 * bend;
}

void fragment() {
	vec4 tex_primary = texture(albedo_texture, UV);
	vec4 tex_secondary = texture(albedo_texture_2, UV);
	float variant_pick = step(0.5, v_variant);
	vec4 tex = mix(tex_primary, tex_secondary, variant_pick * use_secondary_texture);
	float alpha_value = tex.a * tint.a;
	if (alpha_value < alpha_cutoff) {
		discard;
	}
	ALBEDO = tex.rgb * tint.rgb;
}
