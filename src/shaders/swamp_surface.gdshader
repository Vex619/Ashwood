shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;
// Reactive Swamp Mud & Water Surface Shader (Zone 2 Swampy Marsh).
// Reads `player_foot_world_pos` updated on each footstep to deform the mud
// around the boy's feet and emit expanding concentric wet ripples.

uniform vec3 player_foot_world_pos = vec3(0.0, -100.0, 0.0);
uniform float foot_ripple_age : hint_range(0.0, 10.0) = 10.0;
uniform vec3 monster_world_pos = vec3(0.0, -100.0, 0.0);
uniform float monster_ripple_intensity : hint_range(0.0, 2.0) = 0.0;

uniform vec3 mud_albedo : source_color = vec3(0.055, 0.062, 0.052);
uniform vec3 water_film_tint : source_color = vec3(0.08, 0.105, 0.095);
uniform float base_roughness : hint_range(0.02, 1.0) = 0.14;
uniform float mud_metallic : hint_range(0.0, 1.0) = 0.08;

// Deformation & ripple parameters
uniform float depression_radius : hint_range(0.1, 2.5) = 0.75;
uniform float depression_depth : hint_range(0.0, 0.35) = 0.095;
uniform float ripple_max_radius : hint_range(0.5, 5.0) = 2.6;
uniform float ripple_speed : hint_range(0.5, 6.0) = 2.1;
uniform float ripple_frequency : hint_range(4.0, 40.0) = 18.0;
uniform float ripple_normal_strength : hint_range(0.0, 2.0) = 0.65;

varying vec3 v_world_pos;

float hash21(vec2 p) {
	p = fract(p * vec2(234.56, 789.12));
	p += dot(p, p + 34.56);
	return fract(p.x * p.y);
}

float mud_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float dist_xz = length(world_pos.xz - player_foot_world_pos.xz);

	// Soft pocket depression around the foot impact point + rim displacement swell
	float influence = exp(- (dist_xz * dist_xz) / max(depression_radius * depression_radius * 0.35, 0.001));
	float rim = exp(- pow(dist_xz - depression_radius * 0.65, 2.0) / 0.08) * 0.28;
	float age_atten = clamp(1.0 - foot_ripple_age * 0.22, 0.15, 1.0);
	float dy = (-depression_depth * influence + depression_depth * rim) * age_atten;

	// Subtle ambient marsh surface undulation + Mire Stalker wake displacement
	float m_dist_xz = length(world_pos.xz - monster_world_pos.xz);
	float m_wake = sin(m_dist_xz * 10.0 - TIME * 14.0) * exp(-m_dist_xz * 0.9) * 0.065 * monster_ripple_intensity;
	float wave = sin(world_pos.x * 1.7 + TIME * 1.1) * cos(world_pos.z * 2.1 - TIME * 0.8) * 0.008;
	VERTEX.y += dy + wave + m_wake;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 delta_xz = v_world_pos.xz - player_foot_world_pos.xz;
	float dist = length(delta_xz);
	vec2 dir = dist > 0.0001 ? (delta_xz / dist) : vec2(1.0, 0.0);

	// Expanding concentric wave packet + continuous ambient micro-ripples
	float age = clamp(foot_ripple_age, 0.0, 6.0);
	float wave_front = age * ripple_speed;
	float packet_env = exp(- pow(dist - wave_front, 2.0) * 3.2) * exp(-age * 0.85) * smoothstep(ripple_max_radius, 0.2, dist);
	float continuous_env = exp(-dist * 1.35) * 0.35;
	float phase = dist * ripple_frequency - TIME * (ripple_speed * 4.5);
	float d_ring = cos(phase) * (packet_env + continuous_env);

	// Mire Stalker submerged ripple rings
	vec2 m_delta_xz = v_world_pos.xz - monster_world_pos.xz;
	float m_dist = length(m_delta_xz);
	vec2 m_dir = m_dist > 0.0001 ? (m_delta_xz / m_dist) : vec2(1.0, 0.0);
	float m_env = exp(-m_dist * 0.65) * monster_ripple_intensity;
	float m_ring = cos(m_dist * 22.0 - TIME * 16.0) * m_env;

	// Organic mud micro-bumps
	float n_a = mud_noise(v_world_pos.xz * 3.8 + vec2(TIME * 0.03, 0.0));
	float n_b = mud_noise(v_world_pos.xz * 9.5 - vec2(0.0, TIME * 0.04));
	vec2 mud_grad = vec2(n_a - 0.5, n_b - 0.5) * 0.18;

	vec2 normal_xy = dir * (d_ring * ripple_normal_strength) + m_dir * (m_ring * ripple_normal_strength * 1.25) + mud_grad;
	vec3 tangent_normal = normalize(vec3(-normal_xy.x, -normal_xy.y, 1.0));
	NORMAL_MAP = tangent_normal * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;

	// Wet sheen increases in the depressed footprint & along ripple crests
	float wet_mask = clamp(packet_env + continuous_env + m_env + n_a * 0.35, 0.0, 1.0);
	ALBEDO = mix(mud_albedo, water_film_tint, wet_mask * 0.55);
	ROUGHNESS = mix(base_roughness + 0.22, base_roughness * 0.45, wet_mask);
	METALLIC = mud_metallic;
	SPECULAR = 0.68;
}
