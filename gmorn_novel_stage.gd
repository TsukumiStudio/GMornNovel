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

## `foreground` の小道具は発話者の強調よりも手前に固定する。
func _load_novel_character(character_name: String, path: String, scale: float, foreground := false) -> void:
	host.novel_characters[character_name] = {"path": path, "scale": scale}
	var texture := _load_novel_resource(path, "立ち絵（%s）" % character_name) as Texture2D
	var portrait := _novel_portrait_for(character_name)
	portrait.z_index = 1 if foreground else 0
	portrait.setup(character_name, texture, scale)

## 台本が指す素材を読む。無ければ warning を残して null を返す。**台本は止めない。**
##
## `load()` に無い道を渡すとエンジンの ERROR が出る。元版にだけある素材（OP新版の
## 曲など）を指した台本でも、その行が抜けるだけで済むようにする。

func _load_novel_resource(path: String, what: String) -> Resource:
	if not ResourceLoader.exists(path):
		push_warning("ノベル: %sが読めない（%s）" % [what, path])
		return null
	return load(path)

## IDに対応する立ち絵。無ければ作って置き場の末尾へ足す。
##
## IDで初めて呼ばれた瞬間に Image を作る。話す人物は台詞ごとに最前面へ
## 並べ替えるので、重なった場合も話者が見える。

func _novel_portrait_for(character_name: String) -> NovelPortrait:
	if host.novel_portraits.has(character_name):
		return host.novel_portraits[character_name]
	var portrait := host.portrait_scene.instantiate() as NovelPortrait
	portrait.name = ("Portrait_" + character_name).validate_node_name()
	portrait.visible = false
	host.novel_portrait_host.add_child(portrait)
	host.novel_portraits[character_name] = portrait
	return portrait

## 前の物語の立ち絵を全部捨てる。名前が同じでも物語ごとに作り直す。
##
## `queue_free()` だけだと同じこまの中では子として残り、同じ名前の作り直しが
## 黙って別名にされる。外してから捨てる。

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

## 台詞・立ち絵を含めて黒幕で覆う。黒幕は通常背景より前に置くので、
## `background()` だけでは覆えない会話枠まで確実に隠せる。
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

## 黒幕の前へ全画面ロゴを出す。存在しない素材は既存の背景命令と同じく警告だけで進める。
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

## 次の台本へ黒幕・ロゴを持ち越さない。
func _clear_novel_outro() -> void:
	if host.novel_blackout != null:
		host.novel_blackout.visible = false
	_hide_novel_logo()

## 立ち絵を (x, y) へ出す。置き方は `NovelPortrait.show_at()`。
##
## 人物ごとに独立して表示する。ただし別の人物を**完全に同じ座標**へ出す場合は、
## 先に居た人物を隠して入れ替える。近接した座標は別の立ち位置として併存する。

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

## 立ち絵を (x, y) へ動かす。補間中は台本を待機し、着いてから次の命令へ進む。
##
## 元版（`chara_move`）と同じく、移動完了まで次の台詞・非表示・別の演出を実行しない。
## `chara_show` の淡入だけは、従来どおり待たずに進む。

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

## 話している人物の立ち絵だけを明るく・高くする。
##
## 触るのは目標だけで、寄せは立ち絵が自分で行う（`NovelPortrait._process`）。
## 濃さ（アルファ）は必ず元のまま残す。立ち絵はデータの指定で0.3秒かけて現れ、
## その途中で同じ人物が話し始める並びが実データのほとんどを占める。ここで
## 濃さまで書き込むと、出かけた立ち絵が一瞬で出来上がり、フェードインが
## 起きなかったことになる。

func _focus_novel_speaker(character_name: String) -> void:
	for portrait: NovelPortrait in host.novel_portraits.values():
		portrait.set_focused(character_name.is_empty() or portrait.character_id == character_name)
	if character_name.is_empty() or not host.novel_portraits.has(character_name):
		return
	var speaker: NovelPortrait = host.novel_portraits[character_name]
	if speaker.visible and is_instance_valid(host.novel_portrait_host):
		host.novel_portrait_host.move_child(speaker, host.novel_portrait_host.get_child_count() - 1)

## 背景を差し替える。`duration` が0より大きければ2枚目を淡く重ね、終わるまで待つ
## （真を返す）。
##
## 元版は2枚でクロスフェードする（`MornLuaNovelBackgroundView`）。1枚を透明に
## してから淡入する作りだと、差し替えの瞬間に前の絵が消えて職場が透けていた。
## 前の絵はそのまま残し、上に次の絵を淡く出す。淡入が終わったら絵を1枚目へ
## 写して2枚目を伏せる（`_settle_novel_background`）ので、役は入れ替えない。

func _begin_novel_background(path: String, duration: float) -> bool:
	var texture := _load_novel_resource(path, "背景") as Texture2D
	if texture == null:
		return false
	if duration <= 0.0:
		_settle_novel_background(texture)
		return false
	# 同じ半透明背景を重ねると途中だけ二重に暗くなり、確定時に明るさが跳ねる。
	# 台本の待機時間は保ち、すでに表示中の1枚を使い続ける。
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

## 淡入が終わった背景を1枚目へ写し、2枚目を伏せる。

func _settle_novel_background(texture: Texture2D) -> void:
	host.novel_background.texture = texture
	host.novel_background.visible = true
	host.novel_background.modulate.a = 1.0
	host.novel_background_next.visible = false
	host._mark_initial_visual_ready()

## 立ち絵・背景・吹き出しをまとめて消す。`duration` が0より大きければ淡出し、
## 消え切るまで待つ（真を返す）。0なら即座に伏せる。元版は0でも背景を伏せる。

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

## 吹き出しを出す。元版は同じ吹き出しなら文字を空にし、違えば作り直す。
## どちらも文字は空になるので、ここでも空にする。

func _show_novel_bubble() -> void:
	host.novel_dialogue_panel.visible = true
	host.novel_dialogue_panel.modulate.a = 1.0
	host.novel_dialogue_intentionally_hidden = false
	host.novel_speaker.text = ""
	host.novel_message.text = ""

## 吹き出しを畳む。元版は吹き出しの実体ごと捨てる（`bubble_hide`）。

func _hide_novel_bubble() -> void:
	host.novel_dialogue_panel.visible = false
	host.novel_speaker.text = ""
	host.novel_message.text = ""
