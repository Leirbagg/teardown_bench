class_name Dag
extends RefCounted
## Utilitaires de graphe orienté. Les arêtes sont un Dictionary : id -> PackedStringArray des cibles.
## Les cibles absentes des clés sont ignorées : le validateur les signale séparément.

enum _Mark { UNVISITED, IN_PROGRESS, DONE }


## Renvoie le premier cycle trouvé sous forme de chemin fermé (["a", "b", "a"]), ou un tableau vide.
static func find_cycle(edges: Dictionary) -> PackedStringArray:
	var marks: Dictionary = {}
	var path: Array[String] = []
	for node: String in edges:
		if marks.get(node, _Mark.UNVISITED) == _Mark.UNVISITED:
			var cycle: PackedStringArray = _visit(node, edges, marks, path)
			if not cycle.is_empty():
				return cycle
	return PackedStringArray()


static func _visit(node: String, edges: Dictionary, marks: Dictionary, path: Array[String]) -> PackedStringArray:
	marks[node] = _Mark.IN_PROGRESS
	path.append(node)
	for target: String in edges[node]:
		if not edges.has(target):
			continue
		var mark: int = marks.get(target, _Mark.UNVISITED)
		if mark == _Mark.IN_PROGRESS:
			var cycle: PackedStringArray = PackedStringArray(path.slice(path.find(target)))
			cycle.append(target)
			return cycle
		if mark == _Mark.UNVISITED:
			var found: PackedStringArray = _visit(target, edges, marks, path)
			if not found.is_empty():
				return found
	path.pop_back()
	marks[node] = _Mark.DONE
	return PackedStringArray()
