class_name SecondOrderDynamics
extends RefCounted
## Pole-matched, zero-allocation second-order dynamics solver for Vector3 signals.
##
## Models the response y(t) of the system:
##     y + k1 * y' + k2 * y'' = x + k3 * x'
## parameterised by:
##     f    - natural frequency (Hz). Speed of response.
##     zeta - damping coefficient. 0 = undamped, <1 = underdamped (overshoot),
##            1 = critically damped, >1 = overdamped (sluggish, heavy).
##     r    - initial response. 0 = smooth ease-in, 1 = immediate, >1 = overshoot,
##            <0 = anticipation (wind-up).
##
## Integration is semi-implicit Euler with stability clamping: when the step is
## small relative to the system's poles, k2 is clamped so the iteration can never
## diverge; when the step is large (frame-time spike) the coefficients are
## pole-matched (exact discretisation of the continuous poles), which keeps the
## response stable and accurate regardless of dt.
##
## All state is stored in value-type members (Vector3 / float). update() never
## allocates, so the solver is safe to tick every physics frame.

## Largest timestep accepted by update(). Anything larger (hitches, breakpoints,
## window drags) is sub-divided so the response remains physically plausible.
const MAX_STEP_SEC: float = 1.0 / 30.0
## Hard cap on sub-steps per update() call.
const MAX_SUBSTEPS: int = 8
const MIN_FREQUENCY_HZ: float = 0.001
const MIN_ZETA: float = 0.0

var frequency: float = 1.0
var zeta: float = 1.0
var response: float = 0.0

var _xp: Vector3 = Vector3.ZERO
var _y: Vector3 = Vector3.ZERO
var _yd: Vector3 = Vector3.ZERO

var _k1: float = 0.0
var _k2: float = 0.0
var _k3: float = 0.0
var _w: float = 0.0
var _z: float = 0.0
var _d: float = 0.0


func _init(p_frequency: float = 1.0, p_zeta: float = 1.0, p_response: float = 0.0, x0: Vector3 = Vector3.ZERO) -> void:
	reconfigure(p_frequency, p_zeta, p_response)
	reset(x0)


## Recomputes the solver constants. Cheap (a handful of float ops), safe to call
## every frame when blending spring parameters. State (position/velocity) is kept.
func reconfigure(p_frequency: float, p_zeta: float, p_response: float) -> void:
	frequency = maxf(p_frequency, MIN_FREQUENCY_HZ)
	zeta = maxf(p_zeta, MIN_ZETA)
	response = p_response

	_w = TAU * frequency
	_z = zeta
	_d = _w * sqrt(absf(zeta * zeta - 1.0))
	_k1 = zeta / (PI * frequency)
	_k2 = 1.0 / (_w * _w)
	_k3 = response * zeta / _w


## Snaps the solver to x0 with zero velocity.
func reset(x0: Vector3) -> void:
	_xp = x0
	_y = x0
	_yd = Vector3.ZERO


## Adds an instantaneous velocity kick to the output (e.g. landing jolt).
func apply_impulse(velocity_impulse: Vector3) -> void:
	_yd += velocity_impulse


## Advances the solver toward target x, estimating the input velocity from the
## previous target. Returns the new output value.
func update(dt: float, x: Vector3) -> Vector3:
	if dt <= 0.0:
		return _y
	var xd: Vector3 = (x - _xp) / dt
	_xp = x
	return _integrate(dt, x, xd)


## Advances the solver toward target x using an explicitly supplied input
## velocity xd (avoids finite-difference noise when the caller knows it).
func update_with_velocity(dt: float, x: Vector3, xd: Vector3) -> Vector3:
	if dt <= 0.0:
		return _y
	_xp = x
	return _integrate(dt, x, xd)


func get_value() -> Vector3:
	return _y


func get_velocity() -> Vector3:
	return _yd


func _integrate(dt: float, x: Vector3, xd: Vector3) -> Vector3:
	var remaining: float = dt
	var steps: int = 0
	while remaining > 0.0 and steps < MAX_SUBSTEPS:
		var h: float = minf(remaining, MAX_STEP_SEC)
		if steps == MAX_SUBSTEPS - 1:
			h = remaining
		_step(h, x, xd)
		remaining -= h
		steps += 1
	return _y


func _step(h: float, x: Vector3, xd: Vector3) -> void:
	var k1_stable: float
	var k2_stable: float
	if _w * h < _z:
		# Small step: clamp k2 to guarantee stability without introducing jitter.
		k1_stable = _k1
		k2_stable = maxf(_k2, maxf(h * h * 0.5 + h * _k1 * 0.5, h * _k1))
	else:
		# Large step relative to the poles: pole-zero matching.
		var t1: float = exp(-_z * _w * h)
		var alpha: float
		if _z <= 1.0:
			alpha = 2.0 * t1 * cos(h * _d)
		else:
			alpha = 2.0 * t1 * cosh(h * _d)
		var beta: float = t1 * t1
		var denom: float = 1.0 + beta - alpha
		if denom <= 0.000001:
			denom = 0.000001
		var t2: float = h / denom
		k1_stable = (1.0 - beta) * t2
		k2_stable = h * t2
	if k2_stable <= 0.0000001:
		k2_stable = 0.0000001

	_yd += h * (x + _k3 * xd - _y - k1_stable * _yd) / k2_stable
	_y += h * _yd
