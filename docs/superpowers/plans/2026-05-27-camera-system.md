# Camera System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a two-camera pixel-perfect rendering system using SubViewport that works correctly in both fullscreen and windowed mode.

**Architecture:** LowResCamera (Camera2D inside SubViewport) pixel-snaps to the player's integer position each visual frame. HighResCamera (Camera2D in the main scene, outside SubViewport) applies smooth lerp with velocity lead-ahead at zoom=3, giving an effective 640x360 visible area. Scene restructuring in main.tscn is done by the user in the Godot editor — no .tscn files are created or modified by code.

**Tech Stack:** Godot 4.x, GDScript, SubViewport/SubViewportContainer

---

### Task 1: Create LowResCamera script

**Files:**
- Create: `world/cameras/low_res_camera.gd`

- [ ] **Step 1: Create the cameras folder and script**

```gdscript
# world/cameras/low_res_camera.gd
class_name LowResCamera extends Camera2D

@export var follow_target: Player

func _process(_delta: float) -> void:
	global_position = follow_target.global_position.round()
```

- [ ] **Step 2: Verify it parses without errors**

```bash
godot --headless --path /home/migu/repos/GitHub/mortalportal --quit 2>&1 | grep -i "error\|script"
```

Expected: no SCRIPT ERROR lines referencing `low_res_camera.gd`.

- [ ] **Step 3: Commit**

```bash
git add world/cameras/low_res_camera.gd
git commit -m "Add LowResCamera script"
```

---

### Task 2: Create HighResCamera script

**Files:**
- Create: `world/cameras/high_res_camera.gd`

- [ ] **Step 1: Write the script**

```gdscript
# world/cameras/high_res_camera.gd
class_name HighResCamera extends Camera2D

@export var sub_viewport_container: SubViewportContainer
@export var player: Player
@export var smooth_speed: float = 3.0
@export var velocity_influence: float = 0.2

const MAX_OFFSET := 50.0

func _physics_process(delta: float) -> void:
	var center_pos := sub_viewport_container.global_position + Vector2(sub_viewport_container.size) / 2.0
	var target_offset := player.velocity * velocity_influence
	target_offset.x = clamp(target_offset.x, -MAX_OFFSET, MAX_OFFSET)
	target_offset.y = clamp(target_offset.y, -MAX_OFFSET, MAX_OFFSET)
	global_position = global_position.lerp(center_pos + target_offset, smooth_speed * delta)
```

- [ ] **Step 2: Verify it parses without errors**

```bash
godot --headless --path /home/migu/repos/GitHub/mortalportal --quit 2>&1 | grep -i "error\|script"
```

Expected: no SCRIPT ERROR lines referencing `high_res_camera.gd`.

- [ ] **Step 3: Commit**

```bash
git add world/cameras/high_res_camera.gd
git commit -m "Add HighResCamera script"
```

---

### Task 3: Restructure main.tscn (user action in Godot editor)

**Files:**
- Modify: `world/main.tscn` (editor only)

This task is performed by the user in the Godot editor. Document it here for completeness.

- [ ] **Step 1: Add SubViewportContainer**

In `world/main.tscn`, add a `SubViewportContainer` as a child of `Main`. Set its layout to **Full Rect** (anchors preset). Set `Handle Input Locally = false` in the Inspector.

- [ ] **Step 2: Add SubViewport inside the container**

Add a `SubViewport` as a child of `SubViewportContainer`. Set:
- `Size = Vector2i(1920, 1080)`
- `Disable 3D = true`
- `Handle Input Locally = false`
- `Default Texture Filter = Nearest` (canvas_item_default_texture_filter = 0)
- `Audio Listener Enable 2D = true`
- `Render Target Update Mode = Always`

- [ ] **Step 3: Move Player and LevelController inside SubViewport**

Drag `Player` and `LevelController` to become children of `SubViewport`. Re-wire `LevelController`'s `@export player` to point to `SubViewport/Player`.

- [ ] **Step 4: Add LowResCamera inside SubViewport**

Add a `Camera2D` node as a child of `SubViewport`. Assign the script `world/cameras/low_res_camera.gd`. Set `@export follow_target` to `SubViewport/Player`.

- [ ] **Step 5: Add HighResCamera in main scene**

Add a `Camera2D` node as a direct child of `Main` (sibling of `SubViewportContainer`). Assign the script `world/cameras/high_res_camera.gd`. Set:
- `Zoom = Vector2(3, 3)`
- `@export sub_viewport_container` → `SubViewportContainer`
- `@export player` → `SubViewportContainer/SubViewport/Player`

- [ ] **Step 6: Save the scene**

Save `world/main.tscn`. Then commit from the terminal:

```bash
git add world/main.tscn characters/player/player.tscn
git commit -m "Restructure main.tscn for SubViewport camera system"
```

---

### Task 4: Verify end-to-end

- [ ] **Step 1: Headless parse check**

```bash
godot --headless --path /home/migu/repos/GitHub/mortalportal --quit 2>&1 | grep -E "ERROR|SCRIPT ERROR"
```

Expected: no errors.

- [ ] **Step 2: Run the game in windowed mode**

Open the project in the Godot editor and run `world/main.tscn`. Confirm:
- Player is visible and standing on the level platform.
- Camera follows the player smoothly.
- Running left/right produces a slight velocity lead-ahead offset.
- No black screen or misaligned view in windowed mode.

- [ ] **Step 3: Run in a smaller window**

Resize the editor game window to a non-fullscreen size. Confirm the game scales correctly with no clipping or broken camera.
