shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float ping_age = -1.0;
uniform vec3 ping_origin = vec3(0.0, 1.2, 4.0);
uniform vec3 echo_color : source_color = vec3(1.0, 0.231, 0.306);
varying vec3 world_position;
varying vec3 world_normal;
void vertex() {
 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
 world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
 float arrival = distance(world_position, ping_origin) / 6.0;
 float since = ping_age - arrival;
 float glow = (since >= 0.0) ? exp(-since * 1.9) : 0.0;
 float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.0);
 vec3 cell = abs(fract(world_position * 7.0) - 0.5);
 float line = smoothstep(0.455, 0.49, max(cell.x, max(cell.y, cell.z)));
 ALBEDO = echo_color * glow * (0.09 + rim * 0.85 + line * 0.35);
}
