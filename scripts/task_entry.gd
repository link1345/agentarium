extends Button
signal reorder_requested(source: String, target: String, after: bool)
var task_id := ""
var reorder_enabled := false
var drop_mark := false
var drop_after := false
var drag_armed := false
var drag_origin := Vector2.ZERO
static var active_task := ""
static var pointer := Vector2.ZERO

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_DRAG if reorder_enabled else Control.CURSOR_POINTING_HAND
	mouse_exited.connect(func(): drop_mark=false;queue_redraw())

func _preview() -> Label:
	var preview := Label.new()
	preview.text = text
	preview.add_theme_color_override("font_color",Color("fff0ce"))
	preview.add_theme_font_size_override("font_size",16)
	return preview

func _gui_input(event: InputEvent) -> void:
	if not reorder_enabled: return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		drag_armed=event.pressed
		drag_origin=event.position
	elif event is InputEventMouseMotion and drag_armed and event.position.distance_to(drag_origin)>10:
		drag_armed=false
		if not get_viewport().gui_is_dragging():
			active_task=task_id
			force_drag({"kind":"agentarium-task", "id":task_id},_preview())

func _get_drag_data(_position: Vector2) -> Variant:
	if not reorder_enabled: return null
	drag_armed=false
	active_task=task_id
	set_drag_preview(_preview())
	return {"kind":"agentarium-task", "id":task_id}

func _can_drop_data(at: Vector2, data: Variant) -> bool:
	drop_mark = reorder_enabled and data is Dictionary and data.get("kind")=="agentarium-task" and data.get("id") is String and data.id!=task_id
	drop_after = at.y>=size.y/2
	queue_redraw()
	return drop_mark

func _drop_data(at: Vector2, data: Variant) -> void:
	if active_task==data.get("id") and _can_drop_data(at,data):
		active_task=""
		reorder_requested.emit(data.id,task_id,drop_after)
	drop_mark=false
	queue_redraw()

func _notification(what: int) -> void:
	if what==NOTIFICATION_DRAG_END:
		active_task=""
		drag_armed=false
		drop_mark=false
		queue_redraw()

func _input(event: InputEvent) -> void:
	if not reorder_enabled: return
	if event is InputEventMouseMotion:
		pointer=event.position
		if not active_task.is_empty():
			drop_mark=active_task!=task_id and _contains_pointer()
			drop_after=pointer.y>=get_global_rect().get_center().y
			queue_redraw()
	elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed and not active_task.is_empty():
		pointer=event.position
		if _contains_pointer():
			var source := active_task
			active_task=""
			if source!=task_id: reorder_requested.emit(source,task_id,pointer.y>=get_global_rect().get_center().y)

func _contains_pointer() -> bool:
	return get_global_rect().has_point(pointer) and get_parent().get_parent().get_global_rect().has_point(pointer)

func _draw() -> void:
	if drop_mark:
		var y := size.y-2 if drop_after else 2.0
		draw_line(Vector2(0,y),Vector2(size.x,y),Color("ffd18d"),3,true)
