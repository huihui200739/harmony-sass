# Changelog

All notable changes to this project are documented here.

## 0.4.0 - 2026-07-22

- Added official Dart Sass deprecation controls to the ArkWeb runtime bridge.
- Added structured deprecation IDs, Sass warning stacks and `@debug` messages.
- Added batch compilation for multiple entry stylesheets in one virtual
  project.
- Added external document change detection while automatic compilation is
  enabled, including unsaved-edit conflict protection.
- Changed the existing save action to persist all modified project files while
  keeping save-as scoped to the active file.
- Expanded runtime and ArkTS coverage for diagnostics and batch compilation.

## 0.3.0 - 2026-07-22

- Added an in-memory multi-file project importer backed by official Dart Sass.
- Added relative `@use`, `@forward`, `@import`, partial, `_index` and
  import-only file resolution.
- Added SCSS, indented Sass and CSS syntax modes with expanded or compressed
  output.
- Added Source Maps, loaded URL reporting, compiler warnings and complete
  structured error spans.
- Added HarmonyOS file open, project file selection, save, save-as, CSS copy,
  CSS export and Source Map export.
- Added active entry switching, virtual load paths, automatic compilation and
  PC keyboard shortcuts while preserving the two-pane editor layout.
- Added project path/model tests and end-to-end runtime project fixtures.

## 0.2.0 - 2026-07-21

- Replaced the handwritten `ScssLite` subset with official Dart Sass 1.101.3.
- Added a local, invisible ArkWeb runtime without changing the visible editor UI.
- Added support for mixins, functions, control flow, arithmetic, at-rules and
  built-in Sass modules.
- Added structured Dart Sass errors with line and column information.
- Added upstream compatibility fixtures and bundled third-party notices.

## 0.1.0 - 2026-07-12

- First open-source MVP for HarmonyOS PC.
- Added native ArkTS SCSS Lite compiler core.
- Supports variables, nested selectors, selector lists, and `&` parent selectors.
- Added a two-pane SCSS-to-CSS editor UI.
- Added unit coverage for core compilation behavior and malformed source.
