class_name Sfx
extends RefCounted
# Safe access to the Audio autoload (autoload/audio.gd) for game code, like GSBridge does for
# GameState: scripts never name `Audio` directly (tools/ test scripts compile scenes before the
# autoloads exist), and a missing autoload or sound name simply plays nothing.
#
#   Sfx.play("jump")                       Sfx.play("footstep_1", -2.0, 0.08)
#   Sfx.random(["zombie_growl_1", "zombie_growl_2"])
#   Sfx.geiger(0.7)  Sfx.heartbeat(true)  Sfx.danger(true)   (every frame while it applies)

static func audio() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("Audio")

# Returns the AudioStreamPlayer used, or null.
static func play(sound: String, volume_db := 0.0, pitch_var := 0.0) -> AudioStreamPlayer:
	var a := audio()
	return a.play_sfx(sound, volume_db, pitch_var) if a else null

static func random(sounds: Array, volume_db := 0.0, pitch_var := 0.0) -> AudioStreamPlayer:
	var a := audio()
	return a.play_random(sounds, volume_db, pitch_var) if a else null

static func geiger(frac: float) -> void:
	var a := audio()
	if a:
		a.set_geiger(frac)

static func heartbeat(on: bool) -> void:
	var a := audio()
	if a:
		a.set_heartbeat(on)

static func danger(on: bool) -> void:
	var a := audio()
	if a:
		a.set_danger(on)
