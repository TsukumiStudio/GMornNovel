extends RefCounted

const NovelPortrait := preload("gmorn_novel_portrait.gd")
const SHORTS_PHONE_HIDDEN_OFFSET_Y := 1080.0
var host: Control
const SHORTS_TRANSITION_DURATION := 0.28
var shorts_tween: Tween

func _shorts_track() -> Control:
	var track := host.novel_shorts.get_node_or_null("Screen/Track") as Control
	if track != null:
		return track
	return host.novel_shorts.get_node_or_null("Track") as Control


func _init(main: Control) -> void:
	host = main

## `foreground` の小道具は発話者の前面並べ替えより手前に固定する。
func _load_novel_character(character_name: String, path: String, scale: float, foreground := false) -> void:
	host.novel_characters[character_name] = {"path": path, "scale": scale}
	var texture := _load_novel_resource(path, "立ち絵（%s）" % character_name) as Texture2D
	var portrait := _novel_portrait_for(character_name)
	portrait.z_index = 1 if foreground else 0
	portrait.setup(character_name, texture, scale)

## 無い素材は warning だけで null を返し、台本は止めない。`load()` に無い道を渡すと
## エンジンの ERROR が出る。
func _load_novel_resource(path: String, what: String) -> Resource:
	if not ResourceLoader.exists(path):
		push_warning("ノベル: %sが読めない（%s）" % [what, path])
		return null
	return load(path)

func _novel_portrait_for(character_name: String) -> NovelPortrait:
	if host.novel_portraits.has(character_name):
		return host.novel_portraits[character_name]
	var portrait := host.portrait_scene.instantiate() as NovelPortrait
	portrait.name = ("Portrait_" + character_name).validate_node_name()
	portrait.visible = false
	host.novel_portrait_host.add_child(portrait)
	host.novel_portraits[character_name] = portrait
	return portrait

## `queue_free()` だけだと同じこまの中では子として残り、同じ名前の作り直しが黙って
## 別名にされる。外してから捨てる。
func _clear_novel_portraits() -> void:
	host.novel_portraits.clear()
	if not is_instance_valid(host.novel_portrait_host):
		return
	for child: Node in host.novel_portrait_host.get_children():
		host.novel_portrait_host.remove_child(child)
		child.queue_free()

func _clear_novel_shorts() -> void:
	var track := _shorts_track()
	if track == null:
		(host.novel_shorts as TextureRect).texture = null
		host.novel_shorts.scale = Vector2.ONE
		host.novel_shorts.visible = false
		return
	if shorts_tween != null and shorts_tween.is_valid():
		shorts_tween.kill()
	track = _shorts_track()
	var current := track.get_node("Current") as TextureRect
	var next := track.get_node("Next") as TextureRect
	current.texture = null
	next.texture = null
	track.position = Vector2.ZERO
	track.scale = Vector2.ONE
	host.novel_shorts.position.y = 0.0
	host.novel_shorts.visible = false

func _show_novel_shorts(path: String) -> void:
	var texture := _load_novel_resource(path, "ショート動画") as Texture2D
	if texture == null:
		return
	var track := _shorts_track()
	if track == null:
		(host.novel_shorts as TextureRect).texture = texture
		host.novel_shorts.scale = Vector2.ONE
		host.novel_shorts.visible = true
		host._mark_initial_visual_ready()
		return
	var current := track.get_node("Current") as TextureRect
	var next := track.get_node("Next") as TextureRect
	if shorts_tween != null and shorts_tween.is_valid():
		shorts_tween.kill()
	track.scale = Vector2.ONE
	if current.texture == null:
		current.texture = texture
		next.texture = null
		track.position = Vector2.ZERO
		host.novel_shorts.position.y = SHORTS_PHONE_HIDDEN_OFFSET_Y
		host.novel_shorts.visible = true
		shorts_tween = host.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		shorts_tween.tween_property(host.novel_shorts, "position:y", 0.0, SHORTS_TRANSITION_DURATION)
	else:
		next.texture = texture
		next.position.y = track.size.y
		host.novel_shorts.visible = true
		shorts_tween = host.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		shorts_tween.set_parallel(true)
		shorts_tween.tween_property(current, "position:y", -track.size.y, SHORTS_TRANSITION_DURATION)
		shorts_tween.tween_property(next, "position:y", 0.0, SHORTS_TRANSITION_DURATION)
		shorts_tween.chain().tween_callback(func() -> void:
			current.texture = next.texture
			current.position = Vector2.ZERO
			next.texture = null
			next.position = Vector2.ZERO
		)
	host._mark_initial_visual_ready()

func _zoom_novel_shorts(scale: float) -> void:
	var track := _shorts_track()
	if track == null:
		host.novel_shorts.scale = Vector2.ONE * scale
		return
	track.scale = Vector2.ONE * scale

func _hide_novel_shorts() -> void:
	var track := _shorts_track()
	if track == null:
		host.novel_shorts.visible = false
		return
	if shorts_tween != null and shorts_tween.is_valid():
		shorts_tween.kill()
	shorts_tween = host.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	shorts_tween.tween_property(host.novel_shorts, "position:y", SHORTS_PHONE_HIDDEN_OFFSET_Y, SHORTS_TRANSITION_DURATION)
	shorts_tween.tween_callback(func() -> void:
		host.novel_shorts.visible = false
		track.position = Vector2.ZERO
		track.scale = Vector2.ONE
		host.novel_shorts.position.y = 0.0
	)

## 黒幕は `background()` では覆えない会話枠まで隠す。
func _begin_novel_blackout() -> void:
	for portrait: NovelPortrait in host.novel_portraits.values():
		portrait.visible = false
	host.novel_background.visible = false
	host.novel_background_next.visible = false
	host.novel_dialogue_panel.visible = false
	host.novel_dialogue_intentionally_hidden = true
	_clear_novel_shorts()
	if host.novel_blackout != null:
		host.novel_blackout.visible = true

func _show_novel_logo(path: String) -> void:
	if host.novel_logo == null:
		push_warning("ノベル: ロゴ表示ノードが無い")
		return
	var texture := _load_novel_resource(path, "ロゴ") as Texture2D
	if texture == null:
		return
	host.novel_logo.texture = texture
	host.novel_logo.visible = true

func _hide_novel_logo() -> void:
	if host.novel_logo != null:
		host.novel_logo.visible = false

func _clear_novel_outro() -> void:
	if host.novel_blackout != null:
		host.novel_blackout.visible = false
	_hide_novel_logo()

## 別の人物を完全に同じ座標へ出す場合だけ、先に居た人物を隠して入れ替える。
## 近接した座標は別の立ち位置として併存する。
func _show_novel_character(character_name: String, position_x: float, position_y: float, duration: float) -> void:
	if not host.novel_portraits.has(character_name):
		push_warning("ノベル: 読み込んでいない立ち絵を出そうとした（%s）" % character_name)
		return
	var portrait: NovelPortrait = host.novel_portraits[character_name]
	if portrait.texture == null:
		push_warning("ノベル: 絵の無い立ち絵を出そうとした（%s）" % character_name)
		return
	var spot := Vector2(position_x, position_y)
	for other: NovelPortrait in host.novel_portraits.values():
		if other != portrait and other.visible and other.normalized == spot:
			other.visible = false
	portrait.show_at(position_x, position_y, duration)

## 移動が終わるまで台本を待たせる（`chara_show` の淡入は待たない）。
func _begin_novel_character_move(character_name: String, position_x: float, position_y: float, duration: float) -> bool:
	if not host.novel_portraits.has(character_name):
		push_warning("ノベル: 読み込んでいない立ち絵を動かそうとした（%s）" % character_name)
		return false
	var portrait := host.novel_portraits[character_name] as NovelPortrait
	portrait.move_to(position_x, position_y, duration)
	if duration <= 0.0:
		return false
	host.novel_player._wait_for_novel_tween(portrait.move_tween)
	return true

func _hide_novel_character(character_name: String) -> void:
	if host.novel_portraits.has(character_name):
		(host.novel_portraits[character_name] as NovelPortrait).visible = false

## 目標だけ変え、寄せは立ち絵の `_process` に任せる。濃さ（アルファ）は触らない。
## 淡入の途中で同じ人物が話し始める並びが多く、ここで書くと淡入が消える。
func _focus_novel_speaker(character_name: String) -> void:
	for portrait: NovelPortrait in host.novel_portraits.values():
		portrait.set_focused(character_name.is_empty() or portrait.character_id == character_name)
	if character_name.is_empty() or not host.novel_portraits.has(character_name):
		return
	var speaker: NovelPortrait = host.novel_portraits[character_name]
	if speaker.visible and is_instance_valid(host.novel_portrait_host):
		host.novel_portrait_host.move_child(speaker, host.novel_portrait_host.get_child_count() - 1)

## 前の絵を残したまま上に次の絵を淡く出す。1枚を透明にしてから淡入すると、
## 差し替えの瞬間に下の画面が透ける。淡入後は1枚目へ写し、役は入れ替えない。
func _begin_novel_background(path: String, duration: float) -> bool:
	var texture := _load_novel_resource(path, "背景") as Texture2D
	if texture == null:
		return false
	if duration <= 0.0:
		_settle_novel_background(texture)
		return false
	# 同じ半透明背景を重ねると途中だけ二重に暗くなり、確定時に明るさが跳ねる。
	# 待機時間だけ保つ。
	if host.novel_background.visible and host.novel_background.texture == texture \
			and is_equal_approx(host.novel_background.modulate.a, 1.0):
		host.novel_player._wait_for_novel_seconds(duration)
		return true
	host.novel_background_next.texture = texture
	host.novel_background_next.modulate.a = 0.0
	host.novel_background_next.visible = true
	var tween := host.create_tween()
	tween.tween_property(host.novel_background_next, "modulate:a", 1.0, duration)
	host.novel_player._wait_for_novel_tween(tween, _settle_novel_background.bind(texture))
	return true

func _settle_novel_background(texture: Texture2D) -> void:
	host.novel_background.texture = texture
	host.novel_background.visible = true
	host.novel_background.modulate.a = 1.0
	host.novel_background_next.visible = false
	host._mark_initial_visual_ready()

## 0 でも背景を伏せる（元版と同じ）。
func _begin_novel_all_hide(duration: float) -> bool:
	if duration <= 0.0:
		for portrait: NovelPortrait in host.novel_portraits.values():
			portrait.visible = false
		host.novel_background.visible = false
		host.novel_background_next.visible = false
		host.novel_dialogue_panel.visible = false
		host.novel_dialogue_intentionally_hidden = true
		return false
	var tween := host.create_tween().set_parallel(true)
	for portrait: NovelPortrait in host.novel_portraits.values():
		if portrait.visible:
			portrait.stop_fade()
			tween.tween_property(portrait, "modulate:a", 0.0, duration)
	tween.tween_property(host.novel_background, "modulate:a", 0.0, duration)
	if host.novel_background_next.visible:
		tween.tween_property(host.novel_background_next, "modulate:a", 0.0, duration)
	tween.tween_property(host.novel_dialogue_panel, "modulate:a", 0.0, duration)
	host.novel_player._wait_for_novel_tween(tween, _begin_novel_all_hide.bind(0.0))
	return true

## 文字も空にする（元版と同じ）。
func _show_novel_bubble() -> void:
	host.novel_dialogue_panel.visible = true
	host.novel_dialogue_panel.modulate.a = 1.0
	host.novel_dialogue_intentionally_hidden = false
	host.novel_speaker.text = ""
	host.novel_message.text = ""

func _hide_novel_bubble() -> void:
	host.novel_dialogue_panel.visible = false
	host.novel_speaker.text = ""
	host.novel_message.text = ""
