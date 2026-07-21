# Harmony Sass

**Harmony Sass** is a HarmonyOS PC SCSS editor that runs the official
[Dart Sass](https://github.com/sass/dart-sass) implementation locally.

The visible ArkTS two-pane interface remains unchanged from the original MVP.
Compilation is no longer handled by the former handwritten `ScssLite` parser.
Instead, the official Dart Sass JavaScript distribution is bundled into the
application and executed in an invisible ArkWeb runtime.

## Current implementation

- Native HarmonyOS ArkTS editor UI
- Official Dart Sass `1.101.3` compiler
- Variables, nesting, parent selectors and selector lists
- Mixins, functions, conditionals, loops and arithmetic
- At-rules including `@media`
- Built-in modules such as `sass:color`, `sass:math` and `sass:list`
- Structured compiler errors with line and column information
- No network or remote compilation service

The current editor compiles one in-memory SCSS document with Dart Sass
`compileString()`. Built-in `sass:*` modules work. Imports from project files
will require a HarmonyOS file picker and a virtual importer, which are tracked
separately in the roadmap.

## Upstream source

- Dart Sass implementation:
  [sass/dart-sass](https://github.com/sass/dart-sass)
- Sass language specification:
  [sass/sass](https://github.com/sass/sass)

The generated runtime in `entry/src/main/resources/rawfile` is built from the
official `sass` npm distribution. Version and build dependencies are pinned in
`tools/package.json`.

## Build

### Prerequisites

- DevEco Studio with HarmonyOS **6.1.1 (API 24)** SDK
- The Java runtime bundled with DevEco Studio
- Node.js **20.19 or newer** to regenerate and test the Dart Sass runtime

On macOS, run:

```bash
bash ./scripts/verify.sh
```

The script:

1. installs the pinned runtime build dependencies;
2. rebuilds and tests the bundled Dart Sass runtime;
3. installs HarmonyOS package dependencies;
4. runs the ArkTS tests;
5. creates an unsigned HAP.

The expected package path is:

```text
entry/build/default/outputs/default/entry-default-unsigned.hap
```

The HAP is unsigned for development. A release build requires your own signing
configuration and HarmonyOS release credentials.

## Runtime verification

The compatibility suite compares the bundled browser runtime byte-for-behavior
with the same pinned official Dart Sass package:

```bash
npm --prefix tools ci
npm --prefix tools run verify
```

Fixtures cover variables and nesting, mixins, media queries, conditionals,
arithmetic, custom functions, built-in modules, quoted punctuation, local
variable scope and retained comments.

## Licensing

Harmony Sass is licensed under [MIT](LICENSE). The bundled Dart Sass
distribution and its dependency notices are included alongside the runtime in
`entry/src/main/resources/rawfile`.
