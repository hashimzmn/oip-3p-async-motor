# motor_drive Script Overview

---

## Purpose

`motor_drive.gd` is the control and communication interface for the three-phase asynchronous motor part in OIP. Not to be confused with a regular VFD or VSD drive, this drive script allows the implementation of a motor with a boolean control. Moreover, it provides the interface to connect to external control/feedback using a **tag** system, and is compatible with OPCUA.

---

## Main Functions

### Boolean Control

The script provides two buttons to manually control the motor:

- **Start** — starts the motor.
- **Stop** — stops the motor.

Both commands are then forwarded to the child node `RotorBody3`.

### External Communication

When comms is enabled, the script registers command and feedback tags using `OIPComms`.

The following command bits are read:

| Tag | Description |
|---|---|
| `StartCmd` | Requests the motor to run |
| `StopCmd` | Requests the motor to stop |

Here the stop command has priority. If both commands are active, the motor is stopped.

### Motor Feedback

Afterwards, the script reads the current motor state from `RotorBody3` and writes it to the external control system.

| Tag | Description |
|---|---|
| `Running` | Indicates that the motor is running |
| `Stopping` | Indicates that the motor is slowing down |
| `RPM` | Current rotor speed |
| `TorqueNm` | Current motor torque in newton-metres |
| `CurrentA` | Current electrical current in amperes |

### Communication Lifecycle

When the simulation starts, the required tags are registered. During every tag-group poll, the script:

1. Reads the start and stop commands.
2. Starts or stops the motor.
3. Updates the motor feedback.
4. Writes the feedback tags.

---

## Crucial

> The script must be attached to the motor root node and expects a simulated rotor to exist. Here:

```text
RotorBody3
```

---

# rotor_body Script Overview

---

## Purpose

`rotor_body.gd` is used to implement the mechanical and electrical behaviour of the motor's rotor.

The script should be attached to a rotor child node (here: `RotorBody3`).

---

## Motor State Control

The script uses two main state variables:

- `_running` — the motor produces torque.
- `_stopping` — the motor stops producing torque but continues rotating to a stop.

The `set_running()` function toggels the motor start/stop.

---

## Torque-Speed Model

The motor torque is calculated from the current rotor speed using a three-region piecewise torque-speed curve shown:

<p align="center">
<img src=".src/Motor/motor_torque_speed_characteristic.png"
     alt="Motor torque-speed characteristic"
     width="700">
</p>

| Region | Speed range | Description |
|---|---|---|
| Region I | `0` to `n_p` | Starting torque decreases toward the pull-up torque |
| Region II | `n_p` to `n_k` | Torque increases toward the breakdown torque |
| Region III | `n_k` to `n_s` | Torque decreases toward the rated and synchronous-speed region |

The main torque parameters are:

- `T_st` — starting torque.
- `T_p` — pull-up torque.
- `T_k` — breakdown torque.
- `T_r` — rated torque.

And are obtained for the motor from its [datasheet](https://www.rossi.com/-/media/Feature/Download-Files/Technical-Catalogs/TX/TX-series-catalog-EN.pdf).

---

## Rotor Dynamics

With the torque-speed model determining the motor torque generated at the current rotor speed. The torque can then used to calculate the rotor speed at the next simulation time step.

The rotor dynamics are described by the first-order differential equation:

$$
J\dot{\omega}=T_m-T_L,
$$

where:

- $J$ is the rotational inertia,
- $\omega$ is the angular speed,
- $T_m$ is the motor torque obtained from the torque-speed model,
- $T_L$ is the applied load torque.

Rearranging gives the angular acceleration:

$$
\dot{\omega}
=
\frac{T_m-T_L}{J}.
$$

Here, the differential equation is solved/approximated using the explicit Euler method:

$$
\omega_{k+1}
=
\omega_k
+
\frac{T_{m,k}-T_L}{J}\Delta t.
$$

The updated angular speed is then converted from radians per second to revolutions per minute:

$$
n
=
\omega\frac{60}{2\pi}.
$$

The rotor speed is limited to the synchronous speed `n_s`.

---

## Current Model

The motor current is estimated from the current rotor speed. This is done by interpolating between the starting current and the rated current using the square root of the motor slip.

The starting current is calculated as:

$$
I_{\mathrm{st}}
=
k_{\mathrm{st}} I_r,
$$

where:

- $I_{\mathrm{st}}$ is the starting current,
- $I_r$ is the rated current,
- $k_{\mathrm{st}}$ is the configured starting-current ratio.

The slip is defined as:

$$
s
=
1-\frac{n}{n_s},
$$

where:

- $n$ is the current rotor speed,
- $n_s$ is the synchronous speed.

Using the square root of the slip, the motor current is modelled as:

$$
I(n)
=
I_r
+
\left(
I_{\mathrm{st}}-I_r
\right)
\sqrt{
1-\frac{n}{n_s}
}.
$$

At standstill, where $n=0$, the current is equal to the starting current:

$$
I(0)=I_{\mathrm{st}}.
$$

As the rotor speed approaches the synchronous speed, the slip approaches zero and the current approaches the rated current:

$$
I(n_s)=I_r.
$$

When the motor is switched off and the rotor has reached rest, the script manually sets the current to zero.

---

## Visual Rotation

The node is visually rotated according to the calculated rotor speed.

The rotation axis can be selected as:

- `X`
- `Y`
- `Z`

The `invert_spin` option reverses the visual rotation direction.

---

## Debug Output

At the configured debug interval, the script prints:

- Running state.
- Stopping state.
- Rotor speed in RPM.
- Motor torque in newton-metres.
- Mechanical power in watts.
- Current in amperes.

Mechanical power is calculated as:

```text
Mechanical power = Torque × Angular velocity
```

---

## Debugging Debug! aka Meta-Debugging or $Debugging^2$

The debug block is placed inside Godot’s built-in `_process(delta)` callback:

```gdscript
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
```

`_process(delta)` is a native Godot callback inherited from `Node`.

It is something that is **not** manually by the script. Instead, Godot automatically calls it once per rendered frame while the node is active in the scene tree and processing is enabled.

The `delta` parameter contains the elapsed time, in seconds, since the previous rendered frame.

For example, at approximately 60 frames per second:

```text
delta ≈ 0.0167 seconds
```

Using `delta` is a trick that allows the simulation to update according to elapsed time rather than according to the number of rendered frames.

In this script, `_process(delta)` performs four main tasks:

1. Updates the rotor motion.
2. Updates the motor current.
3. Updates the visible rotation of the rotor, and,
4. the debug.

> **NOTE:** If the debug block were placed before the update functions, it would still print, but it would display the values calculated during the previous frame.

Because `_process(delta)` usually runs **many** times per second, printing during every frame would create quite a number of outputs!

The script therefore uses an accumulator:

```gdscript
_print_accum += delta
```

This adds the elapsed frame time to `_print_accum`.

Once the configured interval has been reached:

```gdscript
if _print_accum >= print_interval_s:
```

the values are printed and the accumulator is reset:

```gdscript
_print_accum = 0.0
```

---

## Some things to consider:

### Was the debug placed outside a function?

The print statement must be inside a function or callback.

### Was it placed inside `_ready()?

```gdscript
func _ready() -> void:
	print("rpm:", _rpm)
```

`_ready()` is called only once when the node enters the scene tree. And therefore, the debug gets printed only once per run.

### Is the debug inside a function that is never called?

```gdscript
func print_debug_values() -> void:
	print("rpm:", _rpm)
```

This function produces no output unless it is called...

```gdscript
func _process(delta: float) -> void:
	print_debug_values()
```

Here it is called in process.

### Has the accumulator been allowed to update?

This condition will never be reached if `_print_accum` remains at zero:

```gdscript
if _print_accum >= print_interval_s:
	print("rpm:", _rpm)
```

The accumulator must be updated inside `_process(delta)`:

```gdscript
_print_accum += delta
```

---

## Getters

The script provides the following getter functions:

| Function | Returned value |
|---|---|
| `get_rpm()` | Rotor speed in RPM |
| `get_torque_nm()` | Motor torque in newton-metres |
| `get_current_a()` | Motor current in amperes |
| `get_omega()` | Angular velocity in radians per second |

These values can be accessed by the parent `motor_drive` script and sent externally.
