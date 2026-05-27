# Player Design

Date: 2026-05-26
Branch: composition_refactor

## Scope

Port the player character from the prerefactor as a composition-based scene. Excludes the portal gun (deferred until LevelController is built) and mobile mode (PC-only for now).

## Scene structure

```
CharacterBody2D  (characters/player/player.gd)
├── AnimatedSprite2D
├── CollisionShape2D
├── PortalMovementComponent  (body = <root>, wired in editor)
└── Area2D  (enemy hitbox)
    └── CollisionShape2D
```

The user creates `characters/player/player.tscn` in the Godot editor.

`PortalMovementComponent` is wired via `@export var body: CharacterBody2D` set to the scene root in the editor. It owns the `move_and_collide` call. `player.gd` sets velocity each tick then calls `_movement.tick(delta)`.

## Physics constants

```
RUN_SPEED        = 400.0
ACCEL            = 1000.0
FRICTION         = 1000.0
GRAVITY          = 1500.0
JUMP_FORCE       = -400.0
MAX_FALL_SPEED   = 2000.0
JUMP_BUFFER_TIME = 0.15
COYOTE_TIME      = 0.10
```

## player.gd responsibilities

Four concerns, all inline:

1. **Gravity + jump** - applies gravity each tick when not grounded. Two timers enable forgiving jump feel:
   - Jump buffer: pressing jump sets `_jump_buffer = JUMP_BUFFER_TIME`; decrements each tick; fires jump when `_jump_buffer > 0` and the player is eligible to jump.
   - Coyote time: when grounded, `_coyote_timer` resets to `COYOTE_TIME`; decrements each tick while airborne. Jump is eligible when `is_grounded or _coyote_timer > 0`. Both timers reset to 0 on jump.
2. **Horizontal movement** - `move_toward` with ACCEL toward run speed, FRICTION toward zero.
3. **Aim flip** - `animated_sprite_2d.flip_h` set from mouse x vs player global x each tick. (Future: gun pivot will read aim direction independently.)
4. **Animation** - 4-state selector in priority order: `jump` (velocity.y outside ±50), `crouch` ("down" action held), `run` (abs(velocity.x) > 20), `idle`.

After all movement is resolved: `global_position = global_position.round()` to prevent subpixel shimmer on pixel art sprites.

## Enemy hitbox

`Area2D` child with a `CollisionShape2D` roughly matching the player body collider. Collision layer 0, collision mask set to the enemies physics layer. `body_entered` signal connects to `player.gd`. Handler calls `die()` if the entering body is in the "enemies" group.

## Public interface

```gdscript
signal died

func die() -> void       # hides sprite, disables processing, emits died
func respawn(pos: Vector2) -> void  # resets position/velocity, re-enables processing, shows sprite
```

`_alive: bool` is private state guarding both methods against double-calls.

## Files

- `characters/player/player.gd` - new file (this session), `class_name Player`
- `characters/player/player.tscn` - created by user in editor

## Out of scope

- Portal gun / gun_pivot - blocked on LevelController
- Mobile mode / joystick aim
- HealthComponent / damage system (player dies on any enemy contact for now)
