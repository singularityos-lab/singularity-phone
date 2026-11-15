# singularity-phone

> [!IMPORTANT]
> Report bugs and request features in the
> [Singularity Desktop tracker](https://github.com/singularityos-lab/singularity-desktop/issues/new/choose).

Phone for the [Singularity Desktop Environment](https://github.com/singularityos-lab): make and receive voice calls with the built-in modem through ModemManager.

## Requirements

- [Meson](https://mesonbuild.com/) ≥ 1.0
- [Vala](https://vala.dev/) compiler
- GTK4, libgee-0.8, json-glib
- [libsingularity](https://github.com/singularityos-lab/libsingularity)
- ModemManager at runtime, with a modem that supports voice calls

## Build & Install

```sh
meson setup build
meson compile -C build
meson install -C build
```

## Usage

Type a number with the keypad or the keyboard and press Enter to call. During a call the digits you type are sent as tones. `tel:` links open the keypad with the number filled in.

Recent and missed calls are kept in `$XDG_DATA_HOME/singularity-phone/calls.json`.

Other programs can start a call over D-Bus:

```sh
gdbus call --session -d dev.sinty.phone -o /dev/sinty/phone/Phone -m dev.sinty.Phone1.Dial "+390212345678"
```

`dev.sinty.Phone1.Prefill` puts the number on the keypad without calling.

## License

GPL-3.0-only - see [LICENSE](LICENSE).
