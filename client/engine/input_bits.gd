## Button bitmask used by the sim, the input buffer, recordings and (later) netcode.
## Directions are in screen terms (LEFT/RIGHT); the sim converts them to forward/back.
extends RefCounted

const UP := 1
const DOWN := 2
const LEFT := 4
const RIGHT := 8
const LP := 16
const HP := 32
const LK := 64
const HK := 128

const DIRS := UP | DOWN | LEFT | RIGHT
const BUTTONS := LP | HP | LK | HK
const ALL := DIRS | BUTTONS

## Bit index (0..7) for each single-bit constant, used by the per-bit age arrays.
static func index(bit: int) -> int:
	var i := 0
	while bit > 1:
		bit >>= 1
		i += 1
	return i


## Opposite directions cancel out (SOCD cleaning) so every client agrees on the same mask.
static func clean(mask: int) -> int:
	mask &= ALL
	if mask & LEFT and mask & RIGHT:
		mask &= ~(LEFT | RIGHT)
	if mask & UP and mask & DOWN:
		mask &= ~(UP | DOWN)
	return mask
