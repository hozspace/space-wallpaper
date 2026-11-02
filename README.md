# Space Wallpaper

A procedurally generated wallpaper for macOS. A small rocket flies an endless journey through space, passing planets and weaving through meteor belts.

## Building

Needs macOS 14 or later, Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

The rocket sprite isn't included. Put a rocket image, pointing right on a transparent background, at `App/Rocket/rocket.png`.

```sh
make run-release   # build and start the wallpaper
make test          # route, flight and meteor tests
make preview       # open it in a normal window instead
```

Settings and Quit live under the sparkles icon in the menu bar.

## Layout

- `App/Planets` planet types and their shaders
- `App/Meteors` meteor belts
- `App/Rocket` the rocket's flames and rotation
- `App/Sky` stars, clouds and speed dust
- `App/Flight` the ship, camera and saved journey
- `App/Settings` the settings window
- `Packages/SpaceCore` the route, flight and seeded generation, with its tests
- `tools/Snapshot.swift` renders a single frame to a PNG (`make snapshot-tool`)

## Credits

- Planet, ring and meteor shaders are ported from [PixelPlanets](https://github.com/Deep-Fold/PixelPlanets) by Deep-Fold (MIT, see `licences/`).
- [Departure Mono](https://departuremono.com) by Helena Zhang (SIL Open Font License, see `App/Settings/Fonts/`).

## Licence

MIT, see `LICENSE`.
