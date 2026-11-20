# Naml.claude

نواة **i386** بحد أدنى من الخيارات: 256MB RAM، `initramfs`، و`/dev/fb0` بدقة
800×600 عبر `simpledrm` (أو `vesafb` كاحتياط).

وفوقها مسار **سطح مكتب** كامل: جذر Alpine i386 المثبَّت على قرص ext4، مع Xorg
على `fbdev` ومدير نوافذ fluxbox (راجع [سطح المكتب](#سطح-المكتب-xorg--fluxbox)).

## الملفات

| الملف | الوظيفة |
| --- | --- |
| `naml-i386.config` | شريحة kconfig الأساسية (تُدمج فوق `allnoconfig`) |
| `naml-disk.config` | اختياري: ATA/SATA + ext4/vfat مدمجة |
| `naml-init` | PID 1 مصغّر (تهيئة، إشراف على الواجهة، إيقاف آمن) |
| `naml-shell` | واجهة كونسول دنيا على `tty1` (استبدلها بواجهتك) |
| `init.conf` | إعدادات `naml-init` → `/etc/naml/init.conf` |
| `build-busybox-i386.sh` | يبني BusyBox ثابت i386 → `out/busybox-i386-static` |
| `build-naml-kernel.sh` | بناء النواة + شجرة initramfs + التغليف |
| `install-naml-boot.sh` | تثبيت النواة على الجهاز الهدف وكتابة مداخل GRUB |
| `naml-desktop.config` | اختياري: شريحة ماوس PS/2 + USB HID لسطح المكتب |
| `build-naml-rootfs.sh` | يبني جذر Alpine i386 (Xorg + fluxbox) → `out/naml-rootfs-i386.tar.gz` |
| `rootfs-overlay/` | ملفات تُنسخ فوق الجذر: `inittab`، `rc.sysinit`، `naml-x`، `xorg.conf.d` |
| `install-naml-desktop.sh` | يهيّئ قسم ext4 وينسخ الجذر + النواة ويكتب مدخل GRUB |
| `.github/workflows/build-naml.yml` | نفس البناء كاملاً في CI (BusyBox + جذر + نواة + initramfs) |

## تبعيات جهاز البناء

```sh
# Debian/Ubuntu
sudo apt install -y build-essential gcc-multilib libc6-dev-i386 bc bison flex \
                    libssl-dev libelf-dev cpio gzip bzip2 xz-utils tar coreutils \
                    binutils curl
# Fedora
sudo dnf install -y gcc make bc bison flex openssl-devel elfutils-libelf-devel \
                    cpio gzip bzip2 xz tar curl binutils
```

## البناء

```sh
chmod +x naml-init naml-shell build-busybox-i386.sh build-naml-kernel.sh install-naml-boot.sh

sh build-busybox-i386.sh

BB=out/busybox-i386-static INIT=./naml-init NAML_SHELL_BIN=./naml-shell \
  CONF=./init.conf sh build-naml-kernel.sh

# صورة واحدة مضمّنة (بلا ملف initrd في GRUB)
BB=out/busybox-i386-static INIT=./naml-init NAML_SHELL_BIN=./naml-shell \
  CONF=./init.conf EMBED=1 sh build-naml-kernel.sh
```

المخرجات في `out/`: `vmlinuz-naml`، `initramfs-naml.cpio.gz`، `naml-i386.config`،
`System.map-naml`، `KVERSION`، `busybox-i386-static`، `BBVERSION`. السكربت يفشل
البناء إن لم تتحقق الخيارات الحرجة (`FB`، `FB_CORE`، `FB_DEVICE` في ≥6.6،
`SYSFB_SIMPLEFB`/`X86_SYSFB`، `FRAMEBUFFER_CONSOLE`، `DRM_SIMPLEDRM`، …).

في GitHub: **Actions → Build NAML i386 Kernel → Run workflow**، ثم حمّل الـ
Artifact `naml-i386-kernel-*` من صفحة التشغيل. الافتراضيات مثبّتة
(`kver=6.6.155`، `bbver=1.36.1`) ليكون البناء قابلاً للتكرار؛ غيّرهما في النموذج
عند الحاجة (الفارغ = أحدث إصدار).

## سطح المكتب (Xorg + fluxbox)

جذر Alpine 3.20 i386 مبني بلا `root` على جهاز البناء: الحزم تُفكّ بـ
`apk --root --no-scripts`، وكل التهيئة من عندنا (بلا openrc وبلا udev).

```sh
# على جهاز البناء (يحتاج شبكة فقط)
sh build-naml-rootfs.sh          # → out/naml-rootfs-i386.tar.gz (~27MB)

# نواة سطح المكتب (تدمج naml-desktop.config: ماوس PS/2 + USB HID)
NAML_DESKTOP=1 BB=out/busybox-i386-static INIT=./naml-init \
  NAML_SHELL_BIN=./naml-shell CONF=./init.conf sh build-naml-kernel.sh

# على الجهاز الهدف (نواة 32-بت): يهيّئ /dev/sda1 ويعبّئه
sudo ROOTDEV=/dev/sda1 YES=1 SET_PASS=1 \
  ./install-naml-desktop.sh out/vmlinuz-naml out/naml-rootfs-i386.tar.gz
```

ماذا يعمل داخل سطح المكتب:

- `busybox init` هو PID 1؛ `/etc/inittab` يشغّل `/etc/naml/rc.sysinit` ثم
  `/usr/bin/naml-x` على `tty1` (و getty على `tty2`/`tty3`).
- Xorg 21 على سائق **fbdev** مع `ShadowFB` (فرق ملموس على VGA بلا تسريع)،
  الدقة 800×600×16 من `vga=0x314` أو `simpledrm`.
- fluxbox + طرفيتا xterm، وخطوط DejaVu/Liberation عبر **Xft/fontconfig**
  (لا خطوط X core ولا `fonts.dir`، لذلك لا `mkfontscale` في الصورة).
- إدخال: لوحة PS/2 + ماوس PS/2، وأيضاً لوحة/ماوس USB عبر `USB_HID`.

ما **لا** يحتوي عليه: متصفح ويب، تسريع رسومي (DRM/KMS)، صوت، أو بيئة GTK/Qt.
على 256MB يبقى Xorg + fluxbox + طرفيتين حوالي 60–80MB من RAM.

## التثبيت على الجهاز الهدف

```sh
sudo ROOTDEV=/dev/sda1 ./install-naml-boot.sh out/vmlinuz-naml out/initramfs-naml.cpio.gz
```

## التحقق بعد الإقلاع

```sh
ls -l /dev/fb0
cat /proc/fb                              # 0 simpledrmdrmfb (أو VESA VGA)
cat /sys/class/graphics/fb0/virtual_size   # 800,600
cat /sys/class/graphics/fb0/bits_per_pixel # 16
fbset -i
free -m ; dmesg | grep -iE 'fb0|simpledrm|vesa|Console'
```

## ملاحظات

- `800x600x16` ≈ 0.9 MiB للـ framebuffer، و`x32` ≈ 1.9 MiB.
- `simpledrm` هو المسار الأساسي لـ `fb0`؛ `vesafb` احتياط عند غياب DRM.
  عند تفعيل الاثنين، `simpledrm` يزيح `vesafb` من الأبريتشر، فمدخل GRUB
  الثاني (`vga=0x314`) يفيد فقط إن لم يمنح GRUB وضعاً رسومياً.
- `CONFIG_FB_DEVICE=y` إلزامي في ≥6.6، و`CONFIG_SYSFB_SIMPLEFB`/`X86_SYSFB` إلزامي
  لظهور جهاز الـ framebuffer الأصلي. `FB_CORE` تُختار تلقائياً مع `FB=y`.
- `DEBUG_KERNEL` و`PERF_EVENTS` و`PNP` و`MICROCODE` تُختار قسراً في هذه الشريحة،
  لذلك لا تُطلب في قائمة `off` ولا تُعدّ ساقطة.
- `busybox`/`naml-shell` يجب أن يكونا **i386**؛ السكربت يفحص ترويسة ELF ويرفض x86_64
  وينسخ المكتبات تلقائياً للثنائيات الديناميكية (سكربتات `#!` تُقبل كما هي).
- GRUB Legacy (`/boot/grub/menu.lst`) بدلاً من GRUB2:

  ```
  title naml fb0 800x600
  root (hd0,0)
  kernel /boot/vmlinuz-naml vga=0x314 video=vesafb:ywrap,mtrr:3 console=tty1 quiet loglevel=3 edd=off
  initrd /boot/initramfs-naml.img
  ```
