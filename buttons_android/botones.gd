extends CanvasLayer


func _ready():

	if GameSettings.mobile_mode:

		show()

	else:

		hide()
		process_mode = Node.PROCESS_MODE_DISABLED
func _on_top_pressed() -> void:
	
	$Control/Top.modulate= Color(1,0.5,0.5)

func _on_top_released() -> void:
	$Control/Top.modulate= Color(1,1,1)

func _on_right_pressed() -> void:
	$Control/right.modulate= Color(1,0.5,0.5)

func _on_right_released() -> void:
	$Control/right.modulate= Color(1,1,1)


func _on_left_pressed() -> void:
	$Control/left.modulate= Color(1,0.5,0.5)

func _on_left_released() -> void:
	$Control/left.modulate= Color(1,1,1)

func _on_cuadrado_pressed() -> void:
	$Control/Cuadrado.modulate= Color(1,0.5,0.5)


func _on_cuadrado_released() -> void:
	$Control/Cuadrado.modulate= Color(1,1,1)


func _on_circulo_pressed() -> void:
	$Control/Circulo.modulate= Color(1,0.5,0.5)


func _on_circulo_released() -> void:
	$Control/Circulo.modulate= Color(1,1,1)


func _on_pause_pressed() -> void:
	$Control/Pause.modulate= Color(1,0.5,0.5)

func _on_pause_released() -> void:
	$Control/Pause.modulate= Color(1,1,1)
