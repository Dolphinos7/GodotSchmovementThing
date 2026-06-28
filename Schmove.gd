extends CharacterBody3D

enum State { GROUNDED, AIRBORNE }

# --- Tunables ---------------------------------------------------------------

const SPEED = 5.0 # base ground walk speed
const JUMP_VELOCITY = 6.0 # upward velocity applied on jump - tuned down so bouncing off a ramp clearly beats it
const DOUBLE_JUMP_VELOCITY = 9.0 # upward velocity applied on the one extra airborne jump

const AIR_ACCEL = 300.0 # how sharply turning redirects air velocity - surf servers crank this way up from Source's strict default for fast, sharp turns
const AIR_STRAFE_SPEED = 1.5 # cap on holding a static direction in air - must keep turning to gain more than this

const DASH_SPEED = 12.0 # velocity impulse added in the dash direction
const DASH_COOLDOWN = 3.0 # seconds before dash can be used again

const GROUND_FRICTION = 8.0 # rate excess ground speed (from a dash) bleeds toward SPEED while sliding
const SLIDE_DURATION = 1.5 # seconds a slide stays active once triggered
const SLIDE_COOLDOWN = 2.0 # seconds before slide can be triggered again
const SLIDE_BUFFER_WINDOW = 0.5 # seconds an airborne slide press stays buffered, waiting for you to land

const RAMP_BOUNCE_MULTIPLIER = 2.0 # scales a surface's exported "bounce" value (see RampSurface.gd) into the restitution used in _bounce_off_ramps

# --- Node references ---------------------------------------------------------

@onready var debug_label: Label = $"../CanvasLayer/DebugText"

# Built at runtime in _ready() instead of placed in the scene file - avoids
# the editor's in-memory copy of the scene going stale if this script edits
# the .tscn directly while it's open.
var slide_tint: ColorRect
var slide_cooldown_label: Label
var dash_cooldown_label: Label

# --- Runtime state -------------------------------------------------------------

var state: State = State.AIRBORNE

var mouse_sens := 0.3
var camera_anglev := 0.0

var dash_cooldown := 0.0
var can_air_dash := true
var can_double_jump := true

var is_sliding := false
var slide_time_remaining := 0.0
var slide_cooldown := 0.0
var slide_buffer_time_remaining := 0.0

var debug_wish_dir := Vector3.ZERO

# --- Lifecycle -----------------------------------------------------------------

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_build_slide_ui()

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and key_event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseMotion:
		var mouse_event := event as InputEventMouseMotion
		self.rotate_y(deg_to_rad(-mouse_event.relative.x * mouse_sens))
		var changev := -mouse_event.relative.y * mouse_sens
		if camera_anglev + changev > -50 and camera_anglev + changev < 50:
			camera_anglev += changev
			$Schmeepera.rotate_x(deg_to_rad(changev))

func _physics_process(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	# Wish direction follows your held key combo rotated by view yaw only -
	# no pitch. This is what makes CS-style air strafing work: looking
	# up/down should never weaken or tilt your horizontal wish direction,
	# only turning left/right (yaw) does, since that's what _air_accelerate
	# measures against your current velocity to gain speed off a turn.
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	debug_wish_dir = direction

	var camera_basis: Basis = ($Schmeepera as Node3D).global_transform.basis

	_update_state()
	_handle_slide(delta)

	if Input.is_action_just_pressed("ui_accept"):
		if state == State.GROUNDED:
			velocity.y = JUMP_VELOCITY
		elif can_double_jump:
			velocity.y = DOUBLE_JUMP_VELOCITY
			can_double_jump = false

	match state:
		State.GROUNDED:
			_process_grounded(direction, delta)
		State.AIRBORNE:
			_process_airborne(direction, delta)

	# Applied after the state-specific movement above, not before - grounded
	# movement overwrites velocity.x/z outright, which would erase a dash
	# impulse added any earlier in the frame.
	_try_dash(direction, camera_basis, delta)

	move_and_slide()
	_bounce_off_ramps()
	_update_debug_label()
	_update_slide_ui()

# --- State machine ---------------------------------------------------------------

func _update_state() -> void:
	var was_grounded: bool = state == State.GROUNDED
	if is_on_floor():
		state = State.GROUNDED
		can_air_dash = true
		can_double_jump = true
		# Landed with a buffered slide press still alive - trigger it
		# immediately instead of requiring a perfectly-timed second press.
		if not was_grounded and slide_buffer_time_remaining > 0.0:
			_start_slide()
	else:
		state = State.AIRBORNE

func _process_grounded(direction: Vector3, delta: float) -> void:
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	var target_speed: float = SPEED if direction else 0.0

	var new_speed: float
	if not is_sliding or horizontal_speed <= SPEED:
		# Normal walking/stopping - snap straight to target, same as before.
		# Also applies if you're carrying excess speed but aren't sliding -
		# that's what makes dashing without sliding a non-event on the ground.
		new_speed = target_speed
	else:
		# Sliding and carrying more speed than base walk allows (e.g. just
		# dashed) - bleed the excess off gradually via friction instead of
		# snapping back down to walk speed instantly.
		new_speed = move_toward(horizontal_speed, target_speed, GROUND_FRICTION * delta)

	var horizontal_dir: Vector3 = direction if direction else Vector3(velocity.x, 0, velocity.z).normalized()
	velocity.x = horizontal_dir.x * new_speed
	velocity.z = horizontal_dir.z * new_speed

func _process_airborne(wish_dir: Vector3, delta: float) -> void:
	velocity += get_gravity() * delta
	_air_accelerate(wish_dir, delta)

func _air_accelerate(wish_dir: Vector3, delta: float) -> void:
	if not wish_dir:
		return

	# current_speed is your velocity's component along wish_dir right now.
	# Holding a static wish_dir (not turning) means current_speed quickly
	# rises to meet AIR_STRAFE_SPEED and add_speed hits zero - acceleration
	# stops dead. The only way to keep add_speed positive is to keep
	# changing wish_dir (turning the camera), which keeps its dot product
	# with your existing velocity low even though your actual speed is high.
	var current_speed: float = velocity.dot(wish_dir)
	var add_speed: float = AIR_STRAFE_SPEED - current_speed
	if add_speed <= 0.0:
		return

	var accel_speed: float = min(AIR_ACCEL * AIR_STRAFE_SPEED * delta, add_speed)
	velocity += wish_dir * accel_speed

# --- Abilities ------------------------------------------------------------------

func _try_dash(wish_dir: Vector3, camera_basis: Basis, delta: float) -> void:
	dash_cooldown = max(dash_cooldown - delta, 0.0)
	if dash_cooldown > 0.0:
		return
	if state == State.AIRBORNE and not can_air_dash:
		return
	if not Input.is_action_just_pressed("dash"):
		return

	# Dash toward whatever direction you're currently trying to move in;
	# fall back to camera-forward if no movement key is held. Always
	# flattened - this is a horizontal dash, vertical velocity is untouched.
	var dash_dir: Vector3 = wish_dir if wish_dir else -camera_basis.z
	dash_dir.y = 0.0
	if not dash_dir:
		return
	dash_dir = dash_dir.normalized()

	# Added to existing velocity rather than overwriting it, so a dash
	# composes with whatever momentum you're already carrying instead of
	# resetting it.
	velocity.x += dash_dir.x * DASH_SPEED
	velocity.z += dash_dir.z * DASH_SPEED
	dash_cooldown = DASH_COOLDOWN
	if state == State.AIRBORNE:
		can_air_dash = false

func _handle_slide(delta: float) -> void:
	slide_cooldown = max(slide_cooldown - delta, 0.0)
	slide_buffer_time_remaining = max(slide_buffer_time_remaining - delta, 0.0)

	if Input.is_action_just_pressed("slide"):
		if state == State.GROUNDED:
			_start_slide()
		else:
			# Not grounded yet - buffer the press so landing within the
			# window triggers it automatically, instead of the press just
			# being dropped.
			slide_buffer_time_remaining = SLIDE_BUFFER_WINDOW

	if is_sliding:
		slide_time_remaining -= delta
		if slide_time_remaining <= 0.0 or state == State.AIRBORNE:
			is_sliding = false

func _start_slide() -> void:
	if slide_cooldown > 0.0:
		return
	is_sliding = true
	slide_time_remaining = SLIDE_DURATION
	slide_cooldown = SLIDE_COOLDOWN
	slide_buffer_time_remaining = 0.0

func _bounce_off_ramps() -> void:
	# Only bounces off ramps you fly into from the air - state here still
	# reflects whatever you were in at the start of this frame, before the
	# move above, so this is "were you airborne when you hit the ramp."
	if state != State.AIRBORNE:
		return

	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var normal: Vector3 = collision.get_normal()
		if normal.angle_to(Vector3.UP) <= floor_max_angle:
			continue # walkable floor, not a ramp face

		# How fast you're moving *into* the surface (negative = into it).
		# Default move_and_slide() just zeroes this component out so you
		# slide along the surface - here it's reflected back out instead,
		# so the whole velocity vector (not just Y) bounces off the ramp the
		# way it physically would off a real ramp.
		var into_normal_speed: float = velocity.dot(normal)
		if into_normal_speed >= 0.0:
			continue # already moving away from it, nothing to bounce

		# Bounciness comes from a "bounce" value exported on whatever you
		# hit (see RampSurface.gd) - level builders attach that script and
		# set bounce per ramp. Anything without it just doesn't bounce.
		var bounce: float = 0.0
		var collider: Object = collision.get_collider()
		if collider:
			var collider_bounce = collider.get("bounce")
			if collider_bounce != null:
				bounce = collider_bounce
		if bounce <= 0.0:
			continue

		velocity -= normal * into_normal_speed * (1.0 + bounce * RAMP_BOUNCE_MULTIPLIER)
		break

# --- UI / debug --------------------------------------------------------------------

func _build_slide_ui() -> void:
	var canvas_layer: CanvasLayer = $"../CanvasLayer"

	slide_tint = ColorRect.new()
	slide_tint.color = Color(0.0, 1.0, 0.0, 0.0)
	slide_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slide_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas_layer.add_child(slide_tint)

	slide_cooldown_label = Label.new()
	slide_cooldown_label.text = "SLIDE READY"
	slide_cooldown_label.add_theme_font_size_override("font_size", 24)
	slide_cooldown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slide_cooldown_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	slide_cooldown_label.position = Vector2(-80.0, 20.0)
	slide_cooldown_label.size = Vector2(160.0, 30.0)
	canvas_layer.add_child(slide_cooldown_label)

	dash_cooldown_label = Label.new()
	dash_cooldown_label.text = "DASH READY"
	dash_cooldown_label.add_theme_font_size_override("font_size", 24)
	dash_cooldown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dash_cooldown_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	dash_cooldown_label.position = Vector2(-80.0, 50.0)
	dash_cooldown_label.size = Vector2(160.0, 30.0)
	canvas_layer.add_child(dash_cooldown_label)

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
	var slide_line: String = "sliding %s  slide_cd %.2f  buffer %.2f  speed %.2f" % [
		str(is_sliding), slide_cooldown, slide_buffer_time_remaining,
		Vector2(velocity.x, velocity.z).length()
	]
	match state:
		State.GROUNDED:
			debug_label.text = "State: GROUNDED\n%s\n%s" % [input_line, slide_line]
		State.AIRBORNE:
			debug_label.text = "State: AIRBORNE\n%s\n%s" % [input_line, slide_line]

func _update_slide_ui() -> void:
	slide_tint.color = Color(0.0, 1.0, 0.0, 0.18 if is_sliding else 0.0)

	if slide_cooldown <= 0.0:
		slide_cooldown_label.text = "SLIDE READY"
	else:
		slide_cooldown_label.text = "SLIDE: %.1fs" % slide_cooldown

	if dash_cooldown <= 0.0:
		dash_cooldown_label.text = "DASH READY"
	else:
		dash_cooldown_label.text = "DASH: %.1fs" % dash_cooldown
