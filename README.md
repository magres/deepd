# deepd — настоящий глубокий сон для Android TV приставок

`deepd` — крошечный shell-демон (около 100 строк, без внешних зависимостей),
который учит Android TV приставку **настоящему сну**: прошивка сама
«засыпает» лишь наполовину, а `deepd` доводит её до suspend-to-RAM.

Ориентир — **Amlogic-приставки с кастомной прошивкой** (Tanix, T95, X96,
Ugoos и т.п.), но механика обычная для любого Android 5+ с `mem` в
`/sys/power/state`.

| | |
| --- | --- |
| Проверено на железе | Tanix TX92 (Amlogic S912, Android 9, прошивка slimBOXtv) |
| Вход в сон | HDMI-CEC «ТВ выключился», кнопка корпуса, `input keyevent` и любой штатный источник сна |
| Выход из сна | CEC-включение ТВ, кнопка корпуса, клавиши пульта (RF/IR) |

---

## Зачем это нужно (проблематика)

Стандартный «сон» Amlogic-приставок выглядит так: экран гаснет, USB и HDMI
приглушаются, но **процессор не уходит в suspend**. Мы измерили это на
Tanix TX92 (сон от CEC-standby ТВ):

```
PowerManagerService: Going to sleep ...        ← framework «уснул»
[early_suspend] video/aocec/hdmitx...          ← fb, USB, CEC спят
/proc/uptime продолжает тикать                 ← ядро живёт, CPU работает
```

Результат: ночью процессор работает впустую (греет и шумит), сеть и
передний дисплей тоже не отдыхают. Прошивка пропускает последний шаг —
`echo mem > /sys/power/state`.

deepd добавляет именно его. Все проверки ниже — реальные замеры на TX92:
во время глубокого сна сеть отвалится (`adb` отвечает `No route to
host`), после пробуждения ядро пишет пары `PM: suspend entry/exit`, а
wake по CEC фиксируется как `wakeup_reason:0x8` (включая наш замер
непрерывного сна ≈16 часов с ночи на утро).

## Как это работает

```
   штатный источник сна (CEC Standby / кнопка / таймер / ...)
        │
        ▼
framework: mWakefulness=Asleep          ← прошивка сама сюда приходит
        │  (deepd проверяет каждые grace сек)
        ▼
deepd: echo mem > /sys/power/state      ← настоящий suspend-to-RAM
        │  (сеть и интерфейсы гаснут)
        ▼
   wake: ТВ вкл (CEC), кнопка корпуса, пульт
        │
        ▼
deepd: input keyevent 224 (KEYCODE_WAKEUP) + cooldown
        │
        ▼
   ATV снова на экране
```

## Почему рут не всегда нужен

- **Установка через TWRP — вообще без root и без adb**: recovery имеет
  полный доступ, копирует файлы и правит CEC-настройку. Плюс TWRP-зип
  не трогает прошивку: только `/system/bin/deepd.sh`,
  `/system/etc/deepd.conf`, `/system/etc/init/deepd.rc`.
- **В работе** демон единственный раз в цикл пишет `mem` в
  `/sys/power/state`. На Amlogic BSP-ядрах этот узел принадлежит группе
  `system` (`-rw-rw---- system system`), поэтому служба запускается как
  `user system` — **без root в рантайме**. На строгих сборках, где узел
  доступен только uid 0, deepd сам пробует запись через `su` (если на
  прошивке есть root) — если и это не выходит, аккуратно завершается
  с пояснением в `/data/local/tmp/deepd.log`.
- Вывод: «рут нужен» только как «на прошивке есть возможность записи в
  /sys/power/state» — у большинства Amlogic-сборок это правда и без
  root-прав в рантайме. У стоковых/брендовых прошивок root нет — deepd
  там неприменим в принципе.

## Артефакты релиза и куда они подходят

На странице [Releases](https://github.com/magres/deepd/releases) для
каждого тега `v*`:

| артефакт | что это | кому подходит |
| --- | --- | --- |
| `deepd-twrp-install-amlogic-android5-9-vX.Y.Z.zip` | флешабельный zip | боксы **Amlogic с кастомной прошивкой Android 5–9** (классическая схема `/system`), у которых установлен TWRP/совместимый recovery. ПК не нужен |
| `deepd-twrp-uninstall-amlogic-android5-9-vX.Y.Z.zip` | zip отката | те же боксы; снимает deepd и возвращает CEC-настройку |
| `Source code (zip)` | исходники | путь «через adb с ПК» (любой бокса с root через adb) |

Не подходят TWRP-зипам: стоковые прошивки с verified boot (`/system`
только для чтения), Android 10+ / A/B / system-as-root (пока не
поддерживаются), recovery отсутствует. Для шифрованного `/data` zip
поставит файлы, но шаг включения CEC пропустит с предупреждением —
включить CEC потом через adb.

## Для домохозяйки: установка

### Путь A — через TWRP (без ПК)

Что нужно заранее:
1. **root или доступный `su` на прошивке** не обязателен, но прошивка
   должна позволять запись `/system` (кастомные сборки — ок);
2. на приставке установлен **TWRP** (или совместимый recovery);
3. знать, как попасть в recovery (обычно: выключить → нажать кнопку
   сброса/при включении питания — у каждой модели по-своему).

Шаги:
1. Скачайте из Releases файл
   `deepd-twrp-install-amlogic-android5-9-…zip` на флешку (FAT32).
2. Загрузитесь в TWRP → **Install** → выберите zip → смахните
   для подтверждения.
3. Нажмите **Reboot to system**.
4. Проверка: выключите ТВ — через 8–15 сек приставка уйдёт в настоящий
   сон (дисплей тускнеет, сеть отвалится). Включите ТВ — ATV вернётся сам
   за 5–25 секунд.

Откат: flash `deepd-twrp-uninstall-…zip` той же процедурой.

### Путь B — через adb с ПК

Что нужно заранее:
1. Приставка в сети (Wi-Fi или провод) и **включённый режим отладки
   по ADB**.
2. **root из adb** (`adb root` или `su` на прошивке).
3. Узнайте IP приставки (Настройки → Сеть, или из роутера). Пример:
   `192.168.1.100`.

Шаги:
1. Скачайте platform-tools (официальный adb от Google):
   <https://developer.android.com/tools/releases/platform-tools> —
   распакуйте архив так, чтобы внутри была папка `platform-tools`.
2. Скачайте последнюю версию deepd — «Releases» здесь же (или
   «Code → Download ZIP»), распакуйте; для Windows положите папку
   `platform-tools` внутрь папки deepd.
3. Установите:
   - **Windows:** дважды щёлкните `scripts\install_windows.bat`, нажмите
     `[1]`, введите IP и ждите. Установщик скопирует файлы, включит
     HDMI-CEC и перезагрузит приставку.
   - **Linux/macOS:** `./scripts/install.sh 192.168.1.100`.
4. После перезагрузки — проверка (шаг 5 из пути A).

**«Если там написано…» — типовые ошибки**

| Сообщение | Что это и что делать |
| --- | --- |
| «no root access» | Прошивка без root: deepd не заработает (adb-путь). Попробуйте TWRP-путь |
| «adb not found» | platform-tools не там: распакуйте внутрь папки deepd или добавьте в PATH |
| «unable to connect» | Приставка выключена/не в сети, или ADB-отладка отключена |
| «no mem suspend support» | Ядро не умеет suspend-to-RAM: устройство не подходит |
| «/system is read-only» (TWRP) | verified boot: zip на эту прошивку не годится |
| «/data unavailable: CEC not changed» (TWRP) | файлы поставлены; включите CEC потом через adb |
| Сон не наступает | См. FAQ и «Диагностика» |

## Проверь свою коробку за 5 минут

Не уверены в боксе? Прогоните этот чек-лист до установки (адб/терминал
на приставке):

1. root есть? `adb shell su -c 'id -u'` → должно быть `0`
   (или `adb root` работает).
2. Ядро умеет suspend? `cat /sys/power/state` → в списке должно быть
   `mem`.
3. CEC включён в framework? `settings get global hdmi_control_enabled` →
   `1` (установщик включит сам, но проверить не мешает).
4. Сон приходит? `dumpsys power | grep mWakefulness=` после выключения
   ТВ → должно стать `Asleep` (если навсегда `Awake` — CEC/источника сна
   нет, см. FAQ).
5. Deep работает? После сна: `su -c "dmesg | grep 'PM: suspend'"` →
   пара `entry/exit` означает настоящий suspend; пробуждение от ТВ:
   `wakeup_reason:0x8` (Amlogic).

Если все 5 шагов у вас зелёные — deepd будет работать.

## Это универсально? Пределы

| Слой | Что нужно | Amlogic (проверено) | Другие SoC (RK/Realtek и др.) |
| --- | --- | --- | --- |
| запись /system | root или recovery | есть на кастомных прошивках | зависит |
| suspend-to-RAM | `mem` в `/sys/power/state` | есть | обычно есть, но зависит от ядра |
| сон от CEC | `hdmi_control_enabled=1` | да (установщик включит) | зависит от прошивки |
| запись `/sys/power/state` | узел доступен `system`-у (0660) или `su` | да (`system system` на BSP) | часто нужен root/su — есть fallback |
| **wake по CEC из deep** | AOCEC (Amlogic) | **да** (`wakeup_reason:0x8`) | часто **нет** — будить пультом/кнопкой корпуса |
| watchdog «ТВ выключен» | HPD гаснет при выключении ТВ | зависит от ТВ | выключен по умолчанию |

Итого: **Amlogic-first**. На других SoC сон работает, пробуждение —
через пульт или кнопку корпуса; отчитайтесь в issue (шаблон
«Device report»), матрица совместимости пополняется.

## Частный случай: Tanix TX92 (slimBOXtv, Android 9)

Что делает установщик на этой сборке:

- включает framework-CEC: `settings put global hdmi_control_enabled 1`
  (в slimBOX он выключен по умолчанию; предыдущее значение сохраняется
  в `/data/local/tmp/deepd-cec.bak`, TWRP-зип делает бэкап
  `settings_global.xml.deepd.bak` и восстанавливает его при откате);
- кладёт `/system/bin/deepd.sh`, `/system/etc/deepd.conf`,
  `/system/etc/init/deepd.rc` (стандартные пути; boot и прошивку не
  трогаем).

Что это даёт на TX92 (всё проверено фактически):

- сон по CEC: `<Standby>` от ТВ → `PowerManagerService: Going to sleep due
  to HDMI standby` → deepd → пары `PM: suspend entry/exit` в dmesg;
- wake по CEC: включение ТВ → ядро логирует `wakeup_reason:0x8`, ATV
  возвращается сам;
- передний дисплей (если стоит демон-сервис
  [vfdsvc](https://github.com/magres/vfdsvc)) в соне — тусклое или
  погашенное время (ключ `standby=dim|off` в его конфиге).

## Настройка `/system/etc/deepd.conf`

| ключ | по умолчанию | что делает |
| --- | --- | --- |
| `grace` | `6` | период опроса framework, сек |
| `cooldown` | `20` | после пробуждения не спать повторно, сек |
| `tv_off_grace` | `0` | watchdog «ТВ выключен — усни» (см. ниже), сек; 0 = выключен |
| `hpd_state_path` | (пусто) | sysfs HPD-узел для watchdog (Amlogic: `/sys/class/amhdmitx/amhdmitx0/hpd_state`) |
| `debug` | `0` | `1` — писать каждый тик watchdog в лог |

Пауза на время обслуживания: `touch /data/local/tmp/deepd.pause`, снять:
`rm`.

## Watchdog «ТВ выключен» (опционально)

Некоторые пульты с аэромышью будят спящую приставку в самый момент
нажатия «power»: гироскоп в режиме мыши шлёт поток событий, и framework
отменяет начавшийся сон. Watchdog возвращает box в сон, если box оказался
жив при выключенном ТВ, но работает лишь у ТВ, где HPD падает при
выключении. Проверка (Amlogic):

```sh
cat /sys/class/extcon/hdmi_power/state   # HDMI=1 ТВ вкл, HDMI=0 выкл
```

Если линия не падает (бывает у некоторых Philips) — держите
`tv_off_grace=0` и выключайте режим мыши кнопкой пульта, или возьмите
пульт, который шлёт gyro-события только при реальном движении
(пример — Ugoos UR02).

## Диагностика

- `/data/local/tmp/deepd.log` — журнал демона: `start`,
  `framework asleep -> suspend to mem`, `resumed`, ошибки записи;
- `adb shell su -c "dmesg | grep -E 'suspend (entry|exit)|wakeup_reason'"` —
  был ли настоящий suspend и причина wake (`0x6` — ИК/кнопка, `0x8` — CEC);
- `adb shell dumpsys power | grep mWakefulness=` — состояние framework;
- «Сеть отвалилась» во время сна — это **норма** (deep sleep гасит сеть).

## Откат

- TWRP: flash `deepd-twrp-uninstall-…zip`.
- adb: `./scripts/install.sh <ip> --uninstall` (или
  `scripts\install_windows.bat` → `[0] UNINSTALL`).

Удаляет три файла deepd и возвращает прежнее значение
`hdmi_control_enabled` (adb-путь) или восстанавливает бэкап XML (TWRP).

## English

`deepd` fixes Android TV boxes that never really sleep: the firmware only
suspends the display, USB and CEC while the CPU stays awake. Once the
framework is `Asleep`, the daemon writes `mem` to `/sys/power/state`
(real suspend-to-RAM); after the kernel resumes it sends
`KEYCODE_WAKEUP`, then waits `cooldown` seconds. On Amlogic BSP kernels
`/sys/power/state` is writable by the `system` group, so the init service
runs as `user system` — no runtime root; on stricter builds the write
falls back to `su`. Install either by flashing
`deepd-twrp-install-amlogic-android5-9-…zip` from TWRP recovery (no PC,
no adb needed) or via `scripts/install.sh <ip>` / the Windows batch
(needs adb root). The installer flips HDMI-CEC on
(`hdmi_control_enabled=1`), backing up the old value for rollback.
Verified on Tanix TX92 (Amlogic S912, Android 9): sleep by CEC Standby,
wake by CEC (`wakeup_reason:0x8`), power button, RF/IR remotes, ≈16 h of
continuous deep suspend. Not supported in v0.2: A/B / system-as-root,
stock verified-boot firmwares. On other SoCs wake-on-CEC may be
unavailable — wake via remote or case button. Options: `grace`,
`cooldown`, optional `tv_off_grace` + `hpd_state_path` watchdog,
`debug`; pause via `touch /data/local/tmp/deepd.pause`. Rollback:
`deepd-twrp-uninstall-…zip` or `install.sh <ip> --uninstall`.

## FAQ

**Приставка вообще не уходит в сон.** Проверьте
`dumpsys power | grep mWakefulness=`: если framework остаётся `Awake` —
либо CEC не включён (`hdmi_control_enabled`), либо события аэромыши
будят box в момент попытки уснуть (см. watchdog и режим мыши пульта).

**Включил ТВ — ATV не вернулся.** На не-Amlogic SoC wake по CEC из deep
sleep может не работать: будите пультом/кнопкой корпуса. На Amlogic —
смотрите `dmesg` (`wakeup_reason`).

**Часы сбились после отключения из розетки.** У SoC нет батарейки RTC —
время подправится по NTP при загрузке; на сон это не влияет.

**Сеть пропала, хотя ничего не нажимал.** Это deep sleep — сеть
недоступна до пробуждения. Если нужно поработать по adb при выключенном
ТВ — поставьте паузу (`touch /data/local/tmp/deepd.pause`).

**TWRP пишет «/system is read-only».** Прошивка с verified boot —
установиться не даст; deepd на такую прошивку не применим.

## Лицензия

GPL-3.0 (`LICENSE`).
