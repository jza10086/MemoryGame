## Lightweight catalog data. Do not load gameplay scenes or scripts here.
extends RefCounted

static func party_definition() -> Dictionary:
	return {"player_counts": [1], "controls": {"direction_up": "向上", "direction_right": "向右", "direction_down": "向下", "direction_left": "向左", "direction_undo": "撤销", "direction_confirm": "确认", "direction_restart": "重新开始"}}
