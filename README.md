# Keyboard Control (web)

A single-page web app that detects and controls **XINMENG (新盟) K980 and similar keyboards** over **USB cable, 2.4G dongle and Bluetooth**, straight from the browser, with no driver install.

**Open it:** https://ryhan0912-arch.github.io/keyboard-control-web/ in Chrome or Edge on Windows, macOS, Linux or ChromeOS.

## XINMENG (新盟) K980

Identified on a real keyboard:

| Mode | Shows up as | What the page does |
|---|---|---|
| USB cable | `258A:0049` "Newmen Bluetooth Keyboard" | **Saved lighting** (28 effects + off, 7 colors or rainbow, brightness 0–4, speed 1–4), written into the keyboard's memory and verified on the real keyboard. Also live per-key colors. |
| 2.4G | `25A7:FA70` "2.4G Wireless Receiver" (keystrokes verified to come from this dongle) | Recognized and connected; lighting is changed over the cable |
| Bluetooth | "K980 5.0" | Recognized and connected; battery via Web Bluetooth |

Saved lighting is read-modify-write. The page reads the keyboard's own lighting config, changes only the effect, color, brightness and speed bytes,
writes it back and reads it again to confirm. If the config doesn't look as expected, nothing is written.
Because the lighting is stored in the keyboard, it stays the same in 2.4G and Bluetooth mode.

Only known keyboards are listed. Other 2.4G receivers (mice etc.) are ignored. When several connections are present, the one in use is picked (cable, then Bluetooth, then dongle).

## Other keyboards

**Shift+click + Add keyboard** to list every HID device on the computer and pick any other keyboard.
The page then looks at the device's own HID report layout and picks the matching protocol automatically:

| Protocol | Recognized by | Examples | What you can control |
|---|---|---|---|
| XVX / K98 (cable) | 64-byte feature report | `05AC:024F` "K98 Keyboard" | Lighting effects, per-key colors, settings, clock |
| XVX / K98 (wireless) | 32-byte output report | "2.4G Dongle", Bluetooth with vendor channel | Lighting effects, settings, clock, battery |
| Sinowealth per-key | feature report `0x08` | `258A:0049` "Newmen Bluetooth Keyboard" | Live per-key colors, brightness |
| Basic | anything else | any keyboard | Device inspector, raw command console |

Over Bluetooth, **Read battery over Bluetooth** reads the standard battery service (Web Bluetooth).

Devices you've added once are found again automatically. Unplugging, switching mode and waking up are all handled.

## Features

- Lighting: 19 effects plus per-key and off, color, colorful/rainbow, brightness, speed, direction
- Per-key colors on a drawing of the keyboard (K98 layout, or the 126-slot Sinowealth grid)
- Lock the Windows key, disable Alt+F4 / Alt+Tab, Fn swap, sleep timer, key response time, clock sync
- Battery level: automatic over the 2.4G dongle, on request over Bluetooth
- Device inspector showing every HID interface and report, plus a raw report console for unknown keyboards
- Communication log with copy button for troubleshooting

## How to use

1. Close the keyboard maker's own app (also from the system tray).
2. Connect the keyboard by cable, 2.4G dongle or Bluetooth. Press a key to wake a sleeping wireless keyboard.
3. First time only: click **+ Add keyboard** and pick your keyboard from the full list.

## How it works

- XVX / K98 protocol: read from the vendor's K98 driver (`DeviceDriver.exe`, v1.0.0.0), cross-checked with
  [gmk67-openrgb](https://github.com/yasasgit/gmk67-openrgb) and [openrgb-aula-f75-max](https://github.com/linuslul13/openrgb-aula-f75-max).
- Sinowealth per-key protocol: from [redragon-ks82b-rgb](https://github.com/Saka-CS/redragon-ks82b-rgb) and
  [Fizz-Rgb-Driver](https://github.com/kayradivrik/Fizz-Rgb-Driver). The page never sends Sinowealth firmware or flash commands.

Keyboards don't report their current lighting or settings back, so the page shows the values you last sent from this browser.

## Requirements

- Chrome or Edge 89 or newer on a desktop computer (WebHID; Web Bluetooth for the Bluetooth battery)
- Phones, Firefox and Safari are not supported

## License

Released under the **GNU General Public License v3.0**.

## Disclaimer

Unofficial community project, **not affiliated with, endorsed by, or supported by Xingmeng / XVX or any keyboard maker**.
Brand and model names are used only to describe compatibility. The raw console sends whatever you type, so use it at your own risk.

## Why lighting can't be changed through the 2.4G dongle

Xinmeng's own K980 tri-mode driver (`K980三模 Keyboard Setup V1.0`) only talks to the keyboard over the USB cable (`258A:0049`).
It has no 2.4G or Bluetooth support. The dongle carries key presses only. Lighting set over the cable is stored in the keyboard and used in all three modes.
