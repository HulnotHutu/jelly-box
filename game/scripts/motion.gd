class_name JellyMotion
extends RefCounted

# 动作层 v7：全部参数开放为可调变量（调参台滑块实时直连）
# 形变的样子由资产 Shape Keys 承载；本层输出权重与缩放

signal state_changed(s: int)

enum S { IDLE, ANTICIPATE, RISE, FALL, LAND, RECOVER }

# ---- 可调参数（默认值 = "正常"定版：呼吸 0.04 / 漫游 0.3）----
var intensity := 1.0        # 全局强度：缩放所有偏离原形的分量
var jump_vy := 4.0          # 跳跃力度
var squash_land := 0.12     # 落地砸扁深度
var bulge_land := 0.10      # 落地左右鼓出
var squash_antic := 0.07    # 蓄力压扁深度
var stretch_gain := 0.12    # 拉伸权重倍率（轻探即可，避免吓人）
var bend_gain := 0.35       # 弯曲权重倍率
var wobble_kick := 0.08     # 落地甩动幅度
var wobble_decay := 1.2     # 甩动衰减速度
var wander_amp := 0.30      # 漫游幅度
var breath_amp := 0.04      # 呼吸幅度
var recover_w := 0.05       # 回弹力度

var st: int = S.IDLE
var st_t := 0.0
var vy := 0.0
var h := 0.0
var vx := 0.0               # 虚拟游走速度：决定身体朝哪边弯，不移动位置
var wobble := 0.0
var bdir := 1.0
var jump_wait := 12.0        # 距下一次跳跃（稀有事件，闲逛才是常态）

# 闲逛小剧场
var routine := "none"             # 当前小剧场：none / stretch / sway / shake
var routine_t := 0.0
var routine_wait := 3.0
var routine_emo := "happy"
const ROUTINES := ["stretch", "sway", "shake"]
const ROUTINE_DUR := {"stretch": 1.6, "sway": 1.4, "shake": 1.0}
const ROUTINE_EMO := {"stretch": "happy", "sway": "blink", "shake": "strain"}

func advance(delta: float, gt: float) -> Dictionary:
	st_t += delta
	var sy := 1.0
	var sxz := 1.0
	var stretch := 0.0
	var bend := 0.0
	var wander_vx := wander_amp * (0.30 * sin(gt * 0.9 + 1.7) + 0.15 * sin(gt * 0.41 + 4.0))
	wobble = maxf(0.0, wobble - wobble_decay * wobble * delta)
	var rock := wobble * sin(gt * 9.0)

	if st == S.IDLE:
		vx = wander_vx
		sy = 1.0 + breath_amp * sin(gt * 2.2)
		# 闲逛小剧场：伸懒腰 / 左右晃 / 摇摇头（期间抑制跳跃）
		if routine == "none":
			routine_wait -= delta
			if routine_wait <= 0.0:
				routine = ROUTINES[randi() % ROUTINES.size()]
				routine_t = 0.0
				routine_emo = ROUTINE_EMO[routine]
		else:
			routine_t += delta
		bend = clampf(absf(vx) / 0.35, 0.0, 1.0) * bend_gain * 0.8
		if absf(vx) > 0.01: bdir = signf(vx)
		# 小剧场的专属形变
		if routine == "stretch":
			var ks := clampf(routine_t / ROUTINE_DUR["stretch"], 0.0, 1.0)
			# 伸懒腰 = 倍率的 2 倍（仍柔和），并有上限保护
			stretch = maxf(stretch, sin(ks * PI) * minf(stretch_gain * 2.0, 0.6))
		elif routine == "sway":
			var s := sin(routine_t * 4.5)
			if absf(s) > 0.05: bdir = signf(s)
			bend = clampf(absf(s), 0.0, 1.0) * bend_gain       # 左右晃一晃
		elif routine == "shake":
			var sh := sin(routine_t * 8.0)
			if absf(sh) > 0.05: bdir = signf(sh)
			bend = clampf(absf(sh) * 0.9, 0.0, 1.0) * bend_gain   # 摇摇头
		# 小剧场结束 → 歇 2.5~5 秒再演下一段
		if routine != "none" and routine_t >= ROUTINE_DUR[routine]:
			routine = "none"
			routine_wait = 2.5 + randf() * 2.5
		# 跳跃：稀有时间事件（大部分时间闲着做形变）
		jump_wait -= delta
		if routine == "none" and jump_wait <= 0.0 and st_t > 0.3:
			jump_wait = 12.0 + randf() * 8.0
			_enter(S.ANTICIPATE)
	elif st == S.ANTICIPATE:
		var k := clampf(st_t / 0.16, 0.0, 1.0)
		sy = 1.0 - squash_antic * k
		sxz = 1.0 + squash_antic * 0.9 * k
		if absf(vx) > 0.01: bdir = signf(vx)
		bend = clampf(absf(vx) / 0.35, 0.0, 1.0) * bend_gain * 0.8
		if st_t >= 0.16:
			vy = jump_vy
			_enter(S.RISE)
	elif st == S.RISE:
		vy -= 11.0 * delta
		h += vy * delta
		stretch = clampf(vy / jump_vy, 0.0, 1.0) * stretch_gain
		if absf(vx) > 0.01: bdir = signf(vx)
		bend = clampf(absf(vx) / 0.35, 0.0, 1.0) * bend_gain * 0.7
		if vy <= 0.0: _enter(S.FALL)
	elif st == S.FALL:
		vy -= 11.0 * delta
		h += vy * delta
		stretch = clampf(absf(vy) / jump_vy, 0.0, 1.0) * stretch_gain * 0.9
		bend = clampf(absf(vx) / 0.35, 0.0, 1.0) * bend_gain * 0.7
		if h <= 0.0:
			h = 0.0
			wobble = wobble_kick
			_enter(S.LAND)
	elif st == S.LAND:
		var k := clampf(st_t / 0.12, 0.0, 1.0)
		sy = 1.0 - squash_land * (1.0 - k)
		sxz = 1.0 + bulge_land * (1.0 - k)
		if absf(rock) > 0.02: bdir = signf(rock)
		bend = clampf(absf(rock) / 0.30, 0.0, 1.0) * bend_gain
		if st_t >= 0.12: _enter(S.RECOVER)
	elif st == S.RECOVER:
		vx = lerpf(vx, wander_vx, 3.0 * delta)
		var k := clampf(st_t / 0.4, 0.0, 1.0)
		var w := sin(k * PI * 2.5) * (1.0 - k) * recover_w
		sy = 1.0 + w
		sxz = 1.0 - w * 0.7
		if absf(vx) > 0.01: bdir = signf(vx)
		bend = clampf(absf(vx) / 0.35, 0.0, 1.0) * bend_gain * 0.6
		if st_t >= 0.4: _enter(S.IDLE)                # 回弹结束 → 回到待机循环

	# 全局强度：缩放一切偏离原形的分量
	sy = 1.0 + (sy - 1.0) * intensity
	sxz = 1.0 + (sxz - 1.0) * intensity
	stretch = clampf(stretch * intensity, 0.0, 1.0)
	bend = clampf(bend * intensity, 0.0, 1.0)
	return {"h": h, "state": st, "sy": sy, "sxz": sxz, "stretch": stretch, "bend": bend, "bdir": bdir}

func _enter(s: int) -> void:
	st = s
	st_t = 0.0
	state_changed.emit(s)
