class_name SettingsStore
extends RefCounted
# Player settings saved in user://settings.cfg (a ConfigFile, so it also works in the web build).
# No autoload needed: everything is static and loads itself on first use.
#
#   SettingsStore.get_value("music_volume")      -> 0.8
#   SettingsStore.set_value("fullscreen", true)  -> saves the file and returns
#   SettingsStore.apply()                        -> pushes volumes and fullscreen to the engine
#   if SettingsStore.hint_once("first_crate"): show_hint(...)

const MUSIC_BUS := &"Music"
const SFX_BUS := &"SFX"
const LIGHTS_QUALITIES := ["full", "simple", "off"]
const SECTION := "settings"

const DEFAULTS := {
	"music_volume": 0.8,
	"sfx_volume": 0.8,
	"fullscreen": false,
	"lights_quality": "full",
	"tutorial_seen": false,
	"hints_seen": {},
}

# Tests point this at another file so they never touch the player's real settings.
static var path: String = "user://settings.cfg"
static var _data: Dictionary = {}
static var _loaded: bool = false

# ---------------------------------------------------------------- file

# Reads the file (missing or damaged file -> defaults). Called automatically; call it
# yourself with force = true to re-read from disk.
static func load_settings(force: bool = false) -> void:
	if _loaded and not force:
		return
	_loaded = true
	_data = DEFAULTS.duplicate(true)
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	for key in DEFAULTS:
		var default_value: Variant = DEFAULTS[key]
		var v: Variant = cfg.get_value(SECTION, key, default_value)
		_data[key] = _clean(key, v, default_value)

# Returns OK or an error code.
static func save_settings() -> int:
	load_settings()
	var cfg := ConfigFile.new()
	for key in _data:
		cfg.set_value(SECTION, key, _data[key])
	return cfg.save(path)

# Deletes the file and goes back to defaults (used by tests).
static func reset(delete_file: bool = true) -> void:
	if delete_file and FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	_data = DEFAULTS.duplicate(true)
	_loaded = true

static func _clean(key: String, v: Variant, default_value: Variant) -> Variant:
	match key:
		"music_volume", "sfx_volume":
			if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
				return clampf(float(v), 0.0, 1.0)
			return default_value
		"lights_quality":
			return v if typeof(v) == TYPE_STRING and v in LIGHTS_QUALITIES else default_value
		"hints_seen":
			return (v as Dictionary).duplicate() if typeof(v) == TYPE_DICTIONARY else {}
		_:
			return v if typeof(v) == typeof(default_value) else default_value

# ---------------------------------------------------------------- values

static func get_value(key: String) -> Variant:
	load_settings()
	return _data.get(key, DEFAULTS.get(key))

# Stores a value (cleaned up: volumes are clamped, bad values fall back) and saves the file.
static func set_value(key: String, value: Variant, save_now: bool = true) -> void:
	load_settings()
	if not DEFAULTS.has(key):
		push_warning("SettingsStore: unknown setting '%s'" % key)
		return
	_data[key] = _clean(key, value, DEFAULTS[key])
	if save_now:
		save_settings()

# True the first time an id is asked (and remembers it), false after that.
static func hint_once(id: String) -> bool:
	load_settings()
	var seen: Dictionary = _data["hints_seen"]
	if seen.get(id, false):
		return false
	seen[id] = true
	save_settings()
	return true

static func hint_seen(id: String) -> bool:
	load_settings()
	return bool((_data["hints_seen"] as Dictionary).get(id, false))

# ---------------------------------------------------------------- applying

# Makes sure the Music and SFX buses exist (they send to Master) and returns their index.
# Falls back to Master (0) if a bus cannot be created.
static func ensure_bus(bus_name: StringName) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, &"Master")
	return idx if idx >= 0 and idx < AudioServer.bus_count else 0

static func _set_bus_volume(bus_name: StringName, linear: float) -> void:
	var idx := ensure_bus(bus_name)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(idx, linear <= 0.001)

# Pushes the saved volumes and window mode to the engine.
# On the web the browser only allows fullscreen from a click, so the start-up call
# (from_user = false) leaves the window alone there.
static func apply(from_user: bool = false) -> void:
	load_settings()
	_set_bus_volume(MUSIC_BUS, float(_data["music_volume"]))
	_set_bus_volume(SFX_BUS, float(_data["sfx_volume"]))
	if DisplayServer.get_name() == "headless":
		return
	if OS.has_feature("web") and not from_user:
		return
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if bool(_data["fullscreen"]) else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want:
		DisplayServer.window_set_mode(want)
