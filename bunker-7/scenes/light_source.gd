class_name LightSource
extends PointLight2D
# A world light (lamp, glow, pulse) managed by Lighting (scenes/lighting.gd):
# Lighting decides which ones are on (quality, the cap, near the camera) and
# animates flicker / pulse on the ones that are on. Make them with
#   Lighting.add_lamp(parent, pos, color, energy, radius, flicker)
# Without a Lighting node in the scene a LightSource just stays on (no cap,
# no animation) unless the stored quality is "off".

var base_energy := 1.0
var radius := 64.0
var flicker := 0.0       # 0 = steady; 0.15 = a gentle slow wobble of the energy
var pulse := 0.0         # 0 = none; else pulses per second (energy 40%..100%)
var priority := 0.0      # px "closer" when the cap picks which lights stay on
var wanted := true       # false = always off (an unused pool light)
var manager: Node = null # the Lighting node that registered this light
var _seed := 0.0
var pick_score := 0.0        # scratch for Lighting's pick (no allocation)
var picked := false

func configure(c: Color, energy_: float, radius_: float, flicker_ := 0.0) -> LightSource:
	color = c
	base_energy = energy_
	energy = energy_
	radius = radius_
	flicker = flicker_
	texture = Lighting.radial_texture()
	texture_scale = radius_ * 2.0 / float(Lighting.TEX_SIZE)
	shadow_enabled = false
	range_item_cull_mask = Lighting.MASK_WORLD | Lighting.MASK_BACKGROUND
	_seed = randf() * 100.0
	return self

func _enter_tree() -> void:
	add_to_group("light_sources")   # Lighting.GROUP_SOURCES
	var l := Lighting.find(self)
	if l:
		l.register(self)
	else:
		enabled = Lighting.stored_quality() != "off"

func _exit_tree() -> void:
	if manager and is_instance_valid(manager):
		manager.unregister(self)

# Called by Lighting every frame on lights that are on. Cheap: a few sines.
func animate(t: float) -> void:
	var e := base_energy
	if flicker > 0.0:
		var n := sin(t * 1.3 + _seed) * 0.5 + sin(t * 3.1 + _seed * 1.7) * 0.3 + sin(t * 7.3 + _seed * 2.3) * 0.2
		e *= 1.0 + flicker * n
	if pulse > 0.0:
		e *= 0.7 + 0.3 * sin(t * TAU * pulse + _seed)
	energy = e
