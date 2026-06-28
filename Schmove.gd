extends CharacterBody3D

@onready var debug_label: Label = $"../CanvasLayer/DebugText"

enum State { GROUNDED, AIRBORNE, SURFING }

var mouse_sens = 0.3
var camera_anglev=0
var state: State = State.AIRBORNE

# Ramp contact found during the *previous* move_and_slide() - collision data
# isn't available until after a move, so this frame's state decision is based
# on last frame's contact, same way is_on_floor() already works.
var touching_ramp := false
var ramp_normal := Vector3.ZERO
var ramp_align := 0.0
var prev_wish_tangent_dir := Vector3.ZERO
var debug_wish_tangent_y := 0.0
var debug_target_y := 0.0
var debug_wish_dir := Vector3.ZERO

const SPEED = 5.0
const JUMP_VELOCITY = 9.0
const AIR_ACCEL = 20.0
const AIR_MAX_SPEED = 20.0
const RAMP_STICK_FORCE = 0.5
const RAMP_STEER_RATE = 10.0
const RAMP_TANGENT_MIN = 0.05
const RAMP_CLIMB_ACCEL = 4.0
const RAMP_FLICK_BOOST = 1.0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseMotion:
		self.rotate_y(deg_to_rad(-event.relative.x*mouse_sens))
		var changev=-event.relative.y*mouse_sens
		if camera_anglev+changev>-50 and camera_anglev+changev<50:
			camera_anglev+=changev
			$Schmeepera.rotate_x(deg_to_rad(changev))

func _physics_process(delta: float) -> void:
	# Get the input direction.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	var camera_basis: Basis = ($Schmeepera as Node3D).global_transform.basis

	# Wish direction follows the actual input combo (camera basis with pitch
	# included) - used by both air strafing and surf-state ramp interaction.
	var air_wish_dir := Vector3.ZERO
	if input_dir:
		air_wish_dir = (camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	debug_wish_dir = air_wish_dir

	_update_state()

	if Input.is_action_just_pressed("ui_accept") and state == State.GROUNDED:
		velocity.y = JUMP_VELOCITY

	match state:
		State.GROUNDED:
			_process_grounded(direction)
		State.AIRBORNE:
			_process_airborne(air_wish_dir, delta)
		State.SURFING:
			_process_surfing(air_wish_dir, delta)

	move_and_slide()
	_scan_for_ramp_contact(air_wish_dir)
	_update_debug_label()

func _update_state() -> void:
	if touching_ramp:
		state = State.SURFING
	elif is_on_floor():
		state = State.GROUNDED
	else:
		state = State.AIRBORNE

func _process_grounded(direction: Vector3) -> void:
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

func _process_airborne(wish_dir: Vector3, delta: float) -> void:
	velocity += get_gravity() * delta
	_air_accelerate(wish_dir, delta)

func _air_accelerate(wish_dir: Vector3, delta: float) -> void:
	if not wish_dir:
		return
	var current_speed: float = velocity.dot(wish_dir)
	var add_speed: float = clamp(AIR_MAX_SPEED - current_speed, 0.0, AIR_ACCEL * delta)
	velocity += wish_dir * add_speed

func _process_surfing(wish_dir: Vector3, delta: float) -> void:
	# Gravity still pulls; the surf logic below decides how much survives.
	velocity += get_gravity() * delta

	# Strip only the into-surface component, keeping whatever tangential
	# momentum you already had - touching a wall never discards speed you'd
	# already built up, even if your current aim has no forward lean at all.
	velocity -= ramp_normal * velocity.dot(ramp_normal)

	# Keep a small bias pressed into the surface so next frame's
	# move_and_slide() still registers contact - a purely tangential
	# velocity can graze the ramp without re-triggering a collision, which
	# is what was causing the surf/airborne state flicker.
	velocity -= ramp_normal * RAMP_STICK_FORCE

	if not wish_dir:
		prev_wish_tangent_dir = Vector3.ZERO
		debug_wish_tangent_y = 0.0
		debug_target_y = 0.0
		return

	var wish_tangent: Vector3 = wish_dir - ramp_normal * wish_dir.dot(ramp_normal)
	debug_wish_tangent_y = wish_tangent.y
	if wish_tangent.length() < RAMP_TANGENT_MIN:
		# No meaningful lean along the surface at all (aiming dead-on
		# perpendicular) - nothing to steer toward, so hover instead of
		# steering toward a noisy near-zero direction.
		velocity.y = 0.0
		prev_wish_tangent_dir = Vector3.ZERO
		debug_target_y = 0.0
		return

	# Steer the conserved speed toward wherever your aim projects onto the
	# ramp surface - gradual, not instant, so turning into/along the slope
	# redirects momentum into a climb. This is the only place vertical
	# velocity changes while leaning into a climb, so it's no longer fighting
	# a separate damping step every frame.
	var speed: float = velocity.length()
	if speed < 0.01:
		return
	var steer_weight: float = clamp(RAMP_STEER_RATE * delta, 0.0, 1.0)
	var new_dir: Vector3 = velocity.normalized().slerp(wish_tangent.normalized(), steer_weight)
	var target: Vector3 = new_dir * speed

	# No static angle ever climbs - holding steady only ever trends toward
	# flat (dead-on, align=1) or descending (leaning away, align->0 at the
	# gate edge). align^2 - 1 is 0 at dead-on and increasingly negative the
	# further you lean, so the baseline never pulls you upward on its own.
	var climb_bias: float = ramp_align * ramp_align - 1.0
	target.y = climb_bias * speed
	debug_target_y = target.y

	# How fast your aim itself is rotating (radians/sec) - this is the only
	# source of upward motion. Holding a steady angle (turn_rate ~ 0) just
	# follows the baseline above; a sharp flick converts existing speed into
	# a direct upward kick, like using your momentum to jump off the ramp.
	var wish_tangent_dir: Vector3 = wish_tangent.normalized()
	var turn_rate: float = 0.0
	if prev_wish_tangent_dir and delta > 0.0:
		turn_rate = prev_wish_tangent_dir.angle_to(wish_tangent_dir) / delta
	prev_wish_tangent_dir = wish_tangent_dir

	velocity.x = target.x
	velocity.z = target.z
	velocity.y = move_toward(velocity.y, target.y, RAMP_CLIMB_ACCEL * delta)
	velocity.y += turn_rate * speed * RAMP_FLICK_BOOST * delta

func _scan_for_ramp_contact(wish_dir: Vector3) -> void:
	touching_ramp = false
	ramp_normal = Vector3.ZERO
	ramp_align = 0.0
	if not wish_dir:
		return # not holding any key at all - never counts as surfing

	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var normal := collision.get_normal()
		if normal.angle_to(Vector3.UP) <= floor_max_angle:
			continue # walkable floor, not a ramp face

		# Only "stick" if you're actually pushing into the surface (full 3D,
		# not flattened) - holding away from it should just fall back to
		# plain air strafing, not be governed by surf logic at all.
		if wish_dir.dot(normal) >= 0.0:
			continue

		touching_ramp = true
		ramp_normal = normal

		var flat_wish: Vector3 = Vector3(wish_dir.x, 0, wish_dir.z)
		var flat_normal: Vector3 = Vector3(normal.x, 0, normal.z)
		if flat_wish and flat_normal:
			ramp_align = flat_wish.normalized().dot(-flat_normal.normalized())
		break

func _held_keys_string() -> String:
	var keys: Array[String] = []
	if Input.is_action_pressed("move_forward"):
		keys.append("W")
	if Input.is_action_pressed("move_back"):
		keys.append("S")
	if Input.is_action_pressed("move_left"):
		keys.append("A")
	if Input.is_action_pressed("move_right"):
		keys.append("D")
	if keys.is_empty():
		return "(none)"
	return " ".join(keys)

func _update_debug_label() -> void:
	var input_line: String = "keys %s  wish (%.2f, %.2f, %.2f)" % [
		_held_keys_string(), debug_wish_dir.x, debug_wish_dir.y, debug_wish_dir.z
	]
	match state:
		State.GROUNDED:
			debug_label.text = "State: GROUNDED\n%s" % input_line
		State.AIRBORNE:
			debug_label.text = "State: AIRBORNE\n%s" % input_line
		State.SURFING:
			debug_label.text = "State: SURFING\n%s\nalign %.2f  vel.y %.2f\nwish_tangent.y %.2f  target.y %.2f\nnormal (%.2f, %.2f, %.2f)" % [
				input_line, ramp_align, velocity.y, debug_wish_tangent_y, debug_target_y,
				ramp_normal.x, ramp_normal.y, ramp_normal.z
			]
