## Global combat rules from the design doc's "Controls and combat" section.
## Per-fighter numbers (frame data, boxes, speeds) live in each fighter's data file, never here.
extends RefCounted

const TICKS_PER_SECOND := 60

## Positions are whole numbers in sub-units: 100 sub-units = 1 pixel.
const FP := 100

const STAGE_WIDTH := 1920 * FP
const STAGE_MARGIN := 40 * FP
const START_GAP := 300 * FP          # distance between fighters at round start
const MAX_SEPARATION := 900 * FP     # fighters can't walk further apart than the camera shows

# Rounds
const ROUND_SECONDS := 99
const ROUNDS_TO_WIN := 2
const INTRO_FRAMES := 100            # "Round 1 ... Fight!"
const ROUND_END_FRAMES := 150
const KO_FREEZE := 30
const FINISHER_WINDOW := 120         # 2 seconds to press Super after the final round
const FINISHER_FRAMES := 120

# Hit feel
const HITSTOP_LIGHT := 4
const HITSTOP_HEAVY := 8

# Damage
const COUNTER_HIT_PCT := 120
const SCALING_FREE_HITS := 3         # each hit after the 3rd does 10% less...
const SCALING_STEP_PCT := 10
const SCALING_FLOOR_PCT := 40        # ...down to 40%
const MOTION_BONUS_PCT := 110        # classic motion inputs do 10% more damage

# Meter: 3 bars. Landing hits builds the most, then taking damage, then blocking.
const METER_PER_BAR := 500
const METER_BARS := 3
const METER_MAX := METER_PER_BAR * METER_BARS
const METER_ON_HIT_PCT := 100        # of the move's base damage
const METER_ON_DAMAGE_TAKEN_PCT := 50
const METER_ON_BLOCK_PCT := 30

# Juggles, knockdown, throws
const JUGGLE_LIMIT := 3
const AIR_HIT_VX := 250              # pop-up when a normal hit lands on an airborne fighter
const AIR_HIT_VY := 900
const KNOCKDOWN_FRAMES := 40
const GETUP_FRAMES := 24             # fully invincible while getting up
const THROW_BREAK_WINDOW := 7
const THROW_TECH_FRAMES := 20
const THROW_TECH_PUSH := 120 * FP
const THROW_RECOVERY := 24           # thrower's frames after a throw lands
const KO_POP_VY := 1300
const KO_POP_VX := 350

# Input reading
const INPUT_BUFFER := 6              # a button press stays usable for this many frames
const CHORD_WINDOW := 3              # two buttons count as "together" within this many frames
const SIMPLE_SPECIAL_WINDOW := 5     # direction must be freshly pressed this recently for direction+button specials
const MOTION_WINDOW := 15            # frames to complete a quarter-circle / dragon-punch motion
const DASH_WINDOW := 12              # double-tap window
const LAND_FRAMES := 3
const PUSHBACK_TICKS := 6
