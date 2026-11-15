extends Node
# Audio (autoload "Audio"): sound effects, music with crossfade, ambience and the expedition's
# radiation / health loops. Every call is safe: an unknown or missing sound just does nothing.
#
#   Audio.play_sfx("pickup")                  # one-shot on the SFX bus (pooled voices)
#   Audio.play_sfx("footstep_1", -4.0, 0.1)   # extra dB, random pitch +-10%
#   Audio.play_music("music_bunker")          # crossfades; same track = no restart
#   Audio.stop_music(1.0)
#   Audio.set_music_volume(0.5)               # 0..1, saved in SettingsStore
#
# Music follows the current scene by itself (SCENE_MUSIC). The expedition calls
# set_geiger / set_heartbeat / set_danger every frame; they switch off by themselves
# a moment after the calls stop (scene left, player dead).
#
# Web: browsers only start audio after a click or key. Until the first input event the
# requested track is remembered and sound effects are skipped; the track starts on that event.

const DIR := "res://audio/%s.wav"
const MUSIC_BUS := &"Music"
const SFX_BUS := &"SFX"
const VOICES := 10
const STALE := 0.3              # s without a set_* call -> that loop turns off

# Per-sound base volume (dB, before the call's own volume_db). Judged by peak / rms: the files
# peak around -1..-6 dBFS; one-shots sit at -6..-12, music -12..-16, ambience lower.
const BASE_DB := {
	"music_menu": -13.0, "music_bunker": -14.0, "music_expedition": -14.0, "music_danger": -11.0,
	"music_gameover": -12.0, "music_ending": -13.0,
	"amb_wind": -20.0,
	"geiger_1": -10.0, "geiger_2": -10.0, "geiger_3": -11.0, "heartbeat": -8.0, "rad_warning": -12.0,
	"footstep_1": -12.0, "footstep_2": -12.0, "jump": -12.0, "land": -11.0,
	"swing": -8.0, "axe_chop": -8.0, "tree_fall": -7.0, "pickaxe_hit": -7.0, "rock_break": -8.0,
	"pickup": -10.0, "drop": -12.0,
	"zombie_growl_1": -9.0, "zombie_growl_2": -9.0, "zombie_hit": -9.0, "zombie_death": -8.0,
	"player_hurt": -7.0, "player_death": -6.0,
	"hatch_open": -7.0, "hatch_close": -7.0, "ladder_climb": -9.0, "door_open": -7.0,
	"build_ok": -6.0, "build_fail": -10.0, "eat": -5.0, "drink": -9.0, "sleep": -8.0,
	"flashlight_toggle": -6.0, "popup_open": -8.0, "popup_close": -8.0, "slot_select": -8.0,
	"day_start": -9.0, "ui_click": -8.0, "ui_hover": -16.0, "ui_back": -10.0, "ui_confirm": -10.0,
}

# Scene file -> [music, ambience]. Scenes not listed keep whatever plays.
const SCENE_MUSIC := {
	"res://scenes/main_menu.tscn": ["music_menu", ""],
	"res://scenes/bunker.tscn": ["music_bunker", ""],
	"res://scenes/morning.tscn": ["music_bunker", ""],
	"res://scenes/overnight.tscn": ["music_bunker", ""],
	"res://scenes/night_event.tscn": ["music_bunker", ""],
	"res://scenes/scar_pick.tscn": ["music_bunker", ""],
	"res://scenes/expedition.tscn": ["music_expedition", "amb_wind"],
	"res://scenes/game_over.tscn": ["music_gameover", ""],
	"res://scenes/ending.tscn": ["music_ending", ""],
}
const DANGER_TRACK := "music_danger"
const DANGER_HOLD := 4.0        # danger music stays at least this long after the last trigger

var _streams := {}              # name -> AudioStream (or null if missing)
var _pool: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _music: Array[AudioStreamPlayer] = []
var _active := 0                # index into _music of the player that is fading in / playing
var _music_name := ""           # what is (or should be) playing
var _base_music := ""           # the scene's track (danger switches away from it)
var _music_tweens: Array = [null, null]
var _amb: AudioStreamPlayer
var _amb_name := ""
var _last_scene: Node = null
var _unlocked := true           # false on the web until the first input event
## true with the Dummy audio driver (headless runs, tests): everything is set up and
## loaded but nothing is started, because a stream still playing at exit is reported by the
## engine as a leak. Tests may set it false (then stop_all() a few frames before quitting).
var silent := false
var _pending_music := ""
var _pending_fade := 1.0

var _geiger_frac := 0.0
var _geiger_age := 99.0
var _geiger_left := 0.0
var _heart_on := false
var _heart_age := 99.0
var _heart_left := 0.0
var _danger_age := 99.0
var _danger_hold := 0.0

# Players are made in _init so calls work even before _ready (tools/ scripts call right away).
func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ensure_buses()
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.name = "Voice%d" % i
		p.bus = SFX_BUS
		add_child(p)
		_pool.append(p)
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.name = "Music%d" % i
		m.bus = MUSIC_BUS
		m.volume_db = -80.0
		add_child(m)
		_music.append(m)
	_amb = AudioStreamPlayer.new()
	_amb.name = "Ambience"
	_amb.bus = SFX_BUS
	add_child(_amb)
	_unlocked = not OS.has_feature("web")
	silent = AudioServer.get_driver_name() == "Dummy"

func _ready() -> void:
	SettingsStore.apply()
	if _unlocked:
		_flush_pending()

# Stopping every player before the tree goes away keeps the engine from reporting a leaked
# AudioStreamPlayback (and a "resource still in use") at exit.
func _exit_tree() -> void:
	stop_all()

func stop_all() -> void:
	for p in _pool:
		p.stop()
		p.stream = null
	for m in _music:
		m.stop()
		m.stream = null
	_amb.stop()
	_amb.stream = null
	_music_name = ""
	_amb_name = ""
	_streams.clear()

# Music and SFX buses (send to Master). Safe to call again: existing buses are reused.
func ensure_buses() -> void:
	SettingsStore.ensure_bus(MUSIC_BUS)
	SettingsStore.ensure_bus(SFX_BUS)

# ---------------------------------------------------------------- streams

func has_sound(sound: String) -> bool:
	return _stream(sound) != null

func _stream(sound: String) -> AudioStream:
	if sound == "":
		return null
	if _streams.has(sound):
		return _streams[sound]
	var path := DIR % sound
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path) as AudioStream
	_streams[sound] = s
	return s

# Music and the wind loop through their WAV loop points; anything else asked to loop
# (or a loop file imported without points) gets a forward loop over the whole sample.
func _looping(s: AudioStream) -> AudioStream:
	var w := s as AudioStreamWAV
	if w == null or w.loop_mode != AudioStreamWAV.LOOP_DISABLED:
		return s
	var c := w.duplicate() as AudioStreamWAV
	c.loop_mode = AudioStreamWAV.LOOP_FORWARD
	c.loop_begin = 0
	c.loop_end = int(c.get_length() * c.mix_rate)
	return c

# ---------------------------------------------------------------- sound effects

# Plays a one-shot. Returns the voice used, or null (unknown name, web audio not started yet).
func play_sfx(sound: String, volume_db := 0.0, pitch_var := 0.0) -> AudioStreamPlayer:
	if not _unlocked or not is_inside_tree():
		return null
	var s := _stream(sound)
	if s == null:
		return null
	var p := _free_voice()
	p.stream = s
	p.volume_db = float(BASE_DB.get(sound, -8.0)) + volume_db
	p.pitch_scale = clampf(1.0 + randf_range(-pitch_var, pitch_var), 0.5, 2.0) if pitch_var > 0.0 else 1.0
	_start(p)
	return p

# One of several variants at random ("zombie_growl" -> zombie_growl_1 / _2).
func play_random(names: Array, volume_db := 0.0, pitch_var := 0.0) -> AudioStreamPlayer:
	if names.is_empty():
		return null
	return play_sfx(str(names[randi() % names.size()]), volume_db, pitch_var)

func _free_voice() -> AudioStreamPlayer:
	for p in _pool:
		if not p.playing:
			return p
	var p := _pool[_next_voice]   # all busy: steal the oldest round-robin
	_next_voice = (_next_voice + 1) % _pool.size()
	return p

# ---------------------------------------------------------------- music

func current_music() -> String:
	return _music_name

func play_music(track: String, fade := 1.0) -> void:
	if track == _music_name and track != "":
		return
	if not _unlocked or not is_inside_tree():
		_pending_music = track
		_pending_fade = fade
		_music_name = track
		return
	var s := _stream(track)
	if s == null:
		return   # unknown track: keep what plays
	_music_name = track
	var old := _active
	_active = 1 - _active
	var p := _music[_active]
	p.stream = _looping(s)
	p.volume_db = -60.0 if fade > 0.0 else _music_db(track)
	_start(p)
	_fade_player(_active, _music_db(track), fade, false)
	_fade_player(old, -60.0, fade, true)

func stop_music(fade := 1.0) -> void:
	_music_name = ""
	_base_music = ""
	_pending_music = ""
	_fade_player(0, -60.0, fade, true)
	_fade_player(1, -60.0, fade, true)

func _music_db(track: String) -> float:
	return float(BASE_DB.get(track, -14.0))

func _fade_player(i: int, to_db: float, time: float, stop_after: bool) -> void:
	var p := _music[i]
	if _music_tweens[i] != null and (_music_tweens[i] as Tween).is_valid():
		(_music_tweens[i] as Tween).kill()
	_music_tweens[i] = null
	if not p.playing and not (silent and p.stream != null):
		return
	if time <= 0.0:
		p.volume_db = to_db
		if stop_after:
			p.stop()
		return
	var tw := create_tween()
	tw.tween_property(p, "volume_db", to_db, time)
	if stop_after:
		tw.tween_callback(p.stop)
	_music_tweens[i] = tw

# ---------------------------------------------------------------- ambience

func play_ambience(sound: String) -> void:
	if sound == _amb_name:
		return
	_amb_name = sound
	_amb.stop()
	if sound == "" or not _unlocked or not is_inside_tree():
		return
	var s := _stream(sound)
	if s == null:
		return
	_amb.stream = _looping(s)
	_amb.volume_db = float(BASE_DB.get(sound, -20.0))
	_start(_amb)

func _start(p: AudioStreamPlayer) -> void:
	if not silent:
		p.play()

# ---------------------------------------------------------------- expedition loops

# frac 0..1 = radiation fill. Ticks get faster (and denser) as it rises; silent below 0.15.
func set_geiger(frac: float) -> void:
	_geiger_frac = clampf(frac, 0.0, 1.0)
	_geiger_age = 0.0

func set_heartbeat(on: bool) -> void:
	_heart_on = on
	_heart_age = 0.0

# Call with true while danger lasts (high radiation, zombies close): music_danger replaces
# the expedition track, and goes back DANGER_HOLD s after the calls with true stop.
func set_danger(on: bool) -> void:
	if on:
		_danger_age = 0.0
		_danger_hold = DANGER_HOLD

func _tick_loops(delta: float) -> void:
	_geiger_age += delta
	_heart_age += delta
	_danger_age += delta
	if get_tree().paused:
		return
	var g := _geiger_frac if _geiger_age < STALE else 0.0
	if g > 0.15:
		_geiger_left -= delta
		if _geiger_left <= 0.0:
			# about 1.5 clicks/s at 15% .. 16/s at 100%, randomised like a real counter
			var rate := lerpf(1.5, 16.0, (g - 0.15) / 0.85)
			_geiger_left = randf_range(0.3, 1.7) / rate
			play_random(["geiger_1", "geiger_2", "geiger_3"], lerpf(-4.0, 0.0, g), 0.08)
	if _heart_on and _heart_age < STALE:
		_heart_left -= delta
		if _heart_left <= 0.0:
			_heart_left = 1.0
			play_sfx("heartbeat")
	else:
		_heart_left = 0.0
	if _danger_hold > 0.0:
		_danger_hold -= delta
	_update_scene_music()

# ---------------------------------------------------------------- scene music

func _process(delta: float) -> void:
	var scene := get_tree().current_scene
	if scene != _last_scene:
		_last_scene = scene
		_danger_hold = 0.0
		if scene != null and SCENE_MUSIC.has(scene.scene_file_path):
			var pair: Array = SCENE_MUSIC[scene.scene_file_path]
			_base_music = str(pair[0])
			play_ambience(str(pair[1]))
		elif scene != null and scene.scene_file_path != "":
			play_ambience("")
	_tick_loops(delta)

func _update_scene_music() -> void:
	if _base_music == "":
		return
	var want := _base_music
	if _base_music == "music_expedition" and _danger_hold > 0.0:
		want = DANGER_TRACK
	if want != _music_name:
		play_music(want, 1.5 if want == DANGER_TRACK or _music_name == DANGER_TRACK else 1.0)

# ---------------------------------------------------------------- web unlock

func _input(event: InputEvent) -> void:
	if _unlocked:
		return
	if (event is InputEventMouseButton or event is InputEventKey or event is InputEventScreenTouch) and event.is_pressed():
		unlock()

# Starts audio (the web build calls it on the first click / key; elsewhere audio starts unlocked).
func unlock() -> void:
	if _unlocked:
		return
	_unlocked = true
	_flush_pending()

# Starts the track / ambience that was asked for while audio could not play yet.
func _flush_pending() -> void:
	var track := _pending_music
	_pending_music = ""
	_music_name = ""
	if track != "":
		play_music(track, _pending_fade)
	var amb := _amb_name
	_amb_name = ""
	play_ambience(amb)

# ---------------------------------------------------------------- volume (0..1, saved)

func get_music_volume() -> float:
	return float(SettingsStore.get_value("music_volume"))

func get_sfx_volume() -> float:
	return float(SettingsStore.get_value("sfx_volume"))

func set_music_volume(v: float) -> void:
	SettingsStore.set_value("music_volume", v)
	SettingsStore.apply()

func set_sfx_volume(v: float) -> void:
	SettingsStore.set_value("sfx_volume", v)
	SettingsStore.apply()
