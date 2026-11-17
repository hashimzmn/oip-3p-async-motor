# An Implementation of a Three Phase Asynchronous Motor Part in Open Industry Project 

# Introduction
This repo provides the components/scripts necessary to implement a three-phase asynchronous motor part in Open Industry Project.

The 3D model of the part was obtained from:

[Rossi HB 63–180L asynchronous three-phase motor CAD model](https://rossi.partcommunity.com/3d-cad-models/hb-63-180l-asynchronous-three-phase-motor-rossi?info=rossi%2Ftx11_motori%2Fasync_3_phase%2Fhb_asmtab.prj)

A ready to be imported model of the motor is provided in provided in [parts/](./parts/).

The following is the godot node-tree of the implemented part:

| Node | Node Type |
|---|---|
| `3PAsynchronousMotor` | `Node3D` |
| &emsp;`EnclosureBody` | `StaticBody3D` |
| &emsp;&emsp;`CollisionShape3D` | `CollisionShape3D` |
| &emsp;`EnclosureVisual` | `Node3D` |
| &emsp;&emsp;`StatorHousing` | `MeshInstance3D` |
| &emsp;&emsp;`DriveEndShield` | `MeshInstance3D` |
| &emsp;&emsp;`FanCover` | `MeshInstance3D` |
| &emsp;&emsp;`Nameplate` | `MeshInstance3D` |
| &emsp;&emsp;`TerminalBox` | `MeshInstance3D` |
| &emsp;`RotorBody` | `RigidBody3D` |
| &emsp;&emsp;`RotorShaft` | `MeshInstance3D` |
| &emsp;&emsp;`CollisionShape3D` | `CollisionShape3D` |
| &emsp;&emsp;`ShaftJoint` | `Joint3D` |


Two scripts:

- motor_drive.gd
- rotor_body.gd

are provided in [src/Motor/](./src/Motor/). Please refer to the README in the corresponding directory for a detailed overview.


For a more, overall, detailed overview of the implementation please refer to the [seminar report](./docs/Zaman-seminar_report.pdf) provided.
