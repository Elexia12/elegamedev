class_name Level
extends Node2D
## Builds a level from an ASCII map. One character = one 32x32 tile.
##
##   #  solid ground          =  vapor vent (only vapor passes)   -  one-way platform
##   B  breakable block       ^  spikes                           o  dew drop
##   P  player start          K  checkpoint                       G  goal (Shiny Puddle)
##   E  sponge (walker)       X  urchin (spiky walker)            F  dust moth (flyer)
##   C  cold modifier (ice)   H  hot modifier (vapor)             S  size modifier (big)

const T := GameConst.TILE

const MAP := [
	"##################################################################################################################################################",
	"#                                            ##################                                             ##              ######################",
	"#                                            ##################                                             ##              ######################",
	"#                                            ##################                                             ##              ######################",
	"#                                            ##################                                             ##              ######################",
	"#                                            ##################                                             ##              ######################",
	"#                                            ##################                                             ##              ######################",
	"#                                            ##################                                             ##              ######################",
	"#                                            ##################          ooo    K         F                 ##              ######################",
	"#                                            ##################        #####===######  ------               ##              ######################",
	"#                                            ##################        #####===######                       ##              ######################",
	"#                                F           ##################                    ##                       ##              ######################",
	"#                        oo                  ##################                    ##                       BB              ######################",
	"#        oo              --                  ##################                    ##                       BB              ######################",
	"#       ----   o                             ##################                    ##                       BB              ######################",
	"#             ###                                   o    o                         ##                       BB              ######################",
	"#  P          ###   E          E     K  C        X    X    X      K  H             ##    E   X   K   S      BB   E  X  E    ######################",
	"########################    ###########################################################################################BBBB#######################",
	"########################    ###########################################################################################BBBB#######################",
	"########################    ###########################################################################################                         ##",
	"########################    ###########################################################################################   o                     ##",
	"########################^^^^###########################################################################################       ^^     oo     G   ##",
	"##################################################################################################################################################",
	"##################################################################################################################################################",
]

var tiles := {}        # Vector2i -> "#", "=" or "-" (used for drawing)
var player_start := Vector2.ZERO
var pixel_size := Vector2.ZERO
var dew_count := 0
var _breakables := {}  # Vector2i -> Breakable


func build() -> void:
	var width := 0
	for row: String in MAP:
		width = maxi(width, row.length())
	pixel_size = Vector2(width, MAP.size()) * T

	var drawer := TileDrawer.new()
	drawer.level = self
	add_child(drawer)

	for y in MAP.size():
		var row: String = MAP[y]
		var x := 0
		while x < row.length():
			var c := row[x]
			var center := (Vector2(x, y) + Vector2(0.5, 0.5)) * T
			match c:
				"#", "=", "-":
					# Merge horizontal runs of the same tile into one collider.
					var x2 := x
					while x2 + 1 < row.length() and row[x2 + 1] == c:
						x2 += 1
					_add_run(x, x2, y, c)
					for i in range(x, x2 + 1):
						tiles[Vector2i(i, y)] = c
					x = x2
				"B":
					var b := Breakable.new()
					b.cell = Vector2i(x, y)
					b.level = self
					b.position = center
					add_child(b)
					_breakables[b.cell] = b
				"P":
					player_start = center
				"E", "X", "F":
					var e := Enemy.new()
					e.kind = {"E": Enemy.Kind.WALKER, "X": Enemy.Kind.SPIKY, "F": Enemy.Kind.FLYER}[c]
					e.position = center
					add_child(e)
				"C", "H", "S":
					var m := Modifier.new()
					m.kind = {"C": GameConst.Mod.COLD, "H": GameConst.Mod.HOT, "S": GameConst.Mod.SIZE}[c]
					m.position = center
					add_child(m)
				"o", "K", "^", "G":
					var trig := LevelTrigger.new()
					trig.kind = {"o": LevelTrigger.Kind.DEW, "K": LevelTrigger.Kind.CHECKPOINT,
							"^": LevelTrigger.Kind.SPIKES, "G": LevelTrigger.Kind.GOAL}[c]
					trig.position = center
					add_child(trig)
					if c == "o":
						dew_count += 1
			x += 1
	drawer.queue_redraw()


func _add_run(x1: int, x2: int, y: int, c: String) -> void:
	var body := StaticBody2D.new()
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	var w := (x2 - x1 + 1) * T
	body.collision_layer = GameConst.LAYER_MESH if c == "=" else GameConst.LAYER_WORLD
	body.collision_mask = 0
	if c == "-":
		rs.size = Vector2(w, 10)
		cs.one_way_collision = true
		body.position = Vector2(x1 * T + w / 2.0, y * T + 5)
	else:
		rs.size = Vector2(w, T)
		body.position = Vector2(x1 * T + w / 2.0, (y + 0.5) * T)
	cs.shape = rs
	body.add_child(cs)
	add_child(body)


func tile_at(cell: Vector2i) -> String:
	return tiles.get(cell, "")


func break_cluster(start: Vector2i) -> void:
	# Flood-fill connected breakables; stagger them for a crumbling effect.
	var queue: Array[Vector2i] = [start]
	var seen := {start: 0}
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		var b: Breakable = _breakables.get(cell)
		if b == null:
			continue
		b.break_now(seen[cell] * 0.05)
		_breakables.erase(cell)
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = cell + d
			if _breakables.has(n) and not seen.has(n):
				seen[n] = seen[cell] + 1
				queue.append(n)


class TileDrawer extends Node2D:
	var level: Level

	func _draw() -> void:
		var t := float(GameConst.TILE)
		for cell: Vector2i in level.tiles:
			var c: String = level.tiles[cell]
			var r := Rect2(Vector2(cell) * t, Vector2(t, t))
			match c:
				"#":
					var exposed := level.tile_at(cell + Vector2i.UP) != "#"
					var inner := not exposed and level.tile_at(cell + Vector2i.DOWN) == "#" \
							and level.tile_at(cell + Vector2i.LEFT) == "#" and level.tile_at(cell + Vector2i.RIGHT) == "#"
					draw_rect(r, Color(0.36, 0.27, 0.22) if inner else Color(0.47, 0.36, 0.28))
					var h := absi(hash(cell))
					for k in 3:
						var p := r.position + Vector2((h >> (k * 4)) % 28 + 2, (h >> (k * 4 + 12)) % 24 + 6)
						draw_rect(Rect2(p, Vector2(3, 2)), Color(0.3, 0.22, 0.18, 0.6))
					if exposed and cell.y > 0:
						draw_rect(Rect2(r.position, Vector2(t, 7)), Color(0.36, 0.72, 0.38))
						draw_rect(Rect2(r.position + Vector2(0, 7), Vector2(t, 3)), Color(0.24, 0.52, 0.28))
				"=":
					draw_rect(r, Color(0.22, 0.24, 0.3, 0.75))
					for k in 5:
						draw_line(r.position + Vector2(k * 8 + 2, 0), r.position + Vector2(k * 8 + 2, t), Color(0.6, 0.65, 0.75), 2.0)
					draw_line(r.position + Vector2(0, t / 2), r.position + Vector2(t, t / 2), Color(0.45, 0.5, 0.6), 2.0)
				"-":
					draw_rect(Rect2(r.position, Vector2(t, 9)), Color(0.62, 0.45, 0.28))
					draw_rect(Rect2(r.position + Vector2(0, 7), Vector2(t, 2)), Color(0.42, 0.3, 0.18))
					draw_line(r.position + Vector2(t - 1, 0), r.position + Vector2(t - 1, 9), Color(0.42, 0.3, 0.18), 1.0)
