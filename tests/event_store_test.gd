extends SceneTree
const Store = preload("res://core/event_store.gd")
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ",message)

func _initialize() -> void:
	var s = Store.new()
	check(s.apply({"id":"1","task_id":"a","type":"task.started","title":"one task","sequence":1}),"start accepted")
	check(s.apply({"id":"2","task_id":"a","type":"input.required","sequence":2}),"question accepted")
	check(s.tasks.a.state=="question" and not s.tasks.a.acknowledged,"question remains pending")
	check(s.apply({"id":"3","task_id":"a","type":"user.acknowledged"}),"ack accepted")
	check(s.tasks.a.state=="idle" and s.tasks.a.acknowledged and s.tasks.a.event_type=="task.paused","ack rests task")
	check(s.apply({"id":"2","task_id":"a","type":"input.required","sequence":2}),"duplicate accepted idempotently")
	check(s.tasks.a.acknowledged,"duplicate cannot clear acknowledgement")
	check(not s.apply({"id":"old","task_id":"a","type":"task.completed","sequence":1}),"out of order rejected")
	check(s.tasks.a.state=="idle","stale event cannot overwrite rest")
	check(s.apply({"id":"4","task_id":"a","type":"task.resumed","sequence":3}),"explicit resume")
	check(s.tasks.a.state=="working","resume actually works")
	for invalid in [null,[],{}, {"id":"x","task_id":"a","type":"unknown"}, {"id":"x","task_id":"a","type":"task.started","url":"file:///C:/Windows"}, {"id":"x","task_id":"a","type":"task.started","summary":123}, {"id":"x","task_id":"a","type":"task.started","pet":"code.gd"}, {"id":"x","task_id":"a","type":"task.started","sequence":-1}]:
		check(not s.apply(invalid),"malformed event rejected")
	check(s.tasks.size()==1,"invalid input does not create task")
	check(Store.safe_url("codex://threads/01a07402-2f90-7dc2-b94f-5d710dc6d1ad"),"Codex task URL")
	check(not Store.safe_url("codex://threads/../../../malicious"),"malformed deep link blocked")
	check(not Store.safe_url("javascript:alert(1)"),"script URL blocked")
	check(s.apply({"id":"5","task_id":"a","type":"task.completed"}),"completion accepted")
	check(not s.tasks.a.acknowledged,"completion persists until ack")
	var restored = Store.new()
	check(restored.restore(JSON.parse_string(JSON.stringify(s.snapshot()))),"disk snapshot restored")
	check(restored.tasks.a.state=="completed" and not restored.tasks.a.acknowledged,"pending completion preserved")
	check(not restored.restore({"version":1,"tasks":{"x":{}},"seen":[]}),"corrupt snapshot rejected")
	check(restored.tasks.a.state=="completed","restore is transactional")
	print("Event store: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
