---
name: Device report
about: Does deepd work on YOUR box? Report here so the compatibility matrix grows.
title: '[device] MODEL, SoC, Android version'
labels: device-report
---

**Box / board:** e.g. Tanix TX92
**SoC:** e.g. Amlogic S912
**Android version:** e.g. 9
**Firmware:** e.g. slimBOXtv custom (root on) / stock
**Recovery:** TWRP installed? yes/no

**Self-check results (commands from README "Check your box in 5 minutes"):**

```
cat /sys/power/state
```
```
settings get global hdmi_control_enabled
```
```
after a sleep attempt: su -c "dmesg | grep -E 'suspend (entry|exit)|wakeup_reason'"
```

**Result:** does the box reach a real suspend (`PM: suspend entry` in dmesg)?
Does it wake when the TV turns on (`wakeup_reason` value)?
Anything odd (network wake, front display, air mouse)?
