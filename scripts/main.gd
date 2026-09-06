extends Control

const Store = preload("res://core/event_store.gd")
const Pet = preload("res://scripts/pet.gd")
const Stage = preload("res://scripts/stage.gd")
const StatusItem = preload("res://scripts/status_item.gd")
const TaskEntry = preload("res://scripts/task_entry.gd")
const GuaAdapter = preload("res://addons/gua/gua_auto_adapter.gd")
const INK := Color("f4efdf")
const MUTED := Color("a6a5b8")
const ACCENT := Color("c5acff")
const STATE_NAMES := {"working":"作業中", "question":"質問待ち", "failed":"失敗", "review":"レビュー到着", "completed":"完了", "idle":"おやすみ"}
const STATE_COLORS := {"working":"bfa7ff", "question":"ffd18d", "failed":"f4a49d", "review":"a5c9f5", "completed":"a6e0c4", "idle":"b2afc6"}
const HEADLINES := {"working":"今日も、こつこつ。", "question":"たすけて～～～！！！", "failed":"あっ。CI、こけちゃった。", "review":"空からレビューのお届け。", "completed":"できた！おつかれさま。", "idle":"ひとやすみ、ひとやすみ。"}
var live = Store.new()
var demo_store = Store.new()
var demo := false
var selected := ""
var mascot := false
var settings_open := false
var import_open := false
var import_path_text := ""
var quiet_mode := false
var reduced_motion := false
var top_mode := 2
var page := 0
var data_dir := ""
var io_error := ""
var gui: Control
var animated: Array = []
var bridge = null
var clock_accum := 0.0
var poll_accum := 0.0
var screenshot_accum := 0.0
var dirty := false
var dragging := false
var drag_origin := Vector2i.ZERO
var drag_window_origin := Vector2i.ZERO
var tray: StatusIndicator
var theater_position := Vector2i(180,100)
var mascot_position := Vector2i(1100,550)
var font: SystemFont
var desktop_sync := true
var sync_pid := -1
var syncing := false
var sync_status := "Codex自動同期を準備中"
var sync_stamp := ""
var sync_revisions: Dictionary = {}
var sync_initialized := false
var sync_since: int = 0
var theater_size := Vector2i(1100,720)
var palette_index := 0
var custom_sheet := ""
var pet_source_hue := 0.72
var pet_hue_tolerance := 0.11
var sidebar_open := true
var edit_mode := false
var hidden_tasks: Array = []
var task_order: Array = []
var add_open := false
var new_task_name := ""
var alert_remaining := 0.0
var alert_task := ""
var alert_title := ""

func _ready() -> void:
	Engine.max_fps = 30
	OS.low_processor_usage_mode = true
	OS.low_processor_usage_mode_sleep_usec = 16000
	get_tree().auto_accept_quit = false
	get_window().close_requested.connect(_close_requested)
	get_window().size_changed.connect(func(): dirty = true)
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Yu Gothic UI", "Noto Sans CJK JP", "Segoe UI"])
	theme = Theme.new()
	theme.default_font = font
	theme.default_font_size = 16
	data_dir = OS.get_environment("AGENTARIUM_DATA_DIR")
	if data_dir.is_empty(): data_dir = OS.get_user_data_dir()
	for folder in [data_dir, data_dir.path_join("inbox"), data_dir.path_join("rejected")]:
		if DirAccess.make_dir_recursive_absolute(folder) != OK: io_error = "保存フォルダーを作成できません"
	_load_builtin_palette()
	_load_state()
	if sync_since == 0:
		sync_since = int(Time.get_unix_time_from_system())
		_save_settings()
	_start_desktop_sync()
	live.changed.connect(_live_changed)
	demo_store.changed.connect(func(id, event_type):
		if event_type == "input.required": _show_question(id, demo_store.tasks[id].title)
		dirty = true)
	if live.tasks.is_empty():
		_seed_demo()
		selected = ""
		demo = false
	else:
		selected = str(live.tasks.keys()[0])
	_setup_tray()
	mascot = not "--theater" in OS.get_cmdline_user_args()
	if "--mascot" in OS.get_cmdline_user_args(): mascot = true
	_apply_window()
	_build()
	if OS.has_environment("GUA_BRIDGE_PORT"):
		bridge = GuaAdapter.new()
		bridge.attach(self)
		if bridge.context == null:
			bridge.dispose()
			bridge = null
			io_error = "Guaのバイナリとアダプターが一致しません"
			return
		var actions: Array[Dictionary] = []
		bridge.configure_game_input_actions("agentarium", actions, true)
		bridge.enable_raw_input()
		bridge.clock_tick.connect(_advance)
		bridge.update("agentarium")
		if not bridge.start_inspector_bridge(int(OS.get_environment("GUA_BRIDGE_PORT"))):
			push_error("Gua bridge could not start")
		else:
			print("Gua: ", bridge.inspector_bridge_url())
	print("Agentarium inbox: ", data_dir.path_join("inbox"))

func _store():
	return demo_store if demo else live

func _ordered_ids() -> Array:
	var store = _store()
	var ids: Array = []
	for id in store.tasks:
		if id not in task_order: task_order.append(id)
	for id in task_order:
		if store.tasks.has(id) and id not in hidden_tasks: ids.append(id)
	return ids

func _content_width() -> float:
	return float(get_window().size.x) - (260.0 if sidebar_open and get_window().size.x>=1000 else 0.0)

func _hide_task(id: String) -> void:
	if not edit_mode: return
	if id not in hidden_tasks: hidden_tasks.append(id)
	if alert_task == id: alert_remaining = 0
	var ids := _ordered_ids()
	if selected == id: selected = str(ids[0]) if not ids.is_empty() else ""
	_reveal_selected()
	_save_settings()
	dirty = true

func _reorder_task(source: String, target: String, after: bool) -> void:
	if not edit_mode: return
	var ids := _ordered_ids()
	if source==target or source not in ids or target not in ids: return
	task_order.erase(source)
	task_order.insert(task_order.find(target)+(1 if after else 0),source)
	selected=source
	_reveal_selected()
	_save_settings()
	dirty=true

func _show_question(id: String, title: String) -> void:
	if id in hidden_tasks: return
	alert_task = id
	alert_title = title
	alert_remaining = 4.5
	dirty = true

func _reveal_selected() -> void:
	var width := _content_width()
	var columns := 3 if width>=1450 else (2 if width>=900 else 1)
	var capacity := columns*(2 if get_window().size.y>=850 else 1) if columns>1 else 1
	page=maxi(0,_ordered_ids().find(selected))/capacity

func _task() -> Dictionary:
	return _store().tasks.get(selected, {"id":"", "title":"まだ、しずかな時間。", "state":"idle", "summary":"イベントが届くと、ペットが目を覚まします。", "pet":"fox", "url":"", "acknowledged":true})

func _seed_demo() -> void:
	demo_store.tasks.clear()
	demo_store.seen.clear()
	var examples := [
		["demo-fox","Agentariumを育てる","fox","task.started","小さなアイデアを、動くかたちに。"],
		["demo-dog","WindowsのCI","dog","task.paused","次のテストまで、ちょっと休憩。"],
		["demo-bird","プルリクエストの確認","bird","task.paused","レビューのお届けを待っています。"]]
	for item in examples:
		demo_store.apply({"id":item[0],"task_id":item[0],"title":item[1],"pet":item[2],"type":item[3],"summary":item[4]})
	selected = "demo-fox"

func _live_changed(id: String, event_type: String) -> void:
	if syncing: return
	demo = false
	var t: Dictionary = live.tasks[id]
	if event_type == "input.required": _show_question(id, t.title)
	if id not in hidden_tasks and (selected not in _ordered_ids() or (t.state in Store.ATTENTION and event_type != "user.acknowledged")):
		selected = id
		_reveal_selected()
	_save_state()
	dirty = true

func _process(delta: float) -> void:
	if bridge != null:
		bridge.update("mascot" if mascot else "theater")
		var c: Dictionary = bridge.context.get_clock()
		if not c.get("installed",false): _advance(delta)
	else:
		_advance(delta)
	poll_accum += delta
	if poll_accum >= 0.5:
		poll_accum = 0
		_poll_inbox()
		_poll_desktop_sync()
	if dirty and not get_viewport().gui_is_dragging():
		dirty = false
		_build()
	if bridge != null:
		screenshot_accum += delta
		if screenshot_accum >= 1.0:
			screenshot_accum = 0
			_capture.call_deferred()

func _advance(delta: float) -> void:
	if alert_remaining > 0:
		alert_remaining = maxf(0, alert_remaining-delta)
		if alert_remaining == 0: dirty = true
	for item in animated:
		if is_instance_valid(item):
			item.advance(delta)

func _capture() -> void:
	await RenderingServer.frame_post_draw
	if bridge != null and get_window().visible:
		bridge.capture_viewport_screenshot()
		var w := get_window()
		var status := {"mascot":mascot,"position":[w.position.x,w.position.y],"size":[w.size.x,w.size.y],"transparent":w.transparent,"transparent_bg":w.transparent_bg,"borderless":w.borderless,"unfocusable":w.unfocusable,"always_on_top":w.always_on_top,"passthrough_points":w.mouse_passthrough_polygon.size(),"tray":tray != null,"quiet":quiet_mode,"reduced_motion":reduced_motion}
		var f := FileAccess.open(data_dir.path_join("gua-window-status.json"),FileAccess.WRITE)
		if f != null: f.store_string(JSON.stringify(status));f.close()

func box(color: Color, radius := 14, border := Color("36364c")) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.set_border_width_all(1)
	s.border_color = border
	s.content_margin_left = 16
	s.content_margin_right = 16
	return s

func label_at(id: String, text: String, rect: Rect2, size_px := 16, color := INK, center := false) -> Label:
	var l := Label.new()
	l.name = id
	l.set_meta("gua_id",id)
	l.text = text
	l.position = rect.position
	l.size = rect.size
	l.add_theme_font_size_override("font_size",size_px)
	l.add_theme_color_override("font_color",color)
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.mouse_filter = MOUSE_FILTER_IGNORE
	if center: l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gui.add_child(l)
	return l

func button_at(id: String, text: String, rect: Rect2, callback: Callable, primary := false) -> Button:
	var b: Button = TaskEntry.new() if id.begins_with("list-") else Button.new()
	b.name = id
	b.set_meta("gua_id",id)
	b.text = text
	b.position = rect.position
	b.size = rect.size
	b.add_theme_stylebox_override("normal",box(ACCENT if primary else Color("252536")))
	b.add_theme_stylebox_override("hover",box(Color("dcc9ff") if primary else Color("38364f")))
	b.add_theme_stylebox_override("pressed",box(Color("a990dc")))
	b.add_theme_stylebox_override("focus",box(Color(0,0,0,0),14,Color("e5d3ff")))
	if rect.size.x < 60:
		for style in ["normal","hover","pressed","focus"]:
			b.get_theme_stylebox(style).content_margin_left=3
			b.get_theme_stylebox(style).content_margin_right=3
	b.add_theme_color_override("font_color",Color("222031") if primary else INK)
	b.add_theme_color_override("font_hover_color",Color("222031") if primary else INK)
	b.pressed.connect(callback)
	gui.add_child(b)
	return b

func _build() -> void:
	animated.clear()
	if gui != null:
		remove_child(gui)
		gui.queue_free()
	gui = Control.new()
	gui.name = "UI"
	gui.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(gui)
	_update_top()
	if mascot:
		_build_mascot()
	else:
		_build_theater()
	if settings_open and not mascot: _build_settings()
	if import_open and not mascot: _build_import()
	if add_open and edit_mode and not mascot: _build_add()
	if alert_remaining > 0: _build_question_alert()

func _item_key(task: Dictionary) -> String:
	if task.get("event_type","")=="ci.failed": return "bomb"
	return {"working":"flask","question":"question","failed":"basin","review":"balloon","completed":"gift","idle":"zzz"}.get(task.state,"zzz")

func _make_pet(rect: Rect2, task: Dictionary) -> Control:
	var p := Pet.new()
	p.position = rect.position
	p.size = rect.size
	p.species = task.pet
	p.state = task.state
	p.accent = Color(STATE_COLORS[task.state])
	p.motion = not reduced_motion and not quiet_mode
	p.set_meta("palette_index",palette_index + absi(str(task.id).hash()) % 4)
	if not custom_sheet.is_empty(): p.sheet_path=custom_sheet
	p.source_hue=pet_source_hue
	p.hue_tolerance=pet_hue_tolerance
	gui.add_child(p)
	animated.append(p)
	var item_key := _item_key(task)
	var icon_path := "res://assets/items/"+item_key+".png"
	if ResourceLoader.exists(icon_path):
		var icon := StatusItem.new()
		icon.texture = load(icon_path)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var side := clampf(rect.size.x*0.32,44,80)
		icon.position = rect.position+Vector2(rect.size.x-side*0.55,0)
		if mascot:
			side=52
			icon.position=rect.position+Vector2(rect.size.x*0.67,24)
		icon.size = Vector2(side,side)
		icon.pivot_offset = icon.size/2
		icon.state = task.state
		icon.motion = not reduced_motion and not quiet_mode
		icon.set_meta("gua_id","item-"+str(task.id))
		icon.tooltip_text = item_key
		gui.add_child(icon)
		animated.append(icon)
	return p

func _build_theater() -> void:
	var w := float(get_window().size.x)
	var h := float(get_window().size.y)
	theater_size = get_window().size
	var bg := ColorRect.new()
	bg.color = Color("11121c")
	bg.size = Vector2(w,h)
	gui.add_child(bg)
	label_at("brand","agentarium",Rect2(24,14,230,40),28)
	button_at("mode-mascot","マスコット",Rect2(w-290,20,120,36),func(): _switch_mode(true))
	button_at("settings","設定",Rect2(w-160,20,64,36),func(): settings_open=not settings_open;dirty=true)
	button_at("quit","終了",Rect2(w-86,20,62,36),_quit)
	label_at("source","DEMO / サンプル" if demo else "CODEX / " + sync_status,Rect2(26,65,w-220,28),13,ACCENT)
	button_at("toggle-demo","実際の作業へ" if demo else "デモを試す",Rect2(w-182,64,158,34),_toggle_demo)
	button_at("toggle-sidebar","☰ 一覧" if not sidebar_open else "☰ 閉じる",Rect2(24,104,108,30),func():sidebar_open=not sidebar_open;_reveal_selected();_save_settings();dirty=true)
	button_at("edit-tasks","完了" if edit_mode else "編集",Rect2(140,104,64,30),func():edit_mode=not edit_mode;add_open=false;dirty=true,edit_mode)
	if edit_mode: button_at("add-task","＋",Rect2(212,104,40,30),func():add_open=true;dirty=true)
	var root_gui := gui
	var content := Control.new()
	content.position.x = 260 if sidebar_open and w>=1000 else 0
	gui.add_child(content)
	gui = content
	w = _content_width()
	var ids: Array = _ordered_ids()
	if selected not in ids: selected = str(ids[0]) if not ids.is_empty() else ""
	var columns := 3 if w >= 1450 else (2 if w >= 900 else 1)
	var rows := 2 if h >= 850 and ids.size()>columns else 1
	var per_page := columns * rows if columns > 1 else 1
	if columns==1: page=maxi(0,ids.find(selected))
	page = clampi(page,0,maxi(0,(ids.size()-1)/per_page))
	var mode_x := 26 if content.position.x>0 else (270 if edit_mode else 216)
	label_at("layout-mode","並列ビュー · %dスレッド" % ids.size() if columns>1 else "個別表示 · %dスレッド" % ids.size(),Rect2(mode_x,106,w-mode_x-130,24),13,MUTED)
	button_at("previous-page","‹",Rect2(w-104,103,34,30),func():page=maxi(0,page-1);selected=str(ids[page]) if columns==1 and not ids.is_empty() else selected;dirty=true)
	button_at("next-page","›",Rect2(w-62,103,34,30),func():page=mini(maxi(0,(ids.size()-1)/per_page),page+1);selected=str(ids[page]) if columns==1 and not ids.is_empty() else selected;dirty=true)
	if columns == 1:
		_build_thread_card(_task(),Rect2(24,144,w-48,h-250),true)
	else:
		var card_width := (w-48-16*(columns-1))/columns
		var card_height := (h-250)/rows
		for i in range(page*per_page,mini((page+1)*per_page,ids.size())):
			var index := i-page*per_page
			var t: Dictionary = _store().tasks[ids[i]]
			_build_thread_card(t,Rect2(24+(index%columns)*(card_width+16),144+(index/columns)*(card_height+12),card_width,card_height),t.id==selected)
		if ids.is_empty(): _build_thread_card(_task(),Rect2(24,144,w-48,h-250),true)
	if demo:
		var demos := [["working","作業中"],["question","質問"],["ci-failed","CI失敗"],["failed","失敗"],["review","レビュー"],["completed","完了"],["idle","休憩"]]
		var bw := (w-60)/7
		for i in demos.size():
			var state: String = demos[i][0]
			var is_ci: bool = _task().get("event_type","")=="ci.failed"
			var active_state: bool = (state=="ci-failed" and is_ci) or (_task().state==state and not (state=="failed" and is_ci))
			button_at("demo-"+state,demos[i][1],Rect2(24+i*(bw+2),h-82,bw,34),func():_demo_event(state),active_state).add_theme_font_size_override("font_size",12)
	label_at("connection-status",io_error if not io_error.is_empty() else ("サンプル表示中" if demo else sync_status),Rect2(26,h-38,w-52,28),12,MUTED)
	gui = root_gui
	if sidebar_open: _build_sidebar()

func _build_sidebar() -> void:
	var root_gui := gui
	var panel := Panel.new()
	panel.position = Vector2(12,144)
	panel.set_meta("gua_id","task-sidebar")
	panel.size = Vector2(248,get_window().size.y-244)
	panel.add_theme_stylebox_override("panel",box(Color("202131"),16))
	gui.add_child(panel)
	gui = panel
	label_at("sidebar-title","タスク一覧",Rect2(12,10,224,26),16)
	label_at("sidebar-help","ドラッグで並べ替え / × 非表示" if edit_mode else "並べ替え・追加は「編集」から",Rect2(12,40,224,22),11,MUTED)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(8,70)
	scroll.size = Vector2(232,panel.size.y-80)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var list := Control.new()
	var ids := _ordered_ids()
	list.custom_minimum_size = Vector2(218,maxf(1,ids.size()*56))
	scroll.add_child(list)
	gui = list
	for i in ids.size():
		var id: String = ids[i]
		var t: Dictionary = _store().tasks[id]
		var entry := button_at("list-"+id,t.title,Rect2(0,i*56,178 if edit_mode else 214,48),func():selected=id;_reveal_selected();sidebar_open=get_window().size.x>=1000;dirty=true,id==selected)
		entry.alignment=HORIZONTAL_ALIGNMENT_LEFT
		for style in ["normal","hover","pressed","focus"]:
			entry.get_theme_stylebox(style).content_margin_left=42
			entry.get_theme_stylebox(style).content_margin_right=6
		entry.add_theme_font_size_override("font_size",14)
		entry.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		entry.tooltip_text=t.title+"\n"+STATE_NAMES[t.state]+("\nドラッグして並べ替え" if edit_mode else "")
		var stamp := TextureRect.new()
		stamp.name="stamp-"+_item_key(t)
		stamp.set_meta("gua_id","stamp-"+id)
		stamp.texture=load("res://assets/items/"+_item_key(t)+".png")
		stamp.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		stamp.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		stamp.position=Vector2(2,4)
		stamp.size=Vector2(40,40)
		stamp.mouse_filter=MOUSE_FILTER_IGNORE
		entry.add_child(stamp)
		entry.set("task_id",id)
		entry.set("reorder_enabled",edit_mode)
		entry.mouse_default_cursor_shape=Control.CURSOR_DRAG if edit_mode else Control.CURSOR_POINTING_HAND
		entry.connect("reorder_requested",_reorder_task)
		if edit_mode:
			button_at("hide-"+id,"×",Rect2(184,i*56+8,30,32),func():_hide_task(id))
	gui = root_gui

func _build_add() -> void:
	var root_gui := gui
	var panel := Panel.new()
	panel.position = Vector2((get_window().size.x-500)/2,140)
	panel.size = Vector2(500,440)
	panel.add_theme_stylebox_override("panel",box(Color("292738"),20,ACCENT))
	gui.add_child(panel)
	gui = panel
	label_at("add-title","タスク項目を追加",Rect2(20,16,390,32),23)
	button_at("close-add","×",Rect2(444,16,36,32),func():add_open=false;dirty=true)
	label_at("add-help","Codexスレッドのディープリンクを貼り付けて接続します。",Rect2(20,58,460,26),12,MUTED)
	var input := LineEdit.new()
	input.set_meta("gua_id","new-task-name")
	input.position=Vector2(20,94)
	input.size=Vector2(340,38)
	input.placeholder_text="codex://threads/スレッドID"
	input.max_length=200
	input.text=new_task_name
	input.text_changed.connect(func(value):new_task_name=value)
	gui.add_child(input)
	button_at("create-task","＋ 追加",Rect2(370,94,110,38),func():
		new_task_name=input.text
		_connect_thread(new_task_name))
	label_at("add-error",io_error,Rect2(20,135,460,24),11,Color("f4a49d"))
	label_at("restore-heading","表示から外したタスクを戻す",Rect2(20,162,450,26),16)
	var scroll := ScrollContainer.new()
	scroll.position=Vector2(20,188)
	scroll.size=Vector2(460,226)
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	gui.add_child(scroll)
	var list := Control.new()
	scroll.add_child(list)
	gui=list
	var row := 0
	for id in hidden_tasks:
		if not _store().tasks.has(id): continue
		var restore_id: String=id
		var entry := button_at("restore-"+id,"＋ "+_store().tasks[id].title,Rect2(0,row*44,440,38),func():hidden_tasks.erase(restore_id);selected=restore_id;_reveal_selected();_save_settings();add_open=false;dirty=true)
		entry.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		row+=1
	list.custom_minimum_size=Vector2(440,maxi(1,row)*44)
	if row==0: label_at("restore-empty","外したタスクはありません",Rect2(0,0,440,32),14,MUTED)
	gui=root_gui

func _connect_thread(value: String) -> void:
	if not edit_mode: return
	var pattern := RegEx.new()
	pattern.compile("^codex://threads/([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})/?$")
	var matched := pattern.search(value.strip_edges())
	if matched==null:
		io_error="codex://threads/UUID 形式のリンクを入力してください"
		dirty=true
		return
	var id := matched.get_string(1).to_lower()
	if not live.tasks.has(id):
		if not live.apply({"id":"link-"+str(Time.get_ticks_usec()),"task_id":id,"type":"task.paused","title":"接続待ち · "+id.left(8),"summary":"この端末のCodexから名前・状態を取得します","url":"codex://threads/"+id}):
			io_error=live.last_error;dirty=true;return
	live.tasks[id]["linked"]=true
	hidden_tasks.erase(id)
	demo=false
	selected=id
	_reveal_selected()
	io_error=""
	new_task_name=""
	add_open=false
	_save_state()
	_save_settings()
	dirty=true

func _build_question_alert() -> void:
	var full := button_at("question-alert","質問が来ました！",Rect2(Vector2.ZERO,Vector2(get_window().size)),func():alert_remaining=0;selected=alert_task;_reveal_selected();dirty=true)
	full.add_theme_font_size_override("font_size",32 if mascot else (64 if get_window().size.x>=900 else 44))
	full.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	for style in ["normal","hover","pressed"]:
		full.add_theme_stylebox_override(style,box(Color("662638"),0,Color("ffb94f")))
	full.add_theme_color_override("font_color",Color("fff2c9"))
	full.add_theme_color_override("font_hover_color",Color("fff2c9"))
	var parent_gui := gui
	gui=full
	var width := float(get_window().size.x)
	var height := float(get_window().size.y)
	label_at("alert-symbol","！",Rect2(0,height/2-(120 if mascot else 210),width,110),70 if mascot else 110,Color("ffc568"),true)
	label_at("alert-thread",alert_title.left(100),Rect2(24,height/2+50,width-48,60),14 if mascot else 24,INK,true).autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label_at("alert-dismiss","クリックですぐ閉じる · 数秒後に自動で閉じます",Rect2(20,height-65,width-40,45),12 if mascot else 18,Color("ffc568"),true).autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	for y in [0.0,height-12]:
		var stripe := ColorRect.new()
		stripe.color=Color("ffc568")
		stripe.position=Vector2(0,y)
		stripe.size=Vector2(width,12)
		stripe.mouse_filter=MOUSE_FILTER_IGNORE
		full.add_child(stripe)
	gui=parent_gui
	if mascot: get_window().mouse_passthrough_polygon=PackedVector2Array()
	if not reduced_motion and not quiet_mode:
		var tween := full.create_tween().set_loops()
		tween.tween_property(full,"modulate",Color("ffd5ad"),0.8)
		tween.tween_property(full,"modulate",Color.WHITE,0.8)

func _build_thread_card(task: Dictionary, rect: Rect2, active: bool) -> void:
	var color := Color(STATE_COLORS[task.state])
	var stage := Stage.new()
	stage.position = rect.position
	stage.size = rect.size
	stage.state = task.state
	stage.accent = color
	stage.motion = not reduced_motion and not quiet_mode
	stage.strong_effects = task.state == "question" or (not quiet_mode and not task.acknowledged)
	gui.add_child(stage)
	animated.append(stage)
	var x := rect.position.x
	var y := rect.position.y
	var w := rect.size.x
	var h := rect.size.y
	var suffix: String = "" if active else "-"+str(task.id)
	var title := label_at("thread-title"+suffix,task.title,Rect2(x+18,y+12,w-78,52),18)
	if edit_mode and not str(task.id).is_empty(): button_at("remove-"+str(task.id),"×",Rect2(x+w-48,y+12,30,30),func():_hide_task(task.id))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.tooltip_text = "このスレッド: " + task.title
	label_at("thread-identity"+suffix,"CODEX スレッド" if str(task.id).length()==36 else "スレッド",Rect2(x+18,y+64,w-36,19),10,MUTED)
	label_at("state"+suffix,("⚠ 回答が必要です · 質問待ち" if task.state=="question" else STATE_NAMES[task.state])+(" ●" if not task.acknowledged else ""),Rect2(x+18,y+86,w-36,24),14,color)
	var portrait := h>=380
	var pet_size := minf(260,h-244) if portrait else minf(200,h-166)
	_make_pet(Rect2(x+(w-pet_size)/2 if portrait else x+w-pet_size-18,y+160+(h-244-pet_size)/2 if portrait else y+86,pet_size,pet_size),task)
	var headline: String = HEADLINES[task.state]
	if task.state == "failed" and task.get("event_type","") != "ci.failed": headline = "あっ。うまくいかなかった。"
	var caption := label_at("headline"+suffix,headline if not quiet_mode else STATE_NAMES[task.state],Rect2(x+18,y+116,w-36 if portrait else w-pet_size-42,38),20 if portrait else 18,INK,portrait)
	caption.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label_at("task-summary"+suffix,task.summary,Rect2(x+18,y+h-72,w-36,26),12,MUTED).tooltip_text=task.summary
	if not str(task.get("github_status","")).is_empty():
		label_at("github-status"+suffix,task.github_status,Rect2(x+18,y+h-96,w-36,22),11,MUTED).tooltip_text=task.github_status+"\n"+str(task.get("github_url",""))
	var ack := button_at("acknowledge"+suffix,"確認した",Rect2(x+18,y+h-40,102,30),func():selected=task.id;_acknowledge())
	ack.disabled=task.acknowledged
	var open := button_at("open-task"+suffix,"スレッドを開く ↗",Rect2(x+130,y+h-40,160,30),func():selected=task.id;_open_task(),active)
	open.disabled=task.url.is_empty()
	var github_url: String = str(task.get("github_url",""))
	if w>=450 and github_url.begins_with("https://github.com/") and Store.safe_url(github_url):
		button_at("open-github"+suffix,"GitHub ↗",Rect2(x+302,y+h-40,112,30),func():OS.shell_open(github_url))

func _build_mascot() -> void:
	var task := _task()
	# Only the visible card + pet silhouette accept mouse input.
	var card := Panel.new()
	card.position = Vector2(25,8)
	card.size = Vector2(310,76)
	card.add_theme_stylebox_override("panel",box(Color("242333"),18))
	gui.add_child(card)
	label_at("mascot-state",("DEMO · " if demo else "")+STATE_NAMES[task.state]+(" ●" if not task.acknowledged else ""),Rect2(40,15,277,25),15,Color(STATE_COLORS[task.state]),true)
	label_at("mascot-summary",task.title,Rect2(40,43,277,29),14,INK,true)
	_make_pet(Rect2(70,79,220,208),task)
	var hit := button_at("mascot-pet","",Rect2(106,101,153,163),func(): pass)
	for style in ["normal","hover","pressed","focus"]: hit.add_theme_stylebox_override(style,StyleBoxEmpty.new())
	hit.tooltip_text = "ドラッグで移動 / ダブルクリックで劇場"
	hit.gui_input.connect(_pet_input)
	button_at("mode-theater","劇場を開く",Rect2(48,275,132,35),func(): _switch_mode(false))
	button_at("mascot-next","次のペット ›",Rect2(188,275,125,35),_next_pet)
	get_window().mouse_passthrough_polygon = PackedVector2Array([Vector2(25,8),Vector2(335,8),Vector2(335,84),Vector2(280,84),Vector2(290,230),Vector2(313,275),Vector2(313,310),Vector2(48,310),Vector2(48,275),Vector2(70,230),Vector2(80,84),Vector2(25,84)])

func _build_settings() -> void:
	var root_gui := gui
	var overlay := Control.new()
	overlay.position = Vector2(maxf(16,get_window().size.x-474),76)
	gui.add_child(overlay)
	gui=overlay
	var panel := Panel.new()
	panel.size=Vector2(450,510)
	panel.add_theme_stylebox_override("panel",box(Color("292738"),20,Color("625374")))
	gui.add_child(panel)
	label_at("settings-title","小さな同居人の設定",Rect2(24,16,400,36),23)
	button_at("focus-mode","集中モード : "+("ON" if quiet_mode else "OFF"),Rect2(24,64,400,40),func():quiet_mode=not quiet_mode;_save_settings();dirty=true)
	button_at("reduced-motion","動きを減らす : "+("ON" if reduced_motion else "OFF"),Rect2(24,114,400,40),func():reduced_motion=not reduced_motion;_save_settings();dirty=true)
	button_at("top-mode","最前面 : "+["通常","常に","未確認の重要イベント時"][top_mode],Rect2(24,164,400,40),func():top_mode=(top_mode+1)%3;_save_settings();dirty=true)
	button_at("desktop-sync","Codex自動同期 : "+("ON" if desktop_sync else "OFF"),Rect2(24,214,400,40),func():desktop_sync=not desktop_sync;_start_desktop_sync();_save_settings();dirty=true)
	button_at("palette-swap","毛色 · %d" % (palette_index+1),Rect2(24,264,195,40),func():palette_index=(palette_index+1)%4;_save_settings();dirty=true)
	button_at("import-pet","ペットを取り込む",Rect2(229,264,195,40),_choose_pet)
	button_at("layout-compact","小さなウィンドウ",Rect2(24,314,195,40),func():get_window().size=Vector2i(640,760);settings_open=false;dirty=true)
	button_at("layout-wide","大きなウィンドウ",Rect2(229,314,195,40),func():get_window().size=Vector2i(1600,900);settings_open=false;dirty=true)
	label_at("settings-info","自動同期はローカルの名前・実行状態だけを読み取ります。\n入力待ちの詳細は、元のCodexスレッドで確認してください。",Rect2(24,370,400,52),12,MUTED)
	button_at("close-settings","できた",Rect2(24,432,400,42),func():settings_open=false;dirty=true,true)
	gui=root_gui

func _toggle_demo() -> void:
	demo = not demo
	if demo: _seed_demo()
	else: selected = str(live.tasks.keys()[0]) if not live.tasks.is_empty() else ""
	page = 0
	dirty = true

func _demo_event(state: String) -> void:
	var types := {"working":"task.started","question":"input.required","ci-failed":"ci.failed","failed":"task.failed","review":"review.received","completed":"task.completed","idle":"task.paused"}
	var summaries := {"working":"実装中。ここは私たちに任せて。", "question":"実装方針を選んでほしいな。元のタスクで回答してね。", "ci-failed":"Windowsのテストが失敗。原因を確認してほしいな。", "failed":"作業でエラーが発生。元のタスクを確認してね。", "review":"プルリクエストに指摘が届いたよ。", "completed":"成果物を用意したよ。受け取ってね。", "idle":"次の仕事まで、ちょっと休憩。"}
	selected = "demo-dog" if state in ["failed","ci-failed"] else ("demo-bird" if state=="review" else "demo-fox")
	demo_store.apply({"id":str(Time.get_ticks_usec()),"task_id":selected,"type":types[state],"summary":summaries[state]})
	_reveal_selected()

func _acknowledge() -> void:
	if selected.is_empty(): return
	if _task().acknowledged: return
	if alert_task == selected: alert_remaining = 0
	_store().apply({"id":"ack-"+str(Time.get_ticks_usec()),"task_id":selected,"type":"user.acknowledged"})
	_reveal_selected()
	dirty = true

func _open_task() -> void:
	var url: String = _task().url
	if not url.is_empty() and Store.safe_url(url):
		var result := OS.shell_open(url)
		if result != OK: io_error = "作業のリンクを開けませんでした"
		# Opening the source does not resolve or acknowledge an event.
		dirty = true

func _next_pet() -> void:
	var ids: Array = _ordered_ids()
	if not ids.is_empty(): selected = ids[(ids.find(selected)+1)%ids.size()]
	dirty = true

func _pet_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.double_click:
			dragging = false
			_switch_mode(false)
		elif event.pressed:
			dragging = true
			drag_origin = DisplayServer.mouse_get_position()
			drag_window_origin = get_window().position
		else:
			dragging = false
			mascot_position = get_window().position
			_save_settings()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and dragging:
		get_window().position += Vector2i(event.relative)
	if event is InputEventMouseButton and not event.pressed and dragging:
		dragging = false
		mascot_position = get_window().position
		_save_settings()

func _switch_mode(value: bool) -> void:
	if mascot: mascot_position = get_window().position
	else: theater_position = get_window().position
	mascot = value
	settings_open = false
	_apply_window()
	_save_settings()
	dirty = true

func _apply_window() -> void:
	var w := get_window()
	w.unresizable = mascot
	w.min_size = Vector2i(360,320) if mascot else Vector2i(560,640)
	w.mouse_passthrough_polygon = PackedVector2Array()
	w.transparent_bg = mascot
	w.transparent = mascot
	w.borderless = mascot
	w.unfocusable = mascot
	w.size = Vector2i(360,320) if mascot else theater_size
	w.position = _clamp_position(mascot_position if mascot else theater_position,w.size)
	w.title = "Agentarium — AIの仕事が、ひと目で生きて見える。"
	w.show()
	_update_top()

func _clamp_position(pos: Vector2i, window_size: Vector2i) -> Vector2i:
	var rect := DisplayServer.screen_get_usable_rect()
	for i in DisplayServer.get_screen_count():
		var candidate := DisplayServer.screen_get_usable_rect(i)
		if candidate.has_point(pos+Vector2i(80,40)): rect = candidate; break
	return Vector2i(clampi(pos.x,rect.position.x,maxi(rect.position.x,rect.end.x-window_size.x)),clampi(pos.y,rect.position.y,maxi(rect.position.y,rect.end.y-window_size.y)))

func _update_top() -> void:
	var attention := false
	for t in _store().tasks.values():
		if not t.acknowledged: attention = true
	get_window().always_on_top = top_mode == 1 or (top_mode == 2 and attention and not quiet_mode)

func _setup_tray() -> void:
	if DisplayServer.get_name() == "headless": return
	if not DisplayServer.has_feature(DisplayServer.FEATURE_STATUS_INDICATOR): return
	tray = StatusIndicator.new()
	tray.name = "Tray"
	tray.icon = load("res://assets/icon.svg")
	tray.tooltip = "Agentarium — クリックで劇場 / 右クリックでメニュー"
	add_child(tray)
	var menu := PopupMenu.new()
	menu.name = "TrayMenu"
	menu.prefer_native_menu = true
	menu.add_item("劇場を開く",0)
	menu.add_item("マスコットを表示",1)
	menu.add_item("集中モード切り替え",2)
	menu.add_separator()
	menu.add_item("終了",3)
	tray.add_child(menu)
	tray.menu = NodePath("TrayMenu")
	menu.id_pressed.connect(_tray_action)
	tray.pressed.connect(func(button,_position):
		if button == MOUSE_BUTTON_LEFT: _switch_mode(false))

func _tray_action(id: int) -> void:
	match id:
		0: _switch_mode(false)
		1: _switch_mode(true)
		2:
			quiet_mode = not quiet_mode
			_save_settings()
			dirty = true
		3: _quit()

func _close_requested() -> void:
	if tray != null: _switch_mode(true)
	else: _quit()

func _quit() -> void:
	_save_settings()
	_save_state()
	# Allow Gua's correlated click completion to reach the client before shutdown.
	get_tree().create_timer(0.25).timeout.connect(func(): get_tree().quit())

func _exit_tree() -> void:
	if sync_pid > 0 and OS.is_process_running(sync_pid): OS.kill(sync_pid)
	if bridge != null: bridge.dispose()

func _load_state() -> void:
	var path := data_dir.path_join("tasks.json")
	if FileAccess.file_exists(path):
		if not live.restore(JSON.parse_string(FileAccess.get_file_as_string(path))):
			io_error = "保存済みタスクを読めません: " + live.last_error
	var cfg := ConfigFile.new()
	if cfg.load(data_dir.path_join("settings.cfg")) == OK:
		quiet_mode = bool(cfg.get_value("display","focus",false))
		desktop_sync = bool(cfg.get_value("sync","enabled",true))
		sync_since = int(cfg.get_value("sync","since",0))
		palette_index = int(cfg.get_value("display","palette",0))
		sidebar_open = bool(cfg.get_value("display","sidebar",true))
		var saved_hidden: Variant = cfg.get_value("tasks","hidden",[])
		var saved_order: Variant = cfg.get_value("tasks","order",[])
		if saved_hidden is Array: hidden_tasks=saved_hidden
		if saved_order is Array: task_order=saved_order
		custom_sheet = str(cfg.get_value("display","custom_sheet",""))
		pet_source_hue = float(cfg.get_value("display","pet_source_hue",pet_source_hue))
		pet_hue_tolerance = float(cfg.get_value("display","pet_hue_tolerance",0.11))
		if not custom_sheet.is_empty() and not FileAccess.file_exists(custom_sheet): custom_sheet=""
		reduced_motion = bool(cfg.get_value("display","reduced_motion",false))
		top_mode = clampi(int(cfg.get_value("display","top",2)),0,2)
		var mp: Variant = cfg.get_value("display","mascot_position",mascot_position)
		var tp: Variant = cfg.get_value("display","theater_position",theater_position)
		if mp is Vector2i: mascot_position = mp
		if tp is Vector2i: theater_position = tp

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("sync","enabled",desktop_sync)
	cfg.set_value("sync","since",sync_since)
	cfg.set_value("display","sidebar",sidebar_open)
	cfg.set_value("tasks","hidden",hidden_tasks)
	cfg.set_value("tasks","order",task_order)
	cfg.set_value("display","palette",palette_index)
	cfg.set_value("display","custom_sheet",custom_sheet)
	cfg.set_value("display","pet_source_hue",pet_source_hue)
	cfg.set_value("display","pet_hue_tolerance",pet_hue_tolerance)
	cfg.set_value("display","focus",quiet_mode)
	cfg.set_value("display","reduced_motion",reduced_motion)
	cfg.set_value("display","top",top_mode)
	cfg.set_value("display","mascot_position",mascot_position)
	cfg.set_value("display","theater_position",theater_position)
	if cfg.save(data_dir.path_join("settings.cfg")) != OK: io_error = "設定を保存できません"

func _save_state() -> bool:
	var path := data_dir.path_join("tasks.json")
	var f := FileAccess.open(path+".tmp",FileAccess.WRITE)
	if f == null:
		io_error = "タスクを保存できません"
		return false
	f.store_string(JSON.stringify(live.snapshot()))
	f.close()
	if DirAccess.rename_absolute(path+".tmp",path) != OK:
		io_error = "タスク保存を確定できません"
		return false
	return true

func _poll_inbox() -> void:
	var folder := data_dir.path_join("inbox")
	var files := DirAccess.get_files_at(folder)
	files.sort()
	var processed := 0
	for file in files:
		if not file.ends_with(".json"): continue
		if processed >= 20: break
		processed += 1
		var path := folder.path_join(file)
		var f := FileAccess.open(path,FileAccess.READ)
		if f == null: continue
		var valid_size := f.get_length() <= 16384
		var payload := f.get_as_text() if valid_size else ""
		f.close()
		if valid_size and live.apply(JSON.parse_string(payload)):
			if _save_state(): DirAccess.remove_absolute(path)
		else:
			io_error = "受信イベントを拒否: " + (live.last_error if valid_size else "16KBを超えています")
			DirAccess.rename_absolute(path,data_dir.path_join("rejected").path_join(file))
			push_warning(io_error)
			dirty = true

func _start_desktop_sync() -> void:
	if sync_pid > 0 and OS.is_process_running(sync_pid): OS.kill(sync_pid)
	sync_pid = -1
	sync_stamp = ""
	sync_initialized = false
	if not desktop_sync or OS.get_environment("AGENTARIUM_DISABLE_SYNC") == "1":
		sync_status = "自動同期 OFF"
		return
	var base := ProjectSettings.globalize_path("res://") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir()
	var python := base.path_join("runtime/python/pythonw.exe")
	var worker := base.path_join("scripts/desktop_sync.py")
	var home := OS.get_environment("CODEX_HOME")
	if home.is_empty(): home = OS.get_environment("USERPROFILE").path_join(".codex")
	if not FileAccess.file_exists(python) or not FileAccess.file_exists(worker):
		sync_status = "自動同期ランタイムがありません"
		return
	sync_pid = OS.create_process(python,PackedStringArray([worker,"--home",home,"--output",data_dir.path_join("desktop-sync.json"),"--watch-file",data_dir.path_join("tasks.json"),"--since",str(sync_since),"--parent",str(OS.get_process_id())]),false)
	sync_status = "Codexに接続中" if sync_pid > 0 else "自動同期を起動できません"

func _poll_desktop_sync() -> void:
	if sync_pid <= 0: return
	if not OS.is_process_running(sync_pid):
		if sync_status!="自動同期が停止しました。設定でONにし直してください":
			sync_status="自動同期が停止しました。設定でONにし直してください"
			dirty=true
		return
	var path := data_dir.path_join("desktop-sync.json")
	if not FileAccess.file_exists(path): return
	var raw := FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(raw)
	if not data is Dictionary: return
	if Time.get_unix_time_from_system()-float(data.get("generated_at",0))>10:
		if sync_status != "同期が停止しています（表示は最終取得時点）":
			sync_status = "同期が停止しています（表示は最終取得時点）"
			dirty=true
		return
	if raw == sync_stamp: return
	sync_stamp=raw
	if not data.get("ok",false):
		sync_status=str(data.get("error","同期できません"))
		dirty=true
		return
	var old_status := sync_status
	sync_status="自動同期中 · 2秒間隔 · 直近24件＋リンク追加分"
	if old_status != sync_status: dirty=true
	var initial: bool = live.tasks.is_empty()
	syncing=true
	var current: Array = []
	var added: Array = []
	for t in data.get("threads",[]):
		var id: String = t.id
		if not Store.safe_url("codex://threads/"+id): continue
		current.append(id)
		var revision: String = t.revision
		var previous: Dictionary = live.tasks.get(id,{})
		# Preserve acknowledged GitHub events across restart while the first
		# asynchronous request is pending; do not briefly replace then re-alert.
		if t.state != "question" and str(t.get("github_status","")) == "GitHub: 確認中" and str(previous.get("desktop_revision","")).begins_with("github:"):
			continue
		if sync_initialized and previous.is_empty() and id not in task_order and id not in hidden_tasks:
			added.append(id)
		var changed_state: bool = sync_revisions.get(id,previous.get("desktop_revision","")) != revision
		if changed_state or previous.is_empty():
			var types := {"working":"task.started","completed":"task.completed","failed":"task.failed","idle":"task.paused"}
			var event_type: String = str(t.get("event_type",types.get(t.state,"task.paused")))
			if event_type not in ["input.required","ci.failed","review.received","task.started","task.completed","task.failed","task.paused"]: continue
			if not live.apply({"id":"desktop-"+str(Time.get_ticks_usec())+id,"task_id":id,"type":event_type,"title":t.title,"summary":t.summary,"url":"codex://threads/"+id}):
				sync_status="スレッド情報を読み込めません: "+live.last_error
				dirty=true
				continue
			live.tasks[id]["desktop_revision"]=revision
			if event_type == "input.required":
				_show_question(id,t.title)
			elif alert_task == id:
				alert_remaining=0
			if initial and t.state=="completed": live.tasks[id].acknowledged=true
			sync_revisions[id]=revision
			dirty=true
		elif previous.title != t.title:
			live.tasks[id].title=t.title
			dirty=true
		for field in ["github_status","github_url"]:
			if live.tasks[id].get(field,"") != t.get(field,""):
				live.tasks[id][field]=t.get(field,"")
				dirty=true
	for id in live.tasks.keys():
		if live.tasks[id].get("linked",false) and id not in current:
			if live.tasks[id].summary!="この端末でスレッドを確認できません":
				live.tasks[id].state="idle"
				live.tasks[id].acknowledged=true
				live.tasks[id].summary="この端末でスレッドを確認できません"
				if live.tasks[id].title.begins_with("接続待ち"): live.tasks[id].title="未接続 · "+str(id).left(8)
				live.tasks[id].erase("desktop_revision")
				sync_revisions.erase(id)
				dirty=true
			continue
		if live.tasks[id].has("desktop_revision") and id not in current:
			live.tasks.erase(id)
			dirty=true
	syncing=false
	sync_initialized=true
	if not added.is_empty():
		# New tasks must be visible without scrolling to the end. Keep the
		# relative order of existing tasks and never restore hidden tasks.
		for i in range(added.size()-1,-1,-1):
			task_order.push_front(added[i])
		if not demo:
			selected=str(added[0])
			_reveal_selected()
		_save_settings()
	if initial and not current.is_empty(): demo=false
	if not live.tasks.has(selected) and not demo:
		selected=str(live.tasks.keys()[0]) if not live.tasks.is_empty() else ""
	if dirty: _save_state()

func _choose_pet() -> void:
	import_open=true
	dirty=true

func _build_import() -> void:
	var panel := Panel.new()
	panel.position=Vector2((get_window().size.x-510)/2,180)
	panel.size=Vector2(510,310)
	panel.add_theme_stylebox_override("panel",box(Color("292738"),18,ACCENT))
	gui.add_child(panel)
	var root_gui := gui
	gui=panel
	label_at("import-title","ペットZIPを取り込む",Rect2(20,16,470,36),23)
	label_at("import-help","ダウンロードしたZIPのフルパスを貼り付けてください。",Rect2(20,64,470,28),13,MUTED)
	var path := LineEdit.new()
	path.name="import-pet-path"
	path.set_meta("gua_id","import-pet-path")
	path.position=Vector2(20,104)
	path.size=Vector2(470,40)
	path.placeholder_text="C:/Users/.../Downloads/agentarium-pet.zip"
	path.text=import_path_text
	path.text_changed.connect(func(value):import_path_text=value)
	panel.add_child(path)
	button_at("import-cancel","キャンセル",Rect2(20,168,180,40),func():import_open=false;dirty=true)
	button_at("import-confirm","取り込む",Rect2(214,168,276,40),func():_import_pet(path.text.strip_edges().trim_prefix('"').trim_suffix('"')),true)
	label_at("import-error",io_error,Rect2(20,220,470,36),12,Color("f4a49d"))
	button_at("reset-pet","標準のLumiに戻す",Rect2(20,263,470,32),func():custom_sheet="";_load_builtin_palette();palette_index=0;import_open=false;settings_open=false;io_error="";_save_settings();dirty=true)
	gui=root_gui
	path.grab_focus()

func _import_pet(path: String) -> void:
	var file := FileAccess.open(path,FileAccess.READ)
	if file==null: io_error="ペットファイルを開けません";dirty=true;return
	if file.get_length()>20*1024*1024: io_error="ペットZIPは20 MiBまでです";dirty=true;return
	file.close()
	if not _pet_zip_is_bounded(path): io_error="ペットZIPの展開サイズ・構造を確認してください";dirty=true;return
	var zip := ZIPReader.new()
	if zip.open(path)!=OK: io_error="ZIPを開けません";dirty=true;return
	var manifest: Variant=JSON.parse_string(zip.read_file("pet.json").get_string_from_utf8())
	if not manifest is Dictionary or manifest.get("spritesheetPath","") not in ["spritesheet.webp","spritesheet.png"]:
		io_error="pet.jsonの画像パスを確認してください";dirty=true;zip.close();return
	var bytes := zip.read_file(manifest.spritesheetPath)
	var image := Image.new()
	var error := image.load_webp_from_buffer(bytes) if manifest.spritesheetPath.ends_with(".webp") else image.load_png_from_buffer(bytes)
	if error!=OK or image.get_width()!=1536 or image.get_height() not in [1872,2288] or image.detect_alpha()==Image.ALPHA_NONE:
		io_error="透明な1536×1872 / 1536×2288画像が必要です";dirty=true;zip.close();return
	var expected := 2 if image.get_height()==2288 else 1
	if int(manifest.get("spriteVersionNumber",expected))!=expected:
		io_error="ペット画像とバージョンが一致しません";dirty=true;zip.close();return
	var palette: Variant=JSON.parse_string(zip.read_file("palette.json").get_string_from_utf8()) if zip.file_exists("palette.json") else {}
	if palette is Dictionary:
		pet_source_hue=clampf(float(palette.get("sourceHue",0.72)),0,1)
		pet_hue_tolerance=clampf(float(palette.get("hueTolerance",0.11)),0.01,0.2)
	zip.close()
	var folder := data_dir.path_join("pets")
	DirAccess.make_dir_recursive_absolute(folder)
	# Only a decoded image is written, under an app-owned content hash. Never extract ZIP paths.
	var target := folder.path_join(FileAccess.get_sha256(path)+".png")
	if image.save_png(target)!=OK: io_error="ペット画像を保存できません";dirty=true;return
	import_open=false
	Pet.texture_cache.clear()
	custom_sheet=target
	palette_index=0
	io_error=""
	_save_settings()
	settings_open=false
	dirty=true

func _load_builtin_palette() -> void:
	var path := "res://assets/pets/lumi/palette.json"
	if not FileAccess.file_exists(path): return
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary:
		pet_source_hue=float(data.get("sourceHue",0.72))
		pet_hue_tolerance=float(data.get("hueTolerance",0.11))

func _pet_zip_is_bounded(path: String) -> bool:
	var bytes := FileAccess.get_file_as_bytes(path)
	var end := -1
	for offset in range(bytes.size()-22,maxi(-1,bytes.size()-65558),-1):
		if bytes.decode_u32(offset)==0x06054b50:
			end=offset
			break
	if end<0: return false
	var count := bytes.decode_u16(end+10)
	if count<2 or count>8 or bytes.decode_u16(end+4)!=0 or bytes.decode_u16(end+6)!=0: return false
	var cursor := bytes.decode_u32(end+16)
	var total := 0
	for _i in count:
		if cursor+46>bytes.size() or bytes.decode_u32(cursor)!=0x02014b50: return false
		var expanded := bytes.decode_u32(cursor+24)
		if expanded>20*1024*1024: return false
		total+=expanded
		if total>24*1024*1024: return false
		cursor+=46+bytes.decode_u16(cursor+28)+bytes.decode_u16(cursor+30)+bytes.decode_u16(cursor+32)
	return cursor<=end
