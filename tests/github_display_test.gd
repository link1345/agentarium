extends SceneTree

func _initialize() -> void:
	var app = load("res://scripts/main.gd").new()
	app.data_dir="res://artifacts/github-display-test"
	DirAccess.make_dir_recursive_absolute(app.data_dir)
	app.sync_pid=OS.get_process_id()
	app.sync_initialized=true
	var id="01a07611-3285-72e1-a243-7600139c36dc"
	app.task_order=[id]
	app.selected=id
	for pair in [["ci.failed","failed"],["review.received","review"],["task.completed","completed"]]:
		var data={"ok":true,"generated_at":Time.get_unix_time_from_system(),"threads":[{"id":id,"title":"GitHub test","revision":pair[0],"state":pair[1],"event_type":pair[0],"summary":"test","github_status":"GitHub: test/repo #1"}]}
		var f=FileAccess.open(app.data_dir.path_join("desktop-sync.json"),FileAccess.WRITE)
		f.store_string(JSON.stringify(data));f.close()
		app._poll_desktop_sync()
		assert(app.live.tasks[id].event_type==pair[0])
		assert(app._item_key(app.live.tasks[id])=={"failed":"bomb","review":"balloon","completed":"gift"}[pair[1]])
		app.live.apply({"id":"ack-"+pair[0],"task_id":id,"type":"user.acknowledged"})
		app.sync_stamp=""
		app._poll_desktop_sync()
		assert(app.live.tasks[id].acknowledged)
		assert(app.live.tasks[id].state=="idle")
	app.sync_pid=-1
	app.free()
	print("PASS: GitHub snapshot -> state, icons, recovery, acknowledgement deduplication")
	quit()
