# SaveManager.gd — Slot-based save system using JSON files.
# Architecture: Each slot stores state.json (game data) + meta.json (UI listing).
# Writes are atomic (write to .tmp, then rename) to prevent corruption on crash.
# Version field enables forward-compatible migration via _migrate().
# Nodes in the "persist" group implement save_to_state()/load_from_state().
extends Node

signal before_save(slot_id: int, state: Dictionary)
signal after_save(slot_id: int)
signal before_load(slot_id: int)
signal after_load(slot_id: int, state: Dictionary)

const SAVE_VERSION: int = 1
const SAVES_DIR := "user://saves"

var current_slot_id: int = 1

# --- Public API ---

func save_current_slot() -> Error:
    var state := _capture_state()
    return save_slot(current_slot_id, state)

func load_current_slot() -> Dictionary:
    return load_slot(current_slot_id)

func save_slot(slot_id: int, state: Dictionary) -> Error:
    _ensure_dir(SAVES_DIR)
    _ensure_dir(_slot_dir(slot_id))

    before_save.emit(slot_id, state)

    var wrapper := {
        "version": SAVE_VERSION,
        "saved_unix": Time.get_unix_time_from_system(),
        "data": state
    }

    # Write state.json atomically
    var state_path := _slot_state_path(slot_id)
    var err := _write_json_atomic(state_path, wrapper)
    if err != OK:
        return err

    var meta := _load_json_or_empty(_slot_meta_path(slot_id))
    if meta.is_empty():
        meta["created_unix"] = wrapper["saved_unix"]
    meta["updated_unix"] = wrapper["saved_unix"]
    meta["slot_id"] = slot_id
    meta["version"] = SAVE_VERSION

    meta["title"] = "Partida %d" % slot_id

    err = _write_json_atomic(_slot_meta_path(slot_id), meta)
    if err != OK:
        return err

    after_save.emit(slot_id)
    return OK

func load_slot(slot_id: int) -> Dictionary:
    before_load.emit(slot_id)

    var state_path := _slot_state_path(slot_id)
    if not FileAccess.file_exists(state_path):
        return {
            "ok": false,
            "err": ERR_FILE_NOT_FOUND,
            "state": {}
        }

    var wrapper := _load_json_or_empty(state_path)
    if wrapper.is_empty():
        return {
            "ok": false,
            "err": ERR_PARSE_ERROR,
            "state": {}
        }

    var file_version := int(wrapper.get("version", 0))
    var data: Dictionary = wrapper.get("data", {})

    if file_version != SAVE_VERSION:
        data = _migrate(data, file_version, SAVE_VERSION)

    _apply_state(data)
    after_load.emit(slot_id, data)

    return {
        "ok": true,
        "err": OK,
        "state": data
    }

func list_slots() -> Array[Dictionary]:
    _ensure_dir(SAVES_DIR)

    var out: Array[Dictionary] = []
    var dir := DirAccess.open(SAVES_DIR)
    if dir == null:
        return out

    dir.list_dir_begin()
    while true:
        var dir_name := dir.get_next()
        if dir_name == "":
            break
        if dir.current_is_dir() and dir_name.begins_with("slot_"):
            var meta_path := SAVES_DIR + "/" + dir_name + "/meta.json"
            var meta := _load_json_or_empty(meta_path)
            if not meta.is_empty():
                out.append(meta)
    dir.list_dir_end()
#
    ## Sort newest first
    #out.sort_custom(func(a: Dictionary, b: Dictionary):
        #return int(a.get("updated_unix", 0)) > int(b.get("updated_unix", 0))
    #)

    return out

# --- Persistence hooks via group ---

func _capture_state() -> Dictionary:
    var state: Dictionary = {}

    for node in get_tree().get_nodes_in_group("persist"):
        if node != null and node.has_method("save_to_state"):
            node.call("save_to_state", state)

    return state

func _apply_state(state: Dictionary) -> void:
    for node in get_tree().get_nodes_in_group("persist"):
        if node != null and node.has_method("load_from_state"):
            node.call("load_from_state", state)

# --- Type helpers (JSON-safe) ---

static func vec2_to_dict(v: Vector2) -> Dictionary:
    return {"x": v.x, "y": v.y}

static func dict_to_vec2(d: Dictionary) -> Vector2:
    return Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0)))

# --- Migrations (versioning)

func _migrate(data: Dictionary, from_version: int, to_version: int) -> Dictionary:
    # v0 -> v1 example (if you ever shipped v0)
    # if from_version == 0 and to_version >= 1:
    #     data["player"] = data.get("player", {})
    #     data["player"]["coins"] = int(data["player"].get("coins", 0))
    return data

# --- File helpers ---

func _slot_dir(slot_id: int) -> String:
    return "%s/slot_%04d" % [SAVES_DIR, slot_id]

func _slot_state_path(slot_id: int) -> String:
    return _slot_dir(slot_id) + "/state.json"

func _slot_meta_path(slot_id: int) -> String:
    return _slot_dir(slot_id) + "/meta.json"

func _ensure_dir(path: String) -> void:
    if DirAccess.dir_exists_absolute(path):
        return
    DirAccess.make_dir_recursive_absolute(path)

func _load_json_or_empty(path: String) -> Dictionary:
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null:
        return {}
    var text := f.get_as_text()
    f.close()

    var json := JSON.new()
    var err := json.parse(text)
    if err != OK:
        return {}
    var data = json.data
    return data if typeof(data) == TYPE_DICTIONARY else {}

func _write_json_atomic(path: String, data: Dictionary) -> Error:
    var tmp_path := path + ".tmp"

    var f := FileAccess.open(tmp_path, FileAccess.WRITE)
    if f == null:
        return FileAccess.get_open_error()

    var text := JSON.stringify(data, "\t")
    f.store_string(text)
    f.flush()
    f.close()

    if FileAccess.file_exists(path):
        var rm := DirAccess.remove_absolute(path)
        if rm != OK:
            return rm

    return DirAccess.rename_absolute(tmp_path, path)
