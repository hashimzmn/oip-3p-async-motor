# =========================
# rotor_body.gd
# attach to: RotorBody3 (child node of root parent node)
# =========================

@tool
class_name RotorBody3
extends Node3D

# -------------------------
# DRIVE-CONTROLLED STATE
# -------------------------
var _running: bool = false
var _stopping: bool = false


func set_running(v: bool) -> void:
	_running = v

	if _running:
		_stopping = false
	else:
		_stopping = true

	print("RotorBody3 set_running ->", _running)


func toggle_running() -> void:
	set_running(not _running)


func is_running() -> bool:
	return _running


func is_stopping() -> bool:
	return _stopping


#func drive_ping(msg: String = "ping") -> void:
	#print("RotorBody3 got drive ping:", msg, " | node:", name)


# =========================================================
# TORQUE-SPEED MODEL
# =========================================================
@export_category("Torque-Speed Model")

# Torques [Nm]
@export var T_st: float = 191.5
@export var T_p: float = 63.83
@export var T_k: float = 211.1
@export var T_r: float = 49.1

# Speeds [rpm]
@export var n_p: float = 1000.0
@export var n_k: float = 1920.0
@export var n_r: float = 2920.0
@export var n_s: float = 3000.0


# =========================================================
# ROTOR DYNAMICS
# =========================================================
@export_category("Rotor Dynamics")

@export var load_torque_nm: float = 49.1
@export var inertia_J: float = 0.02477 # kg m^2, Rossi catalog J0


# =========================================================
# CURRENT MODEL
# =========================================================
@export_category("Current Model")

@export var rated_current_a: float = 30.0
@export var start_current_ratio: float = 8.3


# =========================================================
# VISUAL SPIN
# =========================================================
@export_category("Visual Spin")

@export_enum("X", "Y", "Z") var spin_axis: int = 2
@export var invert_spin: bool = false


# =========================================================
# STATE VARIABLES
# =========================================================
var _rpm: float = 0.0
var _torque_nm: float = 0.0
var _omega: float = 0.0 # rad/s
var _current_a: float = 0.0


# =========================================================
# DEBUG
# =========================================================
@export_category("Debug")
var _print_accum: float = 0.0
@export var print_interval_s: float = 0.25


# =========================================================
# LIFECYCLE
# =========================================================
func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	_update_motion(delta)
	_update_current()
	_update_visual_spin(delta)

	_print_accum += delta

	if _print_accum >= print_interval_s:
		_print_accum = 0.0

		var mech_power_w: float = _torque_nm * _omega

		print(
			"Running:", _running,
			" | Stopping:", _stopping,
			" | rpm:", snapped(_rpm, 0.1),
			" | Torque(Nm):", snapped(_torque_nm, 0.1),
			" | Pm(W):", snapped(mech_power_w, 1.0),
			" | I(A):", snapped(_current_a, 0.01)
		)


# =========================================================
# MOTION UPDATE
# =========================================================
func _update_motion(delta: float) -> void:
	var motor_torque_nm: float = 0.0

	if _running:
		motor_torque_nm = _torque_from_speed(_rpm)
		_stopping = false
	elif _stopping:
		motor_torque_nm = 0.0
	else:
		motor_torque_nm = 0.0

	var net_torque_nm: float = motor_torque_nm - load_torque_nm

	if inertia_J > 1e-9:
		var omega_dot: float = net_torque_nm / inertia_J
		_omega += omega_dot * delta

	if _omega < 0.0:
		_omega = 0.0

	_rpm = _omega * 60.0 / TAU

	if _rpm > n_s:
		_rpm = n_s
		_omega = _rpm * TAU / 60.0

	_torque_nm = motor_torque_nm

	if not _running and _omega <= 1e-6:
		_omega = 0.0
		_rpm = 0.0
		_torque_nm = 0.0
		_stopping = false


# =========================================================
# CURRENT UPDATE
# =========================================================
func _update_current() -> void:
	if not _running and not _stopping and _rpm <= 1e-6:
		_current_a = 0.0
		return

	_current_a = _current_from_speed(_rpm)


func _current_from_speed(n: float) -> float:
	n = clamp(n, 0.0, n_s)

	if rated_current_a < 0.0:
		return 0.0

	var start_current_a: float = start_current_ratio * rated_current_a

	if abs(n_s) < 1e-6:
		return rated_current_a

	var x: float = 1.0 - n / n_s

	return rated_current_a + (start_current_a - rated_current_a) * pow(x, 0.5)


# =========================================================
# VISUAL SPIN
# =========================================================
func _update_visual_spin(delta: float) -> void:
	var omega: float = _rpm * TAU / 60.0

	if invert_spin:
		omega = -omega

	var angle_step: float = omega * delta

	match spin_axis:
		0:
			rotate_x(angle_step)
		1:
			rotate_y(angle_step)
		2:
			rotate_z(angle_step)


# =========================================================
# PIECEWISE TORQUE-SPEED MODEL
# =========================================================
func _torque_from_speed(n: float) -> float:
	n = clamp(n, 0.0, n_s)

	# Region I
	if n <= n_p:
		if abs(n_p) < 1e-6:
			return T_st

		var a1: float = 2.0 * (T_st - T_p) / pow(n_p, 3.0)
		var b1: float = 3.0 * (T_st - T_p) / pow(n_p, 2.0)

		return a1 * pow(n, 3.0) - b1 * pow(n, 2.0) + T_st

	# Region II
	elif n <= n_k:
		var denom2: float = n_k - n_p

		if abs(denom2) < 1e-6:
			return T_k

		var x: float = (n - n_p) / denom2

		return (2.0 * pow(x, 3.0) - 3.0 * pow(x, 2.0) + 1.0) * T_p \
			+ (-2.0 * pow(x, 3.0) + 3.0 * pow(x, 2.0)) * T_k

	# Region III
	else:
		var delta_r: float = n_r - n_k
		var delta_s: float = n_s - n_k

		if abs(delta_r) < 1e-6 \
				or abs(delta_s) < 1e-6 \
				or abs(delta_r - delta_s) < 1e-6:
			return T_r

		var A: float = ((T_r - T_k) * pow(delta_s, 2.0) + T_k * pow(delta_r, 2.0)) / (
			pow(delta_r, 2.0) * pow(delta_s, 2.0) * (delta_r - delta_s)
		)

		var B: float = (T_r - T_k - A * pow(delta_r, 3.0)) / pow(delta_r, 2.0)

		var dn: float = n - n_k

		return A * pow(dn, 3.0) + B * pow(dn, 2.0) + T_k


# =========================================================
# GETTERS
# =========================================================
func get_rpm() -> float:
	return _rpm


func get_torque_nm() -> float:
	return _torque_nm


func get_current_a() -> float:
	return _current_a


func get_omega() -> float:
	return _omega
