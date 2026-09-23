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
func setup(job: RepairJob, number: int, total: int, workshop: Workshop) -> void:
	_counter.text = "Repair %d · $%d" % [workshop.day, workshop.money] if total == 1 \
		else "Day %d · Customer %d of %d · $%d" % [workshop.day, number, total, workshop.money]
	_device.text = job.device.name
	_complaint.text = "\"%s\"" % job.complaint
	var price: int = 0
	for fault: FaultDefinition in job.faults:
		price += fault.price
	_deadline.text = "Pays $%d · promised in %s" % [price, UiFormat.time(job.deadline_s)]
