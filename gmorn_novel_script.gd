extends RefCounted

## ノベル台本(Lua風テキスト)の解釈。読み込んだファイルを命令の配列へ直すだけの
## 純関数。Lua VMではなく、対応する表示命令だけを読む。



static func convert_rich_text(text: String) -> String:
	var converted := text.replace("</color>", "[/color]")
	var color_regex := RegEx.new()
	color_regex.compile("<color=([^>]+)>")
	return color_regex.sub(converted, "[color=$1]", true)

static func parse_novel(path: String, resolve_path := Callable(), ignored_speaker := "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return result
	var message_regex := RegEx.new()
	message_regex.compile('^message\\("((?:[^"\\\\]|\\\\.)*)",\\s*"((?:[^"\\\\]|\\\\.)*)"\\)')
	var background_regex := RegEx.new()
	background_regex.compile('^background\\("((?:[^"\\\\]|\\\\.)*)"(?:,\\s*([0-9.]+))?')
	var load_regex := RegEx.new()
	var name_regex := RegEx.new()
	name_regex.compile('^chara_name\\("((?:[^"\\\\]|\\\\.)*)",\\s*"((?:[^"\\\\]|\\\\.)*)"\\)')
	load_regex.compile('^chara_load\\("((?:[^"\\\\]|\\\\.)*)",\\s*"((?:[^"\\\\]|\\\\.)*)"(?:,\\s*([0-9.]+))?')
	var show_regex := RegEx.new()
	show_regex.compile('^chara_show\\("([^"]+)".*\\{([0-9.]+),\\s*([0-9.]+)\\}(?:,\\s*([0-9.]+))?')
	var hide_regex := RegEx.new()
	hide_regex.compile('^chara_hide\\("([^"]+)"')
	var move_regex := RegEx.new()
	move_regex.compile('^chara_move\\("([^"]+)".*\\{([0-9.]+),\\s*([0-9.]+)\\}(?:,\\s*([0-9.]+))?')
	var duration_regex := RegEx.new()
	duration_regex.compile('^(wait|all_hide)\\(([0-9.]+)')
	var bubble_regex := RegEx.new()
	bubble_regex.compile('^bubble_show\\("([^"]+)"')
	var bubble_hide_regex := RegEx.new()
	bubble_hide_regex.compile('^bubble_hide\\(')
	var wait_submit_regex := RegEx.new()
	wait_submit_regex.compile('^wait_submit\\(')
	var tutorial_regex := RegEx.new()
	tutorial_regex.compile('^start_tutorial\\(\\s*"([^"]+)"\\s*,\\s*(?:"([^"]+)"|([0-9]+))\\s*\\)')
	var legacy_tutorial_regex := RegEx.new()
	legacy_tutorial_regex.compile('^exec_tutorial\\(\\s*([0-9]+)\\s*\\)')
	var blackout_regex := RegEx.new()
	blackout_regex.compile('^blackout\\(')
	var logo_show_regex := RegEx.new()
	logo_show_regex.compile('^logo_show\\("((?:[^"\\\\]|\\\\.)*)"\\)')
	var logo_hide_regex := RegEx.new()
	logo_hide_regex.compile('^logo_hide\\(')
	var bgm_regex := RegEx.new()
	bgm_regex.compile('^bgm\\("((?:[^"\\\\]|\\\\.)*)"(?:,\\s*([0-9.]+))?')
	var bgm_stop_regex := RegEx.new()
	bgm_stop_regex.compile('^bgm_stop\\(\\s*([0-9.]*)')
	var bgm_mute_regex := RegEx.new()
	bgm_mute_regex.compile('^bgm_mute\\(\\s*([0-9.]*)')
	var stream_start_regex := RegEx.new()
	stream_start_regex.compile('^piita_stream_start\\(\\)')
	var se_regex := RegEx.new()
	se_regex.compile('^se\\("((?:[^"\\\\]|\\\\.)*)"')
	var shorts_image_regex := RegEx.new()
	shorts_image_regex.compile('^shorts_(show|set|pita)\\("((?:[^"\\\\]|\\\\.)*)"')
	var shorts_zoom_regex := RegEx.new()
	shorts_zoom_regex.compile('^shorts_zoom\\(([0-9.]+)')
	var shorts_hide_regex := RegEx.new()
	shorts_hide_regex.compile('^shorts_hide\\(\\s*([0-9.]*)')
	var in_block_comment := false
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		# Luaの複数行コメントは、この簡易パーサーでも状態を跨いで無視する。
		# 閉じた後ろに命令が続く書式も残りの文字列を同じ行として解析する。
		if in_block_comment:
			var comment_end := line.find("]]" )
			if comment_end < 0:
				continue
			in_block_comment = false
			line = line.substr(comment_end + 2).strip_edges()
			if line.is_empty():
				continue
		if line.begins_with("--[["):
			var inline_end := line.find("]]", 4)
			if inline_end < 0:
				in_block_comment = true
				continue
			line = line.substr(inline_end + 2).strip_edges()
			if line.is_empty():
				continue
		var match_message := message_regex.search(line)
		if match_message != null:
			var speaker := match_message.get_string(1)
			if not ignored_speaker.is_empty() and speaker == ignored_speaker:
				continue
			result.append({"kind": "message", "speaker": speaker, "text": match_message.get_string(2).replace("\\n", "\n")})
			continue
		var match_background := background_regex.search(line)
		if match_background != null:
			var duration := match_background.get_string(2).to_float() if not match_background.get_string(2).is_empty() else 0.0
			result.append({"kind": "background", "path": _resolve_path(match_background.get_string(1), resolve_path), "duration": duration})
			continue
		var match_load := load_regex.search(line)
		var match_name := name_regex.search(line)
		if match_name != null:
			result.append({"kind": "character_name", "name": match_name.get_string(1), "display_name": match_name.get_string(2)})
			continue
		if match_load != null:
			var scale := match_load.get_string(3).to_float() if not match_load.get_string(3).is_empty() else 1.0
			result.append({"kind": "load", "name": match_load.get_string(1), "path": _resolve_path(match_load.get_string(2), resolve_path), "scale": scale})
			continue
		var match_show := show_regex.search(line)
		if match_show != null:
			var duration := match_show.get_string(4).to_float() if not match_show.get_string(4).is_empty() else 0.0
			result.append({"kind": "show", "name": match_show.get_string(1), "x": match_show.get_string(2).to_float(), "y": match_show.get_string(3).to_float(), "duration": duration})
			continue
		var match_hide := hide_regex.search(line)
		if match_hide != null:
			result.append({"kind": "hide", "name": match_hide.get_string(1)})
			continue
		var match_move := move_regex.search(line)
		if match_move != null:
			var duration := match_move.get_string(4).to_float() if not match_move.get_string(4).is_empty() else 0.0
			result.append({"kind": "move", "name": match_move.get_string(1), "x": match_move.get_string(2).to_float(), "y": match_move.get_string(3).to_float(), "duration": duration})
			continue
		var match_duration := duration_regex.search(line)
		if match_duration != null:
			result.append({"kind": match_duration.get_string(1), "duration": match_duration.get_string(2).to_float()})
			continue
		var match_bubble := bubble_regex.search(line)
		if match_bubble != null:
			result.append({"kind": "bubble"})
			continue
		if bubble_hide_regex.search(line) != null:
			result.append({"kind": "bubble_hide"})
			continue
		if wait_submit_regex.search(line) != null:
			result.append({"kind": "wait_submit"})
			continue
		var match_tutorial := tutorial_regex.search(line)
		if match_tutorial != null:
			var argument: Variant = match_tutorial.get_string(2)
			if argument.is_empty():
				argument = match_tutorial.get_string(3).to_int()
			result.append({"kind": "tutorial", "tutorial": match_tutorial.get_string(1), "argument": argument})
			continue
		var legacy_tutorial := legacy_tutorial_regex.search(line)
		if legacy_tutorial != null:
			# 既存台本との互換。新規台本は用途を明示する start_tutorial を使う。
			result.append({"kind": "tutorial", "tutorial": "fruit_press", "argument": legacy_tutorial.get_string(1).to_int()})
			continue
		if blackout_regex.search(line) != null:
			result.append({"kind": "blackout"})
			continue
		var match_logo_show := logo_show_regex.search(line)
		if match_logo_show != null:
			result.append({"kind": "logo_show", "path": _resolve_path(match_logo_show.get_string(1), resolve_path)})
			continue
		if logo_hide_regex.search(line) != null:
			result.append({"kind": "logo_hide"})
			continue
		var match_bgm := bgm_regex.search(line)
		if match_bgm != null:
			var duration := match_bgm.get_string(2).to_float() if not match_bgm.get_string(2).is_empty() else 0.0
			result.append({"kind": "bgm", "path": _resolve_path(match_bgm.get_string(1), resolve_path), "duration": duration})
			continue
		var match_bgm_stop := bgm_stop_regex.search(line)
		if match_bgm_stop != null:
			result.append({"kind": "bgm_stop", "duration": match_bgm_stop.get_string(1).to_float()})
			continue
		var match_bgm_mute := bgm_mute_regex.search(line)
		if match_bgm_mute != null:
			result.append({"kind": "bgm_mute", "duration": match_bgm_mute.get_string(1).to_float()})
			continue
		if stream_start_regex.search(line) != null:
			result.append({"kind": "stream_start", "stream": "piita"})
			continue
		var match_se := se_regex.search(line)
		if match_se != null:
			result.append({"kind": "se", "path": _resolve_path(match_se.get_string(1), resolve_path)})
			continue
		var match_shorts_image := shorts_image_regex.search(line)
		if match_shorts_image != null:
			result.append({"kind": "shorts_" + match_shorts_image.get_string(1), "path": _resolve_path(match_shorts_image.get_string(2), resolve_path)})
			continue
		var match_shorts_zoom := shorts_zoom_regex.search(line)
		if match_shorts_zoom != null:
			result.append({"kind": "shorts_zoom", "scale": match_shorts_zoom.get_string(1).to_float()})
			continue
		var match_shorts_hide := shorts_hide_regex.search(line)
		if match_shorts_hide != null:
			result.append({"kind": "shorts_hide"})
	return result

static func _resolve_path(path: String, resolver: Callable) -> String:
	return String(resolver.call(path)) if resolver.is_valid() else path
