## Local memory game. The party entry listens for the six-round result.
extends Control
const Controls = preload("res://games/protocols/godot_party_default_protocol/solo_controls.gd")
const Settings = preload("res://games/minigame/gp_direction_code/settings.gd")
var controls: Controls = Controls.new(Settings.schema())
var _active: bool = false
var _stopped: bool = false
var _text_source: RefCounted

signal completed(metrics: Dictionary)

const DEFAULT_TEXT: Translation = preload("res://games/minigame/gp_direction_code/i18n/zh_Hans.po")
const RULES: GDScript = preload("res://games/minigame/gp_direction_code/direction_password_rules.gd")
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

var _i18n: RefCounted
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
	_restart.pressed.connect(_restart_requested)
	_rng.randomize()
	_i18n = _text_source
	reset_game()
	visible = controls.context == null
	if controls.context == null:
		solo_start()

func _process(delta: float) -> void:
	if not _active:
		return
	# Poll while idle too, so released keys rearm the scoped input before a new event.
	controls.is_pressed(&"direction_confirm")
	if phase not in [Phase.PREPARE, Phase.SHOW, Phase.GAP, Phase.ANSWER]:
		return
	_time_left = maxf(0.0, _time_left - delta)
	_progress.value = _time_left / _phase_duration
	if phase == Phase.PREPARE:
		_hero.text = str(maxi(1, ceili(_time_left)))
	elif phase == Phase.ANSWER:
		_hint.text = _text(&"hud.timer", {"time": ceili(_time_left)})
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
	for direction: int in 4:
		if controls.matches(event, [&"direction_up", &"direction_right", &"direction_down", &"direction_left"][direction]):
			enter_direction(direction)
			get_viewport().set_input_as_handled()
			return
	if controls.matches(event, &"direction_undo"):
		undo_direction()
	elif controls.matches(event, &"direction_confirm"):
		activate_primary()
	elif controls.matches(event, &"direction_restart"):
		_restart_requested()

func _restart_requested() -> void:
	if controls.allowed():
		reset_game()

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
	_hero.show()
	_answer_row.hide()
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
	if not controls.allowed():
		return
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
	if not controls.allowed():
		return
	if phase != Phase.ANSWER or direction < 0 or direction >= ARROWS.size() or answers.size() >= sequence.size():
		return
	answers.append(direction)
	_refresh_answer_tiles(false)
	_refresh_controls()

func undo_direction() -> void:
	if not controls.allowed():
		return
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
	for index: int in _answer_row.get_child_count():
		var tile: Label = _answer_row.get_child(index)
		tile.visible = index < sequence.size()
		tile.text = str(index + 1)
		tile.modulate = MUTED
		tile.tooltip_text = ""
	_hero.show()
	_answer_row.show()
	_phase_label.text = _text(&"hud.phase", {"round": round_index + 1, "total": RULES.ROUND_COUNT, "phase": "准备观察"})
	_hero.text = str(int(PREPARE_SECONDS))
	_hero.modulate = TEXT
	_hint.text = _text(&"hud.count", {"count": sequence.size()})
	_answer_caption.text = "观察时不能输入"
	_feedback.text = "先记顺序，等全部方向消失后再作答。"
	_feedback.modulate = MUTED
	_set_timed_phase(Phase.PREPARE, PREPARE_SECONDS)
	_refresh_controls()

func _show_direction() -> void:
	_phase_label.text = _text(&"hud.phase", {"round": round_index + 1, "total": RULES.ROUND_COUNT, "phase": "观察记忆"})
	_hero.text = ARROWS[sequence[_shown_index]]
	_hero.modulate = ACCENT
	_hint.text = _text(&"hud.direction", {"current": _shown_index + 1, "total": sequence.size(), "direction": NAMES[sequence[_shown_index]]})
	for index: int in range(sequence.size()):
		_answer_row.get_child(index).modulate = ACCENT if index == _shown_index else MUTED
	_set_timed_phase(Phase.SHOW, arrow_seconds)

func _begin_answer() -> void:
	_phase_label.text = _text(&"hud.phase", {"round": round_index + 1, "total": RULES.ROUND_COUNT, "phase": "回忆输入"})
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
	_phase_label.text = _text(&"hud.phase", {"round": round_index + 1, "total": RULES.ROUND_COUNT, "phase": "时间到" if timed_out else "答案揭晓"})
	_hero.text = _text(&"hud.points", {"score": result.points})
	_hero.modulate = ACCENT
	_hint.text = _text(&"hud.correct", {"correct": result.correct, "total": sequence.size(), "bonus": " · 全对奖励 +100" if result.perfect else ""})
	_feedback.text = "本轮得分已计入总分。没有淘汰，准备好后进入下一轮。"
	_feedback.modulate = MUTED
	_progress.value = 0.0
	_refresh_answer_tiles(true)
	for index: int in _expected_row.get_child_count():
		var tile: Label = _expected_row.get_child(index)
		tile.visible = index < sequence.size()
		if tile.visible:
			tile.text = ARROWS[sequence[index]]
			tile.modulate = ACCENT
	_expected_row.show()
	_expected_caption.show()
	_update_score()
	_refresh_controls()

func _refresh_answer_tiles(reveal: bool) -> void:
	_answer_caption.text = "你的答案" if reveal else _text(&"hud.entered", {"current": answers.size(), "total": sequence.size()})
	for index: int in range(sequence.size()):
		var filled: bool = index < answers.size()
		var tile: Label = _answer_row.get_child(index)
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
	var accuracy: float = 100.0 * float(total_correct) / float(maxi(total_positions, 1))
	_hint.text = _text(&"hud.totals", {"score": total_score, "maximum": RULES.maximum_score(), "accuracy": "%.1f" % accuracy})
	_answer_caption.text = "每轮成绩"
	for index: int in range(round_results.size()):
		var result: Dictionary = round_results[index]
		var line: Label = _summary_rows.get_child(index)
		line.text = _text(&"hud.result", {"round": index + 1, "correct": result.correct, "total": result.total, "score": result.points, "bonus": "  ·  全对" if result.perfect else ""})
		line.modulate = ACCENT if bool(result["perfect"]) else TEXT
	_feedback.text = _text(&"hud.replay", {"correct": total_correct, "total": total_positions})
	_refresh_controls()

	completed.emit({"score": total_score, "accuracy": accuracy})

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
	_score_label.text = _text(&"hud.score", {"score": total_score})

func _text(key: StringName, values: Dictionary) -> String:
	return DEFAULT_TEXT.get_message(key).format(values) if _i18n == null else _i18n.text(key, values)

## Injected before entering the tree. F6 leaves the formal dependencies unset.
func solo_setup(input: PartyInput, text_source: RefCounted) -> void:
	controls.bind(input)
	_text_source = text_source


func solo_start() -> void:
	if _stopped:
		return
	_active = true
	controls.enabled = true
	show()

func solo_stop() -> void:
	if _stopped:
		return
	_stopped = true
	_active = false
	controls.enabled = false
	set_process(false)
	set_physics_process(false)
	set_process_unhandled_input(false)
	set_process_unhandled_key_input(false)
	if not is_node_ready():
		return
	hide()

func solo_graphics_targets() -> Dictionary:
	return {}

func solo_audio_target() -> PartyGameAudio:
	return null
