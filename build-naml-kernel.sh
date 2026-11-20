#!/bin/sh
# =============================================================================
# build-naml-kernel.sh — نواة i386 + initramfs (naml-init) → out/
#   KVER=6.6.x (فارغ = أحدث KSER)   KSER=6.6   KSRC=/path/linux
#   BB=out/busybox-i386-static (إلزامي)  INIT=./naml-init
#   NAML_SHELL_BIN=./naml-shell   CONF=./init.conf   RCS=./rcS
#   NAML_DISK=1   EMBED=0   JOBS=4   OUT=./out   CACHE=./.naml-cache
# =============================================================================
set -eu

KSER=${KSER:-6.6}
KVER=${KVER:-}
KSRC=${KSRC:-}
WORK=${WORK:-$PWD/.naml-build}
CACHE=${CACHE:-$PWD/.naml-cache}
OUT=${OUT:-$PWD/out}
FRAG=${FRAG:-$PWD/naml-i386.config}
DISKFRAG=${DISKFRAG:-$PWD/naml-disk.config}
NAML_DISK=${NAML_DISK:-1}
DESKFRAG=${DESKFRAG:-$PWD/naml-desktop.config}
NAML_DESKTOP=${NAML_DESKTOP:-0}
EMBED=${EMBED:-0}
JOBS=${JOBS:-$(nproc 2>/dev/null || echo 2)}
CROSS=${CROSS_COMPILE:-}
INIT=${INIT:-$PWD/naml-init}
BB=${BB:-}
NAML_SHELL_BIN=${NAML_SHELL_BIN:-}
CONF=${CONF:-}
RCS=${RCS:-}
LIBDIRS=${LIBDIRS:-/lib/i386-linux-gnu /usr/lib/i386-linux-gnu /lib32 /usr/lib32}
IRFS="$WORK/initramfs"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
say() { printf '\n=== %s ===\n' "$*"; }
fetch() {
    if command -v curl >/dev/null 2>&1; then curl -fsSL "$1"
    elif command -v wget >/dev/null 2>&1; then wget -qO- "$1"
    else die "need curl or wget"; fi
}

for t in make gcc ld readelf bc bison flex perl cpio gzip tar xz find od cut sort sed grep install head; do
    command -v "$t" >/dev/null 2>&1 || die "missing host tool: $t"
done
[ -r "$FRAG" ] || die "missing $FRAG"
mkdir -p "$WORK" "$CACHE" "$OUT"

if [ -z "$CROSS" ]; then
    if printf 'int naml;\n' | ${CC:-gcc} -m32 -x c -c - -o "$WORK/m32.o" 2>/dev/null; then
        say "toolchain: native gcc -m32"
    else
        for c in i686-linux-gnu- i586-linux-gnu- i386-linux-gnu-; do
            if command -v "${c}gcc" >/dev/null 2>&1; then CROSS=$c; break; fi
        done
        [ -n "$CROSS" ] || die "no 32-bit toolchain (gcc-multilib أو gcc-i686-linux-gnu)"
        say "toolchain: ${CROSS}gcc"
    fi
fi
KMAKE="make ARCH=i386"
if [ -n "$CROSS" ]; then KMAKE="$KMAKE CROSS_COMPILE=$CROSS"; fi

if [ -n "$KSRC" ]; then
    KDIR=$KSRC
    [ -f "$KDIR/Makefile" ] || die "KSRC is not a kernel tree"
    KVER=$(cd "$KDIR" && $KMAKE -s kernelversion)
else
    MIRROR=${MIRROR:-https://cdn.kernel.org/pub/linux/kernel/v${KSER%%.*}.x}
    if [ -z "$KVER" ]; then
        say "resolving latest ${KSER}.x"
        KVER=$(fetch "$MIRROR/" \
               | grep -oE "linux-${KSER}\.[0-9]+\.tar\.xz" \
               | sed -e 's/^linux-//' -e 's/\.tar\.xz$//' | sort -V | tail -1)
    fi
    [ -n "$KVER" ] || die "cannot resolve version; run: KVER=6.6.x $0"
    TARBALL="$CACHE/linux-$KVER.tar.xz"
    if [ ! -f "$TARBALL" ]; then say "downloading linux-$KVER"; fetch "$MIRROR/linux-$KVER.tar.xz" > "$TARBALL"; fi
    KDIR="$WORK/linux-$KVER"
    if [ ! -d "$KDIR" ]; then tar -xf "$TARBALL" -C "$WORK"; fi
fi
say "kernel: $KDIR ($KVER)"

is_script() { [ "$(head -c2 "$1" 2>/dev/null)" = "#!" ]; }

elf32_i386() {
    _h=$(od -An -tx1 -N20 "$1" | tr -d ' \n')
    case $_h in 7f454c4601*) ;; *) die "not ELF32: $1" ;; esac
    [ "$(printf '%s' "$_h" | cut -c37-40)" = "0300" ] \
        || die "not i386 code (i386 kernel needs i386 userland): $1"
}

findlib() {
    for _d in $LIBDIRS /lib /usr/lib; do
        if [ -f "$_d/$1" ]; then printf '%s' "$_d/$1"; return 0; fi
    done
    return 1
}

copy_libs() {
    if ! readelf -l "$1" 2>/dev/null | grep -q 'program interpreter'; then return 0; fi
    _it=$(readelf -l "$1" 2>/dev/null | sed -n 's/.*interpreter: \(.*\)]/\1/p')
    if [ -n "$_it" ]; then
        if [ -f "$_it" ]; then
            install -D -m755 "$_it" "$IRFS$_it"
        else
            _src=$(findlib "$(basename "$_it")") || die "missing loader $_it"
            install -D -m755 "$_src" "$IRFS$_it"
        fi
    fi
    for _n in $(readelf -d "$1" 2>/dev/null | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p'); do
        _src=$(findlib "$_n") || die "missing i386 lib $_n (set LIBDIRS=...)"
        install -D -m755 "$_src" "$IRFS/lib/$_n"
    done
}

build_irfs() {
    [ -n "$BB" ] && [ -f "$BB" ] || die "BB=/path/to/busybox-i386-static is required"
    [ -f "$INIT" ] || die "INIT=/path/to/naml-init is required"
    elf32_i386 "$BB"
    if readelf -l "$BB" 2>/dev/null | grep -q 'program interpreter'; then
        die "busybox must be STATIC: $BB"
    fi
    rm -rf "$IRFS"
    mkdir -p "$IRFS/bin" "$IRFS/sbin" "$IRFS/usr/bin" "$IRFS/etc/naml" "$IRFS/lib" \
             "$IRFS/dev/pts" "$IRFS/dev/shm" "$IRFS/proc" "$IRFS/sys" "$IRFS/run" "$IRFS/tmp"
    install -m755 "$BB"   "$IRFS/bin/busybox"
    install -m755 "$INIT" "$IRFS/sbin/naml-init"
    ln -sf /sbin/naml-init "$IRFS/init"
    for a in sh ash mount umount mknod mkdir ln ls cat echo printf sleep sync kill \
             reboot poweroff halt setsid cttyhack env stty mdev ip ifconfig hostname \
             dmesg swapoff switch_root losetup fbset clear reset ps free top vi \
             head tail grep sed awk df du more id uname date; do
        ln -sf busybox "$IRFS/bin/$a"
    done
    if [ -n "$NAML_SHELL_BIN" ]; then
        [ -f "$NAML_SHELL_BIN" ] || die "NAML_SHELL_BIN not found: $NAML_SHELL_BIN"
        install -m755 "$NAML_SHELL_BIN" "$IRFS/usr/bin/naml-shell"
        if is_script "$NAML_SHELL_BIN"; then
            printf '  naml-shell: shell script (uses /bin/sh)\n'
        else
            elf32_i386 "$NAML_SHELL_BIN"
            copy_libs "$NAML_SHELL_BIN"
        fi
    fi
    if [ -n "$CONF" ]; then install -m644 "$CONF" "$IRFS/etc/naml/init.conf"; fi
    if [ -n "$RCS" ];  then install -m755 "$RCS"  "$IRFS/etc/rcS"; fi
    chmod 1777 "$IRFS/tmp"
}

say "initramfs tree"
build_irfs

cd "$KDIR"
say "configure (allnoconfig + fragments)"
$KMAKE allnoconfig
scripts/kconfig/merge_config.sh -m .config "$FRAG" >/dev/null
if [ "$NAML_DISK" = 1 ]; then
    [ -r "$DISKFRAG" ] || die "missing $DISKFRAG"
    scripts/kconfig/merge_config.sh -m .config "$DISKFRAG" >/dev/null
fi
if [ "$NAML_DESKTOP" = 1 ]; then
    [ -r "$DESKFRAG" ] || die "missing $DESKFRAG"
    scripts/kconfig/merge_config.sh -m .config "$DESKFRAG" >/dev/null
fi
if [ "$EMBED" = 1 ]; then
    scripts/config --set-str INITRAMFS_SOURCE "$IRFS"
    scripts/config --enable INITRAMFS_COMPRESSION_GZIP
fi
$KMAKE olddefconfig

MISS=0
need() { for s in "$@"; do
    if ! grep -qx "$s=y" .config; then printf '  MISSING %s=y\n' "$s"; MISS=$((MISS+1)); fi
done; }
need_any() { for s in "$@"; do
    if grep -qx "$s=y" .config; then return 0; fi
done; printf '  MISSING one of: %s\n' "$*"; MISS=$((MISS+1)); }
off() { for s in "$@"; do
    if grep -qx "$s=y" .config; then printf '  MUST BE OFF %s\n' "$s"; MISS=$((MISS+1)); fi
done; }

say "assert config"
need CONFIG_X86_32 CONFIG_NOHIGHMEM CONFIG_BLK_DEV_INITRD CONFIG_RD_GZIP \
     CONFIG_BINFMT_ELF CONFIG_BINFMT_SCRIPT CONFIG_DEVTMPFS CONFIG_PROC_FS \
     CONFIG_PROC_SYSCTL CONFIG_SYSFS CONFIG_TMPFS CONFIG_TTY CONFIG_VT \
     CONFIG_VT_CONSOLE CONFIG_UNIX98_PTYS CONFIG_INPUT CONFIG_KEYBOARD_ATKBD \
     CONFIG_SERIO_I8042 CONFIG_PRINTK CONFIG_FB CONFIG_FB_CORE \
     CONFIG_FRAMEBUFFER_CONSOLE CONFIG_FONT_8x16 CONFIG_DRM CONFIG_DRM_SIMPLEDRM \
     CONFIG_DRM_FBDEV_EMULATION CONFIG_FB_VESA CONFIG_PCI CONFIG_ACPI \
     CONFIG_MAGIC_SYSRQ CONFIG_FUTEX CONFIG_EPOLL
need_any CONFIG_SYSFB_SIMPLEFB CONFIG_X86_SYSFB
if [ "$(printf '%s\n6.6\n' "$KVER" | sort -V | head -1)" = "6.6" ]; then
    need CONFIG_FB_DEVICE
fi
# DEBUG_KERNEL ليست هنا: EXPERT يختارها قسراً فطلب إطفائها يفشل دائماً.
off CONFIG_MODULES CONFIG_64BIT CONFIG_HIGHMEM4G CONFIG_SMP \
    CONFIG_KALLSYMS CONFIG_LOGO CONFIG_BLK_DEV_RAM
if [ "$NAML_DISK" = 1 ]; then
    need CONFIG_ATA CONFIG_ATA_PIIX CONFIG_BLK_DEV_SD CONFIG_EXT4_FS
fi
if [ "$NAML_DESKTOP" = 1 ]; then
    need CONFIG_INPUT_EVDEV CONFIG_MOUSE_PS2 CONFIG_USB CONFIG_USB_HID \
         CONFIG_HID_SUPPORT CONFIG_USB_UHCI_HCD CONFIG_USB_OHCI_HCD
fi
if [ "$MISS" -ne 0 ]; then die "$MISS config assertion(s) failed"; fi
printf '  all assertions passed\n'

say "build bzImage (-j$JOBS)"
$KMAKE -j"$JOBS" bzImage

say "package"
install -m644 arch/x86/boot/bzImage "$OUT/vmlinuz-naml"
install -m644 .config "$OUT/naml-i386.config"
if [ -f System.map ]; then install -m644 System.map "$OUT/System.map-naml"; fi
printf '%s\n' "$KVER" > "$OUT/KVERSION"
( cd "$IRFS" && find . -print | cpio -o -H newc --owner=0:0 2>/dev/null | gzip -9 ) \
    > "$OUT/initramfs-naml.cpio.gz"

say "artifacts in $OUT"
ls -l "$OUT"
printf '\nframebuffer config (after olddefconfig):\n'
grep -E '^CONFIG_(FB|FB_CORE|FB_DEVICE|FB_DEFERRED_IO|FB_VESA|DRM_SIMPLEDRM|DRM_FBDEV_EMULATION|SYSFB_SIMPLEFB|X86_SYSFB|FRAMEBUFFER_CONSOLE|FONT_8x16)=' .config || true
printf '\nnext: sudo ROOTDEV=/dev/sda1 ./install-naml-boot.sh %s %s\n' \
    "$OUT/vmlinuz-naml" "$OUT/initramfs-naml.cpio.gz"
