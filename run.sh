#!/bin/sh
set -eu
command -v socat >/dev/null 2>&1 || { echo "need socat for socket bridge" >&2; exit 1; }

sh build_cpu.sh
cp ppu.sh /tmp/neko_cpu/ppu.sh
chmod +x /tmp/neko_cpu/ppu.sh
cd /tmp/neko_cpu

DISP="${DISPLAY:-:0}"
if [ -S "$DISP" ]; then
    X_ADDR="UNIX-CONNECT:$DISP"
else
    HOST="${DISP%%:*}"
    REST="${DISP#*:}"
    NUM="${REST%%.*}"
    if [ -z "$HOST" ] || [ "$HOST" = "unix" ]; then
        if [ -S "/tmp/.X11-unix/X$NUM" ]; then
            X_ADDR="UNIX-CONNECT:/tmp/.X11-unix/X$NUM"
        elif [ "$(uname)" = "Linux" ]; then
            X_ADDR="ABSTRACT-CONNECT:/tmp/.X11-unix/X$NUM"
        else
            printf 'No X11 socket at /tmp/.X11-unix/X%s (DISPLAY=%s)\n' "$NUM" "$DISP" >&2
            exit 1
        fi
    else
        X_ADDR="TCP:$HOST:$((6000 + NUM))"
    fi
fi
export X_ADDR

cat << 'EOF' > cpu_boot.sh

exec 4<&0 3>&1 </dev/null >/dev/null
exec ./0
EOF

cat << 'EOF' > ppu_boot.sh

exec 8<&0 9>&1
exec socat EXEC:"./ppu.sh" "$X_ADDR"
EOF

chmod +x cpu_boot.sh ppu_boot.sh
exec socat EXEC:"./cpu_boot.sh" EXEC:"./ppu_boot.sh"
