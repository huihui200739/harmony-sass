# Roadmap

## Completed through 0.6.0

- Official Dart Sass runtime integration
- Official Dart Sass `1.101.3` language behavior
- Multi-file virtual project compilation
- Sass module, forwarding, partial, index, CSS fallback and legacy import
  resolution with official-compatible precedence
- SCSS, indented Sass and CSS input
- Expanded and compressed output
- Source Maps with official defaults, warnings, loaded URLs and full error
  spans
- Deprecation controls by ID or compiler version, deprecation IDs, warning and
  error Sass stacks, official `quietDeps` behavior and `@debug` messages
- Multiple-entry batch compilation
- HarmonyOS PC open, save, export, copy and keyboard workflows
- Save-all for modified project files
- Automatic compilation, external file reloading and entry-file switching
- Recursive folder project loading with deduplication and a global 500-file
  limit
- Session restoration for project files, active file, per-file syntax and
  compiler options
- Automatic removal of the untouched built-in example when loading a project
- Virtual-project `NodePackageImporter` with `pkg:`, nearest `node_modules`,
  scoped packages, package exports, nested dependencies and import-only files

## Platform validation and release work

- Validate recursive document-provider URIs on target HarmonyOS PC hardware
- Signed release packages and automated release publishing

## Environment boundaries

These upstream host APIs cannot be reproduced faithfully without Node.js
callbacks, unrestricted host filesystem access, a child process or the
Embedded Protocol:

- JavaScript `Options.functions`
- external JavaScript `Importer` and `FileImporter` callbacks
- external JavaScript `Logger` callback objects
- filesystem-backed `NodePackageImporter` outside the loaded virtual project
- Dart Sass Embedded Protocol
- the complete Dart Sass CLI process and CLI watch contract
- the complete public npm and legacy JavaScript API surface
