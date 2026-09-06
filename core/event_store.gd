extends RefCounted
## Provider-independent task state. An acknowledgement never means work resumed.
signal changed(task_id: String, event_type: String)

const STATES := {
	"task.started": "working", "task.progress": "working", "tool.started": "working",
	"tool.completed": "working", "input.required": "question", "ci.failed": "failed",
	"task.failed": "failed", "review.received": "review", "task.completed": "completed",
	"task.paused": "idle", "task.resumed": "working"
}
const ATTENTION := ["question", "failed", "review", "completed"]
var tasks: Dictionary = {}
var seen: Array = []
var last_error := ""

func apply(event: Variant) -> bool:
	last_error = ""
	if not event is Dictionary:
		return reject("event must be an object")
	for key in ["id", "task_id", "type"]:
		if not event.get(key) is String or event[key].is_empty() or event[key].length() > 160:
			return reject("invalid " + key)
	if event.id in seen:
		return true
	if not STATES.has(event.type) and event.type != "user.acknowledged":
		return reject("unknown event type")
	for key in ["title", "summary", "url", "pet"]:
		if event.has(key) and (not event[key] is String or event[key].length() > 2048):
			return reject("invalid " + key)
	if event.has("url") and not safe_url(event.url):
		return reject("unsupported task URL")
	if event.has("pet") and event.pet not in ["fox", "dog", "bird", "cat"]:
		return reject("unknown pet pack")
	if event.has("sequence") and (not (event.sequence is int or event.sequence is float) or event.sequence < 0 or event.sequence != floor(event.sequence)):
		return reject("invalid sequence")
	if not tasks.has(event.task_id) and event.type == "user.acknowledged":
		return reject("unknown task")
	if not tasks.has(event.task_id) and tasks.size() >= 100:
		return reject("task limit reached (100)")
	var task: Dictionary = tasks.get(event.task_id, {"id": event.task_id, "title": event.task_id, "summary": "", "state": "idle", "pet": "fox", "url": "", "acknowledged": true, "sequence": -1, "updated_at": ""}).duplicate(true)
	if event.has("sequence") and event.sequence <= task.sequence:
		return reject("stale sequence")
	if event.type == "user.acknowledged":
		task.acknowledged = true
		task.state = "idle"
		task.event_type = "task.paused"
		task.summary = "確認しました。ひとやすみ中です。"
	else:
		task.state = STATES[event.type]
		task.event_type = event.type
		task.acknowledged = task.state not in ATTENTION
		for key in ["title", "summary", "url", "pet"]:
			if event.has(key):
				task[key] = event[key]
	if event.has("sequence"):
		task.sequence = event.sequence
	task.updated_at = Time.get_datetime_string_from_system()
	tasks[event.task_id] = task
	seen.append(event.id)
	if seen.size() > 2000:
		seen.pop_front()
	changed.emit(event.task_id, event.type)
	return true

func reject(message: String) -> bool:
	last_error = message
	return false

static func safe_url(url: String) -> bool:
	if url.is_empty():
		return true
	if "\n" in url or "\r" in url or " " in url:
		return false
	if url.begins_with("https://"):
		return url.trim_prefix("https://").get_slice("/", 0).contains(".") and not "@" in url
	if url.begins_with("codex://threads/"):
		var id := url.trim_prefix("codex://threads/")
		return id.length() == 36 and id.replace("-", "").is_valid_hex_number(false)
	return false

func snapshot() -> Dictionary:
	return {"version": 1, "tasks": tasks, "seen": seen}

func restore(data: Variant) -> bool:
	if not data is Dictionary or data.get("version") != 1 or not data.get("tasks") is Dictionary or not data.get("seen") is Array:
		return reject("invalid saved state")
	if data.tasks.size() > 100:
		return reject("saved task limit exceeded")
	for id in data.tasks:
		var t: Variant = data.tasks[id]
		if not t is Dictionary or not t.get("state") in STATES.values() or not t.get("pet") in ["fox", "dog", "bird", "cat"]:
			return reject("invalid saved task")
		for key in ["id", "title", "summary", "url", "updated_at"]:
			if not t.get(key) is String:
				return reject("invalid saved task field")
		if not safe_url(t.url) or not t.get("acknowledged") is bool or not (t.get("sequence") is int or t.get("sequence") is float):
			return reject("invalid saved task metadata")
	tasks = data.tasks.duplicate(true)
	seen = data.seen.slice(maxi(0, data.seen.size() - 2000))
	return true
