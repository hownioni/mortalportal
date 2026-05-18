extends Button


func _ready():

	update_text()


func _pressed():

	GameSettings.mobile_mode = !GameSettings.mobile_mode

	update_text()


func update_text():

	if GameSettings.mobile_mode:

		text = "Modo: Movil"

	else:

		text = "Modo: PC"
