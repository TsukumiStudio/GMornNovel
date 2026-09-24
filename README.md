# GMornNovel

## 概要

Godotのノベル再生アドオン。Lua風の台本を読み、文字送り・立ち絵・背景・音声を再生する。
画面ごとにインスタンスを作り、既読や報酬、画面遷移は利用側へ任せる。

## 動作環境

- Godot 4.7
- 他のGMornアドオン・Autoload・ゲーム固有クラスは不要
- 画像・フォント・音声は利用側で用意する。コードとシーンだけを配布する

## 機能

- 0.04秒ごとの文字表示、文字音は最低0.08秒間隔
- 表示途中のクリックは文字音で全文表示、次のクリックは送り音で次へ進む
- 空白・改行では文字音を鳴らさず、自動進行で送り音を鳴らさない
- 背景クロスフェード、話者ごとの立ち絵、移動、話者の明るさと上下位置
- BGMの淡入・淡出、重ねて鳴らせる単発SE、画像の表示・拡大
- 時間待ち、入力待ち、読了通知、中断後の古い非同期処理の破棄

立ち絵はキャラIDごとに独立して表示し、台詞の表示名とは分離する。別の人物を近い座標へ出しても、すでに
表示している人物を自動では隠さない。ただし完全に同じ座標へ出す場合は先の人物を
隠して入れ替える。台詞の話者は、その都度ほかの立ち絵より前面へ表示する。
- エディターの事前スキャンが不要な相対preload。配置先のフォルダー名は自由

## 1. 導入

```sh
git submodule add https://github.com/TsukumiStudio/GMornNovel.git addons/gmorn_novel
```

Gitを使わない場合は、このディレクトリ一式を `addons/gmorn_novel/` へ配置する。
`gmorn_novel.tscn` をインスタンス化するか、継承シーンを作り、見た目を編集する。
プラグインを有効にしなくても再生できる。リポジトリ直下に `project.godot` は置かない。

既定シーンは1920×1080を基準とする素材未設定のビュー。
背景・立ち絵・送り待ち画像・テーマ・フォントは利用側のシーンで指定する。
立ち絵の座標系を変える場合は `gmorn_novel_portrait.tscn` の継承シーンで
`canvas_size` を設定し、Viewの `portrait_scene` に渡す。

## 2. 台本を再生する

```gdscript
const NovelView := preload("res://addons/gmorn_novel/gmorn_novel.tscn")

func show_story() -> void:
	var view = NovelView.instantiate()
	add_child(view)
	view.character_sound = preload("res://sounds/text.wav")
	view.advance_sound = preload("res://sounds/advance.wav")
	view.finished.connect(func(_id: String, _context: String) -> void: view.queue_free())
	view.play_novel("intro", "res://stories/intro.lua")
```

```lua
background("res://images/room.png", 0.3)
chara_load("案内役", "res://images/guide.png", 1.0)
chara_show("案内役", {0.5, 0.5}, 0.3)
message("案内役", "こんにちは。\n<color=#ffcc00>案内を始めます。</color>")
wait_submit()
all_hide(0.2)
```

Lua VMではなく、1行ずつ表示命令を読む。変数、条件分岐、関数定義は実行しない。
文字列は二重引用符、座標や秒数は非負の数値リテラルで指定する。
対応命令は `message`、`background`、`chara_load/show/move/hide/name`、
`bubble_show/hide`、`fade_out(秒)`、`fade_in(秒)`、`wait`、`wait_submit`、`start_tutorial("種類"[, 引数])`、`all_hide`、`bgm`、`bgm_stop`、`bgm_mute`、`se`、
`shorts_show/set/pita/zoom/hide`。`bubble_show` の引数は互換用で、枠の差し替えには使わない。
`chara_show/move` は演出途中でも次の命令へ進む。
表示中と同じ `background` は重ね直さず、指定秒数だけ待つ。半透明背景が二重になることによる点滅を防ぐ。
`fade_out` / `fade_in` は `fade_handler(種類, 秒数)` の完了をawaitしてから台本を進める。
利用側で全画面の幕へ接続する。待機中の送り入力は無効で、中断・再生差し替え後には古い台本へ戻らない。
`start_tutorial` は利用側が `tutorial_handler` を設定した場合だけ待機命令として扱う。handlerには
`{"kind": "tutorial", "tutorial": 種類, "argument": 引数}` を渡す。handlerがtrueを返したときは、
利用側が進行を再開するまで次の命令へ進まない。旧式の `exec_tutorial(個数)` は
`start_tutorial("fruit_press", 個数)` として読み替える互換入力であり、新規台本には使わない。

台本は実行時にファイルとして読むため、エクスポート設定の非リソースファイル対象に `*.lua` を含める。

### キャラIDと表示名

`message` と `chara_*` の第1引数は同じキャラIDを使う。`chara_name(ID, 表示名)` は以後の名前欄だけを変え、立ち絵の強調・前面表示・移動・非表示には影響しない。

```lua
chara_load("friend", "res://friends/normal.png", 1)
chara_name("friend", "???")
chara_show("friend", {0.3, 0.35}, 0.3)
message("friend", "はじめまして")
chara_name("friend", "友人")
message("friend", "名前を紹介した後の台詞")
```

表示名の変更は画像差替え後も保ち、`play_novel()` のたびにリセットする。保存には関与しない。変更がなければ `message` 命令Dictionaryの `display_name` を使い、省略時はIDそのものを表示する。このため従来の日本語名指定もそのまま動く。既定表示名・旧名のID変換は利用側の `script_loader` で付与し、共通アドオンに作品固有の人物名は置かない。現在の発話者IDは `novel_speaker_id`、立ち絵のIDは `character_id` で取得できる。

## 3. 入力とライフサイクル

| API | 動作 |
|---|---|
| `play_novel(id, path, context = "")` | 台本を先頭から再生。前の待機を破棄する |
| `await wait_for_initial_visual()` | 最初の背景クロスフェード、または背景無しなら最初の台詞準備まで待つ。中断時は `false` |
| `advance()` | 表示途中なら全文表示、それ以外は次へ進む |
| `reveal_all()` | 音を鳴らさず全文表示。ツール用 |
| `is_revealing()` | 文字表示中かを返す |
| `finish()` | 読了として終了し、`finished(id, context)` を発行 |
| `cancel()` | 読了通知を出さず終了。専用BGMを止めてビューを隠す |

マウスは `NovelAdvanceButton` が押した瞬間に受ける。キーボード・パッドは利用側で
アクションを選び、`advance()` を呼ぶ。GMornButtonをクリック領域に使っても、
Viewが `play_submit_sound` を無効化するため、共通決定音は重ならない。

全文表示の操作音は自動音の間隔制限を待たず1回鳴らし、そこから間隔を数え直す。
`character_sound` / `advance_sound` が未設定なら、その音は鳴らない。

## 4. 設定とゲームへの接続

| Viewの設定 | 既定値 |
|---|---:|
| `character_interval` | 0.04秒 |
| `character_sound_interval` | 0.08秒 |
| `bgm_volume_db` / `se_volume_db` | 0dB |

2つの時間設定は、コード／シーンの値 → `gmorn_novel/<設定名>` のProjectSettings →
`GMORN_NOVEL_<大文字の設定名>` の環境変数の順に上書きする。
設定例：`GMORN_NOVEL_CHARACTER_SOUND_INTERVAL=0.12`。

台本内の素材パス変換や演出行の除外は、ゲーム側の `script_loader: Callable` で指定する。
既定のパーサーも `parse_novel(path, resolve_path = Callable(), ignored_speaker = "")` を公開する。

独自の共通音声へ接続する場合は `novel_audio` を、既定の `gmorn_novel_audio.gd` と同じ
メソッドを持つアダプターへ差し替える。既定の音声はView専用BGMで、終了時に停止する。
元のゲームBGMの復帰方針はアダプターが持つ。
`sound_requested(stream)` は既定音声のSE要求通知で、ヘッドレスでも発行する。

## 5. 検証

```sh
sh verify.sh  # GMornNovelリポジトリのルートから実行
```

別名フォルダーへコピーした一時プロジェクトで、キャッシュ・ゲーム素材・外部アドオンなしで検証する。
台本、文字音の間隔、マウス入力、中断、設定の上書きをヘッドレスで確認する。
実際の聴感と描画結果は、この検証の対象外。

## ライセンス

Unlicense。画像・音声・フォントは含まない。
