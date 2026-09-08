extends RefCounted

## 単独利用時の音声。ゲームの共通ミキサーへ繋ぐ場合はこのアダプターを差し替える。
const SoundScene := preload("gmorn_novel_sound.tscn")

var host: Control
var bgm: AudioStreamPlayer
var fade_tween: Tween

func _init(view: Control) -> void:
	host = view
	bgm = host.get_node_or_null("Audio/BgmPlayer")

func play_se(stream: AudioStream) -> void:
	if stream == null:
		return
	host.sound_requested.emit(stream)
	if DisplayServer.get_name() != "headless":
		var player := SoundScene.instantiate() as AudioStreamPlayer
		player.volume_db = host.se_volume_db
		player.stream = stream
		host.add_child(player)
		player.finished.connect(player.queue_free)
		player.play()

func _play_novel_se(path: String) -> void:
	play_se(host.novel_stage._load_novel_resource(path, "効果音") as AudioStream)

func _begin_novel_bgm(path: String, duration: float) -> bool:
	var stream := host.novel_stage._load_novel_resource(path, "曲") as AudioStream
	if stream == null:
		return false
	host.novel_bgm_touched = true
	if bgm != null:
		_stop_fade()
		bgm.stream = stream
		bgm.volume_db = -80.0 if duration > 0.0 else host.bgm_volume_db
		if DisplayServer.get_name() != "headless":
			bgm.play()
		if duration > 0.0:
			fade_tween = host.create_tween()
			fade_tween.tween_property(bgm, "volume_db", host.bgm_volume_db, duration)
	if duration > 0.0:
		host.novel_player._wait_for_novel_seconds(duration)
		return true
	return false

func _begin_novel_bgm_stop(duration: float) -> bool:
	host.last_novel_bgm_stop_fade = duration
	_stop_fade()
	if duration <= 0.0:
		_stop_bgm_for_novel()
		return false
	if bgm != null:
		fade_tween = host.create_tween()
		fade_tween.tween_property(bgm, "volume_db", -80.0, duration)
	host.novel_player._wait_for_novel_seconds(duration, _stop_bgm_for_novel)
	return true

func _stop_bgm_for_novel() -> void:
	_stop_fade()
	host.novel_bgm_stop_count += 1
	if bgm != null:
		bgm.stop()
		bgm.stream = null

func _restore_bgm_after_novel() -> void:
	_stop_bgm_for_novel()
	host.novel_bgm_touched = false

func _stop_fade() -> void:
	if fade_tween != null and fade_tween.is_valid():
		fade_tween.kill()
