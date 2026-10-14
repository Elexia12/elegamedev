class_name FormTuning
extends Resource
## Movement numbers for one droplet form. Edit them on the Player in the Inspector.

@export var speed := 230.0
@export var accel := 1500.0       ## ground acceleration toward target speed
@export var air_accel := 1000.0
@export var friction := 1100.0    ## ground deceleration with no input (low = slides)
@export var gravity := 1250.0
@export var jump := 600.0
@export var max_fall := 700.0
