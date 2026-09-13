class_name CustomerScreen
extends Control
## Accueil d'un client : appareil, plainte et délai promis.

signal start_pressed

@onready var _counter: Label = %Counter
@onready var _device: Label = %Device
@onready var _complaint: Label = %Complaint
@onready var _deadline: Label = %Deadline
@onready var _start_button: Button = %StartButton


func _ready() -> void:
	_start_button.pressed.connect(start_pressed.emit)


## À appeler une fois la scène dans l'arbre.
func setup(job: RepairJob, number: int, total: int) -> void:
	_counter.text = "Customer %d of %d" % [number, total]
	_device.text = job.device.name
	_complaint.text = "\"%s\"" % job.complaint
	_deadline.text = "Promised in %s" % UiFormat.time(job.deadline_s)
