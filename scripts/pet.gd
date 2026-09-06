extends Control
## Original vector pet pack: no external art, emoji fonts or network required.
var species := "fox"
var state := "working"
var motion := true
var elapsed := 0.0
var accent := Color("bca3ff")
var atlas: Texture2D
var sleeping: Texture2D
var source_hue := 0.72
var hue_tolerance := 0.11
var sheet_path := "res://assets/pets/lumi/spritesheet.webp"
static var texture_cache: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not texture_cache.has(sheet_path):
		if ResourceLoader.exists(sheet_path): texture_cache[sheet_path]=load(sheet_path)
		elif FileAccess.file_exists(sheet_path):
			var img := Image.load_from_file(sheet_path)
			if img != null: texture_cache[sheet_path]=ImageTexture.create_from_image(img)
	atlas=texture_cache.get(sheet_path)
	if sheet_path == "res://assets/pets/lumi/spritesheet.webp" and ResourceLoader.exists("res://assets/pets/lumi/sleep.png"):
		sleeping = load("res://assets/pets/lumi/sleep.png")
	if atlas != null:
		var palette := ShaderMaterial.new()
		palette.shader=preload("res://scripts/palette.gdshader")
		palette.set_shader_parameter("source_hue",source_hue)
		palette.set_shader_parameter("hue_tolerance",hue_tolerance)
		var index := int(get_meta("palette_index",0))%4
		var hues := [source_hue,0.46,0.075,0.93]
		# Keep four distinct coats even when the imported source is already mint/peach/rose.
		for i in range(1,4):
			if absf(source_hue-float(hues[i]))<0.08: hues[i]=0.705
		palette.set_shader_parameter("enabled",index!=0)
		palette.set_shader_parameter("target_hue",hues[index])
		material=palette

func advance(delta: float) -> void:
	if motion:
		elapsed += delta
		queue_redraw()

func oval(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 48:
		var angle := TAU * i / 48.0
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(points, color)

func line(a: Vector2, b: Vector2, color: Color, width := 4.0) -> void:
	draw_line(a, b, color, width, true)

func _draw() -> void:
	if atlas != null:
		if state in ["completed","idle"] and sleeping != null:
			var breath := 1.0+0.008*sin(elapsed*1.8) if motion else 1.0
			var dim := size*breath
			draw_texture_rect(sleeping,Rect2((size-dim)/2,dim),false)
			return
		var row: int = {"idle":0,"working":7,"question":6,"failed":5,"review":8,"completed":4}.get(state,0)
		var durations: Array = [[280,110,110,140,140,320],[120,120,120,120,120,120,120,220],[120,120,120,120,120,120,120,220],[140,140,140,280],[140,140,140,140,280],[140,140,140,140,140,140,140,240],[150,150,150,150,150,260],[120,120,120,120,120,220],[150,150,150,150,150,280]][row]
		var total := 0.0
		for duration in durations: total+=duration
		var remaining := fmod(elapsed*1000,total) if motion else 0.0
		var frame := 0
		while frame<durations.size()-1 and remaining>=durations[frame]:
			remaining-=durations[frame]
			frame+=1
		if state in ["completed","idle"]:
			row = 5
			frame = 4
		var scale_factor := minf(size.x/192.0,size.y/208.0)
		var dimensions := Vector2(192,208)*scale_factor
		draw_texture_rect_region(atlas,Rect2((size-dimensions)/2,dimensions),Rect2(frame*192,row*208,192,208))
		return
	var unit := minf(size.x / 240.0, size.y / 230.0)
	var bounce := sin(elapsed * 3.0) * 3.0 if motion and state != "idle" else 0.0
	draw_set_transform(Vector2(size.x / 2.0, size.y - 25.0 * unit), 0, Vector2.ONE * unit)
	oval(Vector2(0, 0), Vector2(80, 13), Color(0, 0, 0, 0.2))
	draw_set_transform(Vector2(size.x / 2.0, size.y - (25.0 + bounce) * unit), 0, Vector2.ONE * unit)
	var fur := Color("f1ad65")
	if species == "dog": fur = Color("debf9b")
	if species == "cat": fur = Color("c0b3ea")
	if species == "bird": fur = Color("8fc9d6")
	var cream := Color("fff1db")
	var ink := Color("2c2637")
	# Tail and feet.
	if species != "bird":
		oval(Vector2(62, -43), Vector2(27, 41), fur.darkened(0.12))
		oval(Vector2(71, -66), Vector2(18, 19), cream)
	oval(Vector2(0, -48), Vector2(49, 54), fur)
	oval(Vector2(0, -39), Vector2(31, 38), cream)
	oval(Vector2(-28, -4), Vector2(21, 12), fur.darkened(0.09))
	oval(Vector2(28, -4), Vector2(21, 12), fur.darkened(0.09))
	if species == "dog":
		oval(Vector2(-47, -112), Vector2(21, 40), fur.darkened(0.3))
		oval(Vector2(47, -112), Vector2(21, 40), fur.darkened(0.3))
	elif species != "bird":
		draw_colored_polygon(PackedVector2Array([Vector2(-50,-108), Vector2(-49,-180), Vector2(-8,-140)]), fur)
		draw_colored_polygon(PackedVector2Array([Vector2(50,-108), Vector2(49,-180), Vector2(8,-140)]), fur)
		draw_colored_polygon(PackedVector2Array([Vector2(-41,-129), Vector2(-42,-164), Vector2(-21,-140)]), Color("f6c7be"))
		draw_colored_polygon(PackedVector2Array([Vector2(41,-129), Vector2(42,-164), Vector2(21,-140)]), Color("f6c7be"))
	else:
		oval(Vector2(-6,-160), Vector2(9,23), fur)
		oval(Vector2(8,-155), Vector2(8,20), fur.lightened(0.15))
	oval(Vector2(0,-108), Vector2(61,53), fur)
	oval(Vector2(-24,-90), Vector2(29,24), cream)
	oval(Vector2(24,-90), Vector2(29,24), cream)
	var blink := fmod(elapsed, 4.8) > 4.6
	for x in [-23, 23]:
		if state == "idle" or blink:
			line(Vector2(x-6,-114), Vector2(x+6,-114), ink, 4)
		else:
			oval(Vector2(x,-114), Vector2(6,9), ink)
			oval(Vector2(x+2,-117), Vector2(2,3), Color.WHITE)
	oval(Vector2(-39,-95), Vector2(10,5), Color("efaeab"))
	oval(Vector2(39,-95), Vector2(10,5), Color("efaeab"))
	if species == "bird":
		draw_colored_polygon(PackedVector2Array([Vector2(-10,-99), Vector2(10,-99), Vector2(0,-87)]), Color("f4c268"))
	else:
		oval(Vector2(0,-95), Vector2(7,5), ink)
		line(Vector2(0,-91),Vector2(0,-84),ink,2)
		draw_arc(Vector2(-5,-86), 5, 0, PI, 12, ink, 2, true)
		draw_arc(Vector2(5,-86), 5, 0, PI, 12, ink, 2, true)
	oval(Vector2(-43,-47), Vector2(13,22), fur)
	oval(Vector2(43,-47), Vector2(13,22), fur)
	if state == "working":
		var laptop := StyleBoxFlat.new()
		laptop.bg_color = Color("4b506b")
		laptop.set_corner_radius_all(6)
		draw_style_box(laptop, Rect2(-48,-54,96,49))
		draw_circle(Vector2(0,-31), 7, accent)
		line(Vector2(-56,-4),Vector2(56,-4), Color("84899e"),5)
	elif state == "completed":
		draw_rect(Rect2(-29,-55,58,49), Color("b6a0ef"))
		draw_rect(Rect2(-34,-58,68,12), Color("d4c4fc"))
		draw_rect(Rect2(-4,-58,8,52), Color("fff0ba"))
		draw_arc(Vector2(-10,-64),10,0,TAU,24,Color("fff0ba"),4,true)
		draw_arc(Vector2(10,-64),10,0,TAU,24,Color("fff0ba"),4,true)
	elif state == "failed":
		# The little accident remains on the floor until the event is dealt with.
		oval(Vector2(82,-7),Vector2(23,10),Color("936145"))
		oval(Vector2(82,-17),Vector2(17,10),Color("a57450"))
		oval(Vector2(85,-28),Vector2(10,9),Color("b4845c"))
		draw_circle(Vector2(77,-17),2,ink)
		draw_circle(Vector2(88,-17),2,ink)
	elif state == "review":
		var drop := 10.0 * sin(elapsed * 2.0) if motion else 0.0
		draw_circle(Vector2(79,-52+drop),21,Color("3e4059"))
		line(Vector2(83,-72+drop),Vector2(91,-86+drop),Color("e8c67a"),3)
		draw_circle(Vector2(92,-87+drop),4,Color("ffcc81"))
	elif state == "question":
		var font := ThemeDB.fallback_font
		draw_circle(Vector2(78,-148),23,Color("ffd18d"))
		draw_string(font,Vector2(68,-136),"!",HORIZONTAL_ALIGNMENT_LEFT,-1,34,ink)
	elif state == "idle":
		draw_string(ThemeDB.fallback_font,Vector2(60,-154),"z z",HORIZONTAL_ALIGNMENT_LEFT,-1,22,accent)
