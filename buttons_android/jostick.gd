extends Control

@onready var knob = $palanca

var max_radius := 80.0
var dragging := false
var touch_index := -1
var direction := Vector2.ZERO


func _ready():
	reset_stick()


func _gui_input(event):

	if event is InputEventScreenTouch:

		if event.pressed and touch_index == -1:
			dragging = true
			touch_index = event.index

		elif not event.pressed and event.index == touch_index:
			reset_stick()


	elif event is InputEventScreenDrag:

		if dragging and event.index == touch_index:

			var center = size / 2
			var offset = event.position - center

			if offset.length() > max_radius:
				offset = offset.normalized() * max_radius

			knob.position = center + offset - knob.size / 2
			direction = offset / max_radius


func reset_stick():

	dragging = false
	touch_index = -1
	direction = Vector2.ZERO

	var center = size / 2
	knob.position = center - knob.size / 2


func get_direction():
	return direction
