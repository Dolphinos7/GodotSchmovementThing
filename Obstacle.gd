extends Area3D

@export var time_penalty: float = 3.0 # seconds added to your run when touched

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if body.has_method("add_time_penalty"):
		body.add_time_penalty(time_penalty)
