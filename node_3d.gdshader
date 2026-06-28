shader_type spatial;

varying vec3 world_pos;

void vertex() {
	// Called for every vertex the material is visible on.
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Called for every pixel the material is visible on.
	float scale = 1.0; // world units per cell
	vec2 cell = floor(world_pos.xz * scale);
	float checker = mod(cell.x + cell.y, 2.0);
	ALBEDO = vec3(checker);
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
