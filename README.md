# Harmony Sass

**Harmony Sass** is an open-source, native ArkTS SCSS editor and compiler for **HarmonyOS PC**.

> Status: `0.1.0 MVP` — buildable and test-covered SCSS Lite implementation.

## Why this project

Sass is a practical first target for HarmonyOS PC adaptation: the core workflow transforms text into text and does not require a container runtime, a Windows compatibility layer, or a full desktop IDE port.

The upstream Dart Sass implementation requires a Dart runtime. Rather than claim an unverified binary port, Harmony Sass starts with a clean ArkTS implementation of a useful SCSS-compatible subset, then expands compatibility through tested increments.

## Features in 0.1

- Native HarmonyOS ArkTS desktop-style editor UI
- SCSS variables: `$brand: #0A7BFF;`
- Nested selectors
- Parent selectors: `&:hover`
- Comma-separated selector lists
- Clear compile errors for unbalanced braces and unresolved variables
- ArkTS unit tests and HAP packaging configuration

### Example

```scss
$brand: #0A7BFF;

.card {
  padding: 20px;

  .title {
    color: $brand;
  }

  &:hover {
    opacity: 0.9;
  }
}
```

Outputs:

```css
.card {
  padding: 20px;
}

.card .title {
  color: #0A7BFF;
}

.card:hover {
  opacity: 0.9;
}
```

## Build

### Prerequisites

- DevEco Studio with HarmonyOS **6.1.1 (API 24)** SDK
- The Java runtime bundled with DevEco Studio

On macOS, run:

```bash
./scripts/verify.sh
```

The script installs HarmonyOS package dependencies, runs unit tests, and creates an unsigned HAP. The expected package path is:

```text
entry/build/default/outputs/default/entry-default-unsigned.hap
```

> The HAP is unsigned for development. A release build requires your own signing configuration and HarmonyOS release credentials.

## Compatibility scope

This project is **not yet a drop-in Dart Sass replacement**. `0.1.0` intentionally supports the basic SCSS authoring workflow listed above. Unsupported directives will be evaluated as part of the roadmap, with behavior backed by tests before being advertised as compatible.

See [the roadmap](docs/ROADMAP.md) for planned work and [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidance.

## License

[MIT](LICENSE)
