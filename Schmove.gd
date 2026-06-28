extends CharacterBody3D

@onready var debug_label: Label = $"../CanvasLayer/DebugText"

var mouse_sens = 0.3
var camera_anglev=0
const SPEED = 5.0
const JUMP_VELOCITY = 9.0
const AIR_ACCEL = 20.0
const AIR_MAX_SPEED = 20.0
const RAMP_BOOST_MIN_SPEED = 3.0
const RAMP_BOOST_ACCEL = 30.0
const RAMP_BOOST_MAX_SPEED = 20.0
const RAMP_HOLD_ALIGNMENT_MIN = 0.1

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
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	var camera_basis: Basis = ($Schmeepera as Node3D).global_transform.basis

	# Normal air-strafe wish direction - follows the actual input combo (camera
	# basis with pitch included), so air strafing away from ramps is unaffected.
	var air_wish_dir := Vector3.ZERO
	if input_dir:
		air_wish_dir = (camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if is_on_floor():
		if direction:
			velocity.x = direction.x * SPEED
			velocity.z = direction.z * SPEED
		else:
			velocity.x = move_toward(velocity.x, 0, SPEED)
			velocity.z = move_toward(velocity.z, 0, SPEED)
	else:
		_air_accelerate(air_wish_dir, delta)

	move_and_slide()
	_apply_ramp_boost(air_wish_dir, delta)

func _air_accelerate(wish_dir: Vector3, delta: float) -> void:
	if not wish_dir:
		return
	var current_speed: float = velocity.dot(wish_dir)
	var add_speed: float = clamp(AIR_MAX_SPEED - current_speed, 0.0, AIR_ACCEL * delta)
	velocity += wish_dir * add_speed

func _apply_ramp_boost(wish_dir: Vector3, delta: float) -> void:
	debug_label.text = "Ramp Boost: OFF"
	if not wish_dir:
		return # not holding any key at all - never boost

	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var normal := collision.get_normal()
		if normal.angle_to(Vector3.UP) <= floor_max_angle:
			continue # walkable floor, not a ramp face

		# How directly your held input pushes into this surface, measured
		# horizontally only - the ramp's own incline angle is intentionally
		# excluded, so a 60-degree ramp and a 90-degree wall feel the same
		# when you're facing toward them. 0 = purely along it, 1 = dead-on.
		var flat_wish: Vector3 = Vector3(wish_dir.x, 0, wish_dir.z)
		var flat_normal: Vector3 = Vector3(normal.x, 0, normal.z)
		if not flat_wish or not flat_normal:
			continue
		var align: float = flat_wish.normalized().dot(-flat_normal.normalized())
		if align <= RAMP_HOLD_ALIGNMENT_MIN:
			continue

		# Damp existing vertical velocity toward zero, in proportion to how
		# perpendicular you're pushing - fully perpendicular zeroes it
		# outright regardless of how fast you were already falling.
		velocity.y = lerp(velocity.y, 0.0, align)

		# Redirect velocity along the ramp surface, then accelerate it toward
		# RAMP_BOOST_MAX_SPEED a little each tick - staying on the ramp longer
		# keeps building speed, but it levels off instead of compounding.
		var along_ramp: Vector3 = velocity - normal * velocity.dot(normal)
		var speed: float = along_ramp.length()
		if speed < RAMP_BOOST_MIN_SPEED:
			debug_label.text = "Ramp Boost: ON (holding, align %.2f)" % align
			break

		var dir: Vector3 = along_ramp / speed
		var add_speed: float = clamp(RAMP_BOOST_MAX_SPEED - speed, 0.0, RAMP_BOOST_ACCEL * delta)
		velocity = dir * (speed + add_speed)
		debug_label.text = "Ramp Boost: ON (%.1f m/s, align %.2f)" % [speed + add_speed, align]
		break
