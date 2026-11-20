#!/bin/sh
# =============================================================================
# build-naml-rootfs.sh — يبني جذر Alpine i386 فيه Xorg على fbdev + fluxbox
#   ALP_REL=3.20  ALP_ARCH=x86  OUT=./out  CACHE=./.naml-cache
#   PKGS="..."    OVERLAY=./rootfs-overlay
# لا يحتاج root: الحزم تُفكّ بـ apk --root --no-scripts، وكل التهيئة من عندنا.
# =============================================================================
set -eu

ALP_REL=${ALP_REL:-3.20}
ALP_ARCH=${ALP_ARCH:-x86}
ALP_VER=${ALP_VER:-}
MIRROR=${MIRROR:-https://dl-cdn.alpinelinux.org/alpine}
WORK=${WORK:-$PWD/.naml-build}
CACHE=${CACHE:-$PWD/.naml-cache}
OUT=${OUT:-$PWD/out}
OVERLAY=${OVERLAY:-$PWD/rootfs-overlay}
RT="$WORK/rootfs"

PKGS=${PKGS:-"alpine-base xorg-server xf86-video-fbdev xf86-video-vesa xf86-input-evdev \
xkeyboard-config setxkbmap xinit xauth xterm fluxbox xsetroot xrandr xset \
fontconfig libxft font-dejavu font-liberation"}

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
say() { printf '\n=== %s ===\n' "$*"; }
fetch() {
    if command -v curl >/dev/null 2>&1; then curl -fsSL "$1"
    elif command -v wget >/dev/null 2>&1; then wget -qO- "$1"
    else die "need curl or wget"; fi
}
fetch_to() {
    if command -v curl >/dev/null 2>&1; then curl -fsSL "$1" -o "$2"
    elif command -v wget >/dev/null 2>&1; then wget -qO "$2" "$1"
    else die "need curl or wget"; fi
}

for t in tar gzip sort find grep sed install; do
    command -v "$t" >/dev/null 2>&1 || die "missing host tool: $t"
done
[ -d "$OVERLAY" ] || die "missing overlay dir: $OVERLAY"
mkdir -p "$WORK" "$CACHE" "$OUT"

case "$(uname -m)" in
    x86_64|amd64) HOSTARCH=x86_64 ;;
    aarch64|arm64) HOSTARCH=aarch64 ;;
    *) die "unsupported host arch for apk.static: $(uname -m)" ;;
esac

say "resolve alpine $ALP_REL/$ALP_ARCH"
if [ -z "$ALP_VER" ]; then
    ALP_VER=$(fetch "$MIRROR/v$ALP_REL/releases/$ALP_ARCH/" \
              | grep -oE "alpine-minirootfs-$ALP_REL\.[0-9]+-$ALP_ARCH\.tar\.gz" \
              | sed -e 's/^alpine-minirootfs-//' -e "s/-$ALP_ARCH\.tar\.gz$//" \
              | sort -V | tail -1)
fi
[ -n "$ALP_VER" ] || die "could not resolve a minirootfs version for $ALP_REL/$ALP_ARCH"
printf '  minirootfs %s\n' "$ALP_VER"

say "fetch apk.static (host $HOSTARCH)"
APKDIR="$CACHE/apk-static-$HOSTARCH"
mkdir -p "$APKDIR"
APK=$APKDIR/sbin/apk.static
if [ ! -x "$APK" ]; then
    APKURL=$(fetch "$MIRROR/v$ALP_REL/main/$HOSTARCH/" \
             | grep -oE 'apk-tools-static-[0-9][^"<]*\.apk' | head -1)
    [ -n "$APKURL" ] || die "apk-tools-static not found for $HOSTARCH"
    fetch_to "$MIRROR/v$ALP_REL/main/$HOSTARCH/$APKURL" "$APKDIR/apk-tools.apk"
    tar -xzf "$APKDIR/apk-tools.apk" -C "$APKDIR"
    [ -x "$APK" ] || die "apk.static missing inside $APKURL"
fi
printf '  %s\n' "$($APK --version 2>&1 | head -1)"

say "fetch minirootfs"
MINI="$CACHE/alpine-minirootfs-$ALP_VER-$ALP_ARCH.tar.gz"
[ -f "$MINI" ] || fetch_to "$MIRROR/v$ALP_REL/releases/$ALP_ARCH/alpine-minirootfs-$ALP_VER-$ALP_ARCH.tar.gz" "$MINI"

rm -rf "$RT"
mkdir -p "$RT"
tar -xzf "$MINI" -C "$RT"

say "install packages ($ALP_ARCH)"
APKARGS="--root $RT --arch $ALP_ARCH --cache-dir $CACHE/apk"
# shellcheck disable=SC2086
$APK $APKARGS update
# --no-scripts: لا chroot ولا root. كل ما تحتاجه الحزم من سكربتات نبنيه بأنفسنا.
# shellcheck disable=SC2086
$APK $APKARGS add --no-scripts $PKGS

say "overlay"
tar -C "$OVERLAY" -cf - . | tar -C "$RT" -xf -
chmod 755 "$RT/usr/bin/naml-x" "$RT/etc/naml/rc.sysinit"
chmod 700 "$RT/root"
chmod 1777 "$RT/tmp" "$RT/var/tmp"

# busybox init هو PID1 (لا openrc). بدون هذا الرابط لا يقلع kernel cmdline init=/sbin/init.
ln -sfn /bin/busybox "$RT/sbin/init"
ln -sfn /proc/mounts "$RT/etc/mtab"

# الخطوط: Xft/fontconfig فقط (DejaVu + Liberation). لا نحتاج fonts.dir للخطوط
# النقطية: mkfontscale يخرج fonts.scale فارغا للـ *.pcf.gz هنا، و xterm/fluxbox
# كلاهما يرسم عبر Xft، فالاعتماد عليه يوفر 6MB ومسار فشل كامل.
say "clean up"
rm -rf "$RT/usr/share/man" "$RT/usr/share/doc" "$RT/usr/share/info" "$RT/var/cache/apk"
mkdir -p "$RT/dev" "$RT/proc" "$RT/sys" "$RT/tmp" "$RT/var/log" "$RT/var/run"
chmod 1777 "$RT/tmp"

say "assert rootfs"
MISS=0
have() { [ -e "$RT/$1" ] || { printf '  MISSING %s\n' "$1"; MISS=$((MISS+1)); }; }
have usr/bin/Xorg
have usr/bin/xinit
have usr/bin/naml-x
have usr/bin/fluxbox
have usr/bin/xterm
have usr/lib/xorg/modules/drivers/fbdev_drv.so
have usr/lib/xorg/modules/input/evdev_drv.so
have usr/lib/libXft.so.2
have usr/share/fonts/dejavu
have etc/inittab
have etc/X11/xorg.conf.d/20-naml.conf
have etc/naml/rc.sysinit
have bin/busybox
[ -L "$RT/sbin/getty" ] || [ -x "$RT/sbin/getty" ] || { printf '  MISSING sbin/getty\n'; MISS=$((MISS+1)); }
# sbin/init رابط مطلق: -e عليه يتبع /bin/busybox على المضيف لا داخل الجذر
[ -L "$RT/sbin/init" ] || { printf '  sbin/init is not a symlink\n'; MISS=$((MISS+1)); }
[ "$(readlink "$RT/sbin/init" 2>/dev/null)" = "/bin/busybox" ] || { printf '  sbin/init -> wrong target\n'; MISS=$((MISS+1)); }
[ -x "$RT/bin/busybox" ] || { printf '  bin/busybox not executable\n'; MISS=$((MISS+1)); }
H=$(od -An -tx1 -N20 "$RT/bin/busybox" 2>/dev/null | tr -d ' \n')
case $H in 7f454c4601*) ;; *) printf '  rootfs busybox is not ELF32\n'; MISS=$((MISS+1));; esac
[ "$MISS" -eq 0 ] || die "$MISS rootfs assertion(s) failed"
printf '  all assertions passed\n'

say "package"
# bbsuid يُنشأ 4111 (بلا قراءة للمالك) — tar يحتاج قراءة حتى لو بنينا كغير root
chmod -R u+rX "$RT" 2>/dev/null || true
TARBALL="$OUT/naml-rootfs-i386.tar.gz"
tar -C "$RT" --numeric-owner -czf "$TARBALL" .
printf '%s\n' "$ALP_VER" > "$OUT/ALPINE-VERSION"
printf '%s\n' "$PKGS"   > "$OUT/ROOTFS-PKGS"
ls -l "$TARBALL"
du -sh "$RT"

say "ok"
printf 'rootfs: %s\n' "$TARBALL"
printf 'target:  sudo ROOTDEV=/dev/sda1 ./install-naml-desktop.sh out/vmlinuz-naml %s\n' "$TARBALL"
