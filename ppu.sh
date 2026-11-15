#!/bin/sh
set -eu
export LC_ALL=C
TILE=32

read_x11_reply() {
    while :; do
        REPLY_BYTES=$(dd bs=1 count=32 2>/dev/null | od -An -v -tu1)
        set -- $REPLY_BYTES
        [ "$#" -ge 32 ] || { echo "X11 EOF" >&2; exit 1; }
        if [ "$1" -eq 1 ]; then
            extra=$(( $5 + $6 * 256 + $7 * 65536 + $8 * 16777216 ))
            if [ "$extra" -gt 0 ]; then
                dd bs=1 count=$((extra * 4)) >/dev/null 2>&1
            fi
            return 0
        elif [ "$1" -eq 0 ]; then
            printf 'X11 error code=%s major=%s minor=%s\n' "$2" "${11}" "$(( $9 + ${10} * 256 ))" >&2
            exit 1
        fi
    done
}

DISP="${DISPLAY:-:0}"
REST="${DISP#*:}"
DISP_NUM="${REST%%.*}"
XAUTH="${XAUTHORITY:-$HOME/.Xauthority}"

HS_PKT=$(
    { [ -r "$XAUTH" ] && od -An -v -tu1 < "$XAUTH" || true; } | awk -v disp="$DISP_NUM" '
    function fb(v) { return (v == 37) ? "%%" : sprintf("\\%03o", v) }
    BEGIN { nb = 0 }
    { for (i = 1; i <= NF; i++) b[++nb] = $i }
    END {
        p = 1; found = 0; alen = 0; dlen = 0; aname = ""; adata = ""
        while (p + 1 <= nb) {
            fam = b[p]*256 + b[p+1]; p += 2
            if (p + 1 > nb) break
            l1 = b[p]*256 + b[p+1]; p += 2 + l1
            if (p + 1 > nb) break
            l2 = b[p]*256 + b[p+1]; p += 2
            num = ""; for (k = 0; k < l2; k++) num = num sprintf("%c", b[p+k]); p += l2
            if (p + 1 > nb) break
            l3 = b[p]*256 + b[p+1]; p += 2
            nm = ""; for (k = 0; k < l3; k++) nm = nm fb(b[p+k]); p += l3
            if (p + 1 > nb) break
            l4 = b[p]*256 + b[p+1]; p += 2
            dt = ""; for (k = 0; k < l4; k++) dt = dt fb(b[p+k]); p += l4
            if (num == disp) {
                if (fam == 256) { aname = nm; alen = l3; adata = dt; dlen = l4; found = 1; break }
                fnm = nm; fl3 = l3; fdt = dt; fl4 = l4; found = 2
            }
        }
        if (found == 2) { aname = fnm; alen = fl3; adata = fdt; dlen = fl4 }
        out = "\\154\\000\\013\\000\\000\\000" \
              fb(alen % 256) fb(int(alen/256)) fb(dlen % 256) fb(int(dlen/256)) "\\000\\000"
        out = out aname
        for (k = 0; k < (4 - (alen % 4)) % 4; k++) out = out "\\000"
        out = out adata
        for (k = 0; k < (4 - (dlen % 4)) % 4; k++) out = out "\\000"
        printf "%s", out
    }'
)

printf -- "$HS_PKT"
HDR=$(dd bs=1 count=8 2>/dev/null | od -An -v -tu1)
set -- $HDR
[ "${1:-0}" -eq 1 ] || { printf 'X11 setup failed (status=%s)\n' "${1:-EOF}" >&2; exit 1; }
ADD_BYTES=$(( ($7 + $8 * 256) * 4 ))
dd bs=1 count="$ADD_BYTES" 2>/dev/null | od -An -v -tu1 > setup.od

printf -- '\142\000\004\000\005\000\000\000\123\110\101\120\105\000\000\000'
read_x11_reply
set -- $REPLY_BYTES
SHAPE_P="$9"
SHAPE_OP="${10}"

awk -v sp="$SHAPE_P" -v sop="$SHAPE_OP" '
function u8(v,    b) { b = int(v) % 256; return (b == 37) ? "%%" : sprintf("\\%03o", b) }
function u16(v) { return u8(v) u8(int(v / 256)) }
function i16(v) { if (v < 0) v += 65536; return u16(v) }
function u32(v) { return u8(v) u8(int(v/256)) u8(int(v/65536)) u8(int(v/16777216)) }
function u32at(p) { return b[p] + b[p+1]*256 + b[p+2]*65536 + b[p+3]*16777216 }
function u16at(p) { return b[p] + b[p+1]*256 }
function alloc_id() { rid_i++; return rid_base + rid_i * step }

function emit_rects(drawable, gc, arr, n,    i, j, end, hdr, body) {
    for (i = 1; i <= n; i += 32) {
        end = (i + 31 < n) ? i + 31 : n
        hdr = u8(70) u8(0) u16(3 + 2 * (end - i + 1)) u32(drawable) u32(gc)
        body = ""
        for (j = i; j <= end; j++) body = body arr[j]
        print hdr body > "init.oct"
    }
}

function set_pose(name, r0,r1,r2,r3,r4,r5,r6,r7,r8,r9,r10,r11,r12,r13,r14,r15) {
    P[name,0]=r0;  P[name,1]=r1;  P[name,2]=r2;   P[name,3]=r3
    P[name,4]=r4;  P[name,5]=r5;  P[name,6]=r6;   P[name,7]=r7
    P[name,8]=r8;  P[name,9]=r9;  P[name,10]=r10; P[name,11]=r11
    P[name,12]=r12;P[name,13]=r13;P[name,14]=r14; P[name,15]=r15
}

function build_sprite(id, pose, flip, dy,    pix, msk, y, x, sy, row, ch, nm, nblk, mr, br, pkt) {
    pix = alloc_id(); msk = alloc_id()
    print u8(53) u8(root_depth) u16(4) u32(pix) u32(win) u16(32) u16(32) > "init.oct"
    print u8(53) u8(1)          u16(4) u32(msk) u32(win) u16(32) u16(32) > "init.oct"
    if (gc_m == 0) {
        gc_m = alloc_id()
        print u8(55) u8(0) u16(6) u32(gc_m) u32(msk) u32(65540) u32(0) u32(0) > "init.oct"
    }
    print u8(56) u8(0) u16(4) u32(gc_m) u32(4) u32(0) > "init.oct"
    print u8(70) u8(0) u16(5) u32(msk) u32(gc_m) i16(0) i16(0) u16(32) u16(32) > "init.oct"
    print u8(56) u8(0) u16(4) u32(gc_w) u32(4) u32(white) > "init.oct"
    print u8(70) u8(0) u16(5) u32(pix) u32(gc_w) i16(0) i16(0) u16(32) u16(32) > "init.oct"

    nm = 0; nblk = 0
    for (y = 0; y < 16; y++) {
        sy = y - dy
        row = (sy >= 0 && sy < 16) ? P[pose, sy] : "                "
        for (x = 0; x < 16; x++) {
            ch = substr(row, (flip ? 16 - x : x + 1), 1)
            if (ch != " ") {
                mr[++nm] = i16(x*2) i16(y*2) u16(2) u16(2)
                if (ch == "#") br[++nblk] = i16(x*2) i16(y*2) u16(2) u16(2)
            }
        }
    }
    print u8(56) u8(0) u16(4) u32(gc_m) u32(4) u32(1) > "init.oct"
    emit_rects(msk, gc_m, mr, nm)
    print u8(56) u8(0) u16(4) u32(gc_w) u32(4) u32(black) > "init.oct"
    emit_rects(pix, gc_w, br, nblk)

    pkt = ""
    if (sp > 0) pkt = pkt u8(sop) u8(2) u16(5) u8(0) u8(0) u8(0) u8(0) u32(win) i16(0) i16(0) u32(msk)
    pkt = pkt u8(62) u8(0) u16(7) u32(pix) u32(win) u32(gc_w) i16(0) i16(0) i16(0) i16(0) u16(32) u16(32)
    printf "SP_%d=\047%s\047\n", id, pkt > "ppu.env"
}

BEGIN { nb = 0 }
{ for (i = 1; i <= NF; i++) b[++nb] = $i }
END {
    rid_base = u32at(5); rid_mask = u32at(9)
    vlen = u16at(17); nfmt = b[22]
    p = 1 + 32 + int((vlen + 3) / 4) * 4 + 8 * nfmt
    root = u32at(p); white = u32at(p + 8); black = u32at(p + 12); root_depth = b[p + 38]

    step = 1; m = rid_mask
    while (m > 0 && int(m % 2) == 0) { step *= 2; m = int(m / 2) }
    rid_i = 0; gc_m = 0

    win = alloc_id(); gc_w = alloc_id()
    print u8(1) u8(0) u16(10) u32(win) u32(root) i16(160) i16(160) u16(32) u16(32) u16(0) u16(1) u32(0) u32(514) u32(white) u32(1) > "init.oct"
    if (sp > 0) print u8(sop) u8(1) u16(4) u8(0) u8(2) u8(0) u8(0) u32(win) i16(0) i16(0) > "init.oct"
    print u8(55) u8(0) u16(6) u32(gc_w) u32(win) u32(65540) u32(white) u32(0) > "init.oct"

    set_pose("SIT",
        "                ",
        "   ##      ##   ",
        "   #.#    #.#   ",
        "   #..####..#   ",
        "   #........#   ",
        "  ##.#....#.##  ",
        "   #........#   ",
        "  ##.#.##.#.##  ",
        "   #.##..##.#   ",
        "    #......#    ",
        "    #......# ## ",
        "   #........#.# ",
        "   #..#..#..##  ",
        "   #..####..#   ",
        "   ###.  .###   ",
        "                ")
    set_pose("WASH1",
        "                ",
        "   ##      ##   ",
        "   #.#    #.#   ",
        "   #..####..#   ",
        "   #........#   ",
        "  ##.##..##.##  ",
        "   #........#   ",
        "  ##........##  ",
        "   #.####...#   ",
        "    #......#    ",
        "   #.......# ## ",
        "   #........#.# ",
        "   #..#..#..##  ",
        "   #..####..#   ",
        "   ###.  .###   ",
        "                ")
    set_pose("SCR1",
        "                ",
        "           ##   ",
        "          #.#   ",
        "  ########..#   ",
        " #.#........#   ",
        "#  #.##..##.##  ",
        "   #...##...#   ",
        "  ##........##  ",
        "#.##........#   ",
        "#.# #......#    ",
        " #..#......# ## ",
        " #..........#.# ",
        "  #...#..#..##  ",
        "   #..####..#   ",
        "    ##.  .###   ",
        "                ")
    set_pose("YAWN",
        "                ",
        "   ##      ##   ",
        "   #.#    #.#   ",
        "   #..####..#   ",
        "   #........#   ",
        "  ##.##..##.##  ",
        "   #........#   ",
        "  ##..####..##  ",
        "   #..####..#   ",
        "    #......#    ",
        "    #......# ## ",
        "   #........#.# ",
        "   #..#..#..##  ",
        "   #..####..#   ",
        "   ###.  .###   ",
        "                ")
    set_pose("SLP1",
        "          ###   ",
        "           #    ",
        "          ###   ",
        "                ",
        "   ##      ##   ",
        "   #.######.#   ",
        "   #........#   ",
        "   #.##..##.#   ",
        "   #........#   ",
        "   #...##...#   ",
        "  #..........#  ",
        " #...........## ",
        " #............# ",
        "  ############  ",
        "                ",
        "                ")
    set_pose("SLP2",
        "                ",
        "      ###       ",
        "       #        ",
        "      ###       ",
        "                ",
        "   ##      ##   ",
        "   #.######.#   ",
        "   #........#   ",
        "   #.##..##.#   ",
        "   #........#   ",
        "  #....##....#  ",
        " #...........## ",
        " #............# ",
        "  ############  ",
        "                ",
        "                ")
    set_pose("AWAKE",
        "#      ##      #",
        " #     ##     # ",
        "   ##  ##  ##   ",
        "   #.#    #.#   ",
        "   #..####..#   ",
        "   #........#   ",
        "  ##.#....#.##  ",
        "   #...##...#   ",
        "  ##........##  ",
        "   #........#   ",
        "    #......#    ",
        "    #......# ## ",
        "   #........#.# ",
        "   #..#..#..##  ",
        "   #..####..#   ",
        "   ###.  .###   ")
    set_pose("RUN1",
        "                ",
        "        #    ## ",
        "        #.###.# ",
        "        #.....# ",
        "       ##..#..# ",
        "       #.....#.#",
        "  #    #.....## ",
        "#.............# ",
        " ## #........#  ",
        "    #.......#   ",
        "   #..####...#  ",
        "  #..#    #...# ",
        "  ###      ###  ",
        "                ",
        "                ",
        "                ")
    set_pose("RUN2",
        "                ",
        "        #    ## ",
        "        #.###.# ",
        "        #.....# ",
        "       ##..#..# ",
        "       #.....#.#",
        "   #####.....## ",
        " #............# ",
        "#.# #........#  ",
        "#.# #.......#   ",
        "####..####...#  ",
        "   #..#  #..#   ",
        "    ###  ###    ",
        "                ",
        "                ",
        "                ")

    printf "ROOT_PKT=\047%s\047\n", u8(38) u8(0) u16(2) u32(root) > "ppu.env"
    printf "WIN_OCT=\047%s\047\n", u32(win) > "ppu.env"

    build_sprite(0,"SIT",0,0);   build_sprite(1,"WASH1",0,0); build_sprite(2,"SIT",0,0)
    build_sprite(3,"SCR1",0,0);  build_sprite(4,"SIT",0,0);   build_sprite(5,"SIT",0,0)
    build_sprite(6,"YAWN",0,0);  build_sprite(7,"SLP1",0,0);  build_sprite(8,"SLP2",0,0)
    build_sprite(9,"AWAKE",0,0)
    build_sprite(10,"RUN1",0,-1); build_sprite(11,"RUN2",0,1)
    build_sprite(12,"RUN1",0,-1); build_sprite(13,"RUN2",0,0)
    build_sprite(14,"RUN1",0,0);  build_sprite(15,"RUN2",0,0)
    build_sprite(16,"RUN1",0,1);  build_sprite(17,"RUN2",0,0)
    build_sprite(18,"RUN1",0,1);  build_sprite(19,"RUN2",0,-1)
    build_sprite(20,"RUN1",1,1);  build_sprite(21,"RUN2",1,0)
    build_sprite(22,"RUN1",1,0);  build_sprite(23,"RUN2",1,0)
    build_sprite(24,"RUN1",1,-1); build_sprite(25,"RUN2",1,0)

    print u8(8) u8(0) u16(2) u32(win) > "init.oct"
}' setup.od

while IFS= read -r line; do
    printf -- "$line"
done < init.oct
. ./ppu.env
printf -- "$SP_0"

b_oct() { [ "$1" -eq 37 ] && printf '%%%%' || printf '\\%03o' "$1"; }


while IFS= read -r cmd <&8; do
    case "$cmd" in
        P)
            printf -- "$ROOT_PKT"
            read_x11_reply
            set -- $REPLY_BYTES
            rx=$(( ${17} + ${18} * 256 ))
            ry=$(( ${19} + ${20} * 256 ))
            [ "$rx" -ge 32768 ] && rx=$((rx - 65536))
            [ "$ry" -ge 32768 ] && ry=$((ry - 65536))
            [ "$rx" -lt 0 ] && rx=0
            [ "$ry" -lt 0 ] && ry=0
            awk -v n="$((rx / TILE))" 'BEGIN{while(n-->0) printf "\n"}' > MX.tmp && mv MX.tmp MX
            awk -v n="$((ry / TILE))" 'BEGIN{while(n-->0) printf "\n"}' > MY.tmp && mv MY.tmp MY
            ;;
        B)
            cx=$(( $(wc -l < CX) * TILE ))
            cy=$(( $(wc -l < CY) * TILE ))
            [ "$cx" -gt 32767 ] && cx=32767
            [ "$cy" -gt 32767 ] && cy=32767
            sp=$(( $(wc -l < SPRITE) % 26 ))
            eval "sp_pkt=\$SP_$sp"
            x_lo=$(b_oct "$((cx & 255))")
            x_hi=$(b_oct "$(((cx >> 8) & 255))")
            y_lo=$(b_oct "$((cy & 255))")
            y_hi=$(b_oct "$(((cy >> 8) & 255))")
            cfg="\014\000\005\000${WIN_OCT}\003\000\000\000${x_lo}${x_hi}\000\000${y_lo}${y_hi}\000\000"
            printf -- "${cfg}${sp_pkt}"
            ;;
    esac
    printf '\n' >&9
done
