class_name NoiseGen
extends RefCounted
## Perlin noise — exact port of the JS Noise class from the HTML prototype.
## Uses the same permutation table generation and fade/lerp/grad functions
## so that identical seeds produce identical output.

var p: PackedInt32Array  # 512-entry permutation table

func _init(seed_val: int = 42) -> void:
	p = PackedInt32Array()
	p.resize(512)
	var base: PackedInt32Array = PackedInt32Array()
	base.resize(256)
	for i in range(256):
		base[i] = i

	# Seeded shuffle — same algorithm as JS prototype
	var s: int = seed_val if seed_val != 0 else 42
	# Local RNG matching the JS version: s = (s * 1664525 + 1013904223) & 0xffffffff
	for i in range(255, 0, -1):
		s = (s * 1664525 + 1013904223) & 0xFFFFFFFF
		# Emulate JS unsigned: if top bit set, add 2^32 before dividing
		var unsigned_s: float = float(s) if s >= 0 else float(s) + 4294967296.0
		var rval: float = unsigned_s / 4294967296.0
		var j: int = int(floor(rval * (i + 1)))
		if j > i:
			j = i
		# swap
		var tmp: int = base[i]
		base[i] = base[j]
		base[j] = tmp

	for i in range(512):
		p[i] = base[i & 255]


func fade(t: float) -> float:
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


func noise_lerp(a: float, b: float, t: float) -> float:
	return a + t * (b - a)


func grad(hash_val: int, x: float, y: float) -> float:
	var h: int = hash_val & 3
	var u: float = x if (h & 1) == 0 else -x
	var v: float = y if (h & 2) == 0 else -y
	return u + v


func get_value(x: float, y: float) -> float:
	var xi: int = int(floor(x)) & 255
	var yi: int = int(floor(y)) & 255
	var xf: float = x - floor(x)
	var yf: float = y - floor(y)
	var u: float = fade(xf)
	var v: float = fade(yf)

	var aa: int = p[p[xi] + yi]
	var ab: int = p[p[xi] + yi + 1]
	var ba: int = p[p[xi + 1] + yi]
	var bb: int = p[p[xi + 1] + yi + 1]

	return noise_lerp(
		noise_lerp(grad(aa, xf, yf), grad(ba, xf - 1.0, yf), u),
		noise_lerp(grad(ab, xf, yf - 1.0), grad(bb, xf - 1.0, yf - 1.0), u),
		v
	)


func fbm(x: float, y: float, octaves: int = 4) -> float:
	var val: float = 0.0
	var amp: float = 1.0
	var freq: float = 1.0
	var max_val: float = 0.0
	for _i in range(octaves):
		val += get_value(x * freq, y * freq) * amp
		max_val += amp
		amp *= 0.5
		freq *= 2.0
	return val / max_val
