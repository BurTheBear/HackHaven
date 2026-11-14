// ECHO reveal shader: surfaces are black except where a ping's ring passes.
// Ping data comes from global shader parameters set by the Echo autoload.
shader_type spatial;
render_mode unshaded, cull_disabled;

global uniform vec4 ping_0;
global uniform vec4 ping_1;
global uniform vec4 ping_2;
global uniform vec4 ping_3;
global uniform vec4 ping_4;
global uniform vec4 ping_5;
global uniform vec4 ping_6;
global uniform vec4 ping_7;
global uniform float ping_radius_0;
global uniform float ping_radius_1;
global uniform float ping_radius_2;
global uniform float ping_radius_3;
global uniform float ping_radius_4;
global uniform float ping_radius_5;
global uniform float ping_radius_6;
global uniform float ping_radius_7;
global uniform vec3 player_pos;
global uniform float step_glow;

uniform vec3 echo_color : source_color = vec3(0.24, 0.96, 1.0);
uniform float ping_speed = 18.0;
uniform float ring_width = 1.2;
uniform float afterglow = 2.0;
uniform float grid_scale = 1.0;
uniform float near_glow = 0.35;

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// x = ring brightness, y = afterglow brightness
vec2 ping_light(vec4 p, float max_r) {
	if (p.w < 0.0) {
		return vec2(0.0);
	}
	float r = p.w * ping_speed;
	float d = distance(wpos, p.xyz);
	if (d > max_r) {
		return vec2(0.0);
	}
	float ring = (1.0 - smoothstep(0.0, ring_width, abs(d - r))) * (1.0 - step(max_r, r));
	float since = p.w - d / ping_speed;
	float glow = step(0.0, since) * (1.0 - clamp(since / afterglow, 0.0, 1.0)) * 0.45;
	float edge = 1.0 - smoothstep(max_r * 0.75, max_r, d);
	return vec2(ring, glow) * edge;
}

void fragment() {
	vec2 l = ping_light(ping_0, ping_radius_0) + ping_light(ping_1, ping_radius_1)
		+ ping_light(ping_2, ping_radius_2) + ping_light(ping_3, ping_radius_3)
		+ ping_light(ping_4, ping_radius_4) + ping_light(ping_5, ping_radius_5)
		+ ping_light(ping_6, ping_radius_6) + ping_light(ping_7, ping_radius_7);
	vec3 g = wpos * grid_scale;
	vec3 f = abs(fract(g + 0.5) - 0.5);
	vec3 w = fwidth(g) * 1.5;
	vec3 lines = (vec3(1.0) - smoothstep(vec3(0.0), w, f)) * (vec3(1.0) - step(vec3(0.9), abs(wnorm)));
	float grid = max(max(lines.x, lines.y), lines.z);
	float rim = 1.0 - abs(dot(NORMAL, VIEW));
	float detail = 0.3 + 0.7 * grid + 0.5 * rim;
	// Footstep glow: each step briefly lights the floor around the player,
	// so walking gives visible feedback in the dark.
	float near = (1.0 - smoothstep(0.6, 1.6, distance(wpos, player_pos))) * step(0.7, wnorm.y) * near_glow * step_glow;
	float intensity = (l.x * 1.4 + l.y) * detail + near * (0.4 + grid);
	ALBEDO = mix(echo_color, vec3(1.0), clamp(l.x * 0.6, 0.0, 1.0)) * intensity;
}
