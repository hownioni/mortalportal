extends Node

var curr_save_file: int = 0
var save_file_name: String = "user://save.json"
const default_dictionary: Dictionary = {
    "level": 1,
    "time_elapsed": 0.0
}

func save_game(save_num:int, data: Dictionary) -> void:
    save_file_name = "user://save" + str(save_num) + ".json"
    var save_file: FileAccess = FileAccess.open(save_file_name, FileAccess.WRITE)
    if save_file == null:
        push_error("Error opening file")
        return
    
    var string_data: String = JSON.stringify(data)
    save_file.store_line(string_data)
    save_file.close()
    
func load_game(save_num:int) -> Dictionary:
    save_file_name = "user://save" + str(save_num) + ".json"
    if FileAccess.file_exists(save_file_name):
        var save_file: FileAccess = FileAccess.open(save_file_name, FileAccess.READ)
        if save_file == null:
            push_error("Error reading file")
            return default_dictionary
        
        var json = JSON.new()
        
        var string_data: String = save_file.get_line()
        if json.parse(string_data) == OK:
            var data: Dictionary = json.get_data()
            save_file.close()
            return data
        push_error("Corrupted data")

    return default_dictionary

func reset_game(save_num: int) -> void:
    save_game(save_num, default_dictionary)
