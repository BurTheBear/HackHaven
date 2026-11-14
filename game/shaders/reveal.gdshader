// ECHO reveal shader: surfaces are black except where a ping's ring passes.
// Ping data comes from global shader parameters set by the Echo autoload.
// Slots 0-3 are the player's pings (radius ~6 = a whisper), 4-7 pebble pings.
// Kept cheap: inactive slots and points the ring hasn't reached return early,
// and textures are only sampled where some light actually reaches.
// Texturing: use_triplanar (cave CSG: world-space tex_floor/tex_wall + normals,
// picked by surface normal), use_albedo_tex (imported props: albedo_tex via UV)
// or use_flat (a plain albedo_color). With none of them on (Listener, phantoms)
// the old texture-less echo_color look is used.
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
global uniform float hint_glow;

uniform vec3 echo_color : source_color = vec3(0.24, 0.96, 1.0);
uniform float ping_speed = 18.0;
uniform float ring_width = 1.2;
uniform float afterglow = 2.0;
uniform float grid_scale = 1.0;
uniform float near_glow = 0.35;
// The afterglow stutters a little as it dies, like a failing light.
uniform float flicker = 0.35;
// Extras below default to OFF so Listener / phantom materials (which don't set
// them) look exactly as before. level.gd switches them on for cave materials.
// Echo memory: a very faint, long-lived trace of what your echoes touched.
uniform float echo_memory = 0.0;
uniform float memory_time = 15.0;
// Always-on floor outline around the player, scaled by Settings.hint_glow.
uniform float floor_hint = 0.0;
// How gold pebble pings look (0 = same color as yours).
uniform float pebble_tint = 0.0;
// Surfaces right next to you stay a little brighter in the afterglow.
uniform float close_boost = 0.0;
// Water: the afterglow ripples outward in rings.
uniform float ripple = 0.0;

// How much the real surface colour is pulled toward echo_color when lit.
uniform float tint = 0.35;
uniform float exposure = 2.2;
uniform float use_triplanar = 0.0;
uniform float use_albedo_tex = 0.0;
uniform float use_flat = 0.0;
uniform float tex_scale = 0.3;
uniform float normal_strength = 1.0;
uniform vec3 albedo_color : source_color = vec3(0.6);
uniform sampler2D tex_floor : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_wall : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D nor_floor : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D nor_wall : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;

const vec3 GOLD = vec3(1.0, 0.76, 0.3);

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Bounce timing (fractions of the ring's travel time T = max_r / ping_speed).
const float EASE_B = 0.3;      // ease-out: starts 1.3x fast, slows to 0.7x at max_r
const float SPRING_W = 7.0;    // spring frequency of the overshoot
const float SPRING_Z = 2.6;    // spring damping
const float BACK_START = 0.22; // return ring leaves after the overshoot peak
const float BACK_SPEED = 0.85; // return ring speed (x ping_speed)

// Thin soft band around 0.
float band(float x, float w) {
	return 1.0 - smoothstep(0.0, w, abs(x));
}

// One ping at `pos`. x = ring, y = afterglow, z = white leading edge, w = memory.
// The ring eases out, overshoots max_r on a damped spring, then a fainter
// return ring bounces back to the origin; two reverb ripples trail the front.
vec4 ping_light(vec3 pos, vec4 p, float max_r, float pebble) {
	if (p.w < 0.0) {
		return vec4(0.0);
	}
	vec3 dv = pos - p.xyz;
	float d = length(dv);
	if (d > max_r * 1.08) {
		return vec4(0.0);
	}
	float t = p.w;
	float T = max_r / ping_speed;
	float x = t / T;
	// Main ring radius: eased growth, then a damped spring around max_r.
	float u = max(x - 1.0, 0.0);
	float e = x < 1.0 ? x + EASE_B * x * (1.0 - x)
		: 1.0 + (1.0 - EASE_B) * sin(SPRING_W * u) / SPRING_W * exp(-SPRING_Z * u);
	float r = max_r * e;
	// > 0: the ring hasn't reached this point yet (nothing else has either).
	float ahead = d - r;
	if (ahead > ring_width * 1.3) {
		return vec4(0.0);
	}
	// Whisper pings (player slots, radius ~6 m) are drawn thinner and dimmer.
	float whisper = (1.0 - pebble) * step(5.5, max_r) * step(max_r, 6.5);
	float thin = mix(1.0, 0.45, whisper);
	float dim = mix(1.0, 0.55, whisper);
	float extra = mix(1.0, 0.7, max(pebble, whisper));
	float edge = 1.0 - smoothstep(max_r * 0.75, max_r * 1.08, d);
	// The front fades out while it springs at max_r.
	float out_amp = 1.0 - smoothstep(0.05, 0.7, u);
	// Leading edge wobbles a little in thickness around the ring.
	vec3 dir = dv / max(d, 0.001);
	float wob = 1.0 + 0.22 * sin(dir.x * 9.0 + dir.z * 7.0 + dir.y * 5.0 + t * 11.0);
	float w = ring_width * thin * wob;
	float ring = band(ahead, w) * out_amp;
	float lead = band(ahead - 0.08, 0.22 * thin * wob) * out_amp;
	// Reverb: two smaller ripples trailing the front, decaying.
	float lag = 0.09 * max_r + 0.7 * ring_width * thin;
	float rip = 0.0;
	if (out_amp > 0.0 && ahead < -0.5 * lag) {
		rip = (band(ahead + lag, w * 0.6) * 0.45 + band(ahead + 2.0 * lag, w * 0.45) * 0.2) * out_amp * extra;
	}
	// Bounce back: a fainter ring travels from max_r back toward the origin.
	float tb0 = T * (1.0 + BACK_START);
	float back = 0.0;
	float flash_b = 0.0;
	if (t > tb0) {
		float rb = max_r - (t - tb0) * ping_speed * BACK_SPEED;
		if (rb > -ring_width) {
			float prog = clamp(1.0 - rb / max_r, 0.0, 1.0);
			float amp = 0.38 * extra * smoothstep(0.0, 0.08, prog) * (1.0 - smoothstep(0.55, 1.0, prog));
			back = band(d - rb, w * 0.7) * amp;
			float sb = t - (tb0 + (max_r - d) / (ping_speed * BACK_SPEED));
			flash_b = step(0.0, sb) * exp(-sb * 7.0) * amp * 1.2;
		}
	}
	// Seconds since the main ring passed this point (invert the ease).
	float y = d / max_r;
	float xa = y >= 1.0 ? 1.0 : ((1.0 + EASE_B) - sqrt((1.0 + EASE_B) * (1.0 + EASE_B) - 4.0 * EASE_B * y)) / (2.0 * EASE_B);
	float since = t - xa * T;
	float passed = step(0.0, since);
	float fade = clamp(since / afterglow, 0.0, 1.0);
	float glow = passed * (1.0 - fade) * 0.45;
	float n = fract(sin(floor(p.w * 14.0) * 12.9898 + p.x * 4.1 + p.z * 1.7) * 43758.5453);
	glow *= 1.0 - flicker * smoothstep(0.35, 1.0, fade) * n;
	glow *= 1.0 + ripple * 0.6 * sin(d * 4.0 - p.w * 7.0);
	// Surfaces flash a little as a ring passes, then settle into the afterglow.
	glow += passed * exp(-since * 6.0) * 0.5 + flash_b;
	float mem = passed * echo_memory * (1.0 - clamp(since / memory_time, 0.0, 1.0));
	return vec4((ring + rip + back) * dim, glow * dim, (lead + back * 0.35) * dim, mem) * edge;
}

void fragment() {
	vec4 a0 = ping_light(wpos, ping_0, ping_radius_0, 0.0);
	vec4 a1 = ping_light(wpos, ping_1, ping_radius_1, 0.0);
	vec4 a2 = ping_light(wpos, ping_2, ping_radius_2, 0.0);
	vec4 a3 = ping_light(wpos, ping_3, ping_radius_3, 0.0);
	vec4 b0 = ping_light(wpos, ping_4, ping_radius_4, 1.0);
	vec4 b1 = ping_light(wpos, ping_5, ping_radius_5, 1.0);
	vec4 b2 = ping_light(wpos, ping_6, ping_radius_6, 1.0);
	vec4 b3 = ping_light(wpos, ping_7, ping_radius_7, 1.0);
	vec4 lp = a0 + a1 + a2 + a3;
	vec4 lb = b0 + b1 + b2 + b3;
	// Memory takes the strongest trace, so overlapping pings don't pile up.
	float mem = max(max(max(a0.w, a1.w), max(a2.w, a3.w)), max(max(b0.w, b1.w), max(b2.w, b3.w)));

	bool textured = use_triplanar > 0.5 || use_albedo_tex > 0.5 || use_flat > 0.5;

	vec3 g = wpos * grid_scale;
	vec3 f = abs(fract(g + 0.5) - 0.5);
	vec3 gw = fwidth(g) * 1.5;
	vec3 lines = (vec3(1.0) - smoothstep(vec3(0.0), gw, f)) * (vec3(1.0) - step(vec3(0.9), abs(wnorm)));
	float grid = max(max(lines.x, lines.y), lines.z);
	float rim = 1.0 - abs(dot(NORMAL, VIEW));
	float detail = textured ? 1.0 : (0.3 + 0.7 * grid + 0.5 * rim);
	// Textured surfaces keep only a very faint grid.
	float gk = textured ? 0.15 * grid : grid;

	float to_player = distance(wpos, player_pos);
	float close = 1.0 + close_boost * (1.0 - smoothstep(1.0, 3.5, to_player));
	float ip = (lp.x * 1.4 + lp.y * close) * detail;
	float ib = (lb.x * 1.4 + lb.y * close) * detail;

	float floor_up = step(0.7, wnorm.y);
	// Footstep glow: each step briefly lights the floor around the player.
	float near = (1.0 - smoothstep(0.6, 1.6, to_player)) * floor_up * near_glow * step_glow * (0.4 + gk);
	// Assist outline (Settings.hint_glow): the floor and the foot of the
	// walls within a few meters, so nobody gets completely lost.
	float around = 1.0 - smoothstep(1.5, 4.0, distance(wpos.xz, player_pos.xz));
	float height = wpos.y - player_pos.y;
	float wall_foot = (1.0 - floor_up) * step(-0.3, height) * (1.0 - smoothstep(0.05, 0.4, height));
	float assist = hint_glow * floor_hint * around * (floor_up * (0.08 + 0.5 * gk) + wall_foot * 0.9) * 0.6;
	float memv = mem * (0.35 + 0.65 * gk);
	float lead = clamp(lp.z + lb.z, 0.0, 1.0);

	vec3 col;
	if (textured) {
		vec3 albedo = vec3(0.6);
		float shade = 1.0;
		float light_sum = ip + ib + near + assist + memv + lead;
		if (light_sum > 0.004) {
			if (use_triplanar > 0.5) {
				vec3 nn = normalize(wnorm);
				vec3 wt = pow(abs(nn), vec3(6.0));
				wt /= (wt.x + wt.y + wt.z);
				float up = smoothstep(0.0, 0.3, nn.y);
				vec2 uvy = wpos.xz * tex_scale;
				vec2 uvx = wpos.zy * tex_scale;
				vec2 uvz = wpos.xy * tex_scale;
				vec3 af = texture(tex_floor, uvy).rgb;
				vec3 aw = texture(tex_wall, uvy).rgb;
				vec3 ax = texture(tex_wall, uvx).rgb;
				vec3 az = texture(tex_wall, uvz).rgb;
				albedo = ax * wt.x + az * wt.z + mix(aw, af, up) * wt.y;
				vec3 nf = texture(nor_floor, uvy).xyz * 2.0 - 1.0;
				vec3 nw = texture(nor_wall, uvy).xyz * 2.0 - 1.0;
				vec3 nx = texture(nor_wall, uvx).xyz * 2.0 - 1.0;
				vec3 nz = texture(nor_wall, uvz).xyz * 2.0 - 1.0;
				vec3 ty = mix(nw, nf, up);
				vec3 off = vec3(ty.x, 0.0, ty.y) * wt.y + vec3(0.0, nx.y, nx.x) * wt.x + vec3(nz.x, nz.y, 0.0) * wt.z;
				vec3 pn = normalize(nn + off * normal_strength);
				vec3 vn = normalize((VIEW_MATRIX * vec4(pn, 0.0)).xyz);
				float rl = clamp(dot(vn, VIEW), 0.0, 1.0) / max(abs(dot(normalize(NORMAL), VIEW)), 0.3);
				shade = clamp(rl, 0.25, 1.3);
			} else if (use_albedo_tex > 0.5) {
				albedo = texture(albedo_tex, UV).rgb * albedo_color;
			} else {
				albedo = albedo_color;
			}
		}
		vec3 base = albedo * shade;
		float lum = dot(base, vec3(0.299, 0.587, 0.114));
		vec3 pc = mix(echo_color, GOLD, pebble_tint);
		vec3 ce = mix(base, echo_color * (0.1 + lum * 2.2), tint);
		vec3 cb = mix(base, pc * (0.1 + lum * 2.2), tint);
		col = (ce * (ip + near + assist + memv) + cb * ib) * exposure;
		// A very faint grid, only where the ring is passing.
		col += echo_color * grid * (lp.x + lb.x) * 0.1;
		float peak = max(max(col.r, col.g), col.b);
		col = mix(col, vec3(peak), clamp((lp.x + lb.x) * 0.12, 0.0, 0.25));
		col += vec3(lead * 0.9);
	} else {
		col = echo_color * (ip + near + assist + memv) + mix(echo_color, GOLD, pebble_tint) * ib;
		float peak = max(max(col.r, col.g), col.b);
		col = mix(col, vec3(peak), clamp((lp.x + lb.x) * 0.35, 0.0, 0.6));
		col += vec3(lead * (0.55 + 0.45 * grid) * 1.2);
	}
	ALBEDO = col;
}
