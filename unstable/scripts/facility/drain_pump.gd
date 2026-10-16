class_name DrainPump
extends Node
## Pumps water out of `source` into `target`, powered by the pressure network,
## at the rate set by its valve. Draining the storage room protects the bonus
## cargo and bleeds off pressure, but floods the lower facility.

@export var valve: Valve
@export var network: PressureNetwork
@export var source: FloodZone
@export var target: FloodZone
## Source level removed per second at 100% (metres).
@export var pump_rate := 0.035
## Share of the pumped water that ends up in the target zone.
@export var transfer_ratio := 0.6
## Extra target rise per second at 100% (pump discharge).
@export var discharge := 0.002
## Pressure spent per second at 100%.
@export var pressure_cost := 1.4

var mission: Mission


func _ready() -> void:
	mission = Mission.of(self)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or not mission.running():
		return
	if valve.opening <= 0.0 or network.pressure <= 2.0:
		return
	network.spend(valve.opening * pressure_cost * delta)
	var moved := minf(source.level, valve.opening * pump_rate * delta)
	source.add_water(-moved)
	target.add_water(moved * transfer_ratio + valve.opening * discharge * delta)
