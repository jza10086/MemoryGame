## Standalone F6 memory prototype. Owns only its UI and local round state.
## Deliberately has no manifest, PartyAPI, networking or persistent settings.
extends Control

const RULES: GDScript = preload("direction_password_rules.gd")
const ARROWS: Array[String] = ["↑", "→", "↓", "←"]
const NAMES: Array[String] = ["上", "右", "下", "左"]
const ACCENT: Color = Color("#6ce5c2")
const TEXT: Color = Color("#edf4ff")
const MUTED: Color = Color("#9aaec9")
const WRONG: Color = Color("#ff997d")
const PREPARE_SECONDS: float = 2.0

enum Phase { READY, PREPARE, SHOW, GAP, ANSWER, REVIEW, FINISHED }

@export_range(0.3, 2.0, 0.05) var arrow_seconds: float = 0.85
@export_range(0.1, 1.0, 0.05) var gap_seconds: float = 0.25

@onready var _board: PanelContainer = %Board
@onready var _phase_label: Label = %PhaseLabel
@onready var _hero: Label = %HeroLabel
@onready var _hint: Label = %HintLabel
@onready var _progress: ProgressBar = %PhaseProgress
@onready var _answer_caption: Label = %AnswerCaption
@onready var _answer_row: HBoxContainer = %AnswerRow
@onready var _expected_caption: Label = %ExpectedCaption
@onready var _expected_row: HBoxContainer = %ExpectedRow
@onready var _summary_rows: VBoxContainer = %SummaryRows
@onready var _feedback: Label = %FeedbackLabel
@onready var _score_label: Label = %ScoreLabel
@onready var _primary: Button = %PrimaryButton
@onready var _undo: Button = %UndoButton
@onready var _restart: Button = %RestartButton

var phase: Phase = Phase.READY
var round_index: int = -1
var sequence: Array[int] = []
var answers: Array[int] = []
var total_score: int = 0
var total_correct: int = 0
var total_positions: int = 0
var round_results: Array[Dictionary] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _direction_buttons: Array[Button] = []
var _answer_tiles: Array[Label] = []
var _shown_index: int = 0
var _time_left: float = 0.0
var _phase_duration: float = 1.0

func _ready() -> void:
	assert(arrow_seconds > 0.0 and gap_seconds > 0.0, "Presentation durations must be positive.")
	_direction_buttons = [%UpButton, %RightButton, %DownButton, %LeftButton]
	for direction: int in range(_direction_buttons.size()):
		_direction_buttons[direction].pressed.connect(enter_direction.bind(direction))
	_primary.pressed.connect(activate_primary)
	_undo.pressed.connect(undo_direction)
	_restart.pressed.connect(reset_game)
	_rng.randomize()
	_style_ui()
	reset_game()

func _process(delta: float) -> void:
	if phase not in [Phase.PREPARE, Phase.SHOW, Phase.GAP, Phase.ANSWER]:
		return
	_time_left = maxf(0.0, _time_left - delta)
	_progress.value = _time_left / _phase_duration
	if phase == Phase.PREPARE:
		_hero.text = str(maxi(1, ceili(_time_left)))
	elif phase == Phase.ANSWER:
		_hint.text = "剩余 %d 秒 · 输入后可撤销，全部填好再提交" % ceili(_time_left)
	if _time_left > 0.0:
		return
	# Only advance one display step per frame: a stalled frame must not skip arrows.
	match phase:
		Phase.PREPARE:
			_show_direction()
		Phase.SHOW:
			_hero.text = ""
			_hint.text = "记住顺序，等待下一个方向…"
			_set_timed_phase(Phase.GAP, gap_seconds)
		Phase.GAP:
			_shown_index += 1
			if _shown_index < sequence.size():
				_show_direction()
			else:
				_begin_answer()
		Phase.ANSWER:
			_finish_round(true)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo or key_event.ctrl_pressed or key_event.alt_pressed or key_event.meta_pressed:
		return
	var key: int = key_event.physical_keycode if key_event.physical_keycode != 0 else key_event.keycode
	match key:
		KEY_UP, KEY_W:
			enter_direction(0)
		KEY_RIGHT, KEY_D:
			enter_direction(1)
		KEY_DOWN, KEY_S:
			enter_direction(2)
		KEY_LEFT, KEY_A:
			enter_direction(3)
		KEY_BACKSPACE:
			undo_direction()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			activate_primary()
		_:
			return
	get_viewport().set_input_as_handled()

## Starts a fresh session immediately; no delayed callbacks survive a restart.
func reset_game() -> void:
	phase = Phase.READY
	round_index = -1
	sequence.clear()
	answers.clear()
	round_results.clear()
	total_score = 0
	total_correct = 0
	total_positions = 0
	_time_left = 0.0
	_answer_tiles.clear()
	_clear_children(_answer_row)
	_clear_children(_expected_row)
	_clear_children(_summary_rows)
	_hero.show()
	_answer_row.show()
	_summary_rows.hide()
	_expected_row.hide()
	_expected_caption.hide()
	_progress.value = 1.0
	_phase_label.text = "单人练习  /  6 轮"
	_hero.text = "↑  →  ↓  ←"
	_hero.modulate = TEXT
	_hint.text = "从 3 个方向开始，每轮增加 1 个，最后一轮 8 个。"
	_answer_caption.text = "准备好后，点击「开始记忆」"
	_feedback.text = "每个正确位置 +100 分 · 全对额外 +100 分 · 无速度加分"
	_feedback.modulate = MUTED
	_update_score()
	_refresh_controls()

## The same semantic actions serve keyboard and mouse, independently of InputMap.
func activate_primary() -> void:
	match phase:
		Phase.READY:
			_begin_round()
		Phase.ANSWER:
			if answers.size() == sequence.size():
				_finish_round(false)
		Phase.REVIEW:
			if round_index + 1 < RULES.ROUND_COUNT:
				_begin_round()
			else:
				_show_summary()
		Phase.FINISHED:
			reset_game()
			_begin_round()

func enter_direction(direction: int) -> void:
	if phase != Phase.ANSWER or direction < 0 or direction >= ARROWS.size() or answers.size() >= sequence.size():
		return
	answers.append(direction)
	_refresh_answer_tiles(false)
	_refresh_controls()

func undo_direction() -> void:
	if phase != Phase.ANSWER or answers.is_empty():
		return
	answers.pop_back()
	_refresh_answer_tiles(false)
	_refresh_controls()

func _begin_round() -> void:
	round_index += 1
	sequence = RULES.make_sequence(RULES.sequence_length(round_index), _rng)
	answers.clear()
	_shown_index = 0
	_expected_row.hide()
	_expected_caption.hide()
	_summary_rows.hide()
	_clear_children(_expected_row)
	_answer_tiles.clear()
	_clear_children(_answer_row)
	for index: int in range(sequence.size()):
		var tile: Label = _make_tile(str(index + 1), MUTED)
		_answer_row.add_child(tile)
		_answer_tiles.append(tile)
	_hero.show()
	_answer_row.show()
	_phase_label.text = "第 %d / %d 轮 · 准备观察" % [round_index + 1, RULES.ROUND_COUNT]
	_hero.text = str(int(PREPARE_SECONDS))
	_hero.modulate = TEXT
	_hint.text = "本轮 %d 个方向 · 相同方向也可能连续出现" % sequence.size()
	_answer_caption.text = "观察时不能输入"
	_feedback.text = "先记顺序，等全部方向消失后再作答。"
	_feedback.modulate = MUTED
	_set_timed_phase(Phase.PREPARE, PREPARE_SECONDS)
	_refresh_controls()

func _show_direction() -> void:
	_phase_label.text = "第 %d / %d 轮 · 观察记忆" % [round_index + 1, RULES.ROUND_COUNT]
	_hero.text = ARROWS[sequence[_shown_index]]
	_hero.modulate = ACCENT
	_hint.text = "第 %d / %d 个方向 · %s" % [_shown_index + 1, sequence.size(), NAMES[sequence[_shown_index]]]
	for index: int in range(_answer_tiles.size()):
		_answer_tiles[index].modulate = ACCENT if index == _shown_index else MUTED
	_set_timed_phase(Phase.SHOW, arrow_seconds)

func _begin_answer() -> void:
	_phase_label.text = "第 %d / %d 轮 · 回忆输入" % [round_index + 1, RULES.ROUND_COUNT]
	_hero.text = "?"
	_hero.modulate = TEXT
	_hint.text = "按记忆输入方向，填满后按 Enter 提交。"
	_feedback.text = "可以撤销修改；提交前不会提示对错。超时会自动结算。"
	_refresh_answer_tiles(false)
	_set_timed_phase(Phase.ANSWER, float(sequence.size()) * 3.0 + 4.0)
	_refresh_controls()

func _set_timed_phase(next_phase: Phase, duration: float) -> void:
	phase = next_phase
	_phase_duration = duration
	_time_left = duration
	_progress.value = 1.0

## Locks the round before scoring, so timeout and submission cannot award twice.
func _finish_round(timed_out: bool) -> void:
	if phase != Phase.ANSWER:
		return
	phase = Phase.REVIEW
	var result: Dictionary[String, Variant] = RULES.score_answers(sequence, answers)
	round_results.append(result)
	total_score += int(result["points"])
	total_correct += int(result["correct"])
	total_positions += int(result["total"])
	_phase_label.text = "第 %d / %d 轮 · %s" % [round_index + 1, RULES.ROUND_COUNT, "时间到" if timed_out else "答案揭晓"]
	_hero.text = "+%d" % int(result["points"])
	_hero.modulate = ACCENT
	_hint.text = "答对 %d / %d 个位置%s" % [int(result["correct"]), sequence.size(), " · 全对奖励 +100" if bool(result["perfect"]) else ""]
	_feedback.text = "本轮得分已计入总分。没有淘汰，准备好后进入下一轮。"
	_feedback.modulate = MUTED
	_progress.value = 0.0
	_refresh_answer_tiles(true)
	for direction: int in sequence:
		_expected_row.add_child(_make_tile(ARROWS[direction], ACCENT))
	_expected_row.show()
	_expected_caption.show()
	_update_score()
	_refresh_controls()

func _refresh_answer_tiles(reveal: bool) -> void:
	_answer_caption.text = "你的答案" if reveal else "已输入 %d / %d" % [answers.size(), sequence.size()]
	for index: int in range(_answer_tiles.size()):
		var filled: bool = index < answers.size()
		var tile: Label = _answer_tiles[index]
		tile.text = ARROWS[answers[index]] if filled else "—"
		if reveal:
			var correct: bool = filled and answers[index] == sequence[index]
			tile.modulate = ACCENT if correct else WRONG
			tile.tooltip_text = "正确" if correct else ("未作答" if not filled else "位置错误")
		else:
			tile.modulate = TEXT if filled else MUTED
			tile.tooltip_text = ""

func _show_summary() -> void:
	phase = Phase.FINISHED
	_phase_label.text = "六轮完成 · 单人练习结算"
	_hero.hide()
	_answer_row.hide()
	_expected_row.hide()
	_expected_caption.hide()
	_summary_rows.show()
	_clear_children(_summary_rows)
	var accuracy: float = 100.0 * float(total_correct) / float(maxi(total_positions, 1))
	_hint.text = "总分 %d / %d    ·    正确率 %.1f%%" % [total_score, RULES.maximum_score(), accuracy]
	_answer_caption.text = "每轮成绩"
	for index: int in range(round_results.size()):
		var result: Dictionary = round_results[index]
		var line: Label = Label.new()
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.add_theme_font_size_override("font_size", 24)
		line.text = "第 %d 轮     %d / %d 正确     +%d 分%s" % [index + 1, int(result["correct"]), int(result["total"]), int(result["points"]), "  ·  全对" if bool(result["perfect"]) else ""]
		line.modulate = ACCENT if bool(result["perfect"]) else TEXT
		_summary_rows.add_child(line)
	_feedback.text = "答对 %d / %d 个位置 · 再玩一次会生成新的随机密码" % [total_correct, total_positions]
	_refresh_controls()

func _refresh_controls() -> void:
	var accepting: bool = phase == Phase.ANSWER
	for button: Button in _direction_buttons:
		button.disabled = not accepting or answers.size() >= sequence.size()
	_undo.disabled = not accepting or answers.is_empty()
	_primary.disabled = phase in [Phase.PREPARE, Phase.SHOW, Phase.GAP] or (accepting and answers.size() != sequence.size())
	match phase:
		Phase.READY:
			_primary.text = "开始记忆  /  Enter"
		Phase.PREPARE, Phase.SHOW, Phase.GAP:
			_primary.text = "请先观察…"
		Phase.ANSWER:
			_primary.text = "提交答案  /  Enter"
		Phase.REVIEW:
			_primary.text = "下一轮  /  Enter" if round_index + 1 < RULES.ROUND_COUNT else "查看总成绩  /  Enter"
		Phase.FINISHED:
			_primary.text = "再玩一次  /  Enter"

func _update_score() -> void:
	_score_label.text = "总分  %d" % total_score

func _make_tile(text: String, color: Color) -> Label:
	var tile: Label = Label.new()
	tile.text = text
	tile.custom_minimum_size = Vector2(74.0, 66.0)
	tile.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tile.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tile.add_theme_font_size_override("font_size", 40)
	tile.add_theme_stylebox_override("normal", _style_box(Color("#17273d"), Color("#2d415e"), 12))
	tile.modulate = color
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tile

func _clear_children(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _style_box(fill: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style

func _style_ui() -> void:
	add_theme_color_override("font_color", TEXT)
	_board.add_theme_stylebox_override("panel", _style_box(Color("#101d30"), Color("#2c405b"), 24))
	_phase_label.modulate = ACCENT
	_hint.modulate = MUTED
	_expected_caption.modulate = MUTED
	_progress.add_theme_stylebox_override("background", _style_box(Color("#1b2b42"), Color("#1b2b42"), 4))
	_progress.add_theme_stylebox_override("fill", _style_box(ACCENT, ACCENT, 4))
	var buttons: Array[Button] = _direction_buttons.duplicate()
	buttons.append_array([_primary, _undo, _restart])
	for button: Button in buttons:
		button.add_theme_font_size_override("font_size", 24)
		button.add_theme_color_override("font_color", TEXT)
		button.add_theme_color_override("font_hover_color", TEXT)
		button.add_theme_color_override("font_pressed_color", TEXT)
		button.add_theme_color_override("font_disabled_color", Color("#60728d"))
		button.add_theme_stylebox_override("normal", _style_box(Color("#20334f"), Color("#3c5475"), 12))
		button.add_theme_stylebox_override("hover", _style_box(Color("#2d4866"), ACCENT, 12))
		button.add_theme_stylebox_override("pressed", _style_box(Color("#163e3a"), ACCENT, 12))
		button.add_theme_stylebox_override("disabled", _style_box(Color("#111d2e"), Color("#22324a"), 12))
	_primary.add_theme_stylebox_override("normal", _style_box(Color("#17483e"), ACCENT, 12))
