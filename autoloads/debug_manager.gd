extends Node

class Save:
    static func save_current_slot() -> void:
        print("Status: %s" % str(SaveManager.save_current_slot()))

    static func load_current_slot() -> void:
        print("Load: %s" % SaveManager.load_current_slot())

    static func reset_current_slot() -> void:
        print("Status: %s" % str(SaveManager.reset_current_slot()))
