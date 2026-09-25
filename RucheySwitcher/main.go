// RucheySwitcher — фоновый переключатель раскладки клавиатуры для Windows.
//
// Режимы работы:
//   - без аргументов: демон, висящий в фоне. Перехватывает CapsLock:
//     нажатие (включение)  -> раскладка RUS (a0010419),
//     повторное (выключение) -> раскладка ENG (a0000419).
//     При старте CapsLock принудительно сбрасывается в off, а сами
//     нажатия CapsLock «проглатываются», чтобы системный CapsLock
//     больше не работал как переключатель заглавных букв.
//     Исключение: Shift+CapsLock пропускается в систему и штатно
//     включает/выключает реальный CapsLock.
//   - list: показать установленные раскладки и текущую.
//   - eng/rus: разово включить указанную раскладку.
//   - toggle: разово переключить на противоположную раскладку.
//
// Сборка фоновой версии (без окна консоли):
//
//	go build -ldflags="-H windowsgui" -o RucheySwitcher.exe .
package main

import (
	"fmt"
	"os"
	"strings"
	"syscall"
	"unsafe"
)

// Константы WinAPI (подробности в MSDN).
const (
	klfActivate               = 0x00000001 // LoadKeyboardLayout: активировать раскладку
	wmInputLangChangeRequest  = 0x0050     // WM_INPUTLANGCHANGEREQUEST: запрос смены раскладки окну
	inputLangChangeSysCharset = 0x0001     // wParam: смена раскладки по системной таблице символов

	vkCapital    = 0x14 // VK_CAPITAL — виртуальный код клавиши CapsLock
	vkShift      = 0x10 // VK_SHIFT — виртуальный код клавиши Shift
	whKeyboardLL = 13   // WH_KEYBOARD_LL — низкоуровневый глобальный клавиатурный хук
	hcAction     = 0    // HC_ACTION: в nCode хука означает «событие нужно обработать»

	wmKeydown    = 0x0100 // WM_KEYDOWN
	wmKeyup      = 0x0101 // WM_KEYUP
	wmSyskeydown = 0x0104 // WM_SYSKEYDOWN (клавиша + Alt)
	wmSyskeyup   = 0x0105 // WM_SYSKEYUP

	llkhfInjected  = 0x10   // LLKHF_INJECTED: событие порождено программно (keybd_event/SendInput)
	keyeventfKeyup = 0x0002 // KEYEVENTF_KEYUP: флаг отпускания клавиши для keybd_event

	errorAlreadyExists = 183 // ERROR_ALREADY_EXISTS: мутекс уже создан другим экземпляром
)

// Ленивые привязки к процедурам WinAPI.
var (
	kernel32                   = syscall.NewLazyDLL("kernel32.dll")
	user32                     = syscall.NewLazyDLL("user32.dll")
	procGetCurrentThreadID     = kernel32.NewProc("GetCurrentThreadId")
	procCreateMutex            = kernel32.NewProc("CreateMutexW") // защита от повторного запуска
	procLoadKeyboardLayout     = user32.NewProc("LoadKeyboardLayoutW")
	procActivateKeyboardLayout = user32.NewProc("ActivateKeyboardLayout")
	procGetKeyboardLayoutList  = user32.NewProc("GetKeyboardLayoutList")
	procGetKeyboardLayoutName  = user32.NewProc("GetKeyboardLayoutNameW")
	procGetForegroundWindow    = user32.NewProc("GetForegroundWindow")
	procGetWindowThreadProcess = user32.NewProc("GetWindowThreadProcessId")
	procAttachThreadInput      = user32.NewProc("AttachThreadInput")
	procPostMessage            = user32.NewProc("PostMessageW")
	procSetWindowsHookEx       = user32.NewProc("SetWindowsHookExW")
	procCallNextHookEx         = user32.NewProc("CallNextHookEx")
	procUnhookWindowsHookEx    = user32.NewProc("UnhookWindowsHookEx")
	procGetMessage             = user32.NewProc("GetMessageW")
	procTranslateMessage       = user32.NewProc("TranslateMessage")
	procDispatchMessage        = user32.NewProc("DispatchMessageW")
	procGetKeyState            = user32.NewProc("GetKeyState")
	procGetAsyncKeyState       = user32.NewProc("GetAsyncKeyState") // физическое состояние клавиш-модификаторов
	procKeybdEvent             = user32.NewProc("keybd_event")      // имитация нажатия клавиши
)

// layout — целевая раскладка: имя для вывода и идентификатор из реестра
// (HKEY_LOCAL_MACHINE\...\Keyboard Layouts, 8 шестнадцатеричных цифр).
type layout struct {
	name string
	id   string
}

// Две раскладки, между которыми переключаемся.
var targets = []layout{
	{"ENG", "a0000419"},
	{"RUS", "a0010419"},
}

// kbdllhookstruct — структура KBDLLHOOKSTRUCT, которую хук WH_KEYBOARD_LL передаёт в lParam.
type kbdllhookstruct struct {
	vkCode      uint32  // виртуальный код клавиши (VK_*)
	scanCode    uint32  // аппаратный скан-код
	flags       uint32  // флаги (LLKHF_*)
	time        uint32  // время события
	dwExtraInfo uintptr // дополнительная информация
}

// point и msg — POINT и MSG в том же порядке полей, что у Windows,
// для корректной передачи через GetMessage/TranslateMessage/DispatchMessage.
type point struct {
	x int32
	y int32
}

type msg struct {
	hwnd    uintptr
	message uint32
	pad     uint32 // выравнивание до 8 байт (в 64-битной Windows)
	wParam  uintptr
	lParam  uintptr
	time    uint32
	pt      point
}

// Состояние демона.
var (
	hookHandle uintptr // дескриптор установленного хука
	capsIsOn   bool    // логическое состояние «виртуального CapsLock» (on=RUS, off=ENG)
	lastDown   bool    // подавляет автоповтор при удержании клавиши
	swallowUp  bool    // нужно ли проглотить следующий keyup CapsLock
	testMode   bool    // KS_TEST=1: реагировать и на программные (injected) нажатия
)

// hexHKL разбирает строку вроде "a0000419" в числовой HKL.
// Используется как запасной вариант, если LoadKeyboardLayout не сработал.
func hexHKL(s string) uintptr {
	var v uint64
	fmt.Sscanf(s, "%x", &v)
	return uintptr(v)
}

// hklOf возвращает актуальный HKL раскладки: сначала пробуем
// LoadKeyboardLayout (она же гарантирует, что раскладка загружена),
// при неудаче — числовой HKL из hex-строки.
func hklOf(l layout) uintptr {
	id, err := syscall.UTF16PtrFromString(l.id)
	if err != nil {
		return 0
	}
	hkl, _, _ := procLoadKeyboardLayout.Call(uintptr(unsafe.Pointer(id)), 0)
	if hkl != 0 {
		return hkl
	}
	return hexHKL(l.id)
}

// nameOf возвращает читаемое имя раскладки по её идентификатору.
func nameOf(id string) string {
	for _, l := range targets {
		if l.id == id {
			return l.name
		}
	}
	return id
}

// currentThreadID возвращает ID текущего потока.
func currentThreadID() uintptr {
	t, _, _ := procGetCurrentThreadID.Call()
	return t
}

// foregroundLayoutID возвращает идентификатор раскладки (8 hex-цифр),
// активной для окна на переднем плане. GetKeyboardLayoutName умеет
// смотреть раскладку только своего потока, поэтому временно
// «прикрепляемся» к потоку активного окна через AttachThreadInput.
func foregroundLayoutID() string {
	hwnd, _, _ := procGetForegroundWindow.Call()
	tid, _, _ := procGetWindowThreadProcess.Call(hwnd, 0)
	if tid == 0 {
		tid = currentThreadID() // нет активного окна — берём своё
	}
	if tid != currentThreadID() {
		procAttachThreadInput.Call(currentThreadID(), tid, 1)
		defer procAttachThreadInput.Call(currentThreadID(), tid, 0)
	}
	var buf [9]uint16 // KLID: 8 символов + завершающий ноль
	procGetKeyboardLayoutName.Call(uintptr(unsafe.Pointer(&buf[0])))
	return strings.ToLower(syscall.UTF16ToString(buf[:8]))
}

// switchTo переключает раскладку: ActivateKeyboardLayout — для своего
// потока, а PostMessage(WM_INPUTLANGCHANGEREQUEST) — для активного окна.
func switchTo(l layout) {
	hkl := hklOf(l)
	if hkl == 0 {
		return
	}
	procActivateKeyboardLayout.Call(hkl, 0)
	hwnd, _, _ := procGetForegroundWindow.Call()
	procPostMessage.Call(hwnd, wmInputLangChangeRequest, inputLangChangeSysCharset, hkl)
	fmt.Println(l.name)
}

// listLayouts выводит все HKL, известные нашему потоку, и текущую раскладку.
func listLayouts() {
	n, _, _ := procGetKeyboardLayoutList.Call(0, 0, 0)
	buf := make([]uintptr, n)
	procGetKeyboardLayoutList.Call(n, uintptr(unsafe.Pointer(&buf[0])), 0)
	for _, hkl := range buf {
		fmt.Printf("%016x\n", hkl)
	}
	fmt.Println("current:", foregroundLayoutID())
}

// capsState — включён ли сейчас системный CapsLock (бит 1 младшего байта).
func capsState() bool {
	r, _, _ := procGetKeyState.Call(vkCapital)
	return r&1 == 1
}

// shiftIsDown — физически ли удержана любая из клавиш Shift
// (старший бит GetAsyncKeyState). Вызывается из хука, поэтому
// нужен именно асинхронный запрос, не зависящий от очереди сообщений.
func shiftIsDown() bool {
	r, _, _ := procGetAsyncKeyState.Call(vkShift)
	return r&0x8000 != 0
}

// setCapsOff принудительно выключает CapsLock: если он включён,
// имитируем нажатие/отпускание клавиши через keybd_event.
// Вызывается при старте, до установки хука.
func setCapsOff() {
	if !capsState() {
		return
	}
	procKeybdEvent.Call(vkCapital, 0x3a, 0, 0)              // 0x3A — скан-код CapsLock, нажатие
	procKeybdEvent.Call(vkCapital, 0x3a, keyeventfKeyup, 0) // отпускание
}

// hookProc — колбэк низкоуровневого клавиатурного хука.
// Возврат 1 означает «событие обработано, дальше не передавать»
// (так мы прячем CapsLock от системы и приложений).
func hookProc(nCode int32, wParam uintptr, lParam unsafe.Pointer) uintptr {
	// nCode < 0: событие должно просто пройти по цепочке хуков.
	if nCode != hcAction {
		r, _, _ := procCallNextHookEx.Call(hookHandle, uintptr(nCode), wParam, uintptr(lParam))
		return r
	}
	k := (*kbdllhookstruct)(lParam)
	// Нас интересует только CapsLock, остальное пропускаем.
	if k.vkCode != vkCapital {
		r, _, _ := procCallNextHookEx.Call(hookHandle, uintptr(nCode), wParam, uintptr(lParam))
		return r
	}
	switch wParam {
	case wmKeydown, wmSyskeydown:
		// Программно сгенерированные нажатия (keybd_event/SendInput) игнорируем,
		// иначе будем реагировать на собственные имитации и чужие инструменты.
		// В тестовом режиме (KS_TEST=1) обрабатываем и их.
		if k.flags&llkhfInjected != 0 && !testMode {
			break
		}
		// Shift+CapsLock пропускаем в систему: Windows сама включает/выключает
		// реальный CapsLock. Ни нажатие, ни отпускание не проглатываем.
		if shiftIsDown() {
			break
		}
		// lastDown фильтрует автоповтор при удержании клавиши.
		if !lastDown {
			lastDown = true
			swallowUp = true
			if capsIsOn {
				capsIsOn = false
				switchTo(targets[0]) // выключение -> ENG
			} else {
				capsIsOn = true
				switchTo(targets[1]) // включение -> RUS
			}
		}
		return 1 // проглатываем нажатие
	case wmKeyup, wmSyskeyup:
		// Проглатываем отпускание только той клавиши, чьё нажатие мы съели.
		if swallowUp {
			swallowUp = false
			lastDown = false
			return 1
		}
	}
	r, _, _ := procCallNextHookEx.Call(hookHandle, uintptr(nCode), wParam, uintptr(lParam))
	return r
}

// run — основной цикл демона.
func run() {
	// Именованный мутекс: второй экземпляр приложения сразу завершается.
	mutexName, _ := syscall.UTF16PtrFromString("KeySwitcher")
	_, _, mutexErr := procCreateMutex.Call(0, 0, uintptr(unsafe.Pointer(mutexName)), 0)
	if en, ok := mutexErr.(syscall.Errno); ok && en == syscall.Errno(errorAlreadyExists) {
		fmt.Println("already running")
		os.Exit(1)
	}

	// Тестовый режим для автоматизированной проверки (см. hookProc).
	testMode = os.Getenv("KS_TEST") != ""

	// Стартовое состояние: CapsLock всегда выключен, логическое состояние off.
	setCapsOff()
	capsIsOn = false
	lastDown = false
	swallowUp = false

	// Заранее загружаем обе раскладки, чтобы их HKL были известны системе.
	for _, l := range targets {
		hklOf(l)
	}

	// Устанавливаем глобальный низкоуровневый хук (работает во всех приложениях).
	// syscall.NewCallback удерживает Go-функцию, чтобы GC её не выбросил.
	h, _, _ := procSetWindowsHookEx.Call(whKeyboardLL, syscall.NewCallback(hookProc), 0, 0)
	if h == 0 {
		fmt.Println("failed to install hook")
		os.Exit(1)
	}
	hookHandle = h
	fmt.Println("running: CapsLock ON -> RUS, OFF -> ENG")

	// Низкоуровневым хукам нужен цикл сообщений в установившем их потоке.
	// Крутим его, пока не придёт WM_QUIT (r == 0) — т.е. по сути до конца процесса.
	var m msg
	for {
		r, _, _ := procGetMessage.Call(uintptr(unsafe.Pointer(&m)), 0, 0, 0)
		if r == 0 {
			break
		}
		procTranslateMessage.Call(uintptr(unsafe.Pointer(&m)))
		procDispatchMessage.Call(uintptr(unsafe.Pointer(&m)))
	}
	procUnhookWindowsHookEx.Call(hookHandle)
}

func main() {
	// Первый аргумент выбирает режим; без аргументов — демон.
	arg := ""
	if len(os.Args) > 1 {
		arg = strings.ToLower(os.Args[1])
	}

	switch arg {
	case "list", "-l", "--list":
		listLayouts()
		return
	case "eng", "en", "english", "a0000419":
		switchTo(targets[0])
		return
	case "rus", "ru", "russian", "a0010419":
		switchTo(targets[1])
		return
	case "toggle":
		if foregroundLayoutID() == targets[1].id {
			switchTo(targets[0])
		} else {
			switchTo(targets[1])
		}
		return
	}
	run()
}
