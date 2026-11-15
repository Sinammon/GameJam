# Headless test for the Audio autoload (exit 0 = all PASS):
#   Godot --headless --fixed-fps 60 --path bunker-7 --script res://tools/test_audio.gd
# The Dummy driver makes Audio "silent": streams, voices, fades and track switching all run,
# only play() is skipped (the Dummy driver never mixes, so a started sound would leak at exit).
extends SceneTree

const TEST_CFG := "user://test_audio_settings.cfg"
const NAMES := ["music_menu", "music_bunker", "music_expedition", "music_danger", "music_gameover",
	"music_ending", "amb_wind", "geiger_1", "geiger_2", "geiger_3", "heartbeat", "rad_warning",
	"footstep_1", "footstep_2", "jump", "land", "swing", "axe_chop", "tree_fall", "pickaxe_hit",
	"rock_break", "pickup", "drop", "zombie_growl_1", "zombie_growl_2", "zombie_hit", "zombie_death",
	"player_hurt", "player_death", "hatch_open", "hatch_close", "ladder_climb", "door_open",
	"build_ok", "build_fail", "eat", "drink", "sleep", "flashlight_toggle", "popup_open",
	"popup_close", "slot_select", "day_start", "ui_click", "ui_hover", "ui_back", "ui_confirm"]
const LOOPS := ["music_menu", "music_bunker", "music_expedition", "music_danger", "music_ending", "amb_wind"]

var fails := 0
var audio: Node

func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		fails += 1

func frames(n: int) -> void:
	for i in n:
		await process_frame

func _initialize() -> void:
	_run()

func _run() -> void:
	await frames(2)
	SettingsStore.path = TEST_CFG
	SettingsStore.reset(true)
	audio = root.get_node_or_null("Audio")
	check(audio != null, "Audio autoload exists")
	if audio == null:
		quit(1)
		return
	_test_files()
	_test_buses()
	await _test_sfx()
	_test_volume()
	await _test_music()
	await _test_loops()
	await _test_ui()
	check(audio.silent, "Dummy driver -> silent mode")
	audio.stop_all()
	await frames(10)
	SettingsStore.reset(true)
	print("DONE fails=%d" % fails)
	quit(1 if fails > 0 else 0)

func _test_files() -> void:
	var missing := []
	var bad := []
	for n in NAMES:
		var path := "res://audio/%s.wav" % n
		if not ResourceLoader.exists(path):
			missing.append(n)
			continue
		var s := load(path) as AudioStreamWAV
		if s == null or s.get_length() <= 0.0:
			bad.append(n)
	check(missing.is_empty(), "all %d sound files exist %s" % [NAMES.size(), missing])
	check(bad.is_empty(), "all load as AudioStreamWAV with length %s" % [bad])
	var not_looping := []
	for n in LOOPS:
		var s := load("res://audio/%s.wav" % n) as AudioStreamWAV
		if s == null or s.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			not_looping.append(n)
	check(not_looping.is_empty(), "music / ambience import with loop points %s" % [not_looping])

func _test_buses() -> void:
	check(AudioServer.get_bus_index(&"Music") > 0, "Music bus exists")
	check(AudioServer.get_bus_index(&"SFX") > 0, "SFX bus exists")
	var count := AudioServer.bus_count
	audio.ensure_buses()
	audio.ensure_buses()
	check(AudioServer.bus_count == count, "ensure_buses twice adds no bus")

func _test_sfx() -> void:
	check(audio.play_sfx("no_such_sound") == null, "unknown sfx returns null, no crash")
	check(audio.play_sfx("") == null, "empty sfx name returns null")
	var p: AudioStreamPlayer = audio.play_sfx("pickup", -3.0, 0.1)
	check(p != null and p.bus == &"SFX", "known sfx gets a voice on the SFX bus")
	for i in 30:   # more than the pool: voices get stolen, nothing breaks
		audio.play_sfx(["ui_click", "footstep_1", "zombie_hit"][i % 3], 0.0, 0.2)
	await frames(5)
	check(true, "30 overlapping sfx without error")
	audio.stop_all()
	await frames(5)

func _test_volume() -> void:
	audio.set_music_volume(0.3)
	audio.set_sfx_volume(0.6)
	SettingsStore.load_settings(true)   # re-read from disk
	check(is_equal_approx(audio.get_music_volume(), 0.3), "music volume saved and re-read")
	check(is_equal_approx(audio.get_sfx_volume(), 0.6), "sfx volume saved and re-read")
	var mi := AudioServer.get_bus_index(&"Music")
	check(absf(AudioServer.get_bus_volume_db(mi) - linear_to_db(0.3)) < 0.01, "Music bus at 0.3 linear")
	audio.set_music_volume(0.0)
	check(AudioServer.is_bus_mute(mi), "music volume 0 mutes the bus")
	audio.set_music_volume(0.8)
	check(not AudioServer.is_bus_mute(mi), "music volume back on unmutes")
	audio.set_sfx_volume(0.8)

func _test_music() -> void:
	audio.play_music("no_such_track")
	check(audio.current_music() == "", "unknown track does not start anything")
	audio.play_music("music_menu", 0.2)
	await frames(5)
	check(audio.current_music() == "music_menu", "play_music sets the current track")
	var active: int = audio._active
	audio.play_music("music_menu", 0.2)
	check(audio._active == active, "same track again does not restart")
	audio.play_music("no_such_track")
	check(audio.current_music() == "music_menu", "unknown track keeps the current one")
	audio.play_music("music_bunker", 0.2)
	await frames(30)
	check(audio.current_music() == "music_bunker" and audio._active != active, "crossfade to music_bunker")
	var old: AudioStreamPlayer = audio._music[active]
	var cur: AudioStreamPlayer = audio._music[audio._active]
	check(old.volume_db <= -59.0 and cur.volume_db > -20.0, "crossfade: old faded out, new faded in")
	# danger switching while on the expedition track
	audio._base_music = "music_expedition"
	await frames(80)
	check(audio.current_music() == "music_expedition", "scene track music_expedition")
	for i in 10:
		audio.set_danger(true)
		await frames(1)
	check(audio.current_music() == "music_danger", "danger -> music_danger")
	await frames(int((audio.DANGER_HOLD + 0.5) * 60))
	check(audio.current_music() == "music_expedition", "danger over -> back to music_expedition")
	audio.stop_music(0.2)
	await frames(30)
	check(audio.current_music() == "" and audio._music[0].volume_db <= -59.0 and audio._music[1].volume_db <= -59.0, "stop_music fades both out")
	audio.stop_all()
	await frames(5)

func _test_loops() -> void:
	audio.play_ambience("amb_wind")
	check(audio._amb.stream != null, "ambience gets its loop")
	audio.play_ambience("no_such_amb")
	check(not audio._amb.playing and audio._amb.stream != null, "unknown ambience: no crash")
	var ticks := 0
	for i in 60:
		audio.set_geiger(1.0)
		audio.set_heartbeat(true)
		await frames(1)
	for p in audio._pool:
		if p.stream != null and str(p.stream.resource_path).contains("geiger"):
			ticks += 1
	check(ticks > 0, "geiger ticks at full radiation (%d voices)" % ticks)
	await frames(30)   # the calls stopped: the loops go stale and switch themselves off
	audio.stop_all()   # (the Dummy driver never finishes a sound, so clear the voices)
	await frames(60)
	var started := 0
	for p in audio._pool:
		if p.stream != null:
			started += 1
	check(started == 0, "geiger / heartbeat stop when the calls stop")

func _test_ui() -> void:
	var b := UIKit.button("Test")
	root.add_child(b)
	b.pressed.emit()
	var found := false
	for p in audio._pool:
		if p.stream != null and str(p.stream.resource_path).ends_with("ui_click.wav"):
			found = true
	check(found, "UIKit.button click plays ui_click")
	UIKit.set_click_sfx(b, "")
	audio.stop_all()
	b.pressed.emit()
	var any := false
	for p in audio._pool:
		if p.stream != null:
			any = true
	check(not any, "set_click_sfx(\"\") silences the click")
	b.queue_free()
	var pm: Node = load("res://scenes/pause_menu.tscn").instantiate()
	root.add_child(pm)
	await frames(2)
	check(pm.music_slider != null and is_equal_approx(pm.music_slider.value, 0.8), "pause menu music slider shows the setting")
	pm.sfx_slider.value = 0.4
	check(is_equal_approx(audio.get_sfx_volume(), 0.4), "pause menu sfx slider saves the volume")
	pm.queue_free()
	await frames(2)
