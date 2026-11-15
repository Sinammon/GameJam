# Headless test for the pause menu, settings store and tutorial (exit 0 = all PASS):
#   Godot --headless --path bunker-7 --script res://tools/test_ui.gd
extends SceneTree

const TEST_CFG := "user://test_settings.cfg"
var fails := 0
var finished_count := 0

func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		fails += 1

func frames(n: int) -> void:
	for i in n:
		await process_frame

func press_key(code: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = down
		Input.parse_input_event(e)
		await frames(2)

func _on_finished() -> void:
	finished_count += 1

func _initialize() -> void:
	_run()

func _run() -> void:
	await frames(2)
	SettingsStore.path = TEST_CFG
	SettingsStore.reset(true)
	await _test_store()
	await _test_pause()
	await _test_tutorial()
	SettingsStore.reset(true)
	check(not FileAccess.file_exists(TEST_CFG), "test settings file cleaned up")
	print("RESULT: %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)

# ---------------------------------------------------------------- settings store

func _test_store() -> void:
	SettingsStore.load_settings(true)
	check(is_equal_approx(float(SettingsStore.get_value("music_volume")), 0.8), "default music 0.8")
	check(is_equal_approx(float(SettingsStore.get_value("sfx_volume")), 0.8), "default sfx 0.8")
	check(SettingsStore.get_value("fullscreen") == false, "default fullscreen off")
	check(SettingsStore.get_value("lights_quality") == "full", "default lights full")
	check(SettingsStore.get_value("tutorial_seen") == false, "default tutorial_seen false")
	SettingsStore.set_value("music_volume", 0.35)
	SettingsStore.set_value("sfx_volume", 1.7)   # clamps
	SettingsStore.set_value("lights_quality", "bogus")   # rejected -> default
	check(SettingsStore.get_value("lights_quality") == "full", "bad lights value falls back")
	SettingsStore.set_value("lights_quality", "simple")
	SettingsStore.set_value("fullscreen", true)
	check(FileAccess.file_exists(TEST_CFG), "settings file written to user://")
	SettingsStore.load_settings(true)   # re-read from disk
	check(is_equal_approx(float(SettingsStore.get_value("music_volume")), 0.35), "music round-trips")
	check(is_equal_approx(float(SettingsStore.get_value("sfx_volume")), 1.0), "sfx clamped and round-trips")
	check(SettingsStore.get_value("lights_quality") == "simple", "lights round-trips")
	check(SettingsStore.get_value("fullscreen") == true, "fullscreen round-trips")
	check(SettingsStore.hint_once("first_crate") == true, "hint_once first time true")
	check(SettingsStore.hint_once("first_crate") == false, "hint_once second time false")
	SettingsStore.load_settings(true)
	check(SettingsStore.hint_once("first_crate") == false, "hint_once remembered after reload")
	check(SettingsStore.hint_once("first_zombie") == true, "hint_once other id true")
	check(SettingsStore.hint_seen("first_crate"), "hint_seen true")
	SettingsStore.set_value("fullscreen", false)
	SettingsStore.apply()
	var mi := AudioServer.get_bus_index("Music")
	var si := AudioServer.get_bus_index("SFX")
	check(mi >= 0 and si >= 0, "Music and SFX buses exist")
	check(absf(db_to_linear(AudioServer.get_bus_volume_db(mi)) - 0.35) < 0.01, "music bus volume applied")
	SettingsStore.apply()
	check(AudioServer.get_bus_index("Music") == mi, "apply twice does not duplicate buses")
	# damaged file -> defaults
	var f := FileAccess.open(TEST_CFG, FileAccess.WRITE)
	f.store_string("this is [[ not a config")
	f.close()
	SettingsStore.load_settings(true)
	check(is_equal_approx(float(SettingsStore.get_value("music_volume")), 0.8), "damaged file gives defaults")
	SettingsStore.reset(true)

# ---------------------------------------------------------------- pause menu

func _test_pause() -> void:
	var pm: PauseMenu = load("res://scenes/pause_menu.tscn").instantiate()
	root.add_child(pm)
	await frames(2)
	check(pm.layer == 100, "pause menu layer 100")
	check(pm.process_mode == Node.PROCESS_MODE_ALWAYS, "pause menu process_mode ALWAYS")
	check(not paused and not pm.is_open, "starts closed, tree running")
	var had_pause_action := InputMap.has_action("pause")
	if not had_pause_action:
		check(PauseMenu.toggle_action() == &"ui_cancel", "fallback action is ui_cancel")
		await press_key(KEY_ESCAPE)
		check(paused and pm.is_open, "Esc opens and pauses (fallback)")
		check(pm.main_page.visible and not pm.settings_page.visible, "main page shown")
		check(pm.resume_button.has_focus(), "Resume has keyboard focus")
		await press_key(KEY_ESCAPE)
		check(not paused and not pm.is_open, "Esc closes and unpauses")
		# now with a real "pause" action
		InputMap.add_action("pause")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_ESCAPE
		InputMap.action_add_event("pause", ev)
	check(PauseMenu.toggle_action() == &"pause", "uses the pause action when it exists")
	await press_key(KEY_ESCAPE)
	check(paused and pm.is_open, "pause action opens")
	check(pm.quit_button.visible == not OS.has_feature("web"), "Quit visibility matches web check")

	# settings page + keyboard
	pm.settings_button.pressed.emit()
	check(pm.settings_page.visible and not pm.main_page.visible, "Settings page opens")
	check(pm.music_slider.has_focus(), "music slider focused")
	var before := pm.music_slider.value
	await press_key(KEY_LEFT)
	check(pm.music_slider.value < before, "Left arrow lowers the slider")
	await press_key(KEY_ESCAPE)
	check(pm.is_open and pm.main_page.visible, "Esc in settings goes back, stays paused")

	pm.open_settings()
	pm.music_slider.value = 0.3
	pm.sfx_slider.value = 0.6
	pm.fullscreen_check.button_pressed = true
	pm.lights_option.select(2)
	pm.lights_option.item_selected.emit(2)
	check(is_equal_approx(float(SettingsStore.get_value("music_volume")), 0.3), "music slider saved")
	check(is_equal_approx(float(SettingsStore.get_value("sfx_volume")), 0.6), "sfx slider saved")
	check(SettingsStore.get_value("fullscreen") == true, "fullscreen saved")
	check(SettingsStore.get_value("lights_quality") == "off", "lights saved")
	var mi := AudioServer.get_bus_index("Music")
	check(absf(db_to_linear(AudioServer.get_bus_volume_db(mi)) - 0.3) < 0.01, "music applied immediately")
	SettingsStore.load_settings(true)
	check(is_equal_approx(float(SettingsStore.get_value("music_volume")), 0.3) and SettingsStore.get_value("lights_quality") == "off", "settings survive reload")
	pm.fullscreen_check.button_pressed = false
	pm.back_button.pressed.emit()
	check(pm.main_page.visible, "Back button returns to main page")

	# tutorial button: signal is emitted
	var got := [0]
	var cb := func(): got[0] += 1
	pm.show_tutorial.connect(cb)
	pm.tutorial_button.pressed.emit()
	check(got[0] == 1, "Tutorial button emits show_tutorial")
	check(get_nodes_in_group("tutorial_open").is_empty(), "no built-in tutorial when someone is connected")
	pm.show_tutorial.disconnect(cb)
	pm.tutorial_button.pressed.emit()
	await frames(2)
	check(get_nodes_in_group("tutorial_open").size() == 1, "built-in tutorial opens when nobody listens")
	await press_key(KEY_ESCAPE)   # closes tutorial, not the pause menu
	await frames(2)
	check(get_nodes_in_group("tutorial_open").is_empty() and pm.is_open and paused, "Esc closes tutorial only, menu stays open and paused")

	check(ResourceLoader.exists(PauseMenu.MAIN_MENU_SCENE), "main menu scene exists")
	pm.resume_button.pressed.emit()
	check(not paused and not pm.is_open, "Resume unpauses")
	pm.enabled = false
	await press_key(KEY_ESCAPE)
	check(not pm.is_open, "disabled menu ignores the key")
	if not had_pause_action:
		InputMap.erase_action("pause")
	pm.queue_free()
	await frames(2)

# ---------------------------------------------------------------- tutorial

func _test_tutorial() -> void:
	SettingsStore.reset(true)
	check(Tutorial.is_first_time(), "tutorial not seen yet")
	check(Tutorial.SLIDES.size() == 7, "7 slides defined")
	var t: Tutorial = Tutorial.open(root)
	t.auto_free = false
	t.finished.connect(_on_finished)
	await frames(2)
	check(t.process_mode == Node.PROCESS_MODE_ALWAYS, "tutorial process_mode ALWAYS")
	check(t.index == 0 and t.back_button.disabled, "starts on slide 1, Back disabled")
	var expected := [
		["The bombs fell. You are the last survivor in Bunker 7.", "Survive 7 days. On Day 7 a convoy comes, if your radio beacon is built."],
		["A / D walk. W or Space jump.", "E opens crates and uses the hatch.", "Mouse click swings your tool."],
		["Radiation rises while you are outside.", "The farther from the hatch, the faster it rises.", "At 100% you start losing hearts. Go home before it fills!"],
		["Open crates, chop trees and mine blocks for wood, scrap and concrete.", "Your backpack holds only so much. Choose what to carry."],
		["Climb down the hatch to reach your bunker.", "Eat, sleep, unlock rooms and build machines. Bring loot home to use it."],
		["If you die you wake up in your bunker.", "You drop your backpack where you fell and gain a permanent Scar perk. Go get your pack!"],
		["Build the Radio Beacon, survive until Day 7, and the convoy will rescue you."],
	]
	var max_h := 0.0
	for i in 7:
		if i > 0:
			t.next_button.pressed.emit()
		await frames(2)
		var texts: Array = []
		for c in t.body_box.get_children():
			texts.append((c as Label).text)
		check(t.index == i and texts == expected[i], "slide %d text and index" % (i + 1))
		check(t.picture_holder.get_child_count() == 1 and t.dots_box.get_child_count() == 7, "slide %d has picture/placeholder and 7 dots" % (i + 1))
		max_h = maxf(max_h, t.panel.size.y)
	check(max_h <= 270.0, "panel fits the 270px screen (max %.0f)" % max_h)
	check(t.next_button.text == "Done" and not t.skip_button.visible, "last slide shows Done, hides Skip")
	await press_key(KEY_LEFT)
	check(t.index == 5, "Left arrow goes back")
	await press_key(KEY_RIGHT)
	check(t.index == 6, "Right arrow goes forward")
	t.back_button.pressed.emit()
	check(t.index == 5, "Back button works")
	check(finished_count == 0, "not finished yet")
	t.show_slide(6)
	t.next_button.pressed.emit()
	check(finished_count == 1 and t.closed, "Done emits finished")
	check(not Tutorial.is_first_time(), "tutorial_seen stored")
	t.queue_free()

	# Skip button, Esc key, Enter on focused Next
	SettingsStore.reset(true)
	var t2: Tutorial = Tutorial.open(root)
	t2.finished.connect(_on_finished)
	await frames(2)
	t2.skip_button.pressed.emit()
	check(finished_count == 2, "Skip emits finished")
	await frames(2)
	check(not is_instance_valid(t2), "auto_free removes the tutorial")
	var t3: Tutorial = Tutorial.open(root)
	t3.finished.connect(_on_finished)
	await frames(2)
	await press_key(KEY_ESCAPE)
	check(finished_count == 3, "Esc emits finished")
	var t4: Tutorial = Tutorial.open(root, true)
	await frames(2)
	check(paused, "pause_game option pauses")
	await press_key(KEY_ENTER)
	check(t4.index == 1, "Enter on focused Next advances (works while paused)")
	t4.close()
	check(not paused, "closing restores the pause state")
	await frames(2)
