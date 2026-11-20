#!/bin/sh
# =============================================================================
# build-busybox-i386.sh — يبني BusyBox ثابت i386 → out/busybox-i386-static
#   BB_VER=1.36.1 (فارغ = أحدث إصدار)  JOBS=4  CROSS_COMPILE=i686-linux-gnu-
# =============================================================================
set -eu

BB_VER=${BB_VER:-}
WORK=${WORK:-$PWD/.naml-build}
CACHE=${CACHE:-$PWD/.naml-cache}
OUT=${OUT:-$PWD/out}
JOBS=${JOBS:-$(nproc 2>/dev/null || echo 2)}
CROSS=${CROSS_COMPILE:-}

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
say() { printf '\n=== %s ===\n' "$*"; }
fetch() {
    if command -v curl >/dev/null 2>&1; then curl -fsSL "$1"
    elif command -v wget >/dev/null 2>&1; then wget -qO- "$1"
    else die "need curl or wget"; fi
}

for t in make gcc ld readelf tar bzip2 grep sed sort find od cut install; do
    command -v "$t" >/dev/null 2>&1 || die "missing host tool: $t"
done
mkdir -p "$WORK" "$CACHE" "$OUT"

if [ -z "$BB_VER" ]; then
    say "resolving latest busybox"
    BB_VER=$(fetch https://busybox.net/downloads/ \
             | grep -oE 'busybox-[0-9]+\.[0-9]+\.[0-9]+\.tar\.bz2' \
             | sed -e 's/^busybox-//' -e 's/\.tar\.bz2$//' | sort -V | tail -1)
fi
BB_VER=${BB_VER:-1.36.1}
say "busybox $BB_VER"

TB="$CACHE/busybox-$BB_VER.tar.bz2"
if [ ! -f "$TB" ]; then fetch "https://busybox.net/downloads/busybox-$BB_VER.tar.bz2" > "$TB"; fi
BD="$WORK/busybox-$BB_VER"
if [ ! -d "$BD" ]; then tar -xjf "$TB" -C "$WORK"; fi
cd "$BD"

# أداة 32-bit: cross إن وُجد، وإلا gcc -m32 من multilib.
# نمرّر CC كوسيط سطر أوامر لأن Makefile الخاص بـ busybox يضبط CC بـ :=
if [ -n "$CROSS" ]; then
    bbmake() { make CROSS_COMPILE="$CROSS" "$@"; }
elif printf 'int n;\n' | ${CC:-gcc} -m32 -x c -c - -o "$WORK/bb32.o" 2>/dev/null; then
    say "toolchain: native gcc -m32"
    bbmake() { make CC="gcc -m32" "$@"; }
else
    die "no 32-bit toolchain (gcc-multilib + libc6-dev-i386 أو cross)"
fi

bb_set() {
    if grep -q "^$1=" .config; then
        sed -i "s|^$1=.*|$1=$2|" .config
    elif grep -q "^# $1 is not set" .config; then
        sed -i "s|^# $1 is not set|$1=$2|" .config
    else
        # سطر مُلحَق برمز غير موجود يُهمله oldconfig بصمت — نرفضه فوراً.
        die "busybox has no symbol $1 (typo?) — check 'make menuconfig' names"
    fi
}

say "configure busybox"
bbmake defconfig >/dev/null
# إصلاحات بناء معروفة على مضيف حديث + تقليص الحجم
bb_set CONFIG_STATIC y
bb_set CONFIG_TC n
bb_set CONFIG_FEATURE_MOUNT_NFS n
bb_set CONFIG_WERROR n
# INIT=n يخفي FEATURE_USE_INITTAB و LINUXRC من القائمة لكنه لا يطفئهما
bb_set CONFIG_INIT n
bb_set CONFIG_FEATURE_USE_INITTAB n
bb_set CONFIG_LINUXRC n
bb_set CONFIG_SELINUX n
bb_set CONFIG_DEBUG n
bb_set CONFIG_FEATURE_INSTALLER y
# أدوات يحتاجها naml-init / naml-shell
for s in ASH SH_IS_ASH BASH_IS_NONE SETSID CTTYHACK MDEV FEATURE_MDEV_CONF \
         STTY FBSET SWITCH_ROOT HALT REBOOT POWEROFF ENV MKNOD MOUNT UMOUNT \
         SLEEP SYNC KILL PRINTF IP FEATURE_IP_ADDRESS FEATURE_IP_LINK \
         FEATURE_IP_ROUTE IFCONFIG HOSTNAME DMESG SWAPOFF LOSETUP CLEAR RESET \
         PS FREE TOP VI HEAD TAIL GREP SED AWK DF DU MORE ID UNAME DATE; do
    bb_set "CONFIG_$s" y
done
yes '' | bbmake oldconfig >/dev/null

say "build busybox (-j$JOBS)"
bbmake -j"$JOBS" busybox >/dev/null

# تحقق: ELF32 i386 + ثابت
H=$(od -An -tx1 -N20 busybox | tr -d ' \n')
case $H in 7f454c4601*) ;; *) die "busybox is not ELF32" ;; esac
[ "$(printf '%s' "$H" | cut -c37-40)" = "0300" ] || die "busybox is not i386"
if readelf -l busybox 2>/dev/null | grep -q 'program interpreter'; then
    die "busybox is not static"
fi

install -m755 busybox "$OUT/busybox-i386-static"
printf '%s\n' "$BB_VER" > "$OUT/BBVERSION"
say "ok: $OUT/busybox-i386-static"
ls -l "$OUT/busybox-i386-static"
