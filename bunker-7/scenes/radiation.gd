extends RefCounted
# Radiation outside: fills while away from the hatch, faster the farther you are
# (both directions). At 100% it stays full and drains health instead of killing:
# `drain_tick` fires at once on reaching 100%, then every DRAIN_EVERY seconds.
# Warnings fire once per upward crossing of 60%, 85% and 100%.

signal warning(level: int)   # 0 = 60%, 1 = 85%, 2 = 100%
signal drain_tick            # take DRAIN_DAMAGE now

# Percent per second next to the hatch .. at the far edge, times the GameState multiplier.
# Tuned so a straight round trip to a farthest crate (2350 px away) costs ~85% on Normal.
const RAD_NEAR := 0.8
const RAD_FAR := 2.8
const WARN_AT := [60.0, 85.0, 100.0]
const DRAIN_EVERY := 2.0       # seconds per half-heart while at 100%
const DRAIN_DAMAGE := 1

var value := 0.0
var _drain_left := 0.0
var _warned := [false, false, false]

static func rate_at(dist: float) -> float:
	return lerpf(RAD_NEAR, RAD_FAR, clampf(dist, 0.0, 1.0))

# dist: 0 at the hatch .. 1 at either world edge. safe: inside the hatch.
func tick(delta: float, dist: float, mult: float, safe: bool) -> void:
	if safe:
		return   # paused in the hatch (no rise, no drain)
	value = minf(value + rate_at(dist) * mult * delta, 100.0)
	_check_warnings()
	if value >= 100.0:
		_drain_left -= delta
		if _drain_left <= 0.0:
			_drain_left += DRAIN_EVERY
			drain_tick.emit()
	else:
		_drain_left = 0.0

func _check_warnings() -> void:
	for i in WARN_AT.size():
		if value >= WARN_AT[i] and not _warned[i]:
			_warned[i] = true
			warning.emit(i)
		elif value < WARN_AT[i] - 5.0:
			_warned[i] = false   # dropped back (only via debug/tests): may warn again

# Geiger states 0..4: calm, ticking, warning, danger, full.
func level() -> int:
	if value >= 100.0: return 4
	if value >= WARN_AT[1]: return 3
	if value >= WARN_AT[0]: return 2
	if value >= 30.0: return 1
	return 0

# Bar colour: green -> yellow (60%) -> red (85%+).
static func color(v: float) -> Color:
	var green := Color(0.45, 0.85, 0.35)
	var yellow := Color(0.95, 0.85, 0.25)
	var red := Color(0.95, 0.3, 0.25)
	if v < 60.0:
		return green.lerp(yellow, clampf((v - 30.0) / 30.0, 0.0, 1.0))
	return yellow.lerp(red, clampf((v - 60.0) / 25.0, 0.0, 1.0))
