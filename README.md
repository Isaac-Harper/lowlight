# Lowlight

Dim your MacBook keyboard backlight below the lowest setting macOS allows.

A menu bar slider with ten steps under the macOS minimum and the normal range above it. Changing keyboard brightness in Control Center takes back over.

## Requirements

- Apple Silicon MacBook
- macOS 26

## Build

```sh
./build.sh
open Lowlight.app
```

## How it works

macOS clamps any nonzero keyboard brightness to a PWM floor, but fades interpolate the raw duty cycle all the way to 0. Lowlight fades down, reads the live duty from the IORegistry, and holds it at the chosen step with slow fades.

Uses private CoreBrightness APIs, so a macOS update may break it.

## License

MIT
