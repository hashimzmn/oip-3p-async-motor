# =========================
# motor_drive.gd
# attach to: 3PAsynchronousMotor (root)
# =========================
@tool
class_name MotorDrive
extends Node3D

# -------------------------
# TEST / MANUAL CONTROL
# -------------------------
@export_tool_button("Start") var start_action = start_motor
@export_tool_button("Stop") var stop_action = stop_motor

# -------------------------
# INTERNAL STATE
# -------------------------
var _tag_group_init: bool = false
var _register_ok_start: bool = false
var _register_ok_stop: bool = false
var _register_ok_running: bool = false
var _register_ok_stopping: bool = false
var _register_ok_rpm: bool = false
var _register_ok_torque: bool = false
var _register_ok_current: bool = false
var _tag_group_original: String

# Maintained-bit inputs from PLC/control system
var _start_cmd: bool = false
var _stop_cmd: bool = false

# Feedback cache
var _running_fb: bool = false
var _stopping_fb: bool = false
var _rpm_fb: float = 0.0
var _torque_fb: float = 0.0
var _current_fb: float = 0.0

# -------------------------
# COMMUNICATIONS
# -------------------------
@export_category("Communications")

## Enable communication with external PLC/control systems.
@export var enable_comms: bool = false

@export var tag_group_name: String

## The tag group for reading drive commands from external systems.
@export_custom(0, "tag_group_enum") var tag_groups:
	set(value):
		tag_group_name = value
		tag_groups = value

@export var tag_start_cmd_name: String = "StartCmd"
@export var tag_stop_cmd_name: String = "StopCmd"
@export var tag_running_name: String = "Running"
@export var tag_stopping_name: String = "Stopping"
@export var tag_rpm_name: String = "RPM"
@export var tag_torque_name: String = "TorqueNm"
@export var tag_current_name: String = "CurrentA"


func _validate_property(property: Dictionary) -> void:
	if property.name == "tag_group_name":
		property.usage = PROPERTY_USAGE_STORAGE

	elif property.name == "enable_comms":
		property.usage = PROPERTY_USAGE_DEFAULT if OIPComms.get_enable_comms() else PROPERTY_USAGE_STORAGE

	elif property.name == "tag_groups":
		property.usage = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_NO_INSTANCE_STATE if OIPComms.get_enable_comms() else PROPERTY_USAGE_NONE

	elif property.name == "tag_start_cmd_name" \
			or property.name == "tag_stop_cmd_name" \
			or property.name == "tag_running_name" \
			or property.name == "tag_stopping_name" \
			or property.name == "tag_rpm_name" \
			or property.name == "tag_torque_name" \
			or property.name == "tag_current_name":
		property.usage = PROPERTY_USAGE_DEFAULT if OIPComms.get_enable_comms() else PROPERTY_USAGE_STORAGE


func _property_can_revert(property: StringName) -> bool:
	return property == "tag_groups"


func _property_get_revert(property: StringName) -> Variant:
	if property == "tag_groups":
		return _tag_group_original

	return null


func _enter_tree() -> void:
	_tag_group_original = tag_group_name

	if tag_group_name.is_empty():
		tag_group_name = OIPComms.get_tag_groups()[0]
		tag_groups = tag_group_name

	SimulationEvents.simulation_started.connect(_on_simulation_started)
	OIPComms.tag_group_initialized.connect(_tag_group_initialized)
	OIPComms.tag_group_polled.connect(_tag_group_polled)
	OIPComms.enable_comms_changed.connect(notify_property_list_changed)


func _exit_tree() -> void:
	SimulationEvents.simulation_started.disconnect(_on_simulation_started)
	OIPComms.tag_group_initialized.disconnect(_tag_group_initialized)
	OIPComms.tag_group_polled.disconnect(_tag_group_polled)
	OIPComms.enable_comms_changed.disconnect(notify_property_list_changed)


func _get_rotor():
	return get_node_or_null("RotorBody3")


func _update_feedback_cache() -> void:
	var rotor = _get_rotor()

	if rotor == null:
		return

	if rotor.has_method("is_running"):
		_running_fb = rotor.call("is_running")

	if rotor.has_method("is_stopping"):
		_stopping_fb = rotor.call("is_stopping")

	if rotor.has_method("get_rpm"):
		_rpm_fb = rotor.call("get_rpm")

	if rotor.has_method("get_torque_nm"):
		_torque_fb = rotor.call("get_torque_nm")

	if rotor.has_method("get_current_a"):
		_current_fb = rotor.call("get_current_a")


# -------------------------
# DRIVE API
# -------------------------
func start_motor() -> void:
	var rotor = _get_rotor()

	if rotor == null:
		print("MotorDrive: RotorBody3 node not found.")
		return

	if rotor.has_method("set_running"):
		rotor.call("set_running", true)
	elif rotor.has_method("toggle_running"):
		rotor.call("toggle_running")


func stop_motor() -> void:
	var rotor = _get_rotor()

	if rotor == null:
		print("MotorDrive: RotorBody3 node not found.")
		return

	if rotor.has_method("set_running"):
		rotor.call("set_running", false)
	elif rotor.has_method("toggle_running"):
		rotor.call("toggle_running")


# -------------------------
# COMMS LIFECYCLE
# -------------------------
func _on_simulation_started() -> void:
	if enable_comms:
		_register_ok_start = OIPComms.register_tag(tag_group_name, tag_start_cmd_name, 1)
		_register_ok_stop = OIPComms.register_tag(tag_group_name, tag_stop_cmd_name, 1)
		_register_ok_running = OIPComms.register_tag(tag_group_name, tag_running_name, 1)
		_register_ok_stopping = OIPComms.register_tag(tag_group_name, tag_stopping_name, 1)
		_register_ok_rpm = OIPComms.register_tag(tag_group_name, tag_rpm_name, 1)
		_register_ok_torque = OIPComms.register_tag(tag_group_name, tag_torque_name, 1)
		_register_ok_current = OIPComms.register_tag(tag_group_name, tag_current_name, 1)


func _tag_group_initialized(tag_group_name_param: String) -> void:
	if tag_group_name_param == tag_group_name:
		_tag_group_init = true


func _tag_group_polled(tag_group_name_param: String) -> void:
	if not enable_comms:
		return

	if not _tag_group_init:
		return

	if tag_group_name_param != tag_group_name:
		return

	# Maintained bits: read the tags each poll.
	if _register_ok_start:
		_start_cmd = OIPComms.read_bit(tag_group_name, tag_start_cmd_name)

	if _register_ok_stop:
		_stop_cmd = OIPComms.read_bit(tag_group_name, tag_stop_cmd_name)

	# Maintained-bit behavior:
	# - Stop has priority!
	# - Start runs only if Stop is not asserted.
	if _stop_cmd:
		stop_motor()
	elif _start_cmd:
		start_motor()

	_update_feedback_cache()

	if _register_ok_running:
		OIPComms.write_bit(tag_group_name, tag_running_name, _running_fb)

	if _register_ok_stopping:
		OIPComms.write_bit(tag_group_name, tag_stopping_name, _stopping_fb)

	if _register_ok_rpm:
		OIPComms.write_float32(tag_group_name, tag_rpm_name, _rpm_fb)

	if _register_ok_torque:
		OIPComms.write_float32(tag_group_name, tag_torque_name, _torque_fb)

	if _register_ok_current:
		OIPComms.write_float32(tag_group_name, tag_current_name, _current_fb)
