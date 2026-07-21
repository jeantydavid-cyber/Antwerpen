extends Spatial

# Procedurally builds the hiding-room: floor, ceiling, walls with a window
# and a door opening, furniture, the ten interactable Areas, Daniel's
# low-detail silhouette, and a sparse dust-mote particle effect.
#
# Everything is generated in _ready() from primitive meshes only — no
# external assets are loaded, matching the "no network dependency" spirit
# of the original browser build.

# -- Palette (coal-smoke chiaroscuro) --
const COAL_BLACK = Color8(0x14, 0x17, 0x1A)
const COAL_BLUE_GREY = Color8(0x2E, 0x3A, 0x45)
const SLATE = Color8(0x55, 0x63, 0x6E)
const CANDLE_AMBER = Color8(0xE9, 0xA8, 0x4C)
const CANDLE_HIGHLIGHT = Color8(0xF4, 0xC8, 0x78)
const DIRTY_SNOW = Color8(0xC4, 0xC9, 0xCC)
const POMEGRANATE_RED = Color8(0xA3, 0x1D, 0x2B)

# -- Room bounds --
const ROOM_HALF_X = 3.0
const ROOM_HALF_Z = 2.5
const ROOM_HEIGHT = 2.8
const WALL_THICK = 0.15

# -- Public state exposed to other scripts --
var player_spawn_position: Vector3 = Vector3.ZERO
var player_spawn_yaw_degrees: float = 0.0

# -- Internal bookkeeping --
var interactables := []
var candle_anchor: Spatial = null
var daniel_anchor: Spatial = null
var daniel_default_transform := Transform.IDENTITY
var hiding_spot_anchors := {}
var evidence_nodes := {}

var mezuzah_node: MeshInstance = null
var mezuzah_frame_local_pos := Vector3.ZERO
var mezuzah_stash_local_pos := Vector3.ZERO

var table_pos := Vector3.ZERO
var table_top_world_y := 0.0


func _ready():
	_build_floor()
	_build_ceiling()
	_build_walls_and_window()
	_build_door()
	_build_table_and_props()
	_build_daniel()
	_build_hiding_spots()
	_build_wall_drawing()
	_build_mizrach_papercut()
	_build_dust_motes()

	player_spawn_position = Vector3(0.4, 0.0, 0.6)
	var target = Vector3(0.85, 0.0, -0.9)
	var dir = target - player_spawn_position
	dir.y = 0.0
	if dir.length() > 0.001:
		dir = dir.normalized()
		player_spawn_yaw_degrees = rad2deg(atan2(-dir.x, -dir.z))
	else:
		player_spawn_yaw_degrees = 0.0


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func get_interactables() -> Array:
	return interactables


func get_candle_anchor() -> Spatial:
	return candle_anchor


func get_daniel_anchor() -> Spatial:
	return daniel_anchor


func get_hiding_spot_anchor(id):
	return hiding_spot_anchors.get(id, null)


func set_daniel_visible(is_visible, at_spot):
	if daniel_anchor == null:
		return

	if at_spot == null or String(at_spot) == "":
		daniel_anchor.transform = daniel_default_transform
		daniel_anchor.visible = is_visible
		return

	var anchor = hiding_spot_anchors.get(at_spot, null)
	if anchor == null:
		daniel_anchor.visible = is_visible
		return

	var target_pos = anchor.global_transform.origin
	match at_spot:
		"hidingWardrobe":
			# Tucked behind the wardrobe's closed doors — geometry mostly
			# occludes him from the room.
			daniel_anchor.global_transform.origin = target_pos
			daniel_anchor.visible = is_visible
		"hidingFloorboards":
			# Sunk beneath the floor plane so the opaque floor occludes him.
			daniel_anchor.global_transform.origin = target_pos - Vector3(0, 0.6, 0)
			daniel_anchor.visible = is_visible
		"hidingCellarHatch":
			# Underground / off-screen entirely.
			daniel_anchor.global_transform.origin = target_pos
			daniel_anchor.visible = false
		_:
			daniel_anchor.global_transform.origin = target_pos
			daniel_anchor.visible = is_visible


func set_evidence_hidden(id, hidden):
	match id:
		"tableBowl", "wallDrawing":
			if evidence_nodes.has(id):
				evidence_nodes[id].visible = not hidden
		"doorframeMezuzah":
			if mezuzah_node != null:
				mezuzah_node.translation = mezuzah_stash_local_pos if hidden else mezuzah_frame_local_pos
		_:
			pass


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _mat(color: Color, opts := {}) -> SpatialMaterial:
	var m = SpatialMaterial.new()
	var alpha = opts.get("alpha", 1.0)
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.roughness = opts.get("roughness", 0.9)
	m.metallic = opts.get("metallic", 0.0)
	if opts.get("transparent", false):
		m.flags_transparent = true
	if opts.get("unshaded", false):
		m.flags_unshaded = true
	if opts.get("emissive", false):
		m.emission_enabled = true
		m.emission = opts.get("emission_color", color)
		m.emission_energy = opts.get("emission_energy", 1.0)
	if opts.get("billboard", false):
		m.params_billboard_mode = SpatialMaterial.BILLBOARD_ENABLED
	return m


func _new_static_body(pos: Vector3, name_: String) -> StaticBody:
	var b = StaticBody.new()
	b.name = name_
	b.translation = pos
	add_child(b)
	return b


func _add_box_part(body: Spatial, size: Vector3, local_pos: Vector3, mat: SpatialMaterial, name_: String, with_collision := true) -> MeshInstance:
	var mi = MeshInstance.new()
	mi.name = name_
	mi.use_in_baked_light = true
	var mesh = CubeMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.translation = local_pos
	body.add_child(mi)
	if with_collision:
		var cs = CollisionShape.new()
		cs.name = name_ + "Shape"
		var shp = BoxShape.new()
		shp.extents = size / 2.0
		cs.shape = shp
		cs.translation = local_pos
		body.add_child(cs)
	return mi


func _add_mesh_only(parent: Spatial, mesh: Mesh, mat: SpatialMaterial, local_pos: Vector3, rot_deg: Vector3, name_: String) -> MeshInstance:
	var mi = MeshInstance.new()
	mi.name = name_
	mi.use_in_baked_light = true
	mi.mesh = mesh
	mi.material_override = mat
	mi.translation = local_pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


func _add_area(parent: Spatial, id: String, size: Vector3, local_pos: Vector3, name_: String) -> Area:
	var area = Area.new()
	area.name = name_
	area.set_script(load("res://scripts/interactable.gd"))
	area.interactable_id = id
	area.translation = local_pos
	area.collision_layer = 2
	area.collision_mask = 0
	var cs = CollisionShape.new()
	var shp = BoxShape.new()
	shp.extents = size / 2.0
	cs.shape = shp
	area.add_child(cs)
	parent.add_child(area)
	interactables.append(area)
	return area


# ---------------------------------------------------------------------------
# Floor / ceiling / walls
# ---------------------------------------------------------------------------

func _build_floor():
	var mat = _mat(Color(0.27, 0.19, 0.12), {"roughness": 0.85})
	var mi = MeshInstance.new()
	mi.name = "Floor"
	var mesh = PlaneMesh.new()
	mesh.size = Vector2(ROOM_HALF_X * 2.0, ROOM_HALF_Z * 2.0)
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)

	var body = _new_static_body(Vector3(0, -0.05, 0), "FloorBody")
	_add_box_part(body, Vector3(ROOM_HALF_X * 2.0, 0.1, ROOM_HALF_Z * 2.0), Vector3.ZERO, mat, "FloorCollider")


func _build_ceiling():
	var mat = _mat(COAL_BLUE_GREY * 0.35, {"roughness": 0.95})
	var mi = MeshInstance.new()
	mi.name = "Ceiling"
	var mesh = PlaneMesh.new()
	mesh.size = Vector2(ROOM_HALF_X * 2.0, ROOM_HALF_Z * 2.0)
	mi.mesh = mesh
	mi.material_override = mat
	mi.translation = Vector3(0, ROOM_HEIGHT, 0)
	mi.rotation_degrees = Vector3(180, 0, 0)
	add_child(mi)


func _build_walls_and_window():
	var wall_mat = _mat(Color(COAL_BLUE_GREY.r * 0.55, COAL_BLUE_GREY.g * 0.55, COAL_BLUE_GREY.b * 0.55), {"roughness": 0.95})

	# -- North wall (z = -ROOM_HALF_Z) with a window opening --
	var north = _new_static_body(Vector3(0, 0, -ROOM_HALF_Z), "NorthWall")
	_add_box_part(north, Vector3(2.5, ROOM_HEIGHT, WALL_THICK), Vector3(-1.75, ROOM_HEIGHT * 0.5, 0), wall_mat, "Left")
	_add_box_part(north, Vector3(2.5, ROOM_HEIGHT, WALL_THICK), Vector3(1.75, ROOM_HEIGHT * 0.5, 0), wall_mat, "Right")
	_add_box_part(north, Vector3(1.0, 1.2, WALL_THICK), Vector3(0, 0.6, 0), wall_mat, "Bottom")
	_add_box_part(north, Vector3(1.0, 0.6, WALL_THICK), Vector3(0, 2.5, 0), wall_mat, "Top")

	# -- East / West walls (solid) --
	var west = _new_static_body(Vector3(-ROOM_HALF_X, 0, 0), "WestWall")
	_add_box_part(west, Vector3(WALL_THICK, ROOM_HEIGHT, ROOM_HALF_Z * 2.0), Vector3(0, ROOM_HEIGHT * 0.5, 0), wall_mat, "Wall")

	var east = _new_static_body(Vector3(ROOM_HALF_X, 0, 0), "EastWall")
	_add_box_part(east, Vector3(WALL_THICK, ROOM_HEIGHT, ROOM_HALF_Z * 2.0), Vector3(0, ROOM_HEIGHT * 0.5, 0), wall_mat, "Wall")

	# -- Window frame + pane, set into the north wall opening --
	var trim_mat = _mat(Color(0.3, 0.22, 0.15), {"roughness": 0.8})
	var win_group = Spatial.new()
	win_group.name = "Window"
	win_group.translation = Vector3(0, 1.7, -ROOM_HALF_Z)
	add_child(win_group)
	_add_mesh_only(win_group, _box(1.08, 0.08, 0.1), trim_mat, Vector3(0, 0.5, 0.03), Vector3.ZERO, "TrimTop")
	_add_mesh_only(win_group, _box(1.08, 0.08, 0.1), trim_mat, Vector3(0, -0.5, 0.03), Vector3.ZERO, "TrimBottom")
	_add_mesh_only(win_group, _box(0.08, 1.08, 0.1), trim_mat, Vector3(-0.5, 0, 0.03), Vector3.ZERO, "TrimLeft")
	_add_mesh_only(win_group, _box(0.08, 1.08, 0.1), trim_mat, Vector3(0.5, 0, 0.03), Vector3.ZERO, "TrimRight")

	var pane_mat = _mat(COAL_BLUE_GREY, {"alpha": 0.35, "transparent": true, "emissive": true, "emission_color": COAL_BLUE_GREY, "emission_energy": 0.35, "roughness": 0.1})
	var pane_body = _new_static_body(win_group.translation, "WindowPane")
	_add_box_part(pane_body, Vector3(0.92, 0.92, 0.03), Vector3.ZERO, pane_mat, "Pane")


func _build_door():
	var wall_mat = _mat(Color(COAL_BLUE_GREY.r * 0.55, COAL_BLUE_GREY.g * 0.55, COAL_BLUE_GREY.b * 0.55), {"roughness": 0.95})

	# -- South wall (z = +ROOM_HALF_Z) with a door opening --
	var south = _new_static_body(Vector3(0, 0, ROOM_HALF_Z), "SouthWall")
	_add_box_part(south, Vector3(2.5, ROOM_HEIGHT, WALL_THICK), Vector3(-1.75, ROOM_HEIGHT * 0.5, 0), wall_mat, "Left")
	_add_box_part(south, Vector3(2.5, ROOM_HEIGHT, WALL_THICK), Vector3(1.75, ROOM_HEIGHT * 0.5, 0), wall_mat, "Right")
	_add_box_part(south, Vector3(1.0, 0.7, WALL_THICK), Vector3(0, 2.45, 0), wall_mat, "Lintel")

	var trim_mat = _mat(Color(0.28, 0.2, 0.13), {"roughness": 0.75})
	var frame = Spatial.new()
	frame.name = "DoorFrame"
	frame.translation = Vector3(0, 0, ROOM_HALF_Z)
	add_child(frame)
	_add_mesh_only(frame, _box(0.08, 2.16, 0.1), trim_mat, Vector3(-0.5, 1.08, -0.06), Vector3.ZERO, "PostLeft")
	_add_mesh_only(frame, _box(0.08, 2.16, 0.1), trim_mat, Vector3(0.5, 1.08, -0.06), Vector3.ZERO, "PostRight")
	_add_mesh_only(frame, _box(1.08, 0.08, 0.1), trim_mat, Vector3(0, 2.14, -0.06), Vector3.ZERO, "Lintel")

	# Door leaf: closed, blocks the opening until later gameplay opens it.
	var leaf_mat = _mat(Color(0.24, 0.17, 0.1), {"roughness": 0.7})
	var leaf_body = _new_static_body(Vector3(0, 1.0, ROOM_HALF_Z - 0.06), "DoorLeaf")
	_add_box_part(leaf_body, Vector3(0.9, 2.0, 0.06), Vector3.ZERO, leaf_mat, "Leaf")

	# Mezuzah case on the right-hand frame post, ~1.4m up.
	var brass_mat = _mat(Color(0.72, 0.58, 0.28), {"metallic": 0.6, "roughness": 0.25})
	mezuzah_node = MeshInstance.new()
	mezuzah_node.name = "Mezuzah"
	mezuzah_node.mesh = _box(0.03, 0.1, 0.03)
	mezuzah_node.material_override = brass_mat
	mezuzah_frame_local_pos = Vector3(0.5, 1.4, ROOM_HALF_Z - 0.07)
	# mezuzah_stash_local_pos is finalized in _build_table_and_props(), once
	# the table's position is known (that function runs right after this one).
	mezuzah_node.translation = mezuzah_frame_local_pos
	mezuzah_node.rotation_degrees = Vector3(0, 0, -20)
	add_child(mezuzah_node)

	_add_area(self, "doorframeMezuzah", Vector3(0.14, 0.2, 0.1), mezuzah_frame_local_pos, "MezuzahArea")

	# Door interactable Area covers the opening.
	_add_area(self, "door", Vector3(1.0, 2.1, 0.4), Vector3(0, 1.0, ROOM_HALF_Z - 0.1), "DoorArea")


# ---------------------------------------------------------------------------
# Table, candle, honey jar, bowl
# ---------------------------------------------------------------------------

func _build_table_and_props():
	table_pos = Vector3(1.0, 0, -1.0)
	var wood_mat = _mat(Color(0.28, 0.19, 0.11), {"roughness": 0.7})

	var table_body = _new_static_body(table_pos, "Table")
	_add_box_part(table_body, Vector3(0.9, 0.05, 0.55), Vector3(0, 0.75, 0), wood_mat, "Top")
	_add_box_part(table_body, Vector3(0.05, 0.75, 0.05), Vector3(0.4, 0.375, 0.24), wood_mat, "LegFR", true)
	_add_box_part(table_body, Vector3(0.05, 0.75, 0.05), Vector3(0.4, 0.375, -0.24), wood_mat, "LegBR", true)
	_add_box_part(table_body, Vector3(0.05, 0.75, 0.05), Vector3(-0.4, 0.375, -0.24), wood_mat, "LegBL", true)
	_add_box_part(table_body, Vector3(0.05, 0.75, 0.05), Vector3(-0.4, 0.375, 0.24), wood_mat, "LegFL", true)

	table_top_world_y = table_pos.y + 0.775

	# Now that table_top_world_y is known, fix the mezuzah's stash spot: a
	# small clear patch on the table, near the front-left corner.
	mezuzah_stash_local_pos = Vector3(table_pos.x - 0.35, table_top_world_y + 0.02, table_pos.z + 0.2)

	_build_candle()
	_build_honey_jar()
	_build_bowl()


func _build_candle():
	var group = Spatial.new()
	group.name = "Candle"
	group.translation = Vector3(table_pos.x - 0.15, table_top_world_y, table_pos.z)
	add_child(group)

	var wax_mat = _mat(Color(0.93, 0.89, 0.78), {"roughness": 0.6})
	var wick_mat = _mat(Color(0.1, 0.08, 0.06), {"roughness": 0.9})
	var flame_mat = _mat(CANDLE_HIGHLIGHT, {"unshaded": true, "emissive": true, "emission_color": CANDLE_AMBER, "emission_energy": 4.0})
	var glow_mat = _mat(CANDLE_AMBER, {"unshaded": true, "transparent": true, "alpha": 0.12, "emissive": true, "emission_color": CANDLE_AMBER, "emission_energy": 2.0})

	var wax = CylinderMesh.new()
	wax.top_radius = 0.035
	wax.bottom_radius = 0.04
	wax.height = 0.12
	_add_mesh_only(group, wax, wax_mat, Vector3(0, 0.06, 0), Vector3.ZERO, "Wax")

	var wick = CylinderMesh.new()
	wick.top_radius = 0.004
	wick.bottom_radius = 0.004
	wick.height = 0.02
	_add_mesh_only(group, wick, wick_mat, Vector3(0, 0.13, 0), Vector3.ZERO, "Wick")

	var flame = CylinderMesh.new()
	flame.top_radius = 0.002
	flame.bottom_radius = 0.018
	flame.height = 0.05
	_add_mesh_only(group, flame, flame_mat, Vector3(0, 0.165, 0), Vector3.ZERO, "Flame")

	var glow = SphereMesh.new()
	glow.radius = 0.07
	glow.height = 0.14
	_add_mesh_only(group, glow, glow_mat, Vector3(0, 0.165, 0), Vector3.ZERO, "Glow")

	candle_anchor = Spatial.new()
	candle_anchor.name = "CandleFlameAnchor"
	candle_anchor.translation = Vector3(0, 0.19, 0)
	group.add_child(candle_anchor)

	_add_area(group, "candle", Vector3(0.14, 0.26, 0.14), Vector3(0, 0.13, 0), "CandleArea")


func _build_honey_jar():
	var group = Spatial.new()
	group.name = "HoneyJar"
	group.translation = Vector3(table_pos.x + 0.2, table_top_world_y, table_pos.z - 0.12)
	add_child(group)

	var jar_mat = _mat(CANDLE_AMBER, {"alpha": 0.55, "transparent": true, "roughness": 0.3, "emissive": true, "emission_color": CANDLE_AMBER, "emission_energy": 0.3})
	var lid_mat = _mat(Color(0.5, 0.4, 0.25), {"roughness": 0.8})
	var thread_mat = _mat(POMEGRANATE_RED, {"roughness": 0.5})

	var jar = CylinderMesh.new()
	jar.top_radius = 0.035
	jar.bottom_radius = 0.04
	jar.height = 0.09
	_add_mesh_only(group, jar, jar_mat, Vector3(0, 0.045, 0), Vector3.ZERO, "JarBody")

	var lid = CylinderMesh.new()
	lid.top_radius = 0.04
	lid.bottom_radius = 0.04
	lid.height = 0.015
	_add_mesh_only(group, lid, lid_mat, Vector3(0, 0.0975, 0), Vector3.ZERO, "Lid")

	# The single pomegranate-red detail in the whole scene: a thin thread
	# (a slim band) tied around the honey jar's neck. Godot 3.5 has no
	# TorusMesh primitive, so a thin, slightly-larger-radius cylinder stands
	# in as the wrapped thread.
	var thread = CylinderMesh.new()
	thread.top_radius = 0.043
	thread.bottom_radius = 0.043
	thread.height = 0.012
	_add_mesh_only(group, thread, thread_mat, Vector3(0, 0.078, 0), Vector3.ZERO, "RedThread")

	_add_area(group, "honeyJar", Vector3(0.1, 0.12, 0.1), Vector3(0, 0.05, 0), "HoneyJarArea")


func _build_bowl():
	var group = Spatial.new()
	group.name = "TableBowl"
	group.translation = Vector3(table_pos.x + 0.2, table_top_world_y, table_pos.z + 0.12)
	add_child(group)

	var bowl_mat = _mat(Color(DIRTY_SNOW.r * 0.85, DIRTY_SNOW.g * 0.85, DIRTY_SNOW.b * 0.85), {"roughness": 0.5})
	var bowl = CylinderMesh.new()
	bowl.top_radius = 0.09
	bowl.bottom_radius = 0.06
	bowl.height = 0.035
	var bowl_mi = _add_mesh_only(group, bowl, bowl_mat, Vector3(0, 0.0175, 0), Vector3.ZERO, "Bowl")
	evidence_nodes["tableBowl"] = bowl_mi

	_add_area(group, "tableBowl", Vector3(0.2, 0.06, 0.2), Vector3(0, 0.02, 0), "TableBowlArea")


func _box(x: float, y: float, z: float) -> CubeMesh:
	var m = CubeMesh.new()
	m.size = Vector3(x, y, z)
	return m


# ---------------------------------------------------------------------------
# Daniel — low-detail primitive silhouette
# ---------------------------------------------------------------------------

func _build_daniel():
	daniel_anchor = Spatial.new()
	daniel_anchor.name = "DanielAnchor"
	var default_pos = Vector3(0.55, 0, -0.85)
	var to_candle = Vector3(table_pos.x - 0.15, 0, table_pos.z) - default_pos
	to_candle.y = 0
	var yaw = 0.0
	if to_candle.length() > 0.001:
		to_candle = to_candle.normalized()
		yaw = rad2deg(atan2(-to_candle.x, -to_candle.z))
	daniel_anchor.translation = default_pos
	daniel_anchor.rotation_degrees = Vector3(0, yaw, 0)
	add_child(daniel_anchor)

	var cloth_mat = _mat(Color(COAL_BLUE_GREY.r * 1.3, COAL_BLUE_GREY.g * 1.3, COAL_BLUE_GREY.b * 1.3), {"roughness": 0.85})
	var skin_mat = _mat(Color(0.72, 0.6, 0.5), {"roughness": 0.8})

	# Folded legs, resting on the floor.
	var leg_mesh = CylinderMesh.new()
	leg_mesh.top_radius = 0.06
	leg_mesh.bottom_radius = 0.06
	leg_mesh.height = 0.32
	_add_mesh_only(daniel_anchor, leg_mesh, cloth_mat, Vector3(0.09, 0.09, 0.15), Vector3(90, 0, 0), "LegLeft")
	_add_mesh_only(daniel_anchor, leg_mesh, cloth_mat, Vector3(-0.09, 0.09, 0.15), Vector3(90, 0, 0), "LegRight")

	# Torso.
	var torso_mesh = CapsuleMesh.new()
	torso_mesh.radius = 0.16
	torso_mesh.mid_height = 0.4
	# CapsuleMesh's long axis is local Z by default in Godot 3.5; rotate it
	# upright so the torso stands along Y.
	_add_mesh_only(daniel_anchor, torso_mesh, cloth_mat, Vector3(0, 0.45, 0), Vector3(90, 0, 0), "Torso")

	# Arms.
	var arm_mesh = CylinderMesh.new()
	arm_mesh.top_radius = 0.045
	arm_mesh.bottom_radius = 0.045
	arm_mesh.height = 0.32
	_add_mesh_only(daniel_anchor, arm_mesh, cloth_mat, Vector3(0.19, 0.55, 0.05), Vector3(0, 0, 20), "ArmLeft")
	_add_mesh_only(daniel_anchor, arm_mesh, cloth_mat, Vector3(-0.19, 0.55, 0.05), Vector3(0, 0, -20), "ArmRight")

	# Head — no face detail, deliberately. Sized for a small child, not an adult.
	var head_mesh = SphereMesh.new()
	head_mesh.radius = 0.105
	head_mesh.height = 0.21
	_add_mesh_only(daniel_anchor, head_mesh, skin_mat, Vector3(0, 0.9, 0), Vector3.ZERO, "Head")

	# Short neck so the head doesn't look like it's resting directly on the torso.
	var neck_mesh = CylinderMesh.new()
	neck_mesh.top_radius = 0.05
	neck_mesh.bottom_radius = 0.06
	neck_mesh.height = 0.08
	_add_mesh_only(daniel_anchor, neck_mesh, skin_mat, Vector3(0, 0.825, 0), Vector3.ZERO, "Neck")

	daniel_default_transform = daniel_anchor.transform

	_add_area(daniel_anchor, "daniel", Vector3(0.45, 1.15, 0.45), Vector3(0, 0.55, 0), "DanielArea")


# ---------------------------------------------------------------------------
# Hiding spots
# ---------------------------------------------------------------------------

func _build_hiding_spots():
	_build_wardrobe()
	_build_floorboards()
	_build_cellar_hatch()


func _build_wardrobe():
	var pos = Vector3(-ROOM_HALF_X + 0.3, 0, 1.0)
	var wood_mat = _mat(Color(0.22, 0.15, 0.09), {"roughness": 0.75})
	var panel_mat = _mat(Color(0.19, 0.13, 0.08), {"roughness": 0.7})

	var body = _new_static_body(pos, "Wardrobe")
	_add_box_part(body, Vector3(0.5, 1.9, 1.0), Vector3(0, 0.95, 0), wood_mat, "Carcass")
	_add_box_part(body, Vector3(0.04, 1.7, 0.46), Vector3(0.27, 0.95, -0.245), panel_mat, "DoorLeft", false)
	_add_box_part(body, Vector3(0.04, 1.7, 0.46), Vector3(0.27, 0.95, 0.245), panel_mat, "DoorRight", false)

	var anchor = Spatial.new()
	anchor.name = "WardrobeHideAnchor"
	anchor.translation = Vector3(0, 0.55, 0)
	body.add_child(anchor)
	hiding_spot_anchors["hidingWardrobe"] = anchor

	_add_area(body, "hidingWardrobe", Vector3(0.6, 1.9, 1.1), Vector3(0, 0.95, 0), "WardrobeArea")


func _build_floorboards():
	var pos = Vector3(-0.4, 0, 1.4)
	var rug_mat = _mat(Color(0.35, 0.28, 0.22), {"roughness": 0.9})
	var plank_mat = _mat(Color(0.32, 0.23, 0.15), {"roughness": 0.7})

	var group = Spatial.new()
	group.name = "Floorboards"
	group.translation = pos
	add_child(group)

	var rug = PlaneMesh.new()
	rug.size = Vector2(1.0, 0.7)
	_add_mesh_only(group, rug, rug_mat, Vector3(0, 0.005, 0), Vector3.ZERO, "Rug")

	var plank = _box(0.5, 0.03, 0.15)
	_add_mesh_only(group, plank, plank_mat, Vector3(0.15, 0.02, 0.05), Vector3.ZERO, "LoosePlank")

	var anchor = Spatial.new()
	anchor.name = "FloorboardsHideAnchor"
	anchor.translation = Vector3(0, 0.05, 0)
	group.add_child(anchor)
	hiding_spot_anchors["hidingFloorboards"] = anchor

	_add_area(group, "hidingFloorboards", Vector3(1.0, 0.3, 0.7), Vector3(0, 0.15, 0), "FloorboardsArea")


func _build_cellar_hatch():
	var pos = Vector3(ROOM_HALF_X - 0.6, 0, ROOM_HALF_Z - 0.6)
	var panel_mat = _mat(Color(0.15, 0.13, 0.11), {"roughness": 0.8})
	var ring_mat = _mat(Color(0.25, 0.24, 0.23), {"metallic": 0.4, "roughness": 0.5})

	var group = Spatial.new()
	group.name = "CellarHatch"
	group.translation = pos
	add_child(group)

	var disc = CylinderMesh.new()
	disc.top_radius = 0.5
	disc.bottom_radius = 0.5
	disc.height = 0.04
	_add_mesh_only(group, disc, panel_mat, Vector3(0, 0.02, 0), Vector3.ZERO, "HatchPanel")

	# Godot 3.5 has no TorusMesh primitive; a small flush cylinder stands in
	# for the recessed pull-ring handle.
	var ring = CylinderMesh.new()
	ring.top_radius = 0.06
	ring.bottom_radius = 0.05
	ring.height = 0.02
	_add_mesh_only(group, ring, ring_mat, Vector3(0, 0.045, 0), Vector3.ZERO, "RingHandle")

	var anchor = Spatial.new()
	anchor.name = "CellarHatchHideAnchor"
	anchor.translation = Vector3(0, 0.02, 0)
	group.add_child(anchor)
	hiding_spot_anchors["hidingCellarHatch"] = anchor

	_add_area(group, "hidingCellarHatch", Vector3(1.0, 0.2, 1.0), Vector3(0, 0.1, 0), "CellarHatchArea")


# ---------------------------------------------------------------------------
# Wall drawing
# ---------------------------------------------------------------------------
#
# Rendered as a small procedural Image/ImageTexture rather than primitive
# meshes, in the visual language of traditional Jewish papercutting
# (mizrach / ketubah papercut): a symmetric silhouette composition — a
# pomegranate tree over a small house, with a bird mirrored on either side.
# Simple enough to still read as a child's own hand, but built on the
# bilateral symmetry that tradition favours rather than a random scribble.

func _build_wall_drawing():
	var group = Spatial.new()
	group.name = "WallDrawingVisual"
	# The east wall's inner (room-facing) surface sits at ROOM_HALF_X - WALL_THICK / 2
	# (= 2.925); the paper is placed just proud of it so it isn't embedded in
	# — and occluded by — the wall's own opaque collision box.
	group.translation = Vector3(ROOM_HALF_X - 0.1, 1.3, -0.4)
	group.rotation_degrees = Vector3(0, 0, 90)
	add_child(group)

	var paper_mat = _mat(Color(0.85, 0.8, 0.68), {"roughness": 0.95, "emissive": true, "emission_color": CANDLE_AMBER, "emission_energy": 0.08})
	paper_mat.albedo_texture = _build_papercut_tree_texture(128)
	var paper = PlaneMesh.new()
	paper.size = Vector2(0.35, 0.45)
	_add_mesh_only(group, paper, paper_mat, Vector3.ZERO, Vector3.ZERO, "Paper")

	evidence_nodes["wallDrawing"] = group

	_add_area(self, "wallDrawing", Vector3(0.4, 0.5, 0.15), group.translation, "WallDrawingArea")


# ---------------------------------------------------------------------------
# Mizrach-style papercut (small, non-interactive devotional object)
# ---------------------------------------------------------------------------
#
# A modest framed paper-cutting near the west wall — a home devotional piece
# in the same warm-paper aesthetic as the wall drawing, understated and not
# a focal point. Purely decorative: no interactable Area, no gameplay hook.

func _build_mizrach_papercut():
	var group = Spatial.new()
	group.name = "MizrachPapercut"
	# Same wall-embedding consideration as the wall drawing: keep the frame
	# just proud of the west wall's inner face (-ROOM_HALF_X + WALL_THICK / 2).
	group.translation = Vector3(-ROOM_HALF_X + 0.1, 1.55, -0.85)
	group.rotation_degrees = Vector3(0, 0, -90)
	add_child(group)

	# Local Y is the wall-normal (depth) axis once the group's rotation is
	# applied. Keep the frame's outer face and the paper plane clearly
	# separated along it so the frame box doesn't occlude the paper.
	var frame_mat = _mat(SLATE * 0.6, {"roughness": 0.8})
	_add_mesh_only(group, _box(0.15, 0.02, 0.15), frame_mat, Vector3(0, -0.01, 0), Vector3.ZERO, "Frame")

	var paper_mat = _mat(Color(0.85, 0.8, 0.68), {"roughness": 0.95})
	paper_mat.albedo_texture = _build_papercut_star_texture(64)
	var paper = PlaneMesh.new()
	paper.size = Vector2(0.11, 0.11)
	_add_mesh_only(group, paper, paper_mat, Vector3(0, 0.01, 0), Vector3.ZERO, "Paper")


# ---------------------------------------------------------------------------
# Papercut texture generation — small procedural Images, no external assets.
# ---------------------------------------------------------------------------

func _build_papercut_tree_texture(size: int) -> ImageTexture:
	var img = Image.new()
	img.create(size, size, false, Image.FORMAT_RGBA8)
	img.lock()

	var paper = Color(0.85, 0.8, 0.68)
	var ink = COAL_BLACK
	var fruit = CANDLE_AMBER

	_pc_fill_rect(img, 0, 0, size - 1, size - 1, size, paper)

	var s = float(size) / 128.0
	var cx = size / 2

	# Ground line.
	_pc_fill_rect(img, int(14 * s), int(99 * s), size - 1 - int(14 * s), int(100 * s), size, ink)

	# House: a solid base block under a peaked roof, both symmetric about the
	# vertical centreline, with a sliver of paper left showing as the door.
	var base_top = int(78 * s)
	var base_bot = int(99 * s)
	_pc_fill_rect(img, cx - int(20 * s), base_top, cx + int(20 * s), base_bot, size, ink)

	var apex_y = int(55 * s)
	_pc_fill_triangle(img, Vector2(cx, apex_y), Vector2(cx - int(24 * s), base_top), Vector2(cx + int(24 * s), base_top), size, ink)

	_pc_fill_rect(img, cx - int(4 * s), base_top + int(9 * s), cx + int(4 * s), base_bot, size, paper)

	# Trunk rising from the roof apex into the canopy.
	_pc_fill_rect(img, cx - int(3 * s), int(30 * s), cx + int(3 * s), apex_y + int(4 * s), size, ink)

	# Canopy, with small warm pomegranates set symmetrically within it.
	var canopy_cy = int(26 * s)
	var canopy_r = int(22 * s)
	_pc_fill_circle(img, cx, canopy_cy, canopy_r, size, ink)

	var fruit_r = max(1, int(3 * s))
	var offsets = [Vector2(0, -8), Vector2(-12, 2), Vector2(12, 2), Vector2(-8, 13), Vector2(8, 13)]
	for o in offsets:
		_pc_fill_circle(img, cx + int(o.x * s), canopy_cy + int(o.y * s), fruit_r, size, fruit)

	# A small bird mirrored on either side of the tree.
	_pc_draw_bird(img, cx - int(34 * s), canopy_cy + int(8 * s), s, size, ink)
	_pc_draw_bird(img, cx + int(34 * s), canopy_cy + int(8 * s), s, size, ink)

	img.unlock()

	# The pinned-paper PlaneMesh maps its local X to world-vertical and its
	# local Z to world-horizontal once the wall group's rotation is applied,
	# which is transposed from the (horizontal-x, vertical-y) space the
	# drawing above was composed in — so transpose the pixels to compensate.
	img = _pc_transpose(img, size)

	var tex = ImageTexture.new()
	tex.create_from_image(img, Texture.FLAG_FILTER)
	return tex


func _build_papercut_star_texture(size: int) -> ImageTexture:
	var img = Image.new()
	img.create(size, size, false, Image.FORMAT_RGBA8)
	img.lock()

	var paper = Color(0.85, 0.8, 0.68)
	var ink = COAL_BLACK
	var spark = CANDLE_AMBER

	_pc_fill_rect(img, 0, 0, size - 1, size - 1, size, paper)

	var cx = size / 2
	var cy = size / 2
	var r = float(size) * 0.34

	var up_pts = _pc_star_points(cx, cy, r, -90.0)
	var down_pts = _pc_star_points(cx, cy, r, -30.0)
	_pc_fill_triangle(img, up_pts[0], up_pts[1], up_pts[2], size, ink)
	_pc_fill_triangle(img, down_pts[0], down_pts[1], down_pts[2], size, ink)

	_pc_fill_circle(img, cx, cy, max(1, int(size * 0.035)), size, spark)

	img.unlock()

	img = _pc_transpose(img, size)

	var tex = ImageTexture.new()
	tex.create_from_image(img, Texture.FLAG_FILTER)
	return tex


func _pc_transpose(img: Image, size: int) -> Image:
	# Transposed (so the drawing's horizontal/vertical composition axes land
	# on the correct world axes once the wall group's rotation is applied)
	# and flipped along the way, so "up" in the drawing (small source y,
	# e.g. the canopy) ends up above "down" (large source y, e.g. the
	# ground line) in the rendered result rather than inverted.
	var out = Image.new()
	out.create(size, size, false, Image.FORMAT_RGBA8)
	img.lock()
	out.lock()
	for y in range(size):
		for x in range(size):
			out.set_pixel(x, y, img.get_pixel(y, size - 1 - x))
	out.unlock()
	img.unlock()
	return out


func _pc_star_points(cx: int, cy: int, r: float, start_deg: float) -> Array:
	var pts = []
	for i in range(3):
		var a = deg2rad(start_deg + i * 120.0)
		pts.append(Vector2(cx + r * cos(a), cy + r * sin(a)))
	return pts


func _pc_draw_bird(img: Image, x: int, y: int, s: float, size: int, color: Color) -> void:
	# A simple two-stroke "seagull" mark, the way a child sketches a bird.
	_pc_fill_triangle(img, Vector2(x - int(10 * s), y), Vector2(x, y - int(6 * s)), Vector2(x - int(1 * s), y + int(1 * s)), size, color)
	_pc_fill_triangle(img, Vector2(x + int(10 * s), y), Vector2(x, y - int(6 * s)), Vector2(x + int(1 * s), y + int(1 * s)), size, color)


func _pc_set_px(img: Image, x: int, y: int, size: int, color: Color) -> void:
	if x < 0 or y < 0 or x >= size or y >= size:
		return
	img.set_pixel(x, y, color)


func _pc_fill_circle(img: Image, cx: int, cy: int, r: int, size: int, color: Color) -> void:
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			var dx = x - cx
			var dy = y - cy
			if dx * dx + dy * dy <= r * r:
				_pc_set_px(img, x, y, size, color)


func _pc_fill_rect(img: Image, x0: int, y0: int, x1: int, y1: int, size: int, color: Color) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			_pc_set_px(img, x, y, size, color)


func _pc_fill_triangle(img: Image, p0: Vector2, p1: Vector2, p2: Vector2, size: int, color: Color) -> void:
	var min_x = int(min(p0.x, min(p1.x, p2.x)))
	var max_x = int(max(p0.x, max(p1.x, p2.x)))
	var min_y = int(min(p0.y, min(p1.y, p2.y)))
	var max_y = int(max(p0.y, max(p1.y, p2.y)))
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			if _pc_point_in_triangle(Vector2(x + 0.5, y + 0.5), p0, p1, p2):
				_pc_set_px(img, x, y, size, color)


func _pc_tri_sign(p1: Vector2, p2: Vector2, p3: Vector2) -> float:
	return (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y)


func _pc_point_in_triangle(pt: Vector2, v1: Vector2, v2: Vector2, v3: Vector2) -> bool:
	var d1 = _pc_tri_sign(pt, v1, v2)
	var d2 = _pc_tri_sign(pt, v2, v3)
	var d3 = _pc_tri_sign(pt, v3, v1)
	var has_neg = (d1 < 0) or (d2 < 0) or (d3 < 0)
	var has_pos = (d1 > 0) or (d2 > 0) or (d3 > 0)
	return not (has_neg and has_pos)


# ---------------------------------------------------------------------------
# Dust motes
# ---------------------------------------------------------------------------

func _build_dust_motes():
	var particles = Particles.new()
	particles.name = "DustMotes"
	particles.translation = Vector3(table_pos.x - 0.15, table_top_world_y + 0.35, table_pos.z)
	particles.amount = 10
	particles.lifetime = 7.0
	particles.emitting = true
	particles.one_shot = false
	particles.explosiveness = 0.0
	particles.randomness = 0.6
	particles.visibility_aabb = AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))

	var pm = ParticlesMaterial.new()
	pm.emission_shape = ParticlesMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.3
	pm.gravity = Vector3(0, 0.03, 0)
	pm.initial_velocity = 0.03
	pm.initial_velocity_random = 0.6
	pm.angular_velocity = 4.0
	pm.angular_velocity_random = 1.0
	pm.scale = 0.5
	pm.scale_random = 0.5
	pm.color = Color(CANDLE_AMBER.r, CANDLE_AMBER.g, CANDLE_AMBER.b, 0.5)
	particles.process_material = pm

	var mote_mat = _mat(CANDLE_AMBER, {"unshaded": true, "transparent": true, "alpha": 0.4, "emissive": true, "emission_color": CANDLE_AMBER, "emission_energy": 1.0, "billboard": true})
	var quad = QuadMesh.new()
	quad.size = Vector2(0.02, 0.02)
	quad.material = mote_mat
	particles.draw_pass_1 = quad

	add_child(particles)
