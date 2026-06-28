extends CharacterBody3D

var mouse_sens = 0.3
var camera_anglev=0
const SPEED = 5.0
const JUMP_VELOCITY = 4.5
const AIR_ACCEL = 20.0
const AIR_MAX_SPEED = 20.0
const RAMP_BOOST_SPEED = 14.0

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

	# Ramp-boost wish direction always points where the camera is facing,
	# ignoring strafe - so holding A/D into a ramp while looking forward still
	# boosts you forward, like pushing into a CS surf ramp. Only used by the
	# ramp boost check below, not general air movement.
	var ramp_wish_dir := Vector3.ZERO
	if input_dir:
		ramp_wish_dir = -camera_basis.z

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
	_apply_ramp_boost(ramp_wish_dir)

func _air_accelerate(wish_dir: Vector3, delta: float) -> void:
	if not wish_dir:
		return
	var current_speed: float = velocity.dot(wish_dir)
	var add_speed: float = clamp(AIR_MAX_SPEED - current_speed, 0.0, AIR_ACCEL * delta)
	velocity += wish_dir * add_speed

func _apply_ramp_boost(wish_dir: Vector3) -> void:
	if not wish_dir:
		return
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var normal := collision.get_normal()
		if normal.angle_to(Vector3.UP) <= floor_max_angle:
			continue # walkable floor, not a ramp face

		# Push along the ramp surface in the camera-forward direction, whether
		# the ramp is dead ahead or off to the side - no longer requires facing
		# directly into it.
		var along_ramp: Vector3 = (wish_dir - normal * wish_dir.dot(normal)).normalized()
		velocity = along_ramp * RAMP_BOOST_SPEED
		break
