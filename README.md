# deepd — настоящий глубокий сон для Android TV приставок

`deepd` — крошечный shell-демон (около 70 строк, без внешних зависимостей),
который учит Android TV приставку **настояще спать**: прошивка сама
«засыпает» лишь наполовину, а `deepd` доводит её до suspend-to-RAM.

Ориентир — **Amlogic-приставки с root** (Tanix, T95, X96, Ugoos и т.п.),
но механика обычная для любого Android 5+ с `mem` в `/sys/power/state`.

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

Результат: ночью процессор веет/шумит впустую, сеть и передний дисплей
тоже не отдыхают. Прошивка пропускает последний шаг —
`echo mem > /sys/power/state`.

Все проверки ниже — реальные замеры на TX92: во время глубокого сна сеть
оступается (`adb` отвечает `No route to host`), после включения приставки
ядро пишет пары `PM: suspend entry/exit`, а пробуждение по CEC фиксируется
как `wakeup_reason:0x8`.

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

## Для домохозяйки: установка за 5 минут

**Что нужно заранее:**
1. Приставка в сети (Wi-Fi или провод) и **включённый режим отладки
   по ADB** (в разных прошивках: Настройки → «Об устройстве/Параметры
   разработчика» → «Отладка по сети/USB» — включите).
2. **Root на прошивке** (на кастомных сборках обычно уже включён;
   на стоковых — часто нет, тогда deepd применить нельзя).
3. Узнайте **IP-адрес приставки**: Настройки → Сеть (или список
   устройств в роутере). Пример: `192.168.1.100`.

**Шаги:**

1. **Скачайте platform-tools** (официальный adb от Google):
   <https://developer.android.com/tools/releases/platform-tools> —
   распакуйте архив; у вас появится папка `platform-tools`.
2. **Скачайте последнюю версию deepd** — «Releases» здесь же на GitHub
   (или «Code → Download ZIP»), распакуйте.
3. **Установите:**
   - **Windows:** распакованную папку `platform-tools` поместите внутрь
     папки deepd; затем дважды щёлкните `scripts\install_windows.bat`,
     нажмите `[1]`, введите IP приставки и ждите. Установщик скопирует
     файлы, включит HDMI-CEC и перезагрузит приставку (1–2 минуты).
   - **Linux/macOS:** если adb не в PATH — пропишите или подложите его
     рядом (tooling/), затем: `./scripts/install.sh 192.168.1.100`.
4. После перезагрузки проще всего проверить работу (шаг 5).
5. **Проверка:** нажмите «вкл» на ТВ-пульте — экран гаснет, через 8–15 сек
   приставка уходит в настоящий сон (передний дисплей тускнеет/гаснет,
   сеть отвалится). Включите ТВ — ATV вернётся сам за 5–25 секунд.

**«Если там написано…» — типовые ошибки**

| Сообщение | Что это и что делать |
| --- | --- |
| «no root access» | Прошивка без root: deepd не заработает. Нужная прошивка с root или включение root в меню |
| «adb not found» | platform-tools не там: распакуйте внутрь папки deepd (Windows) или добавьте в PATH |
| «unable to connect» / «connection refused» | Приставка выключена/не в сети, или ADB-отладка отключена |
| «no mem suspend support» | Ядро не умеет suspend-to-RAM: устройство не подходит |
| Сон не наступает | См. FAQ и «Диагностика» ниже |

## Это универсально? Пределы

deepd — **универсальный механизм**, но у него три уровня успеха
по «железу»:

| Слой | Что нужно | Amlogic (проверено) | Другие SoC (RK/Realtek и др.) |
| --- | --- | --- | --- |
| root | доступ к `/system` и `/sys` | нужен | нужен |
| suspend-to-RAM | `mem` в `/sys/power/state` | есть | обычно есть, но зависит от ядра |
| сон от CEC | прошивочный HdmiControlService (`hdmi_control_enabled=1`, ставится автоматом) | да | зависит от прошивки |
| **wake по CEC из deep** | поддержка в SoC/ядре (у Amlogic — AOCEC) | **да** (`wakeup_reason:0x8`) | часто **нет** — тогда будить пультом/кнопкой корпуса |
| watchdog «ТВ выключен» | HPD гаснет при выключении ТВ (ТВ-специфика) | зависит от ТВ | выключен по умолчанию |

Вывод: на **Amlogic** решение работает «из коробки»; на других SoC вход в
сон работает, но пробуждение возможно пультом/кнопкой корпуса (ограничение
железа, а не демона).

## Частный случай: Tanix TX92 (slimBOXtv, Android 9)

Что именно делает установщик на этой сборке:

- включает framework-CEC: `settings put global hdmi_control_enabled 1`
  (в slimBOX он выключен по умолчанию; предыдущее значение сохраняется
  в `/data/local/tmp/deepd-cec.bak` для отката);
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

Пауза на время обслуживания (чтобы долгие adb-работы при выключенном ТВ
не мешали): `touch /data/local/tmp/deepd.pause`, снять: `rm`.

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
  `framework asleep -> suspend to mem`, `resumed`;
- `adb shell su -c "dmesg | grep -E 'suspend (entry|exit)|wakeup_reason'"` —
  был ли настоящий suspend и причина wake (`0x6` — ИК/кнопка, `0x8` — CEC);
- `adb shell dumpsys power | grep mWakefulness=` — состояние framework;
- «Сеть отвалилась» во время сна — это **норма** (deep sleep гасит сеть).

## Откат

```sh
./scripts/install.sh 192.168.1.100 --uninstall   # Linux/macOS
scripts\install_windows.bat                      # Windows: меню [0] UNINSTALL
```

Удаляет три файла deepd и возвращает прежнее значение
`hdmi_control_enabled`.

## English

`deepd` fixes Android TV boxes that never really sleep: the firmware only
suspends the display, USB and CEC while the CPU stays awake. Once the
framework is `Asleep`, the daemon writes `mem` to `/sys/power/state`
(real suspend-to-RAM); after the kernel resumes it sends
`KEYCODE_WAKEUP`, then waits `cooldown` seconds. Install: download
platform-tools and this repo, then run `scripts\install_windows.bat`
(Windows: menu `[1]`) or `./scripts/install.sh <ip>`. Root is required;
`mem` in `/sys/power/state` is required (checked at start); the HDMI-CEC
flag is flipped automatically and backed up for rollback. Verified on
Tanix TX92 (Amlogic S912, Android 9): sleep by CEC Standby, wake by CEC
(`wakeup_reason:0x8`), power button, RF/IR remotes. On other SoCs
wake-on-CEC may be unavailable — wake via remote or case button.
Options: `grace`, `cooldown`, optional `tv_off_grace` +
`hpd_state_path` watchdog, `debug`; pause via
`touch /data/local/tmp/deepd.pause`. Rollback: `--uninstall`.

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

## Лицензия

GPL-3.0 (`LICENSE`).
