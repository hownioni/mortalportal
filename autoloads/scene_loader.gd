extends Node

signal progress_changed(progress)
signal load_finished

var loading_screen: PackedScene = null
var loaded_resource: PackedScene
