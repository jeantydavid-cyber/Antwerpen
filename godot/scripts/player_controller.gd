extends KinematicBody

# ---------------------------------------------------------------------------
# Player controller: slow, grounded, deliberate first-person movement.
#
# Expected node setup:
#   - This script is attached to a KinematicBody (the player root; yaw is
#     applied directly to this node).
#   - A child Camera and a child CollisionShape (CapsuleShape) are created
#     automatically in _ready() if they are not already present among this
#     node's direct children (looked up by class, not by name), so callers
#     do not need to pre-build them. If a scene already provides its own
#     Camera / CollisionShape children, those are reused as-is.
# ---------------------------------------------------------------------------

signal interact_pressed

# -- Tunables --
const MOUSE_SENSITIVITY := 0.0025 # radians per pixel of relative mouse motion
const PITCH_LIMIT := deg2rad(85.0)

const WALK_SPEED := 2.15
const ACCEL := 4.0 # m/s^2 applied while a movement key is held
const DECEL := 6.0 # m/s^2 applied while no movement key is held (ground friction)
const GRAVITY := 9.8

const STAND_HEIGHT := 1.6
const CROUCH_HEIGHT := 1.05
const CROUCH_LERP_SPEED := 6.0

const HEADBOB_FREQ := 1.8 # cycles per second at walk speed
const HEADBOB_VERT_AMP := 0.03
const HEADBOB_LAT_AMP := 0.015
const BREATH_FREQ := 0.35
const BREATH_AMP := 0.008
const MOTION_FACTOR_LERP_SPEED := 3.0

const INTERACT_REACH := 2.2
const CAPSULE_RADIUS := 0.35
const CAPSULE_HEIGHT := 1.7 # total capsule height (standing)

# -- State --
var camera: Camera
var collision_shape: CollisionShape

var pitch := 0.0
var velocity := Vector3.ZERO

var crouching := false
var crouch_height := STAND_HEIGHT

var reduced_motion := false
var motion_factor := 1.0
var bob_time := 0.0

var _camera_base_local_pos := Vector3.ZERO


func _ready():
	_ensure_camera()
	_ensure_collision_shape()
	_camera_base_local_pos = camera.translation
	crouch_height = STAND_HEIGHT
	camera.translation.y = crouch_height


func _ensure_camera():
	for child in get_children():
		if child is Camera:
			camera = child
			return
	camera = Camera.new()
	camera.name = "Camera"
	camera.translation = Vector3(0, STAND_HEIGHT, 0)
	add_child(camera)


func _ensure_collision_shape():
	for child in get_children():
		if child is CollisionShape:
			collision_shape = child
			return
	collision_shape = CollisionShape.new()
	collision_shape.name = "CollisionShape"
	var capsule := CapsuleShape.new()
	capsule.radius = CAPSULE_RADIUS
	capsule.height = max(0.01, CAPSULE_HEIGHT - CAPSULE_RADIUS * 2.0)
	collision_shape.shape = capsule
	# Center the capsule so its bottom sits at the KinematicBody origin
	# (origin assumed to be at the feet).
	collision_shape.translation = Vector3(0, CAPSULE_HEIGHT * 0.5, 0)
	add_child(collision_shape)


func _input(event):
	if event is InputEventMouseMotion and is_locked():
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		pitch = clamp(pitch - event.relative.y * MOUSE_SENSITIVITY, -PITCH_LIMIT, PITCH_LIMIT)
		if camera:
			camera.rotation.x = pitch

	if event is InputEventKey and event.scancode == KEY_E and event.pressed and not event.echo:
		if is_locked():
			emit_signal("interact_pressed")


func _physics_process(delta):
	if is_locked():
		set_crouch(Input.is_key_pressed(KEY_SHIFT))

	_update_crouch(delta)
	_update_motion_factor(delta)

	if is_locked():
		_process_movement(delta)
	else:
		# Still apply gravity / settle on ground even while unlocked, but no
		# horizontal input.
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y -= GRAVITY * delta
		velocity = move_and_slide(velocity, Vector3.UP)

	_update_head_bob(delta)


func _process_movement(delta):
	var input_dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		input_dir -= transform.basis.z
	if Input.is_key_pressed(KEY_S):
		input_dir += transform.basis.z
	if Input.is_key_pressed(KEY_A):
		input_dir -= transform.basis.x
	if Input.is_key_pressed(KEY_D):
		input_dir += transform.basis.x

	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)

	if input_dir.length() > 0.0:
		input_dir = input_dir.normalized()
		var target_velocity := input_dir * WALK_SPEED
		horizontal_velocity = horizontal_velocity.linear_interpolate(target_velocity, clamp(ACCEL * delta, 0.0, 1.0))
	else:
		horizontal_velocity = horizontal_velocity.linear_interpolate(Vector3.ZERO, clamp(DECEL * delta, 0.0, 1.0))

	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z
	velocity.y -= GRAVITY * delta

	velocity = move_and_slide(velocity, Vector3.UP)


func _update_crouch(delta):
	var target_height = CROUCH_HEIGHT if crouching else STAND_HEIGHT
	crouch_height = lerp(crouch_height, target_height, clamp(CROUCH_LERP_SPEED * delta, 0.0, 1.0))


func _update_motion_factor(delta):
	var target = 0.0 if reduced_motion else 1.0
	motion_factor = lerp(motion_factor, target, clamp(MOTION_FACTOR_LERP_SPEED * delta, 0.0, 1.0))


func _update_head_bob(delta):
	if not camera:
		return

	var horizontal_speed := Vector3(velocity.x, 0.0, velocity.z).length()
	var speed_ratio = clamp(horizontal_speed / WALK_SPEED, 0.0, 1.0)

	bob_time += delta * (1.0 + speed_ratio * 2.0)

	var bob_vert = sin(bob_time * TAU * HEADBOB_FREQ) * HEADBOB_VERT_AMP * speed_ratio
	var bob_lat = sin(bob_time * TAU * HEADBOB_FREQ * 0.5) * HEADBOB_LAT_AMP * speed_ratio

	var breath = sin(bob_time * TAU * BREATH_FREQ) * BREATH_AMP

	var offset_y = (bob_vert + breath) * motion_factor
	var offset_x = bob_lat * motion_factor

	camera.translation.y = crouch_height + offset_y
	camera.translation.x = offset_x


func get_interaction_target(candidates: Array):
	if not camera:
		return null
	var space_state = get_world().direct_space_state
	var from = camera.global_transform.origin
	var to = from - camera.global_transform.basis.z.normalized() * INTERACT_REACH
	var result = space_state.intersect_ray(from, to, [], 0x7FFFFFFF, true, true)
	if result.empty():
		return null
	var collider = result["collider"]
	if candidates.has(collider):
		return collider
	return null


func set_crouch(crouching_now: bool):
	crouching = crouching_now


func set_reduced_motion(reduced: bool):
	reduced_motion = reduced


func lock():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func unlock():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func is_locked() -> bool:
	return Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
