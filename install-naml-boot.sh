#!/bin/sh
# =============================================================================
# install-naml-boot.sh — على الجهاز الهدف
#   sudo ROOTDEV=/dev/sda1 ./install-naml-boot.sh out/vmlinuz-naml out/initramfs-naml.cpio.gz
#   EMBED=1 : لا تمرّر ملف initramfs
# =============================================================================
set -eu

KER=${1:-out/vmlinuz-naml}
IRD=${2:-}
ROOTDEV=${ROOTDEV:-/dev/sda1}
CMDLINE="console=tty1 quiet loglevel=3 edd=off panic=10 vt.global_cursor_default=0"

[ "$(id -u)" = 0 ] || { echo "root required"; exit 1; }
[ -f "$KER" ] || { echo "kernel image not found: $KER"; exit 1; }

install -D -m644 "$KER" /boot/vmlinuz-naml
if [ -n "$IRD" ] && [ -f "$IRD" ]; then
    install -D -m644 "$IRD" /boot/initramfs-naml.img
fi

if mountpoint -q /boot 2>/dev/null; then P=""; else P="/boot"; fi
if [ -f /boot/initramfs-naml.img ]; then IL="	initrd $P/initramfs-naml.img"; else IL=""; fi

cat > /etc/grub.d/40_naml <<EOF
#!/bin/sh
exec tail -n +3 \$0
menuentry "naml | fb0 800x600x16 (simpledrm)" {
	insmod all_video
	search --no-floppy --file --set=root $P/vmlinuz-naml
	set gfxpayload=800x600x16
	linux $P/vmlinuz-naml $CMDLINE
$IL
}
menuentry "naml | fb0 800x600x16 (vesafb / BIOS VBE)" {
	insmod all_video
	search --no-floppy --file --set=root $P/vmlinuz-naml
	set gfxpayload=text
	linux $P/vmlinuz-naml vga=0x314 video=vesafb:ywrap,mtrr:3 $CMDLINE
$IL
}
menuentry "naml | fb0 800x600x32 (simpledrm, 32bpp)" {
	insmod all_video
	search --no-floppy --file --set=root $P/vmlinuz-naml
	set gfxpayload=800x600x32
	linux $P/vmlinuz-naml $CMDLINE
$IL
}
menuentry "naml | disk root $ROOTDEV (يتطلب EMBED=0)" {
	insmod all_video
	search --no-floppy --file --set=root $P/vmlinuz-naml
	set gfxpayload=800x600x16
	linux $P/vmlinuz-naml root=$ROOTDEV rootfstype=ext4 rw init=/sbin/naml-init $CMDLINE
}
EOF
chmod 755 /etc/grub.d/40_naml

if command -v grub-mkconfig >/dev/null 2>&1; then
    grub-mkconfig -o /boot/grub/grub.cfg
elif command -v grub2-mkconfig >/dev/null 2>&1; then
    grub2-mkconfig -o /boot/grub2/grub.cfg
elif command -v update-grub >/dev/null 2>&1; then
    update-grub
else
    echo "GRUB mkconfig not found: أضف مداخل /etc/grub.d/40_naml يدوياً"
fi

echo "installed: /boot/vmlinuz-naml  (prefix '$P')"
# لتثبيت GRUB نفسه (مرة واحدة عند الحاجة): grub-install /dev/sda
