extends RefCounted
## Local bindings shared by formal input and F6 defaults. Reading does not persist them.
static func schema() -> Dictionary:
	var fields: Dictionary = {
		"direction_up": {"type": "array", "control": "binding", "default": [{"kind": "key", "code": KEY_UP, "physical": true}, {"kind": "key", "code": KEY_W, "physical": true}],
			"title": "向上", "action": "direction_up", "audience": "local", "apply": "immediate", "items": {"type": "object", "format": "binding"}, "max_items": 2, "combinations": false},
		"direction_right": {"type": "array", "control": "binding", "default": [{"kind": "key", "code": KEY_RIGHT, "physical": true}, {"kind": "key", "code": KEY_D, "physical": true}],
			"title": "向右", "action": "direction_right", "audience": "local", "apply": "immediate", "items": {"type": "object", "format": "binding"}, "max_items": 2, "combinations": false},
		"direction_down": {"type": "array", "control": "binding", "default": [{"kind": "key", "code": KEY_DOWN, "physical": true}, {"kind": "key", "code": KEY_S, "physical": true}],
			"title": "向下", "action": "direction_down", "audience": "local", "apply": "immediate", "items": {"type": "object", "format": "binding"}, "max_items": 2, "combinations": false},
		"direction_left": {"type": "array", "control": "binding", "default": [{"kind": "key", "code": KEY_LEFT, "physical": true}, {"kind": "key", "code": KEY_A, "physical": true}],
			"title": "向左", "action": "direction_left", "audience": "local", "apply": "immediate", "items": {"type": "object", "format": "binding"}, "max_items": 2, "combinations": false},
		"direction_undo": {"type": "array", "control": "binding", "default": [{"kind": "key", "code": KEY_BACKSPACE, "physical": true}],
			"title": "撤销", "action": "direction_undo", "audience": "local", "apply": "immediate", "items": {"type": "object", "format": "binding"}, "max_items": 2, "combinations": false},
		"direction_confirm": {"type": "array", "control": "binding", "default": [{"kind": "key", "code": KEY_ENTER, "physical": true}, {"kind": "key", "code": KEY_SPACE, "physical": true}, {"kind": "key", "code": KEY_KP_ENTER, "physical": true}],
			"title": "确认", "action": "direction_confirm", "audience": "local", "apply": "immediate", "items": {"type": "object", "format": "binding"}, "max_items": 3, "combinations": false},
		"direction_restart": {"type": "array", "control": "binding", "default": [{"kind": "key", "code": KEY_R, "physical": true}],
			"title": "重新开始", "action": "direction_restart", "audience": "local", "apply": "immediate", "items": {"type": "object", "format": "binding"}, "max_items": 2, "combinations": false}
	}
	var layout: Array[Dictionary] = []
	for key: String in fields:
		layout.append({"field": key})
	return {"schema_format": 3, "settings_version": 1, "fields": fields, "layout": layout}
