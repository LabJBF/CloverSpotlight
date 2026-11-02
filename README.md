# Nyxian Spotlight

**Nyxian Spotlight** is an experimental Theos/Logos tweak exploring native Spotlight integration in the SwitchZart environment.

The repository and tweak target are named **CloverSpotlight**; the Debian package is distributed as **Nyxian Spotlight** (\`com.nyxian.spotlight\`).

> **Experimental status:** version 0.1.6 is a research build. Runtime investigation has identified relevant Spotlight classes and a callable manager selector, but the native Spotlight interface has not yet been successfully presented. A successful build or method call does not mean Spotlight is working.

## Project status

| Area | Status |
| --- | --- |
| Theos package build | Implemented |
| RootHide package scheme | Configured |
| arm64e target | Configured |
| Spotlight runtime investigation | In progress |
| Native Spotlight presentation | Not working yet |
| General device compatibility | Not established |

## Test environment

The current investigation has been performed on:

- iPad (10th generation, arm64e)
- iPadOS 27.0 beta 4
- SwitchZart with RootHide / Procursus

These are test conditions, not a compatibility guarantee. Other devices, iOS/iPadOS versions, and SwitchZart builds may behave differently.

## Technical notes

The investigation focuses on Apple's private Spotlight-related frameworks and runtime components, including \`SpotlightUI.framework\`.

Classes observed during research include:

- \`SPUISpotlightSceneManager\`
- \`SPUISpotlightRemoteViewController\`
- \`SPUISearchViewSceneSpecification\`
- \`SPUISearchViewSceneSettings\`
- \`SPUISearchViewSceneTransitionContext\`

The shared manager and the selector \`launchSpotlightIfNeededWithForegroundPriority:\` were found to be available at runtime. Calling the selector has not produced visible Spotlight UI so far.

Class and selector availability alone do not establish that an API is safe or sufficient to present the interface. The scene lifecycle, required context, and presentation path still need to be understood. Avoid adding guessed selectors or forcing undocumented scene-creation methods.

## Build

This project uses Theos and Logos.

The GitHub Actions workflow builds the Debian package. Check the workflow run and its artifacts for the generated \`.deb\`.

For a local build, configure a compatible Theos installation and SDK, then run:

\`\`\`sh
make clean
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide
\`\`\`

The package is generated in \`packages/\`.

## Installation and troubleshooting

Only install experimental builds on a test environment where you can recover from a SpringBoard issue. Keep a known removal method available before installing.

A successful package installation does not prove that:

- the tweak is injected into SpringBoard;
- the required private framework APIs are available;
- Spotlight's scene can be created;
- the native interface will become visible.

When reporting an issue, include the device model, exact iOS/iPadOS and SwitchZart versions, package version, and relevant \`NyxianSpotlight.log\` output. Do not include personal data or secrets in logs.

## Roadmap

- [ ] Improve runtime diagnostics and logging.
- [ ] Understand the native Spotlight scene lifecycle.
- [ ] Identify the supported presentation path for the target environment.
- [ ] Verify behavior across additional SwitchZart and iOS/iPadOS builds.
- [ ] Present the native Spotlight interface reliably.

## Disclaimer

This project is an independent research effort and is not affiliated with or endorsed by Apple. Spotlight and related framework names are Apple trademarks. Private APIs are undocumented and may change or stop working at any time.
