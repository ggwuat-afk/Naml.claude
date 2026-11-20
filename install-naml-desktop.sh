#!/bin/sh
# =============================================================================
# install-naml-desktop.sh — ينصب سطح مكتب NAML على قرص/قسم على الجهاز الهدف
#   sudo ROOTDEV=/dev/sda1 ./install-naml-desktop.sh out/vmlinuz-naml out/naml-rootfs-i386.tar.gz
#   VGA=0x314      دقة الإقلاع النصية/VESA (0x314 = 800x600x16)
#   YES=1          تأكيد صريح لتهيئة القسم (يمسح كل شيء عليه)
#   SET_PASS=1     تعيين كلمة سر root تفاعلياً بعد النسخ (لطرفيات getty)
# =============================================================================
set -eu

ROOTDEV=${ROOTDEV:-}
VGA=${VGA:-0x314}
YES=${YES:-0}
SET_PASS=${SET_PASS:-0}
MNT=${MNT:-/mnt/naml}
KERNEL=${1:-out/vmlinuz-naml}
ROOTFS=${2:-out/naml-rootfs-i386.tar.gz}

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
say() { printf '\n=== %s ===\n' "$*"; }

[ "$(id -u)" -eq 0 ] || die "run as root (sudo)"
[ -n "$ROOTDEV" ] || die "ROOTDEV is required, e.g. ROOTDEV=/dev/sda1"
[ -b "$ROOTDEV" ] || die "not a block device: $ROOTDEV"
[ -f "$KERNEL" ] || die "kernel not found: $KERNEL"
[ -f "$ROOTFS" ] || die "rootfs not found: $ROOTFS"

printf 'kernel : %s\nrootfs : %s\ntarget : %s\n' "$KERNEL" "$ROOTFS" "$ROOTDEV"
[ "$YES" = 1 ] || die "refusing to format $ROOTDEV without YES=1 (this erases it)"

say "format ext4"
command -v mkfs.ext4 >/dev/null 2>&1 || die "missing e2fsprogs (mkfs.ext4)"
mkfs.ext4 -q -F -L NAML "$ROOTDEV"
UUID=$(blkid -s UUID -o value "$ROOTDEV")
[ -n "$UUID" ] || die "could not read UUID of $ROOTDEV"

say "extract rootfs"
mkdir -p "$MNT"
mount "$ROOTDEV" "$MNT"
trap 'umount "$MNT" 2>/dev/null || true' EXIT INT TERM
# --no-same-owner: كل الملفات تصير root:root مهما كان مستخدم البناء
tar -xzf "$ROOTFS" -C "$MNT" --no-same-owner

say "install kernel"
mkdir -p "$MNT/boot"
install -m644 "$KERNEL" "$MNT/boot/vmlinuz-naml"
[ -f out/System.map-naml ] && install -m644 out/System.map-naml "$MNT/boot/System.map-naml" || true

say "write fstab"
cat > "$MNT/etc/fstab" <<EOF
# NAML desktop
UUID=$UUID  /      ext4  rw,relatime  0 1
tmpfs       /tmp   tmpfs mode=1777,nosuid,nodev 0 0
tmpfs       /dev/shm tmpfs mode=1777,nosuid,nodev 0 0
EOF

say "grub entry"
cat > "$MNT/boot/grub-naml.cfg" <<EOF
menuentry "NAML i386 desktop (800x600)" {
    insmod part_msdos
    insmod ext2
    search --no-floppy --fs-uuid --set=root $UUID
    linux /boot/vmlinuz-naml root=UUID=$UUID rw rootfstype=ext4 vga=$VGA quiet
}
EOF
printf 'كتبت: %s/boot/grub-naml.cfg\n' "$MNT"

if [ "$SET_PASS" = 1 ]; then
    say "root password"
    chroot "$MNT" /bin/sh -c 'passwd root'
fi

say "done"
printf 'الخطوة الأخيرة: انسخ محتوى %s/boot/grub-naml.cfg داخل menuentry في\n' "$MNT"
printf '/boot/grub/grub.cfg على قرص الإقلاع (أو استعمل 40_custom ثم update-grub).\n'
printf 'وإلا: من الطرفية النصية tty2، سجّل الدخول بعد تعيين كلمة السر.\n'
