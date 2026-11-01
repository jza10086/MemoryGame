## Pure single-player direction sequence generation and positional scoring.
## No framework, input mapping, persistence or scene dependencies.
extends RefCounted

const ROUND_COUNT: int = 6
const FIRST_LENGTH: int = 3
const DIRECTION_COUNT: int = 4
const POINTS_PER_DIRECTION: int = 100
const PERFECT_BONUS: int = 100

static func sequence_length(round_index: int) -> int:
	return FIRST_LENGTH + clampi(round_index, 0, ROUND_COUNT - 1)

## Repeats are intentional; the presentation inserts a blank between every arrow.
static func make_sequence(length: int, rng: RandomNumberGenerator) -> Array[int]:
	var result: Array[int] = []
	for index: int in range(maxi(length, 0)):
		result.append(rng.randi_range(0, DIRECTION_COUNT - 1))
	return result

## Missing answers score zero. One wrong position does not erase later correct answers.
static func score_answers(expected: Array[int], answers: Array[int]) -> Dictionary[String, Variant]:
	var correct: int = 0
	for index: int in range(expected.size()):
		if index < answers.size() and expected[index] == answers[index]:
			correct += 1
	var perfect: bool = not expected.is_empty() and correct == expected.size() and answers.size() == expected.size()
	return {
		"correct": correct,
		"total": expected.size(),
		"perfect": perfect,
		"points": correct * POINTS_PER_DIRECTION + (PERFECT_BONUS if perfect else 0),
	}

static func maximum_score() -> int:
	var total: int = 0
	for round_index: int in range(ROUND_COUNT):
		total += sequence_length(round_index) * POINTS_PER_DIRECTION + PERFECT_BONUS
	return total
