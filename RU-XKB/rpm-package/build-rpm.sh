#!/bin/bash

set -x
set -e

PACKAGE_NAME="xkb-ruchey"
VERSION="1.3"
DESCRIPTION="Russian engineering keyboard layout (Ruchey)"
MAINTAINER="Andrey Baryshkin"
PROJECT_URL="https://github.com/A-Projects/Ruchey"

SRC_EOF="EOF"
PACKAGE="${PACKAGE_NAME}_${VERSION}_noarch"


rm -rf ~/rpmbuild
mkdir -p ~/rpmbuild
mkdir -p ~/rpmbuild/RPMS
mkdir -p ~/rpmbuild/RPMS/noarch
mkdir -p ~/rpmbuild/SOURCES
mkdir -p ~/rpmbuild/SPECS
mkdir -p ~/rpmbuild/SRPMS

cp -rf patches/* ~/rpmbuild/SOURCES/

cat > ~/rpmbuild/SPECS/${PACKAGE_NAME}.spec << EOF
Summary:        ${DESCRIPTION}
Name:           ${PACKAGE_NAME}
Version:        1.3
Release:        1
License:        Unlicense
URL:            https://github.com/A-Projects/Ruchey
Requires:       patch
BuildArch:      noarch
BuildRoot:      ~/rpmbuild/

# Build with the following syntax:
# rpmbuild --target noarch -bb ${PACKAGE_NAME}.spec

%description
Build ${DESCRIPTION}

%prep
echo "BUILDROOT = \$RPM_BUILD_ROOT"

mkdir -p \$RPM_BUILD_ROOT/usr/local/share/ruchey/
cp -f ~/rpmbuild/SOURCES/* \$RPM_BUILD_ROOT/usr/local/share/ruchey/

cat > \$RPM_BUILD_ROOT/usr/local/share/ruchey/xkb-patch << ${SRC_EOF}
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
${SRC_EOF}

cat > \$RPM_BUILD_ROOT/usr/local/share/ruchey/xkb-unpatch << ${SRC_EOF}
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
${SRC_EOF}

exit

%files
%attr(0644, root, root) /usr/local/share/ruchey/*.patch
%attr(0755, root, root) /usr/local/share/ruchey/xkb-patch
%attr(0755, root, root) /usr/local/share/ruchey/xkb-unpatch

%post
/usr/local/share/ruchey/xkb-patch

%postun
/usr/local/share/ruchey/xkb-unpatch

%clean
rm -rf \$RPM_BUILD_ROOT/usr/local/share/ruchey

%changelog
* Mar 13 2022 Andrey Baryshkin <${PROJECT_URL}>
  - Build for Fedora Linux
EOF

cd ~/rpmbuild
rpmbuild --target noarch -bb SPECS/${PACKAGE_NAME}.spec
