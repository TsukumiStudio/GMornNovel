extends Control

## ノベルの View。既読や画面遷移は持たず、読み終えたら `finished` で事実だけ返す。

signal finished(id: String, completion_action: String)
signal sound_requested(stream: AudioStream)
## 暗転遷移の明転待ちに使う。
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
## true を返すと、利用側が明示的に進行を再開するまで止まる。
var tutorial_handler: Callable
## 対応命令に無い関数呼び出しを `{"kind": "call", "name", "args"}` で受け取る。
## true を返すと `tutorial_handler` と同じく止まる。未設定なら読み飛ばす。
var command_handler: Callable
## 全画面フェード `(種類, 秒数)`。完了まで await できる処理を接続する。
var fade_handler: Callable
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
## キャラID → 立ち絵。
var novel_portraits: Dictionary = {}
## 台本内だけで有効。次の再生開始時にリセットする。
var novel_display_names: Dictionary = {}
var novel_speaker_id := ""
var novel_id := ""
var novel_waiting := false
## 検査が読む。
var novel_submit_waiting := false
var novel_bgm_touched := false
## 共通 BGM を使うアダプター向けの復帰先。既定の専用 BGM では使わない。
var novel_bgm_before: AudioStream = null
## ヘッドレスでは鳴らないので、検査はこれを読む。
var novel_bgm_stop_count := 0
## 検査が読む。
var last_novel_bgm_stop_fade := -1.0
var novel_revealed := 0.0
var novel_generation := 0
var novel_completion_action := ""
var initial_visual_prepared := false
## `all_hide` / `blackout` で意図して隠した枠に台詞が来ても警告しないための印。
var novel_dialogue_intentionally_hidden := false

func _ready() -> void:
	# Editor 用の代表立ち絵を台本の人物辞書へ混ぜない。
	if representative_portrait != null:
		novel_portrait_host.remove_child(representative_portrait)
		representative_portrait.queue_free()
	novel_background_next.visible = false
	novel_shorts.visible = false
	if novel_blackout != null:
		novel_blackout.visible = false
	if novel_logo != null:
		novel_logo.visible = false
	# GMornButton を使う場合も、クリック音はノベルだけが鳴らす。重なるため。
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

func play_novel(id: String, path: String, completion_action := "") -> void:
	novel_player.play_novel(id, path, completion_action)

## 背景無しの台本は最初の台詞を準備した時点で済む。中断・差し替え時は false。
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

## 待機の続きは再開しない。
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
