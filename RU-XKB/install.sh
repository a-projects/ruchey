#!/bin/bash

if [ ! -f /usr/bin/xmlstarlet ]; then
  echo "Please install xmlstarlet"
  exit 1
fi

if [ "$UID" != "0" ]; then
  echo "Для выполнения установкли необходимы права root"
  exit 1
fi

RUCYR="Russian (Engineering, Cyrillic)"
RULAT="Russian (Engineering, Latin)"
UNIXD=`date +%s`

RU_SYMBOLS=/usr/share/X11/xkb/symbols/ru
if ! grep -q 'ruchey' $RU_SYMBOLS; then
  echo "Изменён: $RU_SYMBOLS"
  cat ruchey_latin >> $RU_SYMBOLS
  cat ruchey_cyrillic >> $RU_SYMBOLS
fi

KEYBOARD_PL="/usr/share/console-setup/KeyboardNames.pl"
if ! grep -q 'ruchey' $KEYBOARD_PL; then
  echo "Изменён: $KEYBOARD_PL"
  cp -f $KEYBOARD_PL "$KEYBOARD_PL.$UNIXD.backup"
  sed -i "s/'ru' => {/'ru' => {\n'$RULAT' => 'ruchey_latin',\n'$RUCYR' => 'ruchey_cyrillic',\n/g" $KEYBOARD_PL
fi

EVDEV_LST="/usr/share/X11/xkb/rules/evdev.lst"
if ! grep -q 'ruchey' $EVDEV_LST; then
  echo "Изменён: $EVDEV_LST"
  cp -f $EVDEV_LST "$EVDEV_LST.$UNIXD.backup"
  sed -i "s/\! variant/\! variant\n  ruchey_cyrillic ru: $RUCYR\n  ruchey_latin ru: $RULAT/g" $EVDEV_LST
fi

BASE_LST="/usr/share/X11/xkb/rules/base.lst"
if ! grep -q 'ruchey' $BASE_LST; then
  echo "Изменён: $BASE_LST"
  cp -f $BASE_LST "$BASE_LST.$UNIXD.backup"
  sed -i "s/\! variant/\! variant\n  ruchey_cyrillic ru: $RUCYR\n  ruchey_latin ru: $RULAT/g" $BASE_LST
fi

EVDEV_XML="/usr/share/X11/xkb/rules/evdev.xml"
if ! grep -q 'ruchey' $EVDEV_XML; then
  echo "Изменён: $EVDEV_XML"
  cp -f $EVDEV_XML "$EVDEV_XML.$UNIXD.backup"
  xmlstarlet ed -L -s "/xkbConfigRegistry/layoutList/layout[configItem/name='ru']/variantList" \
    -t elem -n variant -v "TMP_RUCHEY_CYRILLIC" $EVDEV_XML

  xmlstarlet ed -L -s "/xkbConfigRegistry/layoutList/layout[configItem/name='ru']/variantList" \
    -t elem -n variant -v "TMP_RUCHEY_LATIN" $EVDEV_XML

  sed -i "s/TMP_RUCHEY_CYRILLIC/<configItem><name>ruchey_cyrillic<\/name><description>$RUCYR<\/description><countryList><iso3166Id>RU<\/iso3166Id><\/countryList><\/configItem>/g" \
    $EVDEV_XML

  sed -i "s/TMP_RUCHEY_LATIN/<configItem><name>ruchey_latin<\/name><description>$RULAT<\/description><countryList><iso3166Id>RU<\/iso3166Id><\/countryList><\/configItem>/g" \
    $EVDEV_XML
fi

BASE_XML="/usr/share/X11/xkb/rules/base.xml"
if ! grep -q 'ruchey' $BASE_XML; then
  echo "Изменён: $BASE_XML"
  cp -f $BASE_XML "$BASE_XML.$UNIXD.backup"
  xmlstarlet ed -L -s "/xkbConfigRegistry/layoutList/layout[configItem/name='ru']/variantList" \
    -t elem -n variant -v "TMP_RUCHEY_CYRILLIC" $BASE_XML

  xmlstarlet ed -L -s "/xkbConfigRegistry/layoutList/layout[configItem/name='ru']/variantList" \
    -t elem -n variant -v "TMP_RUCHEY_LATIN" $BASE_XML

  sed -i "s/TMP_RUCHEY_CYRILLIC/<configItem><name>ruchey_cyrillic<\/name><description>$RUCYR<\/description><countryList><iso3166Id>RU<\/iso3166Id><\/countryList><\/configItem>/g" \
    $BASE_XML

  sed -i "s/TMP_RUCHEY_LATIN/<configItem><name>ruchey_latin<\/name><description>$RULAT<\/description><countryList><iso3166Id>RU<\/iso3166Id><\/countryList><\/configItem>/g" \
    $BASE_XML
fi

echo "Для применения параметров необходима перезагрузка!"
echo ""
echo "Вспомогательные команды:"
echo "Список моделей клавиатур:      localectl list-x11-keymap-modles"
echo "Список языковых раскладок:     localectl list-x11-keymap-layouts"
echo "Список вариантов раскладок:    localectl list-x11-keymap-variants ru"
echo "Список переключений раскладок: localectl list-x11-keymap-options"
echo ""
echo "Обновление раскладок без перезапуска X11: dpkg-reconfigure xkb-data"
echo "Выбор раскладки для консоли: dpkg-reconfigure keyboard-configuration"
echo ""

echo "Для применения раскладок в консоли необходимо:"
echo "Изменить файл '/etc/default/keyboard'"
echo '  XKBMODEL="pc104"'
echo '  XKBLAYOUT="ru,ru"'
echo '  XKBVARIANT="ruchey_latin,ruchey_cyrillic"'
echo '  XKBOPTIONS="grp:caps_toggle,lv3:ralt_switch,grp_led:scroll"'
echo '  BACKSPACE="guess"'
echo "И выполнить команду: dpkg-reconfigure -phigh console-setup"
echo ""
echo "Для применения раскладок в initramfs необходимо:"
echo "Изменить файл '/etc/initramfs-tools/initramfs.conf'"
echo '  KEYMAP=y'
echo "И выполнить команду: update-initramfs -u"
echo ""
echo "Для применения раскладок в чистом X11 (не Gnome\KDE) необходимо выполнить команду:"
echo '  setxkbmap -model pc104 -layout ru,ru -variant ruchey_latin,ruchey_cyrillic -option grp:caps_toggle,lv3:ralt_switch'



