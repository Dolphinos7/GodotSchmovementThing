extends Area3D

@export var time_bonus: float = 2.0 # seconds subtracted from your run when grabbed

func _ready() -> void:
	add_to_group("coins")
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if body.has_method("add_time_penalty"):
		body.add_time_penalty(-time_bonus)
		_collect()

func _collect() -> void:
	set_deferred("monitoring", false)
	visible = false

# Called by the player on respawn (see Schmove.gd) so the coin is available
# again on the next attempt instead of staying grabbed forever.
func reset() -> void:
	set_deferred("monitoring", true)
	visible = true
