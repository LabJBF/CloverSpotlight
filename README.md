# CloverSpotlight

A Theos/Logos tweak scaffold for researching native Spotlight integration on iOS/iPadOS.

**Current status: scaffold only.** Version 0.1.0 confirms injection into SpringBoard by logging a constructor message. It does not yet present Spotlight or hook private APIs.

## Target

- Development host: Ubuntu
- Build system: Theos
- Tweak language: Objective-C / Logos
- Injection target: `com.apple.springboard` / `SpringBoard`
- Initial package scheme: rootless
- Architectures: `arm64`, `arm64e`

The target device/environment must be tested independently. A successful package build does not prove that ElleKit injects the tweak or that private APIs are available.

## Ubuntu setup

```bash
chmod +x scripts/*.sh
./scripts/install-ubuntu-deps.sh
./scripts/install-theos.sh
```

Configure an iOS SDK supported by your Theos installation. Then open a new terminal and verify:

```bash
echo "$THEOS"
which make
```

## Build

```bash
make clean
make package
```

The resulting `.deb` is normally written to `packages/`.

## Install

Transfer the package to the test device and install it with the package manager. Keep a way to remove the package if SpringBoard becomes unstable.

## Next engineering steps

1. Confirm package architecture and install paths for the exact SwitchZart/Procursus setup.
2. Verify that the constructor log appears in SpringBoard.
3. Obtain and inspect the exact iOS 27.0 headers for SpotlightUI, SpotlightUIInternalFramework, SearchUI, and SpringBoard.
4. Verify class and selector availability at runtime before adding any Logos hook.
5. Integrate native Spotlight UI only after its lifecycle and presentation path are understood.

Do not add guessed selectors or call private methods based only on class names.
