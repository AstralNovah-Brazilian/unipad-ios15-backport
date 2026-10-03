# UniPad iOS15 (BackPort)

This project is a fork of Oficial UniPad, created with a simple goal: to make it possible to use our beloved UniPad on older devices that support iOS 15.
You can expect the FULL essence of the original project, retaining its behavior, features, and functionality, while making the necessary adaptations to ensure backward compatibility with earlier versions of iOS.

It is important to emphasize that the focus of this fork is not to reinvent UniPad, but rather to extend its lifespan and accessibility, allowing more devices to continue enjoying the app's original experience—simply adapted for iOS 15.

Supporting the following devices:

iPhone:

iPhone 6s
iPhone 6s Plus
iPhone 7
iPhone 7 Plus
iPhone 8
iPhone 8 Plus
iPhone X
iPhone SE (1st gen)
...

iPad:
iPad Air 2
iPad mini 4
iPad (5st gen)
iPad Pro 9,7"
iPad Pro 12,9" (1st gen)
...


# Backport-specific features

- Support for iOS / iPadOS 15.0 and later.
- Rebuilt to work with Xcode 15.2.
- Custom UniPack directory selection.
- Custom Theme directory selection.
- UniPacks and Themes can be stored outside the app's default internal folders.
- Improved support for importing and managing custom themes.
- Custom theme watermark support through custom_logo.png.
- Themes without custom_logo.png do not display a fallback watermark.
- Responsive Play interface adapted for different iPhone and iPad screen sizes.
- Additional quick controls available directly from the Play screen. (Like Web Version)
- Compatibility adaptations for newer UniPad features while preserving the iOS 15 deployment target.
- CoreMIDI and Launchpad support preserved for older iOS / iPadOS versions.


# Oficial App Link!!!
<a href="https://apps.apple.com/us/app/unipad/id6760479102">
  <img src="https://tools.applemediaservices.com/api/badges/download-on-the-app-store/black/en-us?size=250x83" alt="Download on the App Store" height="50">
</a>

UniPad is a performance-based rhythm game that enables connection with a launchpad and allows users to create their own beatmaps using the unique "unipack" format, fostering creativity and sharing within the community. 

# Features ported to iOS15

## Tested on iPad Air2 (iOS 15) and iPhone 8 plus (iOS 16)
- **UniPack Support**: Load and play custom UniPacks (.zip / .unipack) with sound mapping, LED animations and autoplay sequences.
- **Custom Themes**: Supports custom skins, pad textures, phantom overlays, chain LEDs and background artwork. (some things are broken yet how theme preview, but will be fixed soon)
- **Low-Latency Audio**: Multi-channel sound playback built for live performance.

## Not Tested
- **Launchpad & MIDI Support**: Works over USB with automatic detection for:
  - Novation Launchpad S, Mini and MK2
  - Novation Launchpad Pro (Stock firmware)
  - Novation Launchpad Pro (mat1jaczyyy Performance CFW)
  - Novation Launchpad (CoreFW)
  - Novation Launchpad X, Mini MK3 and Pro MK3
  - Midi Fighter 64
  - Mystrix
  - Generic Master Keyboard
  
- Built with SwiftUI and CoreMIDI. 

### Prerequisites

- macOS Ventura 13 with Xcode 15.2 or later
- iOS / iPadOS 15.0+ device or simulator

If you want to delve deeper into the project, I recommend checking out the Oficial project preferably :)

## License

This project is licensed under the [GNU Lesser General Public License v2.1](LICENSE).

## Credits
 
- Only use this project if you have a dead device on iOS 15, otherwise, use the original project. ALWAYS!

- Original UniPad app and concept by [Kim Ji-Sub](https://github.com/kimjisub).
- Thanks to the UniPack creators and custom firmware developers.
