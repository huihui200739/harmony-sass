import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import {
  mkdir,
  mkdtemp,
  readFile,
  rm,
  writeFile
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, resolve } from 'node:path';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
import { pathToFileURL } from 'node:url';
import vm from 'node:vm';
import * as sass from 'sass';

const toolsDir = dirname(fileURLToPath(import.meta.url));
const execFileAsync = promisify(execFile);
const sassCli = resolve(toolsDir, 'node_modules/sass/sass.js');
const sassPackage = JSON.parse(
  await readFile(resolve(toolsDir, 'node_modules/sass/package.json'), 'utf8')
);
const runtimeFile = resolve(
  toolsDir,
  '../entry/src/main/resources/rawfile/sass-runtime.js'
);
const runtimeSource = await readFile(runtimeFile, 'utf8');
const context = {
  console,
  setTimeout,
  clearTimeout,
  TextDecoder,
  TextEncoder,
  URL,
  location: { href: 'resource://rawfile/sass-runtime.html' }
};
context.globalThis = context;
context.self = context;
context.window = context;
vm.createContext(context);
vm.runInContext(runtimeSource, context);

async function officialProjectCss(source, files) {
  const root = await mkdtemp(resolve(tmpdir(), 'harmony-sass-reference-'));
  try {
    for (const file of files) {
      const filePath = resolve(root, file.path);
      await mkdir(dirname(filePath), { recursive: true });
      await writeFile(filePath, file.contents);
    }
    return sass.compileString(source, {
      url: pathToFileURL(resolve(root, 'app.scss')),
      logger: sass.Logger.silent
    }).css;
  } finally {
    await rm(root, { recursive: true, force: true });
  }
}

async function officialCliExport(source, outputFileName, style) {
  const root = await mkdtemp(resolve(tmpdir(), 'harmony-sass-cli-reference-'));
  const sourcePath = resolve(root, 'app.scss');
  const cssPath = resolve(root, outputFileName);
  try {
    await writeFile(sourcePath, source);
    await execFileAsync(process.execPath, [
      sassCli,
      '--embed-sources',
      `--style=${style}`,
      sourcePath,
      cssPath
    ]);
    return {
      css: await readFile(cssPath, 'utf8'),
      sourceMap: JSON.parse(await readFile(`${cssPath}.map`, 'utf8'))
    };
  } finally {
    await rm(root, { recursive: true, force: true });
  }
}

async function officialProjectWarnings(source, files, options = {}) {
  const root = await mkdtemp(resolve(tmpdir(), 'harmony-sass-reference-'));
  const entryPath = options.entryPath || 'app.scss';
  try {
    for (const file of files) {
      const filePath = resolve(root, file.path);
      await mkdir(dirname(filePath), { recursive: true });
      await writeFile(filePath, file.contents);
    }
    const warnings = [];
    sass.compileString(source, {
      url: pathToFileURL(resolve(root, entryPath)),
      quietDeps: options.quietDeps === true,
      loadPaths: (options.loadPaths || []).map(path => resolve(root, path)),
      logger: {
        warn(message, warningOptions) {
          warnings.push({
            message,
            deprecationType: warningOptions.deprecationType
              ? warningOptions.deprecationType.id
              : undefined
          });
        },
        debug() {}
      }
    });
    return warnings;
  } finally {
    await rm(root, { recursive: true, force: true });
  }
}

async function officialPackageResult(source, files, options = {}) {
  const root = await mkdtemp(resolve(tmpdir(), 'harmony-sass-package-reference-'));
  const entryPath = options.entryPath || 'src/app.scss';
  try {
    for (const file of files) {
      const filePath = resolve(root, file.path);
      await mkdir(dirname(filePath), { recursive: true });
      await writeFile(filePath, file.contents);
    }
    const entryFile = resolve(root, entryPath);
    await mkdir(dirname(entryFile), { recursive: true });
    await writeFile(entryFile, source);
    const warnings = [];
    const result = sass.compileString(source, {
      url: pathToFileURL(entryFile),
      importers: [new sass.NodePackageImporter(root)],
      quietDeps: options.quietDeps === true,
      logger: {
        warn(message, warningOptions) {
          warnings.push({
            message,
            deprecationType: warningOptions.deprecationType
              ? warningOptions.deprecationType.id
              : undefined
          });
        },
        debug() {}
      }
    });
    return { css: result.css, warnings };
  } finally {
    await rm(root, { recursive: true, force: true });
  }
}

async function officialPackageError(source, files, options = {}) {
  try {
    await officialPackageResult(source, files, options);
    return null;
  } catch (error) {
    return error;
  }
}

function virtualPackageResult(source, files, options = {}) {
  return JSON.parse(context.harmonySass.compileProject({
    source,
    entryPath: options.entryPath || 'src/app.scss',
    files,
    nodePackageImporter: true,
    packageEntryPointDirectory: options.packageEntryPointDirectory || '',
    quietDeps: options.quietDeps === true
  }));
}

const fixtures = [
  {
    name: 'variables and nesting',
    source: '$brand: #0a7bff; .card { color: $brand; .title { font-weight: 700; } }'
  },
  {
    name: 'mixins',
    source: '@mixin rounded($radius) { border-radius: $radius; } .card { @include rounded(8px); }'
  },
  {
    name: 'media queries',
    source: '.card { width: 20rem; @media (max-width: 600px) { width: 100%; } }'
  },
  {
    name: 'conditionals and arithmetic',
    source: '$wide: true; .card { width: 4px * 3; @if $wide { display: grid; } }'
  },
  {
    name: 'custom functions',
    source: '@function double($value) { @return $value * 2; } .card { gap: double(6px); }'
  },
  {
    name: 'built-in modules',
    source: '@use "sass:color"; .card { color: color.adjust(#036, $lightness: 20%); }'
  },
  {
    name: 'quoted punctuation',
    source: '.card::before { content: "{value;still-string}"; }'
  },
  {
    name: 'local variable scope',
    source: '$size: 1px; .a { $size: 2px; width: $size; } .b { width: $size; }'
  },
  {
    name: 'loud comments',
    source: '/*! retained */ .card { color: red; }'
  }
];

for (const fixture of fixtures) {
  const actual = JSON.parse(context.harmonySass.compile(fixture.source));
  const expected = sass.compileString(fixture.source, {
    syntax: 'scss',
    style: 'expanded',
    sourceMap: false
  }).css;
  assert.equal(actual.ok, true, `${fixture.name} should compile`);
  assert.equal(actual.css, expected, `${fixture.name} should match Dart Sass`);
  assert.equal(actual.version, sassPackage.version);
}

const project = JSON.parse(context.harmonySass.compileProject({
  source: '@use "tokens"; @use "components/button"; .app { color: tokens.$brand; }',
  entryPath: 'src/main.scss',
  files: [
    { path: 'src/_tokens.scss', contents: '$brand: #0a7bff;' },
    {
      path: 'src/components/_button.scss',
      contents: '@use "../tokens"; .button { color: tokens.$brand; }'
    }
  ]
}));
assert.equal(project.ok, true, 'virtual project should compile');
assert.match(project.css, /\.button/);
assert.match(project.css, /\.app/);
assert.equal(project.loadedUrls.length, 3);

const forwarded = JSON.parse(context.harmonySass.compileProject({
  source: '@use "theme"; .card { color: theme.$brand; }',
  entryPath: 'app.scss',
  files: [
    { path: '_colors.scss', contents: '$brand: rebeccapurple;' },
    { path: '_theme.scss', contents: '@forward "colors";' }
  ]
}));
assert.equal(forwarded.ok, true, '@forward should resolve virtual partials');
assert.match(forwarded.css, /rebeccapurple/);

const imported = JSON.parse(context.harmonySass.compileProject({
  source: '@import "legacy";',
  entryPath: 'app.scss',
  files: [
    { path: '_legacy.import.scss', contents: '.legacy { display: block; }' },
    { path: '_legacy.scss', contents: '.wrong { display: none; }' }
  ]
}));
assert.equal(imported.ok, true, '@import should prefer import-only files');
assert.match(imported.css, /\.legacy/);
assert.doesNotMatch(imported.css, /\.wrong/);

const compressed = JSON.parse(context.harmonySass.compileProject({
  source: '.card { color: red; }',
  style: 'compressed'
}));
assert.equal(compressed.ok, true);
assert.equal(compressed.css, '.card{color:red}');

const indented = JSON.parse(context.harmonySass.compileProject({
  source: '.card\n  color: red',
  entryPath: 'app.sass',
  syntax: 'indented'
}));
assert.equal(indented.ok, true);
assert.match(indented.css, /color: red/);

const css = JSON.parse(context.harmonySass.compileProject({
  source: '.card { color: red; }',
  entryPath: 'app.css',
  syntax: 'css'
}));
assert.equal(css.ok, true);
assert.match(css.css, /\.card/);

const sourceMap = JSON.parse(context.harmonySass.compileProject({
  source: '@use "tokens"; .card { color: tokens.$brand; }',
  entryPath: 'src/app.scss',
  sourceMap: true,
  sourceMapIncludeSources: true,
  files: [{
    path: 'src/_tokens.scss',
    contents: '$brand: blue; .tokens { color: $brand; }'
  }]
}));
assert.equal(sourceMap.ok, true);
assert.ok(sourceMap.sourceMap.length > 0);
assert.deepEqual(
  JSON.parse(sourceMap.sourceMap).sources.sort(),
  ['harmony-sass:/src/_tokens.scss', 'harmony-sass:/src/app.scss'].sort()
);
assert.ok(
  Object.hasOwn(JSON.parse(sourceMap.sourceMap), 'sourcesContent'),
  'sourceMapIncludeSources should embed project sources when enabled'
);

const defaultSourceMap = JSON.parse(context.harmonySass.compileProject({
  source: '.card { color: red; }',
  sourceMap: true
}));
assert.equal(defaultSourceMap.ok, true);
assert.equal(
  Object.hasOwn(JSON.parse(defaultSourceMap.sourceMap), 'sourcesContent'),
  false,
  'sourceMapIncludeSources should default to false like official Dart Sass'
);

const loadPathProject = JSON.parse(context.harmonySass.compileProject({
  source: '@use "tokens"; .app { color: tokens.$brand; }',
  entryPath: 'src/app.scss',
  loadPaths: ['shared'],
  files: [{
    path: 'shared/_tokens.scss',
    contents: '$brand: #0a7bff;'
  }]
}));
assert.equal(loadPathProject.ok, true, 'entry imports should search virtual load paths');
assert.match(loadPathProject.css, /#0a7bff/);

const nestedLoadPathProject = JSON.parse(context.harmonySass.compileProject({
  source: '@use "components/button";',
  entryPath: 'src/app.scss',
  loadPaths: ['shared'],
  files: [
    {
      path: 'src/components/_button.scss',
      contents: '@use "tokens"; .button { color: tokens.$brand; }'
    },
    {
      path: 'shared/_tokens.scss',
      contents: '$brand: rebeccapurple;'
    }
  ]
}));
assert.equal(
  nestedLoadPathProject.ok,
  true,
  'nested imports should search virtual load paths after the containing directory'
);
assert.match(nestedLoadPathProject.css, /rebeccapurple/);

const relativeBeforeLoadPath = JSON.parse(context.harmonySass.compileProject({
  source: '@use "tokens"; .app { color: tokens.$brand; }',
  entryPath: 'src/app.scss',
  loadPaths: ['shared'],
  files: [
    { path: 'src/_tokens.scss', contents: '$brand: red;' },
    { path: 'shared/_tokens.scss', contents: '$brand: blue;' }
  ]
}));
assert.equal(relativeBeforeLoadPath.ok, true);
assert.match(relativeBeforeLoadPath.css, /red/);
assert.doesNotMatch(relativeBeforeLoadPath.css, /blue/);

const indexFiles = [{
  path: 'theme/_index.scss',
  contents: '.theme { color: teal; }'
}];
const indexProject = JSON.parse(context.harmonySass.compileProject({
  source: '@use "theme";',
  entryPath: 'app.scss',
  files: indexFiles
}));
assert.equal(indexProject.ok, true, 'directory partial indexes should resolve');
assert.equal(
  indexProject.css,
  await officialProjectCss('@use "theme";', indexFiles)
);

const directBeforeIndexFiles = [
  { path: 'theme.scss', contents: '.direct { color: red; }' },
  { path: 'theme/_index.scss', contents: '.index { color: blue; }' }
];
const directBeforeIndex = JSON.parse(context.harmonySass.compileProject({
  source: '@use "theme";',
  entryPath: 'app.scss',
  files: directBeforeIndexFiles
}));
assert.equal(directBeforeIndex.ok, true, 'direct files should resolve before indexes');
assert.equal(
  directBeforeIndex.css,
  await officialProjectCss('@use "theme";', directBeforeIndexFiles)
);

const sassBeforeCssFiles = [
  { path: 'theme.scss', contents: '.sass { color: red; }' },
  { path: 'theme.css', contents: '.css { color: blue; }' }
];
const sassBeforeCss = JSON.parse(context.harmonySass.compileProject({
  source: '@use "theme";',
  entryPath: 'app.scss',
  files: sassBeforeCssFiles
}));
assert.equal(sassBeforeCss.ok, true, 'Sass files should resolve before CSS fallbacks');
assert.equal(
  sassBeforeCss.css,
  await officialProjectCss('@use "theme";', sassBeforeCssFiles)
);

const ambiguousProject = JSON.parse(context.harmonySass.compileProject({
  source: '@use "theme";',
  entryPath: 'app.scss',
  files: [
    { path: 'theme.scss', contents: '.direct { color: red; }' },
    { path: '_theme.scss', contents: '.partial { color: blue; }' }
  ]
}));
assert.equal(ambiguousProject.ok, false);
assert.equal(
  ambiguousProject.error.message,
  "It's not clear which file to import. Found:\n" +
    '  _theme.scss\n' +
    '  theme.scss'
);

for (const fixture of [
  { style: 'expanded', outputFileName: 'a b.css' },
  { style: 'compressed', outputFileName: 'compressed.css' }
]) {
  const source = '.a { color: red; }';
  const compiled = JSON.parse(context.harmonySass.compileProject({
    source,
    entryPath: 'app.scss',
    style: fixture.style,
    sourceMap: true,
    sourceMapIncludeSources: true
  }));
  assert.equal(compiled.ok, true);
  const finalized = JSON.parse(context.harmonySass.finalizeExports({
    style: fixture.style,
    entries: [{
      css: compiled.css,
      sourceMap: compiled.sourceMap,
      cssFileName: fixture.outputFileName,
      sourceMapFileName: `${fixture.outputFileName}.map`
    }]
  }));
  const expected = await officialCliExport(
    source,
    fixture.outputFileName,
    fixture.style
  );
  const actualMap = JSON.parse(finalized.results[0].sourceMap);
  assert.equal(
    finalized.results[0].css,
    expected.css,
    `${fixture.style} CSS export should match the official CLI`
  );
  assert.equal(actualMap.file, expected.sourceMap.file);
  assert.equal(actualMap.mappings, expected.sourceMap.mappings);
  assert.deepEqual(actualMap.sourcesContent, expected.sourceMap.sourcesContent);
}

const explicitExtensionProject = JSON.parse(context.harmonySass.compileProject({
  source: '@use "theme.scss";',
  entryPath: 'app.scss',
  files: [
    { path: 'theme.scss', contents: '.scss { color: red; }' },
    { path: 'theme.sass', contents: '.sass\n  color: blue' }
  ]
}));
assert.equal(explicitExtensionProject.ok, true);
assert.match(explicitExtensionProject.css, /\.scss/);
assert.doesNotMatch(explicitExtensionProject.css, /\.sass/);

const warning = JSON.parse(context.harmonySass.compileProject({
  source: '@warn "check me"; .card { color: red; }'
}));
assert.equal(warning.ok, true);
assert.equal(warning.warnings.length, 1);
assert.match(warning.warnings[0].message, /check me/);

const debug = JSON.parse(context.harmonySass.compileProject({
  source: '$answer: 6 * 7; @debug $answer; .card { width: $answer * 1px; }'
}));
assert.equal(debug.ok, true);
assert.equal(debug.debugMessages.length, 1);
assert.match(debug.debugMessages[0].message, /42/);

const silencedDeprecation = JSON.parse(context.harmonySass.compileProject({
  source: '@import "legacy";',
  entryPath: 'app.scss',
  silenceDeprecations: ['import'],
  files: [{ path: '_legacy.scss', contents: '.legacy { display: block; }' }]
}));
assert.equal(silencedDeprecation.ok, true);
assert.equal(silencedDeprecation.warnings.length, 0);

const fatalDeprecation = JSON.parse(context.harmonySass.compileProject({
  source: '@import "legacy";',
  entryPath: 'app.scss',
  fatalDeprecations: ['import'],
  files: [{ path: '_legacy.scss', contents: '.legacy { display: block; }' }]
}));
assert.equal(fatalDeprecation.ok, false);
assert.match(fatalDeprecation.error.message, /deprecated/i);

const fatalVersionSource =
  '$channel: red(#123456); .fatal-version { color: $channel; }';
let officialFatalVersionError;
try {
  sass.compileString(fatalVersionSource, {
    fatalDeprecations: [sass.Version.parse('1.80.0')],
    logger: sass.Logger.silent
  });
} catch (error) {
  officialFatalVersionError = error;
}
assert.ok(
  officialFatalVersionError,
  'official Dart Sass should reject deprecations active in version 1.80.0'
);
const fatalDeprecationVersion = JSON.parse(context.harmonySass.compileProject({
  source: fatalVersionSource,
  fatalDeprecations: ['1.80.0']
}));
assert.equal(
  fatalDeprecationVersion.ok,
  false,
  'fatal deprecation versions should activate deprecations from that release'
);
assert.equal(
  fatalDeprecationVersion.error.message,
  officialFatalVersionError.sassMessage
);
assert.equal(
  fatalDeprecationVersion.warnings.some(item =>
    item.message.includes('Invalid deprecation')
  ),
  false
);

const deprecatedDependency =
  '$channel: red(#123456); .dependency { color: $channel; }';
const relativeQuietDeps = JSON.parse(context.harmonySass.compileProject({
  source: '@use "dependency";',
  entryPath: 'src/app.scss',
  quietDeps: true,
  files: [{
    path: 'src/_dependency.scss',
    contents: deprecatedDependency
  }]
}));
const officialRelativeQuietDeps = await officialProjectWarnings(
  '@use "dependency";',
  [{ path: 'src/_dependency.scss', contents: deprecatedDependency }],
  { entryPath: 'src/app.scss', quietDeps: true }
);
assert.deepEqual(
  relativeQuietDeps.warnings.map(item => item.deprecationType),
  officialRelativeQuietDeps.map(item => item.deprecationType),
  'quietDeps should retain deprecations from entry-relative stylesheets'
);

const loadPathQuietDeps = JSON.parse(context.harmonySass.compileProject({
  source: '@use "dependency";',
  entryPath: 'src/app.scss',
  quietDeps: true,
  loadPaths: ['shared'],
  files: [{
    path: 'shared/_dependency.scss',
    contents: deprecatedDependency
  }]
}));
const officialLoadPathQuietDeps = await officialProjectWarnings(
  '@use "dependency";',
  [{ path: 'shared/_dependency.scss', contents: deprecatedDependency }],
  { entryPath: 'src/app.scss', loadPaths: ['shared'], quietDeps: true }
);
assert.deepEqual(
  loadPathQuietDeps.warnings.map(item => item.deprecationType),
  officialLoadPathQuietDeps.map(item => item.deprecationType),
  'quietDeps should suppress deprecations from virtual load paths'
);

const loadPathLoudDeps = JSON.parse(context.harmonySass.compileProject({
  source: '@use "dependency";',
  entryPath: 'src/app.scss',
  quietDeps: false,
  loadPaths: ['shared'],
  files: [{
    path: 'shared/_dependency.scss',
    contents: deprecatedDependency
  }]
}));
const officialLoadPathLoudDeps = await officialProjectWarnings(
  '@use "dependency";',
  [{ path: 'shared/_dependency.scss', contents: deprecatedDependency }],
  { entryPath: 'src/app.scss', loadPaths: ['shared'], quietDeps: false }
);
assert.deepEqual(
  loadPathLoudDeps.warnings.map(item => item.deprecationType),
  officialLoadPathLoudDeps.map(item => item.deprecationType),
  'disabled quietDeps should retain load-path deprecations'
);

const packageFixtures = [
  {
    name: 'package root conditional exports',
    source: '@use "pkg:theme"; .app { color: theme.$brand; }',
    files: [
      {
        path: 'node_modules/theme/package.json',
        contents: JSON.stringify({
          exports: {
            '.': {
              sass: './src/index.scss',
              style: './dist/index.css',
              default: './dist/index.css'
            }
          }
        })
      },
      {
        path: 'node_modules/theme/src/index.scss',
        contents: '@use "tokens"; $brand: tokens.$brand;'
      },
      {
        path: 'node_modules/theme/src/_tokens.scss',
        contents: '$brand: #123456;'
      },
      {
        path: 'node_modules/theme/dist/index.css',
        contents: ':root { --fallback: true; }'
      }
    ]
  },
  {
    name: 'package export conditions follow manifest order',
    source: '@use "pkg:ordered";',
    files: [
      {
        path: 'node_modules/ordered/package.json',
        contents: JSON.stringify({
          exports: {
            '.': {
              default: './dist/index.css',
              sass: './src/index.scss'
            }
          }
        })
      },
      {
        path: 'node_modules/ordered/src/index.scss',
        contents: '.sass-condition { color: red; }'
      },
      {
        path: 'node_modules/ordered/dist/index.css',
        contents: '.default-condition { color: blue; }'
      }
    ]
  },
  {
    name: 'scoped package exact subpath export',
    source: '@use "pkg:@scope/design/tokens"; .app { color: tokens.$brand; }',
    files: [
      {
        path: 'node_modules/@scope/design/package.json',
        contents: JSON.stringify({
          exports: {
            './tokens': './src/_tokens.scss'
          }
        })
      },
      {
        path: 'node_modules/@scope/design/src/_tokens.scss',
        contents: '$brand: #234567;'
      }
    ]
  },
  {
    name: 'package wildcard subpath export',
    source: '@use "pkg:palette/theme/dark"; .app { color: dark.$brand; }',
    files: [
      {
        path: 'node_modules/palette/package.json',
        contents: JSON.stringify({
          exports: {
            './theme/*': './src/themes/*.scss'
          }
        })
      },
      {
        path: 'node_modules/palette/src/themes/dark.scss',
        contents: '$brand: #345678;'
      }
    ]
  },
  {
    name: 'package wildcard export array fallback',
    source: '@use "pkg:array-fallback/theme/dark";',
    files: [
      {
        path: 'node_modules/array-fallback/package.json',
        contents: JSON.stringify({
          exports: {
            './theme/*': [
              './missing/*.scss',
              './src/themes/*.scss'
            ]
          }
        })
      },
      {
        path: 'node_modules/array-fallback/src/themes/dark.scss',
        contents: '.array-fallback { color: #345678; }'
      }
    ]
  },
  {
    name: 'package exported directory index fallback',
    source: '@use "pkg:components/button"; .app { color: button.$brand; }',
    files: [
      {
        path: 'node_modules/components/package.json',
        contents: JSON.stringify({
          exports: {
            './button/index.scss': './src/button.scss'
          }
        })
      },
      {
        path: 'node_modules/components/src/button.scss',
        contents: '$brand: #3f6789;'
      }
    ]
  },
  {
    name: 'package sass root fallback',
    source: '@use "pkg:root-fallback"; .app { color: root-fallback.$brand; }',
    files: [
      {
        path: 'node_modules/root-fallback/package.json',
        contents: JSON.stringify({ sass: 'src/main.scss' })
      },
      {
        path: 'node_modules/root-fallback/src/main.scss',
        contents: '$brand: #456789;'
      }
    ]
  },
  {
    name: 'package style root fallback',
    source: '@use "pkg:style-fallback";',
    files: [
      {
        path: 'node_modules/style-fallback/package.json',
        contents: JSON.stringify({ style: 'dist/index.css' })
      },
      {
        path: 'node_modules/style-fallback/dist/index.css',
        contents: '.style-fallback { color: #4a7890; }'
      }
    ]
  },
  {
    name: 'package partial index fallback',
    source: '@use "pkg:indexed"; .app { color: indexed.$brand; }',
    files: [
      {
        path: 'node_modules/indexed/package.json',
        contents: '{}'
      },
      {
        path: 'node_modules/indexed/_index.scss',
        contents: '$brand: #56789a;'
      }
    ]
  },
  {
    name: 'package direct subpath fallback',
    source: '@use "pkg:plain/colors"; .app { color: colors.$brand; }',
    files: [
      {
        path: 'node_modules/plain/package.json',
        contents: '{}'
      },
      {
        path: 'node_modules/plain/_colors.scss',
        contents: '$brand: #6789ab;'
      }
    ]
  },
  {
    name: 'nearest nested node_modules package',
    source: '@use "pkg:nearest"; .app { color: nearest.$brand; }',
    files: [
      {
        path: 'node_modules/nearest/package.json',
        contents: JSON.stringify({ sass: 'index.scss' })
      },
      {
        path: 'node_modules/nearest/index.scss',
        contents: '$brand: red;'
      },
      {
        path: 'src/node_modules/nearest/package.json',
        contents: JSON.stringify({ sass: 'index.scss' })
      },
      {
        path: 'src/node_modules/nearest/index.scss',
        contents: '$brand: green;'
      }
    ]
  },
  {
    name: 'package dependency resolves from containing package',
    source: '@use "pkg:outer"; .app { color: outer.$brand; }',
    files: [
      {
        path: 'node_modules/outer/package.json',
        contents: JSON.stringify({ sass: 'index.scss' })
      },
      {
        path: 'node_modules/outer/index.scss',
        contents: '@use "pkg:inner"; $brand: inner.$brand;'
      },
      {
        path: 'node_modules/outer/node_modules/inner/package.json',
        contents: JSON.stringify({ sass: 'index.scss' })
      },
      {
        path: 'node_modules/outer/node_modules/inner/index.scss',
        contents: '$brand: #789abc;'
      },
      {
        path: 'node_modules/inner/package.json',
        contents: JSON.stringify({ sass: 'index.scss' })
      },
      {
        path: 'node_modules/inner/index.scss',
        contents: '$brand: red;'
      }
    ]
  }
];

for (const fixture of packageFixtures) {
  const expected = await officialPackageResult(
    fixture.source,
    fixture.files,
    { entryPath: fixture.entryPath }
  );
  const actual = virtualPackageResult(
    fixture.source,
    fixture.files,
    { entryPath: fixture.entryPath }
  );
  assert.equal(actual.ok, true, `${fixture.name} should compile`);
  assert.equal(
    actual.css,
    expected.css,
    `${fixture.name} should match the official NodePackageImporter`
  );
}

const importOnlyPackageFiles = [
  {
    path: 'node_modules/legacy/package.json',
    contents: JSON.stringify({ sass: 'index.scss' })
  },
  {
    path: 'node_modules/legacy/index.scss',
    contents: '.modern { color: blue; }'
  },
  {
    path: 'node_modules/legacy/index.import.scss',
    contents: '.legacy { color: red; }'
  }
];
const officialImportOnlyPackage = await officialPackageResult(
  '@import "pkg:legacy";',
  importOnlyPackageFiles
);
const importOnlyPackage = virtualPackageResult(
  '@import "pkg:legacy";',
  importOnlyPackageFiles
);
assert.equal(importOnlyPackage.ok, true);
assert.equal(importOnlyPackage.css, officialImportOnlyPackage.css);
assert.match(importOnlyPackage.css, /\.legacy/);
assert.doesNotMatch(importOnlyPackage.css, /\.modern/);

const packageDeprecationFiles = [
  {
    path: 'node_modules/deprecated/package.json',
    contents: JSON.stringify({ sass: 'index.scss' })
  },
  {
    path: 'node_modules/deprecated/index.scss',
    contents: '$channel: red(#123456); .dependency { color: $channel; }'
  }
];
const officialPackageQuietDeps = await officialPackageResult(
  '@use "pkg:deprecated";',
  packageDeprecationFiles,
  { quietDeps: true }
);
const packageQuietDeps = virtualPackageResult(
  '@use "pkg:deprecated";',
  packageDeprecationFiles,
  { quietDeps: true }
);
assert.equal(packageQuietDeps.ok, true);
assert.deepEqual(
  packageQuietDeps.warnings.map(item => item.deprecationType),
  officialPackageQuietDeps.warnings.map(item => item.deprecationType),
  'quietDeps should classify pkg: stylesheets like the official importer'
);

const nestedPackageDeprecationFiles = [
  {
    path: 'node_modules/nested-deprecated/package.json',
    contents: JSON.stringify({ sass: 'index.scss' })
  },
  {
    path: 'node_modules/nested-deprecated/index.scss',
    contents: '@use "tokens";'
  },
  {
    path: 'node_modules/nested-deprecated/_tokens.scss',
    contents: '$channel: red(#123456); .dependency { color: $channel; }'
  }
];
const officialNestedPackageQuietDeps = await officialPackageResult(
  '@use "pkg:nested-deprecated";',
  nestedPackageDeprecationFiles,
  { quietDeps: true }
);
const nestedPackageQuietDeps = virtualPackageResult(
  '@use "pkg:nested-deprecated";',
  nestedPackageDeprecationFiles,
  { quietDeps: true }
);
assert.equal(nestedPackageQuietDeps.ok, true);
assert.deepEqual(
  nestedPackageQuietDeps.warnings.map(item => item.deprecationType),
  officialNestedPackageQuietDeps.warnings.map(item => item.deprecationType),
  'quietDeps should cover relative stylesheets inside a pkg: dependency'
);

const packageErrorFixtures = [
  {
    name: 'mixed package export conditions and paths',
    source: '@use "pkg:mixed";',
    files: [
      {
        path: 'node_modules/mixed/package.json',
        contents: JSON.stringify({
          exports: {
            sass: './index.scss',
            './tokens': './tokens.scss'
          }
        })
      },
      {
        path: 'node_modules/mixed/index.scss',
        contents: '.mixed { color: red; }'
      },
      {
        path: 'node_modules/mixed/tokens.scss',
        contents: '$brand: red;'
      }
    ],
    messages: ['conditions and paths', 'same level']
  },
  {
    name: 'non-relative package export',
    source: '@use "pkg:non-relative";',
    files: [
      {
        path: 'node_modules/non-relative/package.json',
        contents: JSON.stringify({
          exports: {
            sass: 'index.scss'
          }
        })
      },
      {
        path: 'node_modules/non-relative/index.scss',
        contents: '.non-relative { color: red; }'
      }
    ],
    messages: ['relative to the package root']
  },
  {
    name: 'ambiguous package export variants',
    source: '@use "pkg:ambiguous/colors";',
    files: [
      {
        path: 'node_modules/ambiguous/package.json',
        contents: JSON.stringify({
          exports: {
            './colors': './src/colors.scss',
            './colors.scss': './src/alternate.scss'
          }
        })
      },
      {
        path: 'node_modules/ambiguous/src/colors.scss',
        contents: '.colors { color: red; }'
      },
      {
        path: 'node_modules/ambiguous/src/alternate.scss',
        contents: '.alternate { color: blue; }'
      }
    ],
    messages: ['multiple potential resolutions', 'colors']
  },
  {
    name: 'malformed package manifest',
    source: '@use "pkg:malformed";',
    files: [
      {
        path: 'node_modules/malformed/package.json',
        contents: '{"sass":'
      },
      {
        path: 'node_modules/malformed/index.scss',
        contents: '.malformed { color: red; }'
      }
    ],
    messages: ['package.json']
  },
  {
    name: 'missing package manifest',
    source: '@use "pkg:missing-manifest";',
    files: [
      {
        path: 'node_modules/missing-manifest/index.scss',
        contents: '.missing-manifest { color: red; }'
      }
    ],
    messages: ['no such file|failed to read']
  }
];

for (const fixture of packageErrorFixtures) {
  const expected = await officialPackageError(fixture.source, fixture.files);
  const actual = virtualPackageResult(fixture.source, fixture.files);
  assert.ok(expected, `${fixture.name} should fail with official Dart Sass`);
  assert.equal(actual.ok, false, `${fixture.name} should fail`);
  for (const message of fixture.messages) {
    assert.match(
      expected.message,
      new RegExp(message, 'i'),
      `${fixture.name} official error should mention ${message}`
    );
    assert.match(
      actual.error.formatted,
      new RegExp(message, 'i'),
      `${fixture.name} virtual error should mention ${message}`
    );
  }
}

const malformedPackageUrls = [
  ['pkg:/theme', 'must not begin with /'],
  ['pkg://host/theme', 'must not have a host'],
  ['pkg:theme?variant=dark', 'must not have a query'],
  ['pkg:', 'must not have an empty path']
];

for (const [url, message] of malformedPackageUrls) {
  const source = `@use "${url}" as malformed;`;
  const expected = await officialPackageError(source, []);
  const actual = virtualPackageResult(source, []);
  assert.ok(expected, `${url} should fail with official Dart Sass`);
  assert.equal(actual.ok, false, `${url} should fail`);
  assert.match(expected.message, new RegExp(message, 'i'));
  assert.match(actual.error.formatted, new RegExp(message, 'i'));
}

const batch = JSON.parse(context.harmonySass.compileBatch({
  entryPaths: ['src/app.scss', 'src/admin.scss', 'src/missing.scss'],
  files: [
    {
      path: 'src/app.scss',
      contents: '@use "tokens"; .app { color: tokens.$brand; }'
    },
    {
      path: 'src/admin.scss',
      contents: '@use "tokens"; .admin { border-color: tokens.$brand; }'
    },
    { path: 'src/_tokens.scss', contents: '$brand: #0a7bff;' }
  ]
}));
assert.equal(batch.ok, false);
assert.equal(batch.results.length, 3);
assert.equal(batch.results[0].ok, true);
assert.match(batch.results[0].css, /\.app/);
assert.equal(batch.results[1].ok, true);
assert.match(batch.results[1].css, /\.admin/);
assert.equal(batch.results[2].ok, false);
assert.match(batch.results[2].error.message, /was not found/);

const failure = JSON.parse(
  context.harmonySass.compile('.card { color: $missing; }')
);
assert.equal(failure.ok, false);
assert.equal(failure.error.line, 1);
assert.equal(failure.error.column, 16);
assert.match(failure.error.message, /Undefined variable/);
assert.match(failure.error.sassStack, /root stylesheet/);
assert.equal(failure.error.span.start.line, 1);
assert.equal(failure.error.span.end.column, 24);

console.log(
  `Verified ${fixtures.length} single-document fixtures, package resolution, diagnostics, deprecations, and project workflows against Dart Sass ${sassPackage.version}.`
);
