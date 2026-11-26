# Keyboard Control (web)

A web app for the **XINMENG (新盟) K980** tri-mode mechanical keyboard (model XM-K980), and similar keyboards.
It runs in the browser with no driver install.

**Open it:** https://ryhan0912-arch.github.io/keyboard-control-web/ in Chrome or Edge (Windows, macOS, Linux, ChromeOS).

## What you can do with a K980

Everything below was tested on a real K980. Settings are **saved inside the keyboard**, so they stay after a restart
and also work in 2.4G and Bluetooth mode. Changing them needs the **USB cable with the keyboard in wired mode**,
the same as Xinmeng's own driver.

| Card | What it does |
|---|---|
| **Lighting** | 20 effects + Game mode + Off, 7 colors or rainbow, brightness, speed, 8 one-click presets, Apply / Undo |
| **Keyboard settings** | Sleep after (never to 60 minutes), debounce level 0–4 |
| **Key remapping** | Any key → another key, a modifier, a media key (play/pause, volume, calculator …), a **key combination** (e.g. End → Win+Shift+S), a macro, or disabled. Keys with Fn shortcuts keep them. Reset all keys. |
| **Macros** | Record or build up to 8 macros (keys with delays, long pauses), play once / N times / while held / until another key, assign to any key |
| **Game mode colors** | Paint a color for every key in 5 color sets on a drawing of the K980 |
| **Music mode** | The keys follow whatever the PC plays (spectrum bars, pulse, rainbow beat, center wave), see below |
| **Reset everything** | Puts lighting, settings, keys, macros and Game mode colors back to how the keyboard originally was |

How the K980 shows up:

| Mode | USB / name | |
|---|---|---|
| Cable (wired) | `258A:0049` "Newmen Bluetooth Keyboard" | full control |
| 2.4G | `25A7:FA70` "2.4G Wireless Receiver" | detected; saved settings work, changes need the cable |
| Bluetooth | "K980 5.0" | detected; saved settings work, changes need the cable |

Only the K980 (and K98-family keyboards) are listed; other receivers such as mice are ignored.
Shift+click **+ Add keyboard** to pick any other device.

## Music mode and the music helper

A web page can't hear the PC's sound by itself, so music mode uses a small helper,
[`music-helper/K980-Music-Helper.cmd`](music-helper/K980-Music-Helper.cmd):

- Double-click it and leave its window open (minimized is fine). It's a plain PowerShell script; open it in Notepad to check it.
- It listens to the **active output device** (speakers, headphones, monitor) with Windows' loopback capture, with no permission
  pop-ups, and switches when you change devices.
- It drives the keyboard lights itself, so music mode **keeps running after the page is closed**. The page controls it:
  start/stop, effect, colors, sensitivity, smoothness. Stopping it brings the saved lighting back.
- It only talks to the page over `ws://127.0.0.1:28420` on this PC and sends nothing anywhere else.
- To start it with Windows, put a shortcut to it in your Startup folder (Win+R → `shell:startup`).

Music mode needs the USB cable: the 2.4G dongle has no channel for live colors.

## How it works

The K980's protocol (SinoWealth BYK916) was worked out from Xinmeng's own K980 tri-mode driver and tested on the keyboard:

- Settings are pages read with feature report `05` `[0x80|op, page]` + `06`, and written with `06` `[op, page, …]`:
  lighting/settings `B6`, key table `D4` (Windows layer), macros `DC`/`E0`/`E4`/`E8`, Game mode colors `BC`/`C0`.
- Changes are only kept after the unlock command the official driver sends (`05 01 02 00 00 00`, its "PSD" setting).
- Every write is read-modify-write: the page reads the keyboard's data, changes only what you edited, writes it back and reads it again to confirm.
  If something doesn't look as expected, nothing is written. Firmware and bootloader commands are never sent.
- Live colors (music mode) use feature report `08`, which the K980 only shows while it keeps receiving frames.

Also cross-checked with [k980-webhid-driver](https://github.com/ReLIFE-1/k980-webhid-driver),
[OpenRGB](https://gitlab.com/CalcProgrammer1/OpenRGB), [redragon-ks82b-rgb](https://github.com/Saka-CS/redragon-ks82b-rgb)
and [Fizz-Rgb-Driver](https://github.com/kayradivrik/Fizz-Rgb-Driver). K98-family support (`05AC:024F`) comes from Xinmeng's K98 driver,
[gmk67-openrgb](https://github.com/yasasgit/gmk67-openrgb) and [openrgb-aula-f75-max](https://github.com/linuslul13/openrgb-aula-f75-max).

Not supported on the K980: mouse buttons on keys (the keyboard doesn't act on them), changes through the dongle or Bluetooth, firmware updates.

## Requirements

- Chrome or Edge on a desktop computer (WebHID)
- Windows for the music helper

## License

Released under the **GNU General Public License v3.0**.

## Disclaimer

Unofficial community project, **not affiliated with, endorsed by, or supported by Xinmeng or any keyboard maker**.
Brand and model names are used only to describe compatibility. Use at your own risk.
