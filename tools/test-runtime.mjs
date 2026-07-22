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

const runtimeMetadata = JSON.parse(context.harmonySass.getMetadata());
assert.equal(runtimeMetadata.version, sassPackage.version);
assert.equal(runtimeMetadata.info, sass.info);
assert.deepEqual(
  runtimeMetadata.compilerVersion,
  versionSnapshot(sass.Version.parse(sassPackage.version)),
  'runtime compiler version should match the pinned official Dart Sass package'
);
assert.deepEqual(runtimeMetadata.compilerModes, ['sync', 'async']);
assert.deepEqual(
  runtimeMetadata.deprecations,
  Object.values(sass.deprecations).map(deprecationSnapshot),
  'runtime metadata should match the pinned official Dart Sass package'
);

async function waitForRuntimeJob(startPayload) {
  const started = JSON.parse(startPayload);
  assert.ok(started.jobId, 'async runtime job should return an ID');
  for (let attempt = 0; attempt < 10000; attempt++) {
    const polled = JSON.parse(
      context.harmonySass.pollAsyncJob(started.jobId)
    );
    if (polled.state === 'complete') return polled.payload;
    if (polled.state !== 'pending') {
      throw new Error(polled.message || `Async job entered ${polled.state}`);
    }
    await new Promise(resolvePromise => setTimeout(resolvePromise, 0));
  }
  throw new Error('Async runtime job timed out.');
}

async function runtimeCompileProjectAsync(request) {
  const payload = await waitForRuntimeJob(
    context.harmonySass.startCompileProjectAsync(request)
  );
  return JSON.parse(payload);
}

async function runtimeCompileBatchAsync(request) {
  const payload = await waitForRuntimeJob(
    context.harmonySass.startCompileBatchAsync(request)
  );
  return JSON.parse(payload);
}

function deprecationSnapshot(deprecation) {
  if (!deprecation) return undefined;
  return {
    id: String(deprecation.id),
    status: String(deprecation.status),
    ...(deprecation.description === undefined
      ? {}
      : {
          description: deprecation.description === null
            ? null
            : String(deprecation.description)
        }),
    ...(deprecation.deprecatedIn === undefined
      ? {}
      : {
          deprecatedIn: deprecation.deprecatedIn === null
            ? null
            : String(deprecation.deprecatedIn),
          deprecatedInVersion: versionSnapshot(deprecation.deprecatedIn)
        }),
    ...(deprecation.obsoleteIn === undefined
      ? {}
      : {
          obsoleteIn: deprecation.obsoleteIn === null
            ? null
            : String(deprecation.obsoleteIn),
          obsoleteInVersion: versionSnapshot(deprecation.obsoleteIn)
        })
  };
}

function versionSnapshot(version) {
  if (version === undefined) return undefined;
  if (version === null) return null;
  return {
    major: Number(version.major),
    minor: Number(version.minor),
    patch: Number(version.patch),
    text: String(version)
  };
}

function sourceSpanSnapshot(span) {
  if (!span) return undefined;
  return {
    text: String(span.text),
    ...(span.context === undefined ? {} : { context: String(span.context) }),
    url: span.url ? String(span.url) : '',
    start: {
      line: span.start.line + 1,
      column: span.start.column + 1,
      offset: span.start.offset
    },
    end: {
      line: span.end.line + 1,
      column: span.end.column + 1,
      offset: span.end.offset
    }
  };
}

function warningSnapshot(warnings) {
  return warnings.map(warning => ({
    message: warning.message,
    deprecation: warning.deprecation === true,
    deprecationType: warning.deprecationType,
    deprecationMetadata: warning.deprecationMetadata,
    stack: warning.stack,
    span: warning.span
  }));
}

async function officialCompileSnapshot(source, request, asynchronous) {
  const warnings = [];
  const debugMessages = [];
  const entryPath = request.entryPath || (
    request.syntax === 'indented'
      ? 'stdin.sass'
      : request.syntax === 'css'
        ? 'stdin.css'
        : 'stdin.scss'
  );
  const options = {
    url: new URL(`harmony-sass:/${entryPath}`),
    syntax: request.syntax ?? 'scss',
    style: request.style ?? 'expanded',
    alertAscii: request.alertAscii === true,
    alertColor: request.alertColor === true,
    sourceMap: request.sourceMap === true,
    sourceMapIncludeSources: request.sourceMapIncludeSources === true,
    charset: request.charset !== false,
    quietDeps: request.quietDeps === true,
    verbose: request.verbose === true,
    fatalDeprecations: (request.fatalDeprecations || []).map(value =>
      typeof value === 'string' && /^\d+\.\d+\.\d+$/.test(value)
        ? sass.Version.parse(value)
        : value
    ),
    futureDeprecations: request.futureDeprecations || [],
    silenceDeprecations: request.silenceDeprecations || [],
    logger: request.quiet === true
      ? sass.Logger.silent
      : {
          warn(message, warningOptions) {
            warnings.push({
              message,
              deprecation: warningOptions.deprecation === true,
              deprecationType: warningOptions.deprecationType
                ? warningOptions.deprecationType.id
                : undefined,
              deprecationMetadata: deprecationSnapshot(
                warningOptions.deprecationType
              ),
              stack: warningOptions.stack || undefined,
              span: sourceSpanSnapshot(warningOptions.span)
            });
          },
          debug(message, debugOptions) {
            debugMessages.push({
              message,
              span: sourceSpanSnapshot(debugOptions.span)
            });
          }
        }
  };
  try {
    const result = asynchronous
      ? await sass.compileStringAsync(source, options)
      : sass.compileString(source, options);
    return {
      ok: true,
      css: result.css,
      sourceMap: result.sourceMap ? JSON.stringify(result.sourceMap) : '',
      loadedUrls: result.loadedUrls.map(url => String(url)),
      warnings,
      debugMessages
    };
  } catch (error) {
    return {
      ok: false,
      formatted: error.message,
      message: error.sassMessage || error.message,
      sassStack: error.sassStack,
      warnings,
      debugMessages
    };
  }
}

function assertCompileSnapshot(actual, expected, label) {
  assert.equal(actual.ok, expected.ok, `${label} success state should match`);
  assert.deepEqual(
    warningSnapshot(actual.warnings || []),
    warningSnapshot(expected.warnings || []),
    `${label} warnings should match`
  );
  assert.deepEqual(
    (actual.debugMessages || []).map(message => ({
      message: message.message,
      span: message.span
    })),
    expected.debugMessages,
    `${label} debug messages should match`
  );
  if (expected.ok) {
    assert.equal(actual.css, expected.css, `${label} CSS should match`);
    assert.equal(
      actual.sourceMap || '',
      expected.sourceMap,
      `${label} Source Map should match`
    );
    assert.deepEqual(
      actual.loadedUrls,
      expected.loadedUrls,
      `${label} loaded URLs should match`
    );
  } else {
    assert.equal(
      actual.error.formatted,
      expected.formatted,
      `${label} formatted error should match`
    );
    assert.equal(
      actual.error.message,
      expected.message,
      `${label} Sass error should match`
    );
    assert.equal(
      actual.error.sassStack,
      expected.sassStack,
      `${label} Sass stack should match`
    );
  }
}

function assertRuntimeStackTrace(error, label) {
  assert.ok(error?.stackTrace, `${label} should expose the official JS stack`);
  assert.match(
    error.stackTrace,
    /^Error: /,
    `${label} stack should retain the JS Error prefix`
  );
  assert.match(
    error.stackTrace,
    /root stylesheet/,
    `${label} stack should retain the Sass source location`
  );
}

function withoutRuntimeStackTraces(value) {
  const copy = JSON.parse(JSON.stringify(value));
  if (copy.error) delete copy.error.stackTrace;
  for (const result of copy.results || []) {
    if (result.error) delete result.error.stackTrace;
  }
  return copy;
}

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

async function compareCliExport(source, options) {
  const root = await mkdtemp(resolve(tmpdir(), 'harmony-sass-cli-options-'));
  const entryPath = options.entryPath || 'src/app.scss';
  const outputPath = options.outputPath || 'dist/app.css';
  const sourcePath = resolve(root, entryPath);
  const cssPath = resolve(root, outputPath);
  const sourceMapPath = `${cssPath}.map`;
  const files = options.files || [];
  try {
    await mkdir(dirname(sourcePath), { recursive: true });
    await mkdir(dirname(cssPath), { recursive: true });
    await writeFile(sourcePath, source);
    for (const file of files) {
      const filePath = resolve(root, file.path);
      await mkdir(dirname(filePath), { recursive: true });
      await writeFile(filePath, file.contents);
    }

    const args = [
      sassCli,
      `--style=${options.style || 'expanded'}`,
      `--source-map-urls=${options.sourceMapUrls || 'relative'}`
    ];
    if (options.embedSources === true) args.push('--embed-sources');
    if (options.embedSourceMap === true) args.push('--embed-source-map');
    args.push(sourcePath, cssPath);
    await execFileAsync(process.execPath, args);

    const compiled = JSON.parse(context.harmonySass.compileProject({
      source,
      entryPath,
      entryUri: pathToFileURL(sourcePath).toString(),
      files: files.map(file => ({
        ...file,
        uri: pathToFileURL(resolve(root, file.path)).toString()
      })),
      style: options.style || 'expanded',
      sourceMap: true,
      sourceMapIncludeSources: options.embedSources === true
    }));
    assert.equal(compiled.ok, true, 'URI-backed export fixture should compile');

    const finalized = JSON.parse(context.harmonySass.finalizeExports({
      style: options.style || 'expanded',
      sourceMapUrls: options.sourceMapUrls || 'relative',
      embedSourceMap: options.embedSourceMap === true,
      entries: [{
        css: compiled.css,
        sourceMap: compiled.sourceMap,
        cssFileName: cssPath.slice(cssPath.lastIndexOf('/') + 1),
        sourceMapFileName: sourceMapPath.slice(
          sourceMapPath.lastIndexOf('/') + 1
        ),
        cssUri: pathToFileURL(cssPath).toString(),
        sourceMapUri: pathToFileURL(sourceMapPath).toString()
      }]
    })).results[0];

    return {
      actual: finalized,
      expectedCss: await readFile(cssPath, 'utf8'),
      expectedSourceMap: options.embedSourceMap === true
        ? ''
        : await readFile(sourceMapPath, 'utf8')
    };
  } finally {
    await rm(root, { recursive: true, force: true });
  }
}

async function compareCliErrorCss(source) {
  const root = await mkdtemp(resolve(tmpdir(), 'harmony-sass-error-css-'));
  const sourcePath = resolve(root, 'src/app.scss');
  const cssPath = resolve(root, 'dist/app.css');
  try {
    await mkdir(dirname(sourcePath), { recursive: true });
    await mkdir(dirname(cssPath), { recursive: true });
    await writeFile(sourcePath, source);
    try {
      await execFileAsync(process.execPath, [
        sassCli,
        '--error-css',
        sourcePath,
        cssPath
      ]);
    } catch {
      // The official CLI exits with an error after writing Error CSS.
    }
    const actual = JSON.parse(context.harmonySass.compileProject({
      source,
      entryPath: 'src/app.scss',
      entryUri: pathToFileURL(sourcePath).toString(),
      errorCss: true
    }));
    assert.equal(actual.ok, false, 'Error CSS fixture should fail compilation');
    return {
      actual: actual.errorCss,
      expected: await readFile(cssPath, 'utf8')
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

  const asyncActual = await runtimeCompileProjectAsync({
    source: fixture.source
  });
  const asyncExpected = await sass.compileStringAsync(fixture.source, {
    syntax: 'scss',
    style: 'expanded',
    sourceMap: false,
    url: new URL('harmony-sass:/stdin.scss')
  });
  assert.equal(asyncActual.ok, true, `${fixture.name} should compile async`);
  assert.equal(
    asyncActual.css,
    asyncExpected.css,
    `${fixture.name} async output should match Dart Sass`
  );
  assert.deepEqual(
    asyncActual.loadedUrls,
    asyncExpected.loadedUrls.map(url => String(url)),
    `${fixture.name} async loaded URLs should match Dart Sass`
  );
}

const releasedJob = JSON.parse(
  context.harmonySass.startCompileProjectAsync({
    source: '.released { color: red; }'
  })
);
assert.equal(
  JSON.parse(context.harmonySass.releaseAsyncJob(releasedJob.jobId)).released,
  true,
  'pending async jobs should be explicitly releasable'
);
assert.equal(
  JSON.parse(context.harmonySass.pollAsyncJob(releasedJob.jobId)).state,
  'missing',
  'released async jobs should no longer be retained'
);
assert.equal(
  JSON.parse(context.harmonySass.releaseAsyncJob(releasedJob.jobId)).released,
  false,
  'releasing an unknown async job should be harmless'
);

const optionFixtures = [
  {
    name: 'expanded output with charset',
    source: '.message::before { content: "你好"; }',
    request: { style: 'expanded', charset: true }
  },
  {
    name: 'expanded output without charset',
    source: '.message::before { content: "你好"; }',
    request: { style: 'expanded', charset: false }
  },
  {
    name: 'compressed output with charset',
    source: '.message::before { content: "你好"; }',
    request: { style: 'compressed', charset: true }
  },
  {
    name: 'compressed output without charset',
    source: '.message::before { content: "你好"; }',
    request: { style: 'compressed', charset: false }
  },
  {
    name: 'ASCII formatted diagnostics',
    source: '.你好 { color: $missing; }',
    request: { alertAscii: true, alertColor: false }
  },
  {
    name: 'colored formatted diagnostics',
    source: '.你好 { color: $missing; }',
    request: { alertAscii: false, alertColor: true }
  }
];

for (const fixture of optionFixtures) {
  const syncActual = JSON.parse(context.harmonySass.compileProject({
    source: fixture.source,
    ...fixture.request
  }));
  const syncExpected = await officialCompileSnapshot(
    fixture.source,
    fixture.request,
    false
  );
  assertCompileSnapshot(syncActual, syncExpected, `${fixture.name} sync`);

  const asyncActual = await runtimeCompileProjectAsync({
    source: fixture.source,
    ...fixture.request
  });
  const asyncExpected = await officialCompileSnapshot(
    fixture.source,
    fixture.request,
    true
  );
  assertCompileSnapshot(asyncActual, asyncExpected, `${fixture.name} async`);
}

for (const fixture of [
  { name: 'unknown input syntax', request: { syntax: 'less' } },
  { name: 'empty input syntax', request: { syntax: '' } },
  { name: 'unknown output style', request: { style: 'nested' } },
  { name: 'empty output style', request: { style: '' } }
]) {
  const source = '.options { color: red; }';
  const syncActual = JSON.parse(context.harmonySass.compileProject({
    source,
    ...fixture.request
  }));
  const syncExpected = await officialCompileSnapshot(
    source,
    fixture.request,
    false
  );
  assertCompileSnapshot(syncActual, syncExpected, `${fixture.name} sync`);

  const asyncActual = await runtimeCompileProjectAsync({
    source,
    ...fixture.request
  });
  const asyncExpected = await officialCompileSnapshot(
    source,
    fixture.request,
    true
  );
  assertCompileSnapshot(asyncActual, asyncExpected, `${fixture.name} async`);
}

const repeatedDeprecations = Array.from(
  { length: 8 },
  (_, index) => `.item-${index} { color: red(#123456); }`
).join('\n');
for (const verbose of [false, true]) {
  const request = { verbose };
  const syncActual = JSON.parse(context.harmonySass.compileProject({
    source: repeatedDeprecations,
    ...request
  }));
  const syncExpected = await officialCompileSnapshot(
    repeatedDeprecations,
    request,
    false
  );
  assertCompileSnapshot(
    syncActual,
    syncExpected,
    `verbose=${verbose} sync deprecations`
  );

  const asyncActual = await runtimeCompileProjectAsync({
    source: repeatedDeprecations,
    ...request
  });
  const asyncExpected = await officialCompileSnapshot(
    repeatedDeprecations,
    request,
    true
  );
  assertCompileSnapshot(
    asyncActual,
    asyncExpected,
    `verbose=${verbose} async deprecations`
  );
}

for (const option of [
  'fatalDeprecations',
  'futureDeprecations',
  'silenceDeprecations'
]) {
  for (const value of ['not-a-deprecation', ' import ', '']) {
    const request = { [option]: [value] };
    const syncActual = JSON.parse(context.harmonySass.compileProject({
      source: '.options { color: red; }',
      ...request
    }));
    const syncExpected = await officialCompileSnapshot(
      '.options { color: red; }',
      request,
      false
    );
    assertCompileSnapshot(
      syncActual,
      syncExpected,
      `${option} ${JSON.stringify(value)} validation sync`
    );

    const asyncActual = await runtimeCompileProjectAsync({
      source: '.options { color: red; }',
      ...request
    });
    const asyncExpected = await officialCompileSnapshot(
      '.options { color: red; }',
      request,
      true
    );
    assertCompileSnapshot(
      asyncActual,
      asyncExpected,
      `${option} ${JSON.stringify(value)} validation async`
    );
  }
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

const entryUri = 'file:///documents/project/src/app.scss';
const tokensUri = 'file:///documents/project/src/_tokens.scss';
const uriBackedProject = JSON.parse(context.harmonySass.compileProject({
  source: '@use "tokens"; .app { color: tokens.$brand; }',
  entryPath: 'src/app.scss',
  entryUri,
  sourceMap: true,
  sourceMapIncludeSources: true,
  files: [{
    path: 'src/_tokens.scss',
    uri: tokensUri,
    contents: '$brand: blue; .tokens { color: $brand; }'
  }]
}));
assert.equal(uriBackedProject.ok, true, 'real project URIs should compile');
assert.deepEqual(uriBackedProject.loadedUrls, [entryUri, tokensUri]);
assert.deepEqual(
  JSON.parse(uriBackedProject.sourceMap).sources,
  [tokensUri, entryUri],
  'Source Maps should retain real entry and imported-file URIs'
);

const uriBackedError = JSON.parse(context.harmonySass.compileProject({
  source: '@use "broken";',
  entryPath: 'src/app.scss',
  entryUri,
  files: [{
    path: 'src/_broken.scss',
    uri: 'file:///documents/project/src/_broken.scss',
    contents: '.broken { color: $missing; }'
  }]
}));
assert.equal(uriBackedError.ok, false);
assert.equal(
  uriBackedError.error.span.url,
  'file:///documents/project/src/_broken.scss',
  'dependency errors should point to the real project document'
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

for (const fixture of [
  {
    name: 'relative external Source Map',
    sourceMapUrls: 'relative',
    embedSourceMap: false
  },
  {
    name: 'absolute external Source Map',
    sourceMapUrls: 'absolute',
    embedSourceMap: false
  },
  {
    name: 'embedded Source Map',
    sourceMapUrls: 'relative',
    embedSourceMap: true
  }
]) {
  const compared = await compareCliExport(
    '@use "tokens"; .app { color: tokens.$brand; }',
    {
      sourceMapUrls: fixture.sourceMapUrls,
      embedSourceMap: fixture.embedSourceMap,
      embedSources: true,
      files: [{
        path: 'src/_tokens.scss',
        contents: '$brand: #123456; .tokens { color: $brand; }'
      }]
    }
  );
  assert.equal(
    compared.actual.css,
    compared.expectedCss,
    `${fixture.name} CSS should match the official CLI byte-for-byte`
  );
  assert.equal(
    compared.actual.sourceMap,
    compared.expectedSourceMap,
    `${fixture.name} map should match the official CLI byte-for-byte`
  );
}

for (const fixture of [
  {
    name: 'external Source Map without embedded sources',
    style: 'expanded',
    embedSourceMap: false
  },
  {
    name: 'compressed embedded Source Map without embedded sources',
    style: 'compressed',
    embedSourceMap: true
  }
]) {
  const compared = await compareCliExport(
    '.app { color: #123456; }',
    {
      style: fixture.style,
      sourceMapUrls: 'relative',
      embedSourceMap: fixture.embedSourceMap,
      embedSources: false
    }
  );
  assert.equal(
    compared.actual.css,
    compared.expectedCss,
    `${fixture.name} CSS should match the official CLI byte-for-byte`
  );
  assert.equal(
    compared.actual.sourceMap,
    compared.expectedSourceMap,
    `${fixture.name} map should match the official CLI byte-for-byte`
  );
}

const crossDirectoryMap = JSON.parse(context.harmonySass.finalizeExports({
  style: 'expanded',
  sourceMapUrls: 'relative',
  embedSourceMap: false,
  entries: [{
    css: '.app {\n  color: red;\n}',
    sourceMap: JSON.stringify({
      version: 3,
      sourceRoot: '',
      sources: ['file:///project/src/app.scss'],
      names: [],
      mappings: 'AAAA'
    }),
    cssFileName: 'app.css',
    sourceMapFileName: 'app.css.map',
    cssUri: 'file:///project/dist/css/app.css',
    sourceMapUri: 'file:///project/maps/app.css.map'
  }]
})).results[0];
assert.match(
  crossDirectoryMap.css,
  /sourceMappingURL=\.\.\/\.\.\/maps\/app\.css\.map/
);
assert.deepEqual(
  JSON.parse(crossDirectoryMap.sourceMap).sources,
  ['../src/app.scss']
);

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
assert.equal(
  debug.debugMessages[0].span.context,
  '$answer: 6 * 7; @debug $answer; .card { width: $answer * 1px; }'
);

const deprecationWarning = JSON.parse(context.harmonySass.compileProject({
  source: '$channel: red(#123456); .card { color: $channel; }'
}));
assert.equal(deprecationWarning.ok, true);
assert.ok(deprecationWarning.warnings.length >= 1);
for (const item of deprecationWarning.warnings) {
  const officialDeprecation = Object.values(sass.deprecations).find(
    deprecation => deprecation.id === item.deprecationType
  );
  assert.deepEqual(
    item.deprecationMetadata,
    deprecationSnapshot(officialDeprecation),
    `${item.deprecationType} warning metadata should match Dart Sass`
  );
  assert.equal(
    item.span.context,
    '$channel: red(#123456); .card { color: $channel; }'
  );
}

const quiet = JSON.parse(context.harmonySass.compileProject({
  source: '@warn "hidden"; @debug "hidden"; .card { color: red; }',
  quiet: true
}));
assert.equal(quiet.ok, true);
assert.deepEqual(quiet.warnings, []);
assert.deepEqual(quiet.debugMessages, []);

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
    name: 'package export conditions skip unknown and null targets',
    source: '@use "pkg:condition-fallback";',
    files: [
      {
        path: 'node_modules/condition-fallback/package.json',
        contents: JSON.stringify({
          exports: {
            '.': {
              browser: './browser.scss',
              sass: null,
              style: './style.css',
              default: './default.css'
            }
          }
        })
      },
      {
        path: 'node_modules/condition-fallback/browser.scss',
        contents: '.browser-condition { color: red; }'
      },
      {
        path: 'node_modules/condition-fallback/style.css',
        contents: '.style-condition { color: green; }'
      },
      {
        path: 'node_modules/condition-fallback/default.css',
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
    name: 'package export nested array and condition fallback',
    source: '@use "pkg:nested-fallback";',
    files: [
      {
        path: 'node_modules/nested-fallback/package.json',
        contents: JSON.stringify({
          exports: {
            '.': [
              null,
              [],
              {
                sass: null,
                default: './src/index.scss'
              }
            ]
          }
        })
      },
      {
        path: 'node_modules/nested-fallback/src/index.scss',
        contents: '.nested-fallback { color: #2468ac; }'
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
    name: 'package wildcard trailer takes precedence',
    source: '@use "pkg:wildcard-priority/theme/dark.scss";',
    files: [
      {
        path: 'node_modules/wildcard-priority/package.json',
        contents: JSON.stringify({
          exports: {
            './theme/*': './fallback/*.scss',
            './theme/*.scss': './specific/*.scss'
          }
        })
      },
      {
        path: 'node_modules/wildcard-priority/fallback/dark.scss.scss',
        contents: '.fallback-wildcard { color: red; }'
      },
      {
        path: 'node_modules/wildcard-priority/specific/dark.scss',
        contents: '.specific-wildcard { color: green; }'
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

const uriPackage = JSON.parse(context.harmonySass.compileProject({
  source: '@use "pkg:theme"; .app { color: theme.$brand; }',
  entryPath: 'src/app.scss',
  entryUri: 'file:///documents/project/src/app.scss',
  nodePackageImporter: true,
  sourceMap: true,
  files: [
    {
      path: 'node_modules/theme/package.json',
      uri: 'file:///documents/project/node_modules/theme/package.json',
      contents: JSON.stringify({ sass: 'index.scss' })
    },
    {
      path: 'node_modules/theme/index.scss',
      uri: 'file:///documents/project/node_modules/theme/index.scss',
      contents: '@use "tokens"; $brand: tokens.$brand;'
    },
    {
      path: 'node_modules/theme/_tokens.scss',
      uri: 'file:///documents/project/node_modules/theme/_tokens.scss',
      contents: '$brand: #123456;'
    }
  ]
}));
assert.equal(uriPackage.ok, true, 'URI-backed pkg: imports should compile');
assert.deepEqual(uriPackage.loadedUrls, [
  'file:///documents/project/src/app.scss',
  'file:///documents/project/node_modules/theme/index.scss',
  'file:///documents/project/node_modules/theme/_tokens.scss'
]);

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
      uri: 'file:///documents/project/src/app.scss',
      contents: '@use "tokens"; .app { color: tokens.$brand; }'
    },
    {
      path: 'src/admin.scss',
      uri: 'file:///documents/project/src/admin.scss',
      contents: '@use "tokens"; .admin { border-color: tokens.$brand; }'
    },
    {
      path: 'src/_tokens.scss',
      uri: 'file:///documents/project/src/_tokens.scss',
      contents: '$brand: #0a7bff;'
    }
  ]
}));
assert.equal(batch.ok, false);
assert.equal(batch.results.length, 3);
assert.equal(batch.results[0].ok, true);
assert.match(batch.results[0].css, /\.app/);
assert.equal(
  batch.results[0].loadedUrls[0],
  'file:///documents/project/src/app.scss'
);
assert.equal(batch.results[1].ok, true);
assert.match(batch.results[1].css, /\.admin/);
assert.equal(batch.results[2].ok, false);
assert.match(batch.results[2].error.message, /was not found/);

const stoppedBatch = JSON.parse(context.harmonySass.compileBatch({
  entryPaths: ['src/broken.scss', 'src/app.scss'],
  stopOnError: true,
  errorCss: true,
  files: [
    {
      path: 'src/broken.scss',
      contents: '.broken { color: $missing; }'
    },
    {
      path: 'src/app.scss',
      contents: '.app { color: blue; }'
    }
  ]
}));
assert.equal(stoppedBatch.ok, false);
assert.equal(stoppedBatch.results.length, 1);
assert.equal(stoppedBatch.results[0].ok, false);
assert.ok(stoppedBatch.results[0].errorCss.length > 0);

const stoppedAsyncBatch = await runtimeCompileBatchAsync({
  entryPaths: ['src/broken.scss', 'src/app.scss'],
  stopOnError: true,
  errorCss: true,
  files: [
    {
      path: 'src/broken.scss',
      contents: '.broken { color: $missing; }'
    },
    {
      path: 'src/app.scss',
      contents: '.app { color: blue; }'
    }
  ]
});
assertRuntimeStackTrace(
  stoppedBatch.results[0].error,
  'sync batch runtime error'
);
assertRuntimeStackTrace(
  stoppedAsyncBatch.results[0].error,
  'async batch runtime error'
);
assert.deepEqual(
  withoutRuntimeStackTraces(stoppedAsyncBatch),
  withoutRuntimeStackTraces(stoppedBatch),
  'async batch stop-on-error and Error CSS should match apart from evaluator stacks'
);

const errorCss = await compareCliErrorCss('@error "坏*/";');
assert.equal(
  errorCss.actual,
  errorCss.expected,
  'Error CSS should match the official CLI byte-for-byte'
);

const failure = JSON.parse(
  context.harmonySass.compile('.card { color: $missing; }')
);
assert.equal(failure.ok, false);
assert.equal(failure.error.line, 1);
assert.equal(failure.error.column, 16);
assert.match(failure.error.message, /Undefined variable/);
assert.match(failure.error.sassStack, /root stylesheet/);
assertRuntimeStackTrace(failure.error, 'sync runtime error');
assert.equal(failure.error.span.start.line, 1);
assert.equal(failure.error.span.end.column, 24);
assert.equal(failure.error.span.context, '.card { color: $missing; }');

const asyncFailure = await runtimeCompileProjectAsync({
  source: '.card { color: $missing; }'
});
assert.equal(asyncFailure.ok, false);
assertRuntimeStackTrace(asyncFailure.error, 'async runtime error');
assert.match(asyncFailure.error.stackTrace, /_asyncStartSync|_EvaluateVisitor/);

console.log(
  `Verified ${fixtures.length} single-document fixtures, compiler options, async lifecycle, package resolution, diagnostics, deprecations, runtime stack traces, and project workflows against Dart Sass ${sassPackage.version}.`
);
