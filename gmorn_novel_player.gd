extends RefCounted

const NovelScript := preload("gmorn_novel_script.gd")

const NOVEL_ADVANCE_BLINK_PERIOD := 0.8


var host: Control
var char_sound_cooldown := 0.0
var waiting_tween: Tween


func _init(main: Control) -> void:
	host = main

func play_novel(id: String, path: String, completion_action := "") -> void:
	_stop_waiting_tween()
	host.novel_generation += 1
	host.novel_commands = host.script_loader.call(path)
	host.novel_index = 0
	host.novel_characters.clear()
	host.novel_display_names.clear()
	host.novel_speaker_id = ""
	host.novel_stage._clear_novel_portraits()
	host.novel_stage._clear_novel_shorts()
	host.novel_id = id
	host.novel_completion_action = completion_action
	host.novel_waiting = false
	host.novel_submit_waiting = false
	host.novel_bgm_touched = false
	host.novel_bgm_before = null
	host.initial_visual_prepared = false
	host.novel_dialogue_intentionally_hidden = false
	host.visible = true
	# 前の物語の最後の絵を残すと、次の最初の `background` が淡入する間に透けて見える。
	host.novel_background.texture = null
	host.novel_background.visible = true
	host.novel_background.modulate.a = 1.0
	host.novel_background_next.visible = false
	host.novel_background_next.modulate.a = 1.0
	host.novel_stage._clear_novel_outro()
	host.novel_dialogue_panel.visible = true
	host.novel_dialogue_panel.modulate.a = 1.0
	host.novel_speaker.text = ""
	host.novel_message.text = ""
	_advance_novel()

## 文字を出している途中なら次へ飛ばさず全部出す。読む前に消えたように見える。
func _advance_novel(from_input := false) -> void:
	if host.novel_waiting:
		return
	if _novel_revealing():
		if from_input:
			_play_char_sound(true)
		_finish_novel_reveal()
		return
	if from_input and host.visible and (host.novel_dialogue_panel.visible or host.novel_submit_waiting):
		host.novel_audio.play_se(host.advance_sound)
	host.novel_submit_waiting = false
	while host.novel_index < host.novel_commands.size():
		var command: Dictionary = host.novel_commands[host.novel_index]
		host.novel_index += 1
		var kind: String = command["kind"]
		if kind == "background":
			if host.novel_stage._begin_novel_background(String(command["path"]), float(command["duration"])):
				return
		elif kind == "character_name":
			var character_id := String(command["name"])
			host.novel_display_names[character_id] = String(command["display_name"])
			if host.novel_speaker_id == character_id:
				host.novel_speaker.text = String(command["display_name"])
		elif kind == "load":
			host.novel_stage._load_novel_character(String(command["name"]), String(command["path"]), float(command["scale"]), bool(command.get("foreground", false)))
		elif kind == "show":
			host.novel_stage._show_novel_character(String(command["name"]), float(command["x"]), float(command["y"]), float(command["duration"]))
		elif kind == "move":
			if host.novel_stage._begin_novel_character_move(String(command["name"]), float(command["x"]), float(command["y"]), float(command["duration"])):
				return
		elif kind == "hide":
			host.novel_stage._hide_novel_character(String(command["name"]))
		elif kind == "bubble":
			host.novel_stage._show_novel_bubble()
		elif kind == "bubble_hide":
			host.novel_stage._hide_novel_bubble()
		elif kind == "all_hide":
			if host.novel_stage._begin_novel_all_hide(float(command["duration"])):
				return
		elif kind in ["fade_out", "fade_in"]:
			if not host.fade_handler.is_valid():
				push_error("ノベル: fade_handlerが未設定です")
				return
			host.novel_waiting = true
			var generation: int = host.novel_generation
			await host.fade_handler.call(kind, float(command["duration"]))
			if not is_instance_valid(host) or not host.is_inside_tree() or host.novel_generation != generation:
				return
			host.novel_waiting = false
		elif kind == "blackout":
			host.novel_stage._begin_novel_blackout()
		elif kind == "logo_show":
			host.novel_stage._show_novel_logo(String(command["path"]))
		elif kind == "logo_hide":
			host.novel_stage._hide_novel_logo()
		elif kind == "wait":
			_wait_for_novel_seconds(float(command["duration"]))
			return
		elif kind == "wait_submit":
			host.novel_submit_waiting = true
			return
		elif kind == "tutorial":
			if host.tutorial_handler.is_valid() and host.tutorial_handler.call(command):
				return
		elif kind == "call":
			if host.command_handler.is_valid() and host.command_handler.call(command):
				return
		elif kind == "bgm":
			if host.novel_audio._begin_novel_bgm(String(command["path"]), float(command["duration"])):
				return
		elif kind == "bgm_stop":
			if host.novel_audio._begin_novel_bgm_stop(float(command["duration"])):
				return
		elif kind == "bgm_mute":
			if host.novel_audio._begin_novel_bgm_mute(float(command["duration"])):
				return
		elif kind == "se":
			host.novel_audio._play_novel_se(String(command["path"]))
		elif kind == "shorts_show" or kind == "shorts_set" or kind == "shorts_pita":
			host.novel_stage._show_novel_shorts(String(command["path"]))
		elif kind == "shorts_zoom":
			host.novel_stage._zoom_novel_shorts(float(command["scale"]))
		elif kind == "shorts_hide":
			host.novel_stage._hide_novel_shorts()
		elif kind == "message":
			# 枠が無いとき台詞を飛ばさず枠を出し直す。飛ばすと遊ぶ側には台詞が消えたように見える。
			if not host.novel_dialogue_panel.visible or host.novel_dialogue_panel.modulate.a < 1.0:
				if not host.novel_dialogue_intentionally_hidden:
					push_warning("ノベル: 吹き出しを出さずに台詞が来た。出し直す（%s）" % host.novel_id)
				host.novel_stage._show_novel_bubble()
			host.novel_speaker_id = String(command["speaker"])
			host.novel_speaker.text = String(host.novel_display_names.get(
				host.novel_speaker_id, command.get("display_name", host.novel_speaker_id)))
			host.novel_message.text = NovelScript.convert_rich_text(String(command["text"]))
			host.novel_stage._focus_novel_speaker(host.novel_speaker_id)
			host._mark_initial_visual_ready()
			_begin_novel_reveal()
			return
	host._mark_initial_visual_ready()
	_finish_novel()

func _begin_novel_reveal() -> void:
	host.novel_revealed = 0.0
	host.novel_message.visible_characters = 0

func _novel_revealing() -> bool:
	return host.novel_message != null and host.novel_message.visible_characters >= 0 \
		and host.novel_message.visible_characters < host.novel_message.get_total_character_count()

## 音は鳴らさない。操作時の音は入力側で1回だけ鳴らす。
func _finish_novel_reveal() -> void:
	host.novel_revealed = float(host.novel_message.get_total_character_count())
	host.novel_message.visible_characters = -1

func _update_novel_reveal(delta: float) -> void:
	char_sound_cooldown = maxf(0.0, char_sound_cooldown - delta)
	if host.novel_message == null or not host.visible or host.novel_waiting:
		return
	if not _novel_revealing():
		return
	host.novel_revealed += delta / host.character_interval
	var total: int = host.novel_message.get_total_character_count()
	var shown := mini(int(host.novel_revealed), total)
	var previous: int = host.novel_message.visible_characters
	if shown >= total:
		host.novel_message.visible_characters = -1
	else:
		host.novel_message.visible_characters = shown

	# 文字が増えたフレームだけ鳴らす。低 FPS でも追いついた文字数分を重ねない。
	if shown > previous and not host.novel_message.get_parsed_text().substr(previous, shown - previous).replace("　", " ").strip_edges().is_empty():
		_play_char_sound()

func _play_char_sound(from_input := false) -> void:
	if not from_input and char_sound_cooldown > 0.0:
		return
	host.novel_audio.play_se(host.character_sound)
	char_sound_cooldown = host.character_sound_interval

## 送り待ちの印。文章が出ていて時間待ちでないときだけ出し、明滅させる。
func _update_novel_advance() -> void:
	if host.novel_advance == null:
		return
	# 出し切るまで印を出すと、まだ続きがあるのに送れそうに見える。
	if not host.visible or host.novel_waiting or not host.novel_dialogue_panel.visible \
			or _novel_revealing():
		host.novel_advance.visible = false
		return
	host.novel_advance.visible = true
	host.novel_advance.modulate.a = 0.5 + 0.5 * sin(host.visual_clock / NOVEL_ADVANCE_BLINK_PERIOD * TAU)

## 既読記録や画面復帰は `finished` の受け手が持つ。
func _finish_novel() -> void:
	host.novel_generation += 1
	host.visible = false
	host.novel_submit_waiting = false
	host.novel_audio._restore_bgm_after_novel()
	var id: String = host.novel_id
	var completion_action: String = host.novel_completion_action
	host.finished.emit(id, completion_action)

func _wait_for_novel_seconds(duration: float, settle := Callable()) -> void:
	host.novel_waiting = true
	_resume_novel_after_delay(maxf(0.0, duration), host.novel_generation, settle)

func _resume_novel_after_delay(duration: float, generation: int, settle: Callable) -> void:
	await host.get_tree().create_timer(duration).timeout
	if not is_instance_valid(host) or not host.is_inside_tree() or generation != host.novel_generation:
		return
	if settle.is_valid():
		settle.call()
	host.novel_waiting = false
	_advance_novel()

func _wait_for_novel_tween(tweener: Tween, settle := Callable()) -> void:
	waiting_tween = tweener
	host.novel_waiting = true
	_resume_novel_after_tween(tweener, host.novel_generation, settle)

func _resume_novel_after_tween(tweener: Tween, generation: int, settle: Callable) -> void:
	await tweener.finished
	if not is_instance_valid(host) or not host.is_inside_tree() or generation != host.novel_generation:
		return
	if settle.is_valid():
		settle.call()
	host.novel_waiting = false
	_advance_novel()

func _cancel_novel() -> void:
	_stop_waiting_tween()
	host.novel_generation += 1
	host.novel_waiting = false
	host.novel_submit_waiting = false
	host.novel_bgm_touched = false
	host.novel_bgm_before = null


func _stop_waiting_tween() -> void:
	if waiting_tween != null and waiting_tween.is_valid():
		waiting_tween.kill()
	waiting_tween = null
