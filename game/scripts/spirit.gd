extends Node3D

# 逻辑层：装配资产（.glb）、决策状态（何时跳/何表情）、路由表现模块
# 建模在 Blender（assets/jelly-box.glb），运动规律在 motion.gd，表情内容在 emotions.gd

const DIR := "/home/hulut/note-space/godot-lab/dust-spirit/"
const IDLE_EMOS := ["happy", "cry", "shock", "blink"]

var gt := 0.0
var frame_i := 0
var shot_done := false
var shot_land := false
var pend_shot := -1
var pend_land := -1

var spirit: Node3D
var emo: JellyEmotions
var motion: JellyMotion
var puff: GPUParticles3D
var cam: Camera3D
var blob_shadow: MeshInstance3D
var world_env: WorldEnvironment
var rain_node: Node3D
var env_normal: Environment
var env_rain: Environment
var key_light: DirectionalLight3D
var soft_light: SpotLight3D
var floor_mat: StandardMaterial3D
var raining := true
var mesh_ref: MeshInstance3D = null
var blend_ids := {}

var cam_yaw := 0.5
var cam_dist := 3.3
var cam_h := 0.9
var cam_target := Vector3(0, 0.4, 0)
var dragging := false
var idle_i := 0

func _ready() -> void:
	# 资产层：实例化 Blender 导出的模型（自带眼睛与表情锚点）
	var packed := load("res://assets/jelly-box.glb")
	var model: Node3D = packed.instantiate()
	spirit = Node3D.new()
	spirit.name = "Spirit"
	spirit.add_child(model)
	add_child(spirit)

	# 缓存资产里的形变目标（Shape Keys → blend shapes）
	var mesh_ref: MeshInstance3D = null
	var blend_ids := {}
	for c in model.find_children("JellyBox*", "MeshInstance3D", true, false):
		mesh_ref = c
		break
	if mesh_ref != null and mesh_ref.mesh != null:
		for i in mesh_ref.mesh.get_blend_shape_count():
			blend_ids[mesh_ref.mesh.get_blend_shape_name(i)] = i
		# 材质修正：背面剔除方向改正（0=CULL_BACK）+ 次表面散射（实心软糖的体内透光）
		for si in mesh_ref.mesh.get_surface_count():
			var smat = mesh_ref.mesh.surface_get_material(si)
			if smat is BaseMaterial3D:
				smat.set("cull_mode", 0)                 # CULL_BACK：只渲染正面
				for p in ["subsurf_scattering_enabled", "subsurface_scattering_enabled"]:
					if p in smat:
						smat.set(p, true)
				for p in ["subsurf_scattering_strength", "subsurface_scattering_strength"]:
					if p in smat:
						smat.set(p, 0.5)
	print("blend shapes:", blend_ids.keys())
	self.mesh_ref = mesh_ref
	self.blend_ids = blend_ids

	# 表现层
	var ink := StandardMaterial3D.new()
	ink.albedo_color = Color(0.008, 0.008, 0.012, 1.0)
	ink.roughness = 0.6
	emo = JellyEmotions.new()
	emo.name = "Emotions"
	emo.setup(model, ink)
	add_child(emo)

	# 动作层
	motion = JellyMotion.new()
	motion.state_changed.connect(_on_state)

	# 布景补充：柔光箱 + 补光（需要 look_at 瞄准，其余布景在 main.tscn）
	var soft := SpotLight3D.new()
	soft.light_color = Color(1, 1, 1)
	soft.light_energy = 2.2
	soft.spot_range = 12.0
	soft.spot_angle = 42.0
	add_child(soft)
	soft.look_at_from_position(Vector3(1.2, 3.2, 3.4), Vector3(0, 0.5, 0), Vector3.UP)
	soft_light = soft

	var fill := OmniLight3D.new()
	fill.light_energy = 0.15
	fill.omni_range = 10.0
	add_child(fill)
	fill.position = Vector3(2.6, 1.6, 2.6)

	# 落地烟尘
	puff = GPUParticles3D.new()
	puff.amount = 16
	puff.lifetime = 0.55
	puff.one_shot = true
	puff.explosiveness = 1.0
	puff.position = Vector3(0, 0.06, 0)
	var pp := ParticleProcessMaterial.new()
	pp.direction = Vector3(0, 1, 0)
	pp.spread = 70.0
	pp.gravity = Vector3(0, -3.0, 0)
	pp.initial_velocity_min = 1.4
	pp.initial_velocity_max = 2.6
	pp.scale_min = 0.8
	pp.scale_max = 2.0
	puff.process_material = pp
	var puff_m := StandardMaterial3D.new()
	puff_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff_m.albedo_color = Color(1, 1, 1, 0.6)
	puff_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var puffmesh := SphereMesh.new()
	puffmesh.radius = 0.05
	puffmesh.height = 0.1
	puffmesh.radial_segments = 8
	puffmesh.rings = 4
	puff.draw_pass_1 = puffmesh
	puff.material_override = puff_m
	add_child(puff)

	# 假接地阴影：柔和暗斑（替代真实光影 → 半透明表面不再透出奇怪阴影）
	var blob := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.68
	sm.height = 0.05
	blob.mesh = sm
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.albedo_color = Color(0.15, 0.19, 0.26, 0.42)
	blob.material_override = bm
	blob.position = Vector3(0, 0.008, 0)
	add_child(blob)
	blob_shadow = blob

	# 天气系统：环境资源热切换 + 雨粒子（开局即为雨天）
	world_env = get_node("WorldEnv") as WorldEnvironment
	rain_node = get_node("Rain") as Node3D
	env_normal = load("res://assets/environment.tres")
	env_rain = load("res://assets/rain.tres")
	key_light = get_node("Key") as DirectionalLight3D
	floor_mat = get_node("Floor").material_override as StandardMaterial3D
	raining = true
	_apply_weather()

	cam = Camera3D.new()
	cam.fov = 42.0
	add_child(cam)
	_update_cam()

func _on_state(s: int) -> void:
	# 状态 → 表情路由 + 落地烟尘
	if s == JellyMotion.S.ANTICIPATE or s == JellyMotion.S.LAND:
		emo.set_emo("strain")
	elif s == JellyMotion.S.RISE or s == JellyMotion.S.FALL:
		emo.set_emo("shock")
	elif s == JellyMotion.S.IDLE:
		emo.set_emo(IDLE_EMOS[idle_i % IDLE_EMOS.size()])
		idle_i += 1
	if s == JellyMotion.S.LAND:
		puff.restart()
		if not shot_land:             # 抓拍落地砸扁（夸张档）
			shot_land = true
			emo.set_emo("strain")
			pend_land = 2

func _process(delta: float) -> void:
	gt += delta
	frame_i += 1
	var m := motion.advance(delta, gt)
	spirit.position = Vector3(0, m.h, 0)          # 原地运动：镜头永远固定
	spirit.scale = Vector3(m.sxz, m.sy, m.sxz)
	blob_shadow.scale = Vector3.ONE * maxf(1.0 - m.h * 0.35, 0.55)   # 跳高时影子缩小
	# 形变权重 → 资产内的 blend shapes（样子由 Blender 里的 Shape Keys 承载）
	if mesh_ref != null and mesh_ref.mesh != null:
		for nm in blend_ids:
			var w := 0.0
			if nm == "Stretch":
				w = m.stretch
			elif nm == "Bend.L":
				w = m.bend * (1.0 if m.bdir < 0 else 0.0)
			elif nm == "Bend.R":
				w = m.bend * (1.0 if m.bdir > 0 else 0.0)
			mesh_ref.set_blend_shape_value(blend_ids[nm], w)
	_update_cam()
	# 闲逛小剧场的表情路由（优先于状态表情）
	if motion.routine != "none":
		emo.set_emo(motion.routine_emo)

	# 验收抓拍（空中帧：拉伸 + 弯曲权重全开；相机不动）
	if frame_i >= 200 and not shot_done:
		shot_done = true
		if motion.routine == "none":
			emo.set_emo("shock")
		pend_shot = 2
	if pend_shot > 0:
		pend_shot -= 1
		if pend_shot == 0:
			_shot(DIR + "shot_front.png")
	if pend_land > 0:
		pend_land -= 1
		if pend_land == 0:
			_shot(DIR + "shot_land.png")

func _shot(path: String) -> void:
	get_viewport().get_texture().get_image().save_png(path)

func _update_cam() -> void:
	cam.position = cam_target + Vector3(sin(cam_yaw) * cam_dist, cam_h - cam_target.y, cos(cam_yaw) * cam_dist)
	cam.look_at(cam_target, Vector3.UP)

func _apply_weather() -> void:
	rain_node.visible = raining
	world_env.environment = env_rain if raining else env_normal
	key_light.light_energy = 0.9 if raining else 1.35
	soft_light.light_energy = 1.3 if raining else 2.2
	floor_mat.albedo_color = Color(0.42, 0.46, 0.55, 1) if raining else Color(0.92, 0.92, 0.93, 1)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_R:
		raining = not raining
		_apply_weather()
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_LEFT or e.button_index == MOUSE_BUTTON_RIGHT:
			dragging = e.pressed
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_dist = maxf(1.8, cam_dist - 0.35)
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_dist = minf(7.0, cam_dist + 0.35)
	elif e is InputEventMouseMotion and dragging:
		cam_yaw += e.relative.x * 0.008
		cam_h = clampf(cam_h + e.relative.y * 0.012, 0.4, 3.5)
