# VALKREN Inner Frame Reference (spec 2026-10-03)

Unarmored mechanical-skeleton reference for the ~5 m Valkren class.
**INNER FRAME = structural and animation authority. PILOT = internal
human-scale constraint. OUTER ARMOR = separate modular shell.**

## Files

| File | Purpose |
| ---- | ------- |
| `tools/valkren_innerframe_reference.gd` | Builder; `DIMS` dict is the single source of truth, `build()` returns the rig, `save_scene()` writes the asset |
| `scenes/mecha/valkren_innerframe_reference.tscn` | Saved reference scene ( Godot 4.6.2, meters, Up +Y, Forward -Z). Open in editor, use CamFront/CamSide/CamRear |
| `imgs/valkren_innerframe_ref/{front,side,rear,three_quarter}.png` | Orthographic reference renders with dimension callouts |
| `test/unit/valkren_innerframe_reference_verify.{gd,tscn}` | Pins every dimension below + production-untouched guard (23 checks) |

## Dimension table (meters, rest pose)

| Landmark | Value | Joint / part |
| -------- | ----- | ------------ |
| Overall height | 4.95 | foot sole 0.00 → head top 4.95 |
| Shoulder span | 1.70 | JNT_ShoulderL/R at (±0.85, 4.40) |
| Upper arm | 0.95 | shoulder 4.40 → elbow 3.45 |
| Forearm | 1.15 | elbow 3.45 → wrist 2.30 |
| Hand | 0.40 | wrist 2.30 → fingertip 1.90 |
| Hip span | 1.10 | JNT_HipL/R at (±0.55, 2.85) |
| Thigh | 1.15 | hip 2.85 → knee 1.70 |
| Shin | 1.45 | knee 1.70 → ankle 0.25 |
| Foot | 0.90 × 0.55 | heel → toe, planted at 0.00 |
| Head | 0.40 × 0.35 | sensor block 4.55 → 4.95 |
| Torso hip–neck | 1.70 | hip 2.85 → neck 4.55 |
| Chest structure | 1.60 | ChestBeam, armor excluded |
| Standing pilot | 1.80 | reference capsule beside frame |
| Seated pilot | ~1.35 | inside tub, head top 4.14 < neck 4.55, width 0.42 < interior 0.89, boots on footwell pedals |

## Layering (strict)

```text
Pilot (180 cm, true meters, never rescaled)
  -> Cockpit (tub + seat + console + sticks + pedals + footwell)
    -> Inner Frame (beams, pelvis, spine, roll cage — dark steel)
      -> Joint Hardware (spheres, drums, axles, pistons — orange/chrome)
        -> Clearance Envelope (faint cyan shells around torso + limbs)
          -> Outer Armor (NOT part of this reference; separate shell)
```

Cockpit notes: split floor (seat zone 3.02 + sunken footwell 2.70);
boots rest on pedals (2.79 contact); cage posts/arch stay outboard of
the pilot volume; front beam moved to the footwell footer so the hatch
face and pilot visibility stay open.

## Production deltas (adoption map — production NOT modified)

| Landmark | Inner-ref (new) | Production (current, 5.33 m frame) |
| -------- | --------------: | ---------------------------------: |
| Overall | 4.95 | 5.33 |
| Shoulder span | 1.70 | 2.63 |
| Hip span | 1.10 | 1.47 |
| Upper arm | 0.95 | 0.73 |
| Forearm | 1.15 | ~0.91 |
| Thigh | 1.15 | 1.54 |
| Shin | 1.45 | 1.48 |
| Seated pilot | 1.35 | 1.09 |

Adopting the new standard means moving production pivots toward the
left column (tscn + HANGAR_POSE + MSS PIVOTS + dummy rest tables +
pinned tests). That migration is a separate design decision and is
**not** part of this reference delivery.

## Negative constraints (enforced by test)

* No second skeleton: InnerRig 2.7 m GLB and the 5.8 m Zenith figure
  are not production scales and are not referenced here.
* Armor never moves joints: `valkren_innerframe_reference_verify`
  asserts production `mecha_base.tscn` pivots are byte-identical.
* No armor geometry in the reference scene (envelopes only).
* Cockpit sized to the pilot, not the reverse.
