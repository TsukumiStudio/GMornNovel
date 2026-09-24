extends SceneTree

const View := preload("gmorn_novel.tscn")
const Parser := preload("gmorn_novel_script.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var texture := GradientTexture2D.new()
	texture.width = 100
	texture.height = 200
	assert(ResourceSaver.save(texture, "res://texture.tres") == OK)
	var sound := AudioStreamWAV.new()
	sound.data = PackedByteArray([0, 0, 0, 0])
	assert(ResourceSaver.save(sound, "res://sound.tres") == OK)
	_write("res://story.lua", '\n'.join([
		'background("res://texture.tres", 0.01)',
		'chara_load("案内", "res://texture.tres", 1)',
		'chara_show("案内", {0.5, 0.5}, 0)',
		'bgm("res://sound.tres", 0.01)',
		'wait(0.01)',
		'message("案内", "<color=red>あいうえお</color>")',
		'chara_move("案内", {0.6, 0.5}, 0)',
		'bgm_stop(0.01)',
		'se("res://sound.tres")',
		'wait_submit()',
		'bubble_hide()',
		'bubble_show("unused")',
		'shorts_show("res://texture.tres")',
		'shorts_zoom(1.2)',
		'shorts_hide()',
		'chara_hide("案内")',
		'all_hide(0)',
	]))
	assert(Parser.parse_novel("res://story.lua").size() == 17, "台本の対応命令を落とした")
	var view = View.instantiate()
	root.add_child(view)
	view.set_process(false)
	view.character_sound = sound
	view.advance_sound = AudioStreamWAV.new()
	var sounds: Array[AudioStream] = []
	view.sound_requested.connect(func(stream: AudioStream) -> void: sounds.append(stream))
	var completions: Array[String] = []
	view.finished.connect(func(id: String, context: String) -> void: completions.append(id + context))
	var initial_visual_count := [0]
	view.initial_visual_ready.connect(func() -> void: initial_visual_count[0] += 1)
	view.play_novel("story", "res://story.lua", "done")
	assert(await view.wait_for_initial_visual(), "最初の背景の準備を待てない")
	assert(initial_visual_count[0] == 1 and view.novel_background.texture != null,
		"最初の背景の準備完了を一度だけ知らせない")
	var deadline := Time.get_ticks_msec() + 2000
	while view.novel_waiting and Time.get_ticks_msec() < deadline:
		await process_frame
	assert(not view.novel_waiting and view.novel_message.visible_characters == 0, "演出待ちから本文へ進まない")
	assert(sounds.is_empty(), "本文の前に音が鳴った")
	assert(view.novel_portraits.size() == 1, "立ち絵が出ない")
	assert(view.novel_portraits["案内"].size == Vector2(100, 200), "立ち絵の大きさが違う")
	view.novel_player._update_novel_reveal(0.04)
	assert(sounds == [sound], "最初の文字音が鳴らない")
	view.novel_player._update_novel_reveal(0.04)
	assert(sounds.size() == 1 and view.novel_message.visible_characters == 2, "間隔内に鳴った、または表示も止めた")
	view.novel_player._update_novel_reveal(0.04)
	assert(sounds.size() == 2, "0.08秒後の音が鳴らない")
	_click(view)
	assert(not view.is_revealing() and sounds.back() == sound and sounds.size() == 3, "全文表示クリックの音が違う")
	_click(view)
	assert(sounds.back() == view.advance_sound, "次へ送るクリックの音が違う")
	deadline = Time.get_ticks_msec() + 2000
	while view.novel_waiting and Time.get_ticks_msec() < deadline:
		await process_frame
	assert(view.novel_submit_waiting and sounds.back().resource_path == "res://sound.tres", "SEか入力待ちを落とした")
	view.advance()
	assert(completions == ["storydone"] and not view.visible, "読了通知か画面の終了が違う")
	assert(not view.novel_shorts.visible and not view.novel_background.visible, "非表示命令を落とした")

	# 表示名を変えても同じIDの立ち絵を使い、画像差替え後も名前を保つ。
	_write("res://names.lua", '\n'.join([
		'chara_load("friend", "res://texture.tres", 1)',
		'chara_show("friend", {0.5, 0.5}, 0)',
		'chara_name("friend", "???")',
		'message("friend", "はじめまして")',
		'chara_name("friend", "友人")',
		'chara_load("friend", "res://texture.tres", 1)',
		'message("friend", "名乗ったあと")',
	]))
	assert(Parser.parse_novel("res://names.lua").size() == 7)
	view.play_novel("names", "res://names.lua")
	var friend = view.novel_portraits["friend"]
	assert(view.novel_speaker.text == "???" and friend.focused)
	view.reveal_all()
	view.advance()
	assert(view.novel_speaker.text == "友人" and view.novel_speaker_id == "friend")
	assert(view.novel_portraits.size() == 1 and view.novel_portraits["friend"] == friend)
	_write("res://name_reset.lua", 'message("friend", "次の話")')
	view.play_novel("reset", "res://name_reset.lua")
	assert(view.novel_speaker.text == "friend" and view.novel_display_names.is_empty())

	# フェードの完了前には次の命令へ進まず、中断した再生を再開しない。
	_write("res://fade.lua", 'fade_out(0.02)\nfade_in(0.02)\nmessage("完了", "明転後")')
	assert(Parser.parse_novel("res://fade.lua").size() == 3)
	var fades: Array[String] = []
	view.fade_handler = func(kind: String, duration: float) -> void:
		fades.append(kind)
		await create_timer(duration).timeout
	view.play_novel("fade", "res://fade.lua")
	assert(view.novel_waiting and fades == ["fade_out"])
	view.advance()
	assert(fades == ["fade_out"], "入力でフェード待機を飛ばした")
	await create_timer(0.1).timeout
	assert(fades == ["fade_out", "fade_in"] and view.novel_speaker.text == "完了")
	view.play_novel("cancel_fade", "res://fade.lua")
	view.cancel()
	await create_timer(0.1).timeout
	assert(fades == ["fade_out", "fade_in", "fade_out"], "中断した台本の明転へ進んだ")

	# 同じViewで再生を差し替えても、古いwait/tweenが新しい本文を書き換えない。
	_write("res://waiting.lua", 'wait(0.05)\nmessage("古い", "古い文章")')
	_write("res://fading.lua", 'background("res://texture.tres", 0.05)\nmessage("古い", "古い文章")')
	_write("res://next.lua", 'message("新しい", "次の文章")')
	for path: String in ["res://waiting.lua", "res://fading.lua"]:
		view.play_novel("old", path)
		assert(view.novel_waiting, "中断対象が待機していない")
		view.cancel()
		view.play_novel("new", "res://next.lua")
		await create_timer(0.1).timeout
		assert(view.novel_speaker.text == "新しい" and view.novel_message.visible_characters == 0,
			"古い非同期処理が新しい台本へ戻った")
		assert(view.novel_background.texture == null, "古い背景が戻った")
	view.play_novel("detached", "res://waiting.lua")
	root.remove_child(view)
	view.queue_free()
	await create_timer(0.1).timeout

	# プロジェクト設定より環境変数を優先する。
	ProjectSettings.set_setting("gmorn_novel/character_sound_interval", 0.2)
	OS.set_environment("GMORN_NOVEL_CHARACTER_SOUND_INTERVAL", "0.12")
	view = View.instantiate()
	root.add_child(view)
	assert(is_equal_approx(view.character_sound_interval, 0.12), "設定の優先順位が違う")
	OS.unset_environment("GMORN_NOVEL_CHARACTER_SOUND_INTERVAL")
	view.queue_free()
	await process_frame
	print("GMORN NOVEL VERIFY: PASS (commands, character IDs, audio, input, cancellation, settings)")
	quit()

func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(text)

func _click(view: Control) -> void:
	var button := view.get_node("NovelAdvanceButton") as BaseButton
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		event.position = button.get_global_rect().get_center()
		view.get_viewport().push_input(event, true)
