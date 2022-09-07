#!/bin/bash

set -x
set -e

PACKAGE_NAME="xkb-ruchey"
VERSION="2.0"
DESCRIPTION="Russian engineering keyboard layout (Ruchey)"
MAINTAINER="Andrey Baryshkin"
PROJECT_URL="https://github.com/A-Projects/Ruchey"

PACKAGE="${PACKAGE_NAME}_${VERSION}_all"

mkdir -p $PACKAGE
mkdir -p $PACKAGE/etc/apt/apt.conf.d/
mkdir -p $PACKAGE/usr/local/share/ruchey
mkdir -p $PACKAGE/DEBIAN

cp -f patches/* $PACKAGE/usr/local/share/ruchey

cat > $PACKAGE/usr/local/share/ruchey/xkb-patch << EOF
#!/bin/bash
if ! grep -q 'ruchey' /usr/share/X11/xkb/symbols/ru; then
  /usr/bin/patch -us /usr/share/X11/xkb/symbols/ru < /usr/local/share/ruchey/ru.patch
fi

if ! grep -q 'ruchey' /usr/share/X11/xkb/rules/base.lst; then
  /usr/bin/patch -us /usr/share/X11/xkb/rules/base.lst < /usr/local/share/ruchey/base.lst.patch
fi

if ! grep -q 'ruchey' /usr/share/X11/xkb/rules/base.xml; then
  /usr/bin/patch -us /usr/share/X11/xkb/rules/base.xml < /usr/local/share/ruchey/base.xml.patch
fi

if ! grep -q 'ruchey' /usr/share/X11/xkb/rules/evdev.lst; then
  /usr/bin/patch -us /usr/share/X11/xkb/rules/evdev.lst < /usr/local/share/ruchey/evdev.lst.patch
fi

if ! grep -q 'ruchey' /usr/share/X11/xkb/rules/evdev.xml; then
  /usr/bin/patch -us /usr/share/X11/xkb/rules/evdev.xml < /usr/local/share/ruchey/evdev.xml.patch
fi
EOF

cat > $PACKAGE/usr/local/share/ruchey/xkb-unpatch << EOF
#!/bin/bash
if grep -q 'ruchey' /usr/share/X11/xkb/symbols/ru; then
  /usr/bin/patch -usR /usr/share/X11/xkb/symbols/ru < /usr/local/share/ruchey/ru.patch
fi

if grep -q 'ruchey' /usr/share/X11/xkb/rules/base.lst; then
  /usr/bin/patch -usR /usr/share/X11/xkb/rules/base.lst < /usr/local/share/ruchey/base.lst.patch
fi

if grep -q 'ruchey' /usr/share/X11/xkb/rules/base.xml; then
  /usr/bin/patch -usR /usr/share/X11/xkb/rules/base.xml < /usr/local/share/ruchey/base.xml.patch
fi

if grep -q 'ruchey' /usr/share/X11/xkb/rules/evdev.lst; then
  /usr/bin/patch -usR /usr/share/X11/xkb/rules/evdev.lst < /usr/local/share/ruchey/evdev.lst.patch
fi

if grep -q 'ruchey' /usr/share/X11/xkb/rules/evdev.xml; then
  /usr/bin/patch -usR /usr/share/X11/xkb/rules/evdev.xml < /usr/local/share/ruchey/evdev.xml.patch
fi
EOF

cat > $PACKAGE/etc/apt/apt.conf.d/90ruchey-xkb-hook << EOF
DPkg::Post-Invoke { "if [ -x /usr/local/share/ruchey/xkb-patch ]; then /usr/local/share/ruchey/xkb-patch; fi"; };
EOF

cat > $PACKAGE/DEBIAN/control << EOF
Package: $PACKAGE_NAME
Version: $VERSION
Architecture: all
Maintainer: $MAINTAINER <$PROJECT_URL>
Description: $DESCRIPTION
Depends: patch
EOF

cat > $PACKAGE/DEBIAN/postinst << EOF
#!/bin/bash
/usr/local/share/ruchey/xkb-patch
EOF

cat > $PACKAGE/DEBIAN/prerm << EOF
#!/bin/bash
/usr/local/share/ruchey/xkb-unpatch
EOF

chmod 755 $PACKAGE/usr/local/share/ruchey/xkb-patch
chmod 755 $PACKAGE/usr/local/share/ruchey/xkb-unpatch
chmod 555 $PACKAGE/DEBIAN/control
chmod 775 $PACKAGE/DEBIAN/postinst
chmod 775 $PACKAGE/DEBIAN/prerm

dpkg-deb -Zxz --build --root-owner-group $PACKAGE
