# Changelog

All notable changes to this project are documented here.

## 0.8.0 - 2026-07-22

- Preserved real HarmonyOS document URIs through entry compilation, relative
  imports, package imports, loaded URLs, structured errors and Source Maps.
- Added official `quiet` logger behavior and CLI-compatible Error CSS without
  changing the existing two-pane UI.
- Added official batch `stopOnError` behavior while retaining the existing
  compile-all and export workflows.
- Added relative and absolute Source Map source URL modes, embedded Source Map
  data URIs and cross-directory `sourceMappingURL` generation.
- Matched official Dart Sass CLI Error CSS and external/embedded Source Map
  exports byte-for-byte in the runtime compatibility suite.

## 0.7.0 - 2026-07-22

- Matched the official Dart Sass CLI file-export behavior when Source Maps are
  enabled.
- Added paired CSS and Source Map export through the existing CSS export
  action without changing the two-pane UI.
- Added the final CSS file to the Source Map `file` field and appended the
  official `sourceMappingURL` comment with expanded/compressed whitespace and
  URI encoding behavior.
- Kept standalone Source Map export while associating the map with its
  corresponding CSS file name.
- Matched the official partial-first ambiguity order and error message for
  conflicting partial and non-partial stylesheets.
- Preserved percent-encoded `#` and `?` characters in document-provider file
  names.
- Added official CLI comparisons for expanded, compressed and space-containing
  output file names.

## 0.6.0 - 2026-07-22

- Added a virtual-project `NodePackageImporter` based on the official Dart Sass
  `1.101.3` implementation.
- Added `pkg:` URL resolution, nearest `node_modules` lookup, scoped packages,
  package `exports`, wildcard exports and manifest-order Sass conditions.
- Added package `sass`/`style`, partial, index, direct subpath and import-only
  fallbacks.
- Added package-internal relative imports, nested package dependencies and
  official `quietDeps` classification for package stylesheets.
- Added project loading for `package.json` manifests without exposing manifests
  as editable Sass entries or changing the two-pane editor layout.
- Added official comparisons for package success paths and package error
  boundaries.

## 0.5.1 - 2026-07-22

- Added official Dart Sass compiler-version values for `fatalDeprecations`.
- Corrected `sourceMapIncludeSources` to use the official default while
  retaining embedded sources for the HarmonyOS editor and exports.
- Separated entry-relative and virtual load-path importers so `quietDeps`
  classifies dependency deprecations like official Dart Sass.
- Added structured `sassStack` data to compiler errors.
- Added official package comparisons for Source Map defaults, fatal
  deprecation versions and dependency warning behavior.

## 0.5.0 - 2026-07-22

- Corrected virtual importer precedence to match official Dart Sass for direct
  files, directory indexes, Sass syntax files, CSS fallbacks, partials,
  explicit extensions and import-only stylesheets.
- Added official package comparisons for importer edge cases and ambiguity
  handling.
- Added recursive mixed file/folder project loading with URI deduplication and
  a global 500-file limit.
- Removed the untouched built-in example automatically when a real project is
  loaded while preserving edited untitled content.
- Added session restoration for authorized project files, the active file,
  per-file syntax overrides, output format, load paths, Source Maps and
  automatic compilation.
- Added batched CSS and Source Map export with collision-resistant output names.
- Added queued automatic compilation, full warning/debug presentation and
  deleted-file detection.
- Documented Node.js callback, package importer, Embedded Protocol, CLI,
  target-device and signing boundaries.

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
