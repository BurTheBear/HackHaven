extends SceneTree
## Check real Control sizes and text wrapping, not just anchor properties.
var failures: Array[String] = []
var checks := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
func settle() -> void:
	for i in 5: await process_frame
func run() -> void:
	var settings = root.get_node("Settings")
	var host := Node3D.new()
	root.add_child(host)
	current_scene = host
	var ui = load("res://scenes/ui.tscn").instantiate()
	host.add_child(ui)
	ui.set_process(false)
	await settle()
	var sentence := "Call out. Listen. Find your way back. The monster follows where the noise was made."
	for width in [1280.0, 320.0, 1920.0]:
		ui.root.size = Vector2(width, 720)
		for font_size in 3:
			settings.subtitle_size = font_size
			ui._apply_sub_size()
			for header in [false, true]:
				if header:
					ui._show_line("MARA", sentence, "LOG 1 / 8")
				else:
					ui._show_line("", sentence, "")
				await settle()
				var label := "%s/%s/header=%s" % [width, font_size, header]
				check(ui._sub_text.size.x >= 200.0, "Readable dialogue width " + label)
				check(ui._sub_box.size.x <= width - 40.0, "Panel fits window " + label)
				check(ui._sub_text.get_line_count() <= 12, "Normal word wrapping " + label)
				check(ui._sub_box.position.x >= 0.0, "Panel stays on screen " + label)
				print("DIALOGUE_LAYOUT ", label, " box=",ui._sub_box.size," text=",ui._sub_text.size," lines=",ui._sub_text.get_line_count())
	# Resizing a visible line also reflows it, with no new dialogue event.
	ui.root.size = Vector2(640, 720)
	await settle()
	check(ui._sub_box.size.x <= 600, "Visible dialogue responds to resize")
	ui._show_line("MARA", "", "LOG 2 / 8")
	await settle()
	check(ui._sub_box.visible and not ui._sub_text.visible, "Header-only log still works")
	# Let the old line begin fading, then replace it with a new one.
	ui._show_line("", "Hi", "")
	await create_timer(2.9).timeout
	ui._show_line("MARA", sentence, "LOG 3 / 8")
	await create_timer(0.7).timeout
	check(ui._sub_box.visible and ui._sub_box.modulate.a > 0.95, "Old fade cannot hide a new line")
	check(ui._sub_text.text == sentence, "New dialogue is retained")
	check(ui._sub_text.visible_characters > 0 and ui._sub_text.visible_characters < sentence.length(), "Typing still advances at the original rate")
	await create_timer(11.0).timeout
	check(not ui._sub_box.visible, "Completed dialogue hides itself")
	print("DIALOGUE_CHECKS: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
