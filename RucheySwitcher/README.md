Переключатель раскладок «Ручей» по клавише CapsLock. Переключатель работает только с раскладками *a0000419* (ENG) и *a0010419* (RUS).

## Сборка
`go build -ldflags="-H windowsgui" -o RucheySwitcher.exe`

## Упаковка
`Compress-Archive -Path .\RucheySwitcher.exe -DestinationPath .\RucheySwitcher-v1.zip`

## Установка
Просто запустить исполняемый файл RucheySwitcher.exe или разместить его в "Автозагрузка"

## Возможности
Можно вызвать переключение вручную:
- `RucheySwitcher.exe eng`
- `RucheySwitcher.exe rus`
- `RucheySwitcher.exe toggle`

Если не хотите, чтобы переключатель висел в памяти, можно воспользоваться ручным режимом и скриптом для *Autohotkey*
```
SetCapsLockState, AlwaysOff
+CapsLock::CapsLock

CapsLock::Run, RucheySwitcher.exe toggle,, hide
```
