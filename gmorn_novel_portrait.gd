extends TextureRect

## ノベルの立ち絵1枚。キャラIDごとに1つ作る（`gmorn_novel_portrait.tscn`）。
##
## 元版（`MornLuaNovelPortraitView`）は話者名で初めて呼ばれた瞬間に Image を作り、
## 0〜1 の正規化座標で自由に置く。左右2枠へ振り分けていた頃は x=0.5 が右へ寄り、
## 3人目が出せなかった。
##
## **置き方は元版の `ShowAsync` と同じ。**絵の中心を (x, y) に置く。x は 0 が左端・
## 1 が右端、y は 0 が下端・1 が上端（元版は上が正）。Godot は下が正なので 1-y で
## 読み替える。大きさも元版の `Preload` と同じく、画像の原寸へ倍率を掛ける。
##
## **話者の上下。**話している人物は 20px 上がって白、それ以外は 10px 下がって 0.55 の
## 灰色になる（元版 `031_LuaNovel.unity` の `_focusYOffset` 20 / `_unfocusYOffset` -10 /
## `_unfocusColor` 0.55）。目標へは毎こま 1-exp(-12·dt) で寄る（`_lerpSpeed` 12）。
## 移動の補間中（`chara_move`）は寄せを止め、補間が置いた位置をそのまま使う。
## 濃さの淡入中も色の寄せは続ける。濃さ（アルファ）は淡入のTweenだけが書く。

@export var canvas_size := Vector2(1920.0, 1080.0)
## 話者が上がる量（px）。元版 `_focusYOffset` 20（上が正）を Godot の向きへ直した値。
const FOCUS_Y_OFFSET := -20.0
## 話者でない人物が下がる量（px）。元版 `_unfocusYOffset` -10。
const UNFOCUS_Y_OFFSET := 10.0
## 話者でない人物の明るさ。元版 `_unfocusColor` (0.55, 0.55, 0.55)。
const UNFOCUS_TONE := 0.55
## 目標へ寄る速さ。元版 `_lerpSpeed` 12。
const LERP_SPEED := 12.0

## 表示名から独立した識別子。表示名の変更で立ち絵の同一性を失わない。
var character_id := ""
## 台本が指定した正規化座標。
var normalized := Vector2.ZERO
## 正規化座標から決めた中心（px）。話者の上下は含まない。
var base_center := Vector2.ZERO
## 話しているか。上下と明るさの目標を決める。
var focused := true
## 上下を含めた中心の目標（px）。
var target_center := Vector2.ZERO
## 明るさの目標。
var target_tone := 1.0
var fade_tween: Tween
var move_tween: Tween

## 絵と倍率を入れる。`chara_load` のたびに呼ばれ、同じIDなら絵が入れ替わる。
func setup(name_in: String, texture_in: Texture2D, scale_in: float) -> void:
	character_id = name_in
	texture = texture_in
	if texture_in != null:
		size = texture_in.get_size() * scale_in
	# 大きさが変わっても中心は動かさない。
	_place(target_center)

## (x, y) を中心に出す。`duration` が 0 より大きければその秒数で淡入する。
##
## 色も濃さも入れ直す。前に暗くされていた人物を出し直すとき、暗さを引き継ぐと
## 出したあと文章までに止まる並びでその間ずっと暗いまま見える。
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

## (x, y) へ `duration` 秒かけて動く。0 なら即座に置く。
## 台本の待機は呼び出し側の `NovelStage` が受け持つ。
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

## 話しているかを教える。上下と明るさの目標だけを変え、寄せは `_process` が行う。
func set_focused(value: bool) -> void:
	focused = value
	_apply_focus()

## 淡入を打ち切る。`all_hide` が濃さを別のTweenで書くときに、取り合わないようにする。
func stop_fade() -> void:
	if fade_tween != null and fade_tween.is_valid():
		fade_tween.kill()

## 移動の補間中か。
func moving() -> bool:
	return move_tween != null and move_tween.is_valid() and move_tween.is_running()

## 淡入の途中か。
func fading() -> bool:
	return fade_tween != null and fade_tween.is_valid() and fade_tween.is_running()

## いまの中心（px）。
func center() -> Vector2:
	return position + size * 0.5

func _process(delta: float) -> void:
	if not visible:
		return
	var t := 1.0 - exp(-LERP_SPEED * delta)
	if not moving():
		_place(center().lerp(target_center, t))
	var tone := lerpf(modulate.r, target_tone, t)
	# 濃さは淡入のTweenが書く。ここで触ると出かけた立ち絵が一瞬で出来上がる。
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

## 正規化座標を画面の中心座標（px）へ。y は元版が上が正なので 1-y。
func _to_center(x: float, y: float) -> Vector2:
	return Vector2(canvas_size.x * x, canvas_size.y * (1.0 - y))
