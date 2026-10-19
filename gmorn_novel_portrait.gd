extends TextureRect

## 立ち絵1枚。キャラIDごとに1つ。絵の中心を正規化座標 (x, y) に置く。
## 左右2枠へ振り分けない。x=0.5 が右へ寄り、3人目が出せなくなる。
## y は元版（Unity）が上が正なので 1-y で読み替える。
##
## 位置と明るさは目標へ毎こま寄る。移動の補間中は寄せを止め、補間が置いた位置を使う。
## 濃さ（アルファ）は淡入の Tween だけが書く。

@export var canvas_size := Vector2(1920.0, 1080.0)
## 元版の値（上が正）を Godot の向きへ直してある。
const FOCUS_Y_OFFSET := -20.0
const UNFOCUS_Y_OFFSET := 10.0
const UNFOCUS_TONE := 0.55
const LERP_SPEED := 12.0

## 表示名から独立させ、表示名の変更で立ち絵の同一性を失わない。
var character_id := ""
var normalized := Vector2.ZERO
## 話者の上下を含まない中心（px）。
var base_center := Vector2.ZERO
var focused := true
var target_center := Vector2.ZERO
var target_tone := 1.0
var fade_tween: Tween
var move_tween: Tween

func setup(name_in: String, texture_in: Texture2D, scale_in: float) -> void:
	character_id = name_in
	texture = texture_in
	if texture_in != null:
		size = texture_in.get_size() * scale_in
	# 大きさが変わっても中心を動かさない。
	_place(target_center)

## 色も濃さも入れ直す。暗くされていた人物を出し直すとき、暗さを引き継ぐと次の文章まで
## ずっと暗いまま見える。
func show_at(x: float, y: float, duration: float) -> void:
	if move_tween != null and move_tween.is_valid():
		move_tween.kill()
	normalized = Vector2(x, y)
	base_center = _to_center(x, y)
	focused = true
	_apply_focus()
	_place(target_center)
	visible = true
	if fade_tween != null and fade_tween.is_valid():
		fade_tween.kill()
	if duration <= 0.0:
		modulate = Color(1.0, 1.0, 1.0, 1.0)
		return
	modulate = Color(1.0, 1.0, 1.0, 0.0)
	fade_tween = create_tween()
	fade_tween.tween_property(self, "modulate:a", 1.0, duration)

## 台本の待機は呼び出し側の stage が受け持つ。
func move_to(x: float, y: float, duration: float) -> void:
	if move_tween != null and move_tween.is_valid():
		move_tween.kill()
	normalized = Vector2(x, y)
	var end_center := _to_center(x, y)
	if duration <= 0.0:
		_set_base_center(end_center)
		return
	move_tween = create_tween()
	move_tween.tween_method(_set_base_center, base_center, end_center, duration)

## 目標だけ変え、寄せは `_process` が行う。
func set_focused(value: bool) -> void:
	focused = value
	_apply_focus()

## `all_hide` が濃さを別の Tween で書くとき、淡入と取り合わないようにする。
func stop_fade() -> void:
	if fade_tween != null and fade_tween.is_valid():
		fade_tween.kill()

func moving() -> bool:
	return move_tween != null and move_tween.is_valid() and move_tween.is_running()

func fading() -> bool:
	return fade_tween != null and fade_tween.is_valid() and fade_tween.is_running()

func center() -> Vector2:
	return position + size * 0.5

func _process(delta: float) -> void:
	if not visible:
		return
	var t := 1.0 - exp(-LERP_SPEED * delta)
	if not moving():
		_place(center().lerp(target_center, t))
	var tone := lerpf(modulate.r, target_tone, t)
	# 濃さは淡入の Tween が書く。ここで触ると出かけた立ち絵が一瞬で出来上がる。
	modulate = Color(tone, tone, tone, modulate.a)

func _set_base_center(value: Vector2) -> void:
	base_center = value
	_apply_focus()
	_place(target_center)

func _apply_focus() -> void:
	target_center = base_center + Vector2(0.0, FOCUS_Y_OFFSET if focused else UNFOCUS_Y_OFFSET)
	target_tone = 1.0 if focused else UNFOCUS_TONE

func _place(center_position: Vector2) -> void:
	position = center_position - size * 0.5

## y は元版が上が正なので 1-y。
func _to_center(x: float, y: float) -> Vector2:
	return Vector2(canvas_size.x * x, canvas_size.y * (1.0 - y))
