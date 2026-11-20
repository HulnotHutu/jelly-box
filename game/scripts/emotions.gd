class_name JellyEmotions
extends Node

# 表现层：颜文字表情内容（胶囊笔画 / 圆环 / 泪珠）
# 笔画挂到资产导出的 EyeSocket 锚点上，并藏起资产自带的默认眼睛

var ink: StandardMaterial3D
var model: Node3D
var anchors := {}          # "L"/"R" -> 模型根空间下的锚点位置
var current := ""
var built: Array = []

func setup(model_node: Node3D, ink_mat: StandardMaterial3D) -> void:
	model = model_node
	ink = ink_mat
	for c in model.find_children("EyeStroke*", "MeshInstance3D", true, false):
		c.visible = false                    # 资产自带眼睛交给表情模块接管
	for n in model.find_children("EyeSocket*", "Node3D", true, false):
		var np: Node3D = n
		# 锚点全局位置换算到模型根空间（Godot 会清理节点名里的 "."，按 x 正负分左右）
		var local := model.global_transform.affine_inverse() * np.global_position
		anchors["L" if np.position.x < 0.0 else "R"] = local
	set_emo("happy")

func _clear() -> void:
	for n in built:
		if is_instance_valid(n):
			n.queue_free()
	built.clear()

func _stroke(anchor: String, p1: Vector2, p2: Vector2) -> void:
	var base: Vector3 = anchors.get(anchor, Vector3.ZERO)
	var cap := CapsuleMesh.new()
	cap.radius = 0.032
	cap.height = maxf((p2 - p1).length() + 0.064, 0.08)
	var mi := MeshInstance3D.new()
	mi.mesh = cap
	mi.material_override = ink
	mi.position = base + Vector3((p1.x + p2.x) * 0.5, (p1.y + p2.y) * 0.5, 0.02)
	mi.rotation.z = atan2(p2.y - p1.y, p2.x - p1.x) - PI / 2.0
	model.add_child(mi)
	built.append(mi)

func _ring(anchor: String) -> void:
	var base: Vector3 = anchors.get(anchor, Vector3.ZERO)
	var tor := TorusMesh.new()
	tor.inner_radius = 0.055
	tor.outer_radius = 0.09
	var mi := MeshInstance3D.new()
	mi.mesh = tor
	mi.material_override = ink
	mi.position = base + Vector3(0, 0, 0.01)
	mi.rotation.x = PI / 2.0
	model.add_child(mi)
	built.append(mi)

func _tear(anchor: String) -> void:
	var base: Vector3 = anchors.get(anchor, Vector3.ZERO)
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(0.75, 0.92, 1.0, 0.9)
	tm.roughness = 0.1
	tm.clearcoat_enabled = true
	tm.clearcoat = 1.0
	var s := SphereMesh.new()
	s.radius = 0.028
	s.height = 0.056
	var mi := MeshInstance3D.new()
	mi.mesh = s
	mi.material_override = tm
	mi.position = base + Vector3(0, -0.115, 0.01)
	model.add_child(mi)
	built.append(mi)

func set_emo(emo: String) -> void:
	if emo == current:
		return
	current = emo
	_clear()
	var th := deg_to_rad(35.0)
	if emo == "strain":                    # > <  顶点朝内
		_stroke("L", Vector2(0.06, 0.0), Vector2(-0.075, 0.086))
		_stroke("L", Vector2(0.06, 0.0), Vector2(-0.075, -0.086))
		_stroke("R", Vector2(-0.06, 0.0), Vector2(0.075, 0.086))
		_stroke("R", Vector2(-0.06, 0.0), Vector2(0.075, -0.086))
	elif emo == "cry":                     # T T  委屈 + 泪珠
		for side in ["L", "R"]:
			_stroke(side, Vector2(-0.06, 0.05), Vector2(0.06, 0.05))
			_stroke(side, Vector2(0.0, 0.05), Vector2(0.0, -0.06))
			_tear(side)
	elif emo == "happy":                   # ^ ^  开心弧
		for side in ["L", "R"]:
			var prev := Vector2(-0.07, -0.02)
			for k in 3:
				var a := deg_to_rad(160.0 - 46.6 * float(k + 1))
				var nxt := Vector2(cos(a) * 0.075, -0.02 + sin(a) * 0.075)
				_stroke(side, prev, nxt)
				prev = nxt
	elif emo == "shock":                   # O O  惊讶圆环
		_ring("L")
		_ring("R")
	elif emo == "blink":                   # - -  眨眼
		for side in ["L", "R"]:
			_stroke(side, Vector2(-0.05, 0.0), Vector2(0.05, 0.0))
