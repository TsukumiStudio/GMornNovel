extends Control

## ノベルの進行・表示・音声・状態はこのノードが持つ。利用側から受け取るのは
## `play_novel()` の再生要求だけで、読み終えたら `finished` を鳴らして事実だけを返す。

signal finished(id: String, completion_action: String)
signal sound_requested(stream: AudioStream)
## 最初の背景または台詞を表示できる状態になった。暗転遷移の明転待ちに使う。
signal initial_visual_ready

const Player := preload("gmorn_novel_player.gd")
const Stage := preload("gmorn_novel_stage.gd")
const Audio := preload("gmorn_novel_audio.gd")
const Parser := preload("gmorn_novel_script.gd")

@export var character_interval := 0.04
@export var character_sound_interval := 0.08
@export var character_sound: AudioStream
@export var advance_sound: AudioStream
@export var portrait_scene: PackedScene = preload("gmorn_novel_portrait.tscn")
@export var bgm_volume_db := 0.0
@export var se_volume_db := 0.0
var script_loader: Callable = Parser.parse_novel
## 利用側固有の待機命令。trueを返すと、利用側が明示的に進行を再開するまで止まる。
var tutorial_handler: Callable
var visual_clock := 0.0


@onready var novel_background: TextureRect = $NovelBackground
@onready var novel_background_next: TextureRect = $NovelBackgroundNext
@onready var novel_portrait_host: Control = $Portraits
@onready var representative_portrait: TextureRect = get_node_or_null("Portraits/RepresentativePortrait")
@onready var novel_shorts: Control = $Shorts
@onready var novel_dialogue_panel: PanelContainer = $DialoguePanel
@onready var novel_speaker: RichTextLabel = $DialoguePanel/Margin/Content/NovelSpeaker
@onready var novel_message: RichTextLabel = $DialoguePanel/Margin/Content/NovelMessage
@onready var novel_advance: TextureRect = $DialoguePanel/Margin/Content/NovelAdvance
@onready var novel_blackout: ColorRect = get_node_or_null("NovelBlackout") as ColorRect
@onready var novel_logo: TextureRect = get_node_or_null("OpeningLogo") as TextureRect

var novel_player: RefCounted
var novel_stage: RefCounted
var novel_audio: RefCounted

var novel_commands: Array[Dictionary] = []
var novel_index := 0
var novel_characters: Dictionary = {}
## キャラID → 立ち絵（`NovelPortrait`）。発話時は同じIDの立ち絵を手前へ出す。
var novel_portraits: Dictionary = {}
## 台本内だけで有効なIDごとの表示名。次の再生開始時にリセットする。
var novel_display_names: Dictionary = {}
var novel_speaker_id := ""
var novel_id := ""
var novel_waiting := false
## `wait_submit` で押されるのを待っているか。検査が読む。
var novel_submit_waiting := false
## 音声アダプターが使用する曲の変更状態。
var novel_bgm_touched := false
## 共通BGMを使うアダプター向けの復帰先。既定の専用BGMでは使用しない。
var novel_bgm_before: AudioStream = null
## ノベルの都合で曲を止めた回数。**窓の無い実行では鳴らないので、検査はこれを読む。**
var novel_bgm_stop_count := 0
## 最後に `bgm_stop` が求めた淡出の秒。検査が読む。
var last_novel_bgm_stop_fade := -1.0
## いま出している文字数。途中の送り操作では全文表示する。
var novel_revealed := 0.0
var novel_generation := 0
var novel_completion_action := ""
## 現在の台本が、最初に見せる絵を準備し終えたか。
var initial_visual_prepared := false
## `all_hide` / `blackout` により会話枠を意図して隠しているか。
var novel_dialogue_intentionally_hidden := false

func _ready() -> void:
	# Editor用の代表立ち絵は、台本の人物辞書や表示制御へ混ぜない。
	if representative_portrait != null:
		novel_portrait_host.remove_child(representative_portrait)
		representative_portrait.queue_free()
	novel_background_next.visible = false
	novel_shorts.visible = false
	if novel_blackout != null:
		novel_blackout.visible = false
	if novel_logo != null:
		novel_logo.visible = false
	# GMornButtonを使う場合も、クリック音はノベルだけが決める。
	var button := $NovelAdvanceButton as BaseButton
	if "play_submit_sound" in button:
		button.set("play_submit_sound", false)
	button.pressed.connect(advance)
	character_interval = _interval("character_interval", character_interval, 0.001)
	character_sound_interval = _interval("character_sound_interval", character_sound_interval, 0.0)
	novel_player = Player.new(self)
	novel_stage = Stage.new(self)
	novel_audio = Audio.new(self)

func _process(delta: float) -> void:
	visual_clock += delta
	if novel_player == null:
		return
	novel_player._update_novel_reveal(delta)
	novel_player._update_novel_advance()

## 台本を再生する。完了時にIDと利用側の文脈をfinishedで返す。

func play_novel(id: String, path: String, completion_action := "") -> void:
	novel_player.play_novel(id, path, completion_action)

## 最初の背景クロスフェードまで待つ。背景無しの台本は最初の台詞を準備した時点で
## 済む。中断・別台本への差し替え時は false を返す。
func wait_for_initial_visual() -> bool:
	var generation := novel_generation
	while is_inside_tree() and visible and generation == novel_generation and not initial_visual_prepared:
		await get_tree().process_frame
	return is_inside_tree() and visible and generation == novel_generation and initial_visual_prepared

func _mark_initial_visual_ready() -> void:
	if initial_visual_prepared:
		return
	initial_visual_prepared = true
	initial_visual_ready.emit()

func advance() -> void:
	novel_player._advance_novel(true)

func finish() -> void:
	novel_player._finish_novel()

func reveal_all() -> void:
	novel_player._finish_novel_reveal()

func is_revealing() -> bool:
	return novel_player._novel_revealing()

func _update_novel_advance() -> void:
	novel_player._update_novel_advance()

## 画面遷移などで途中の物語を打ち切る。待機の続きは再開しない。

func cancel() -> void:
	novel_player._cancel_novel()
	novel_audio._restore_bgm_after_novel()
	visible = false

func _exit_tree() -> void:
	if novel_player != null:
		novel_player._cancel_novel()

func _interval(key: String, fallback: float, minimum: float) -> float:
	var value := fallback
	var setting := "gmorn_novel/" + key
	if ProjectSettings.has_setting(setting):
		value = float(ProjectSettings.get_setting(setting))
	var override := OS.get_environment("GMORN_NOVEL_" + key.to_upper())
	if not override.is_empty() and override.is_valid_float():
		value = override.to_float()
	return maxf(minimum, value) if is_finite(value) else fallback
