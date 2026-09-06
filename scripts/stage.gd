extends Control
var elapsed := 0.0
var state := "working"
var motion := true
var strong_effects := true
var accent := Color("bda5ff")
var glow: GradientTexture2D

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	clip_contents = true
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0,0.28,0.65,1.0])
	gradient.colors = PackedColorArray([Color(accent,0.17),Color(accent,0.10),Color(accent,0.025),Color(accent,0)])
	glow = GradientTexture2D.new()
	glow.gradient = gradient
	glow.width = 512
	glow.height = 512
	glow.fill = GradientTexture2D.FILL_RADIAL
	glow.fill_from = Vector2(0.5,0.5)
	glow.fill_to = Vector2(1.0,0.5)

func advance(delta: float) -> void:
	if motion:
		elapsed += delta
		queue_redraw()

func _draw() -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color("191b2a")
	box.border_color = Color("33334c")
	box.set_border_width_all(1)
	box.set_corner_radius_all(24)
	draw_style_box(box, Rect2(Vector2.ZERO,size))
	if glow != null:
		var diameter := minf(size.x*1.1,size.y*0.95)
		draw_texture_rect(glow,Rect2(Vector2(size.x*0.5,size.y*0.65)-Vector2.ONE*diameter/2,Vector2.ONE*diameter),false)
	for i in 36:
		var p := Vector2(fmod(i*137.7+31,size.x-40)+20, fmod(i*73.3+40,size.y-100)+20)
		var alpha := 0.2 + 0.15 * sin(elapsed+i)
		draw_circle(p, 1.3 if i % 4 else 2.0, Color(accent,alpha))
	draw_line(Vector2(32,size.y-65),Vector2(size.x-32,size.y-65),Color("353449"),1,true)
	if state == "question" and strong_effects:
		var pulse := 0.6 + 0.25*sin(elapsed*2.5) if motion else 0.8
		var warning := StyleBoxFlat.new()
		warning.bg_color = Color(0.8,0.13,0.18,0.07)
		warning.border_color = Color(1.0,0.35,0.3,pulse)
		warning.set_border_width_all(4)
		warning.set_corner_radius_all(24)
		draw_style_box(warning,Rect2(Vector2(2,2),size-Vector2(4,4)))
		for i in range(-1,int(size.x/50)+2):
			var x := i*50.0+fmod(elapsed*18,50)
			draw_colored_polygon(PackedVector2Array([Vector2(x,0),Vector2(x+22,0),Vector2(x+10,9),Vector2(x-12,9)]),Color("ffb94f"))
