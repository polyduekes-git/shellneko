#!/bin/sh
set -eu
DIR=/tmp/neko_cpu
rm -rf "$DIR"
mkdir -p "$DIR"
cd "$DIR"

DEC_MODE="${DEC_MODE:-truncate}"

for r in CX CY MX MY BX BY SX SY STATE SUB_CNT PHASE SPRITE; do
    : > "$r"
done
printf '\n\n\n\n\n\n\n\n\n\n' > CX
printf '\n\n\n\n\n\n\n\n\n\n' > CY
printf '\n\n\n\n' > SUB_CNT

dec() {
    if [ "$DEC_MODE" = "truncate" ]; then
        printf 'truncate -s -1 %s' "$1"
    else
        printf "printf '1d\\\\nw\\\\n' | ed -s %s" "$1"
    fi
}

emit() {
    f="$1"; shift
    printf '#!/bin/sh\n' > "$f"
    for line in "$@"; do printf '%s\n' "$line" >> "$f"; done
    chmod +x "$f"
}

rep() {
    n="$1"; line="$2"; out=""
    i=0; while [ "$i" -lt "$n" ]; do out="${out}${line}
"; i=$((i+1)); done
    printf '%s' "$out"
}

emit 0 'echo P >&3' 'dd bs=1 count=1 <&4 >/dev/null 2>&1' 'exec ./1'
emit 1 'test -s SX || exec ./2' "$(dec SX)" 'exec ./1'
emit 2 'test -s SY || exec ./3' "$(dec SY)" 'exec ./2'
emit 3 'test -s CX || exec ./5' "$(dec CX)" 'echo >> BX' 'exec ./4'
emit 4 'test -s MX || exec ./7' "$(dec MX)" 'exec ./3'
emit 5 'test -s BX || exec ./6' "$(dec BX)" 'echo >> CX' 'exec ./5'
emit 6 'test -s MX || exec ./9' 'echo >> SX' 'exec ./9'
emit 7 'echo >> SX' 'echo >> SX' 'exec ./8'
emit 8 'test -s CX || exec ./5' "$(dec CX)" 'echo >> BX' 'exec ./8'
emit 9  'test -s CY || exec ./11' "$(dec CY)" 'echo >> BY' 'exec ./10'
emit 10 'test -s MY || exec ./13' "$(dec MY)" 'exec ./9'
emit 11 'test -s BY || exec ./12' "$(dec BY)" 'echo >> CY' 'exec ./11'
emit 12 'test -s MY || exec ./15' 'echo >> SY' 'exec ./15'
emit 13 'echo >> SY' 'echo >> SY' 'exec ./14'
emit 14 'test -s CY || exec ./11' "$(dec CY)" 'echo >> BY' 'exec ./14'
emit 15 'test -s SX || exec ./16' "$(dec SX)" 'echo >> SX' 'exec ./35'
emit 16 'test -s SY || exec ./17' "$(dec SY)" 'echo >> SY' 'exec ./35'
emit 17 'test -s PHASE || exec ./18' "$(dec PHASE)" 'exec ./19'
emit 18 'echo >> PHASE' 'exec ./19'
emit 19 'test -s SPRITE || exec ./20' "$(dec SPRITE)" 'exec ./19'
emit 20 'test -s SUB_CNT || exec ./21' "$(dec SUB_CNT)" 'exec ./26'
emit 21 \
    "$(rep 6 'echo >> SUB_CNT')" \
    'test -s STATE || exec ./25' "$(dec STATE)" \
    'test -s STATE || exec ./24' "$(dec STATE)" \
    'test -s STATE || exec ./23' "$(dec STATE)" \
    'test -s STATE || exec ./22' "$(dec STATE)" \
    'exec ./22'
emit 22 "$(rep 4 'echo >> STATE')" 'exec ./26'
emit 23 "$(rep 3 'echo >> STATE')" 'exec ./26'
emit 24 "$(rep 2 'echo >> STATE')" 'exec ./26'
emit 25 'echo >> STATE' 'exec ./26'
emit 26 \
    'test -s STATE || exec ./31' "$(dec STATE)" \
    'test -s STATE || exec ./30' "$(dec STATE)" \
    'test -s STATE || exec ./29' "$(dec STATE)" \
    'test -s STATE || exec ./28' "$(dec STATE)" \
    'exec ./27'
emit 27 "$(rep 4 'echo >> STATE')" "$(rep 7 'echo >> SPRITE')" 'exec ./32'
emit 28 "$(rep 3 'echo >> STATE')" "$(rep 5 'echo >> SPRITE')" 'exec ./32'
emit 29 "$(rep 2 'echo >> STATE')" "$(rep 3 'echo >> SPRITE')" 'exec ./32'
emit 30 'echo >> STATE' 'echo >> SPRITE' 'exec ./32'
emit 31 'exec ./49'
emit 32 'test -s PHASE || exec ./49' "$(dec PHASE)" 'echo >> PHASE' 'echo >> SPRITE' 'exec ./49'
emit 35 'test -s SPRITE || exec ./36' "$(dec SPRITE)" 'exec ./35'
emit 36 \
    'test -s STATE || exec ./39' "$(dec STATE)" \
    'test -s STATE || exec ./39' "$(dec STATE)" \
    'test -s STATE || exec ./39' "$(dec STATE)" \
    'test -s STATE || exec ./39' "$(dec STATE)" \
    'exec ./37'
emit 37 'test -s SUB_CNT || exec ./38' "$(dec SUB_CNT)" 'exec ./37'
emit 38 "$(rep 4 'echo >> SUB_CNT')" "$(rep 9 'echo >> SPRITE')" 'exec ./49'
emit 39 'test -s SUB_CNT || exec ./40' "$(dec SUB_CNT)" 'exec ./39'
emit 40 "$(rep 4 'echo >> SUB_CNT')" 'exec ./41'
emit 41 'test -s PHASE || exec ./42' "$(dec PHASE)" 'exec ./43'
emit 42 'echo >> PHASE' 'exec ./43'
emit 43 'test -s SX || exec ./44' "$(dec SX)" 'test -s SX || exec ./45' "$(dec SX)" 'exec ./46'
emit 44 'test -s SY || exec ./49' "$(dec SY)" 'test -s SY || exec ./47' "$(dec SY)" 'exec ./48'
emit 45 'echo >> CX' 'test -s SY || exec ./50' "$(dec SY)" 'test -s SY || exec ./51' "$(dec SY)" 'exec ./52'
emit 46 'test -s CX || exec ./53' "$(dec CX)" 'exec ./53'
emit 53 'test -s SY || exec ./54' "$(dec SY)" 'test -s SY || exec ./55' "$(dec SY)" 'exec ./56'
emit 47 'echo >> CY' "$(rep 18 'echo >> SPRITE')" 'exec ./57'
emit 48 'test -s CY || exec ./58' "$(dec CY)" "$(rep 10 'echo >> SPRITE')" 'exec ./57'
emit 58 "$(rep 10 'echo >> SPRITE')" 'exec ./57'
emit 50 "$(rep 14 'echo >> SPRITE')" 'exec ./57'
emit 51 'echo >> CY' "$(rep 16 'echo >> SPRITE')" 'exec ./57'
emit 52 'test -s CY || exec ./59' "$(dec CY)" "$(rep 12 'echo >> SPRITE')" 'exec ./57'
emit 59 "$(rep 12 'echo >> SPRITE')" 'exec ./57'
emit 54 "$(rep 22 'echo >> SPRITE')" 'exec ./57'
emit 55 'echo >> CY' "$(rep 20 'echo >> SPRITE')" 'exec ./57'
emit 56 'test -s CY || exec ./60' "$(dec CY)" "$(rep 24 'echo >> SPRITE')" 'exec ./57'
emit 60 "$(rep 24 'echo >> SPRITE')" 'exec ./57'
emit 57 'test -s PHASE || exec ./49' "$(dec PHASE)" 'echo >> PHASE' 'echo >> SPRITE' 'exec ./49'
emit 49 'echo B >&3' 'dd bs=1 count=1 <&4 >/dev/null 2>&1' 'exec ./0'
