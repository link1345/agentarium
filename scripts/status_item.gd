extends TextureRect
var state := "idle"
var motion := true
var elapsed := 0.0
var origin := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	origin = position

func advance(delta: float) -> void:
	if not motion: return
	elapsed += delta
	position.y = origin.y + sin(elapsed * 2.2) * 4.0
	rotation = sin(elapsed * 1.8) * 0.045
