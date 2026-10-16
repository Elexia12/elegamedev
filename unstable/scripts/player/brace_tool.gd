class_name BraceTool
extends CrewTool
## Structural brace. LMB an orange brace plate to place one of the team's
## braces. RMB (or R with any tool) takes it back.


func primary(target: InteractPoint) -> void:
	if handles_point(target):
		crew.mission.send("brace_place", crew.path_to(target))


func secondary(target: InteractPoint) -> void:
	if handles_point(target):
		crew.mission.send("brace_remove", crew.path_to(target))


func prompt(target: InteractPoint) -> String:
	var what := target.describe()
	var socket := target.get_parent() as BraceSocket
	if socket.braced:
		return "%s brace %d%% · RMB/[R] recover brace" % [what, roundi(socket.integrity)]
	var why := socket.block_reason()
	if why != "":
		return "%s · %s" % [what, why]
	return "%s · LMB place brace (%d left)" % [what, crew.mission.toolkit.braces_left]
