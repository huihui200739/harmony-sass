import * as sass from 'sass';

const DART_SASS_INFO = sass.info;
const DART_SASS_VERSION =
  DART_SASS_INFO.split('\n')[0].split('\t')[1] || '1.101.3';
const compiler = sass.initCompiler();
const asyncCompilerPromise = sass.initAsyncCompiler();
const asyncJobs = new Map();
let nextAsyncJobId = 1;
const VIRTUAL_SCHEME = 'harmony-sass:';
const SUPPORTED_SYNTAXES = new Set(['scss', 'indented', 'css']);
const SUPPORTED_STYLES = new Set(['expanded', 'compressed']);
const STYLESHEET_EXTENSIONS = new Set(['.scss', '.sass', '.css']);

function text(value) {
  return value === undefined || value === null ? '' : String(value);
}

function absoluteUrl(value) {
  const source = text(value);
  if (!source) return null;
  try {
    const url = new URL(source);
    return url.protocol ? url : null;
  } catch {
    return null;
  }
}

function stringList(value) {
  if (!Array.isArray(value)) return [];
  return value
    .map(item => text(item).trim())
    .filter(item => item.length > 0);
}

function fatalDeprecationList(value) {
  return stringList(value).map(item => {
    if (!/^\d+\.\d+\.\d+$/.test(item)) return item;
    try {
      return sass.Version.parse(item);
    } catch {
      return item;
    }
  });
}

function compileString(source, options) {
  return compiler.compileString(source, options);
}

async function compileStringAsync(source, options) {
  const asyncCompiler = await asyncCompilerPromise;
  return asyncCompiler.compileStringAsync(source, options);
}

function serializeDeprecation(deprecation) {
  if (!deprecation) return undefined;
  return {
    id: text(deprecation.id),
    status: text(deprecation.status),
    description: deprecation.description === undefined
      ? undefined
      : deprecation.description === null
        ? null
        : text(deprecation.description),
    deprecatedIn: deprecation.deprecatedIn
      ? text(deprecation.deprecatedIn)
      : undefined,
    obsoleteIn: deprecation.obsoleteIn
      ? text(deprecation.obsoleteIn)
      : undefined
  };
}

function runtimeMetadata() {
  return {
    version: DART_SASS_VERSION,
    info: DART_SASS_INFO,
    compilerModes: ['sync', 'async'],
    deprecations: Object.values(sass.deprecations).map(serializeDeprecation)
  };
}

function decode(value) {
  try {
    return decodeURIComponent(value);
  } catch {
    return value;
  }
}

function normalizePath(value) {
  const parts = decode(text(value)).replaceAll('\\', '/').split('/');
  const normalized = [];
  for (const part of parts) {
    if (part === '' || part === '.') continue;
    if (part === '..') {
      normalized.pop();
      continue;
    }
    normalized.push(part);
  }
  return normalized.join('/');
}

function dirname(path) {
  const normalized = normalizePath(path);
  const separator = normalized.lastIndexOf('/');
  return separator === -1 ? '' : normalized.slice(0, separator);
}

function basename(path) {
  const normalized = normalizePath(path);
  const separator = normalized.lastIndexOf('/');
  return separator === -1 ? normalized : normalized.slice(separator + 1);
}

function joinPath(base, child) {
  return normalizePath(`${base}/${child}`);
}

function partialPath(path) {
  const name = basename(path);
  if (name.startsWith('_')) return normalizePath(path);
  return joinPath(dirname(path), `_${name}`);
}

function syntaxForPath(path, fallback = 'scss') {
  if (path.endsWith('.sass')) return 'indented';
  if (path.endsWith('.css')) return 'css';
  if (path.endsWith('.scss')) return 'scss';
  return SUPPORTED_SYNTAXES.has(fallback) ? fallback : 'scss';
}

function virtualUrl(path) {
  const encoded = normalizePath(path)
    .split('/')
    .map(segment => encodeURIComponent(segment))
    .join('/');
  return new URL(`${VIRTUAL_SCHEME}/${encoded}`);
}

function pathFromVirtualUrl(url) {
  return normalizePath(url.pathname);
}

function projectPathFromUrl(files, value) {
  const url = value instanceof URL ? value : absoluteUrl(value);
  if (!url) return null;
  if (url.protocol === VIRTUAL_SCHEME) return pathFromVirtualUrl(url);

  const target = url.toString();
  for (const [path, file] of files) {
    const fileUrl = absoluteUrl(file && file.uri);
    if (fileUrl && fileUrl.toString() === target) return path;
  }
  return null;
}

function projectPathForImportUrl(files, value) {
  const exact = projectPathFromUrl(files, value);
  if (exact) return exact;

  const target = value instanceof URL ? value : absoluteUrl(value);
  if (!target) return null;
  let bestPath = null;
  let bestPrefixLength = -1;
  for (const [path, file] of files) {
    const fileUrl = absoluteUrl(file && file.uri);
    if (!fileUrl ||
      fileUrl.protocol !== target.protocol ||
      fileUrl.host !== target.host) {
      continue;
    }
    const directoryUrl = new URL('.', fileUrl);
    if (!target.pathname.startsWith(directoryUrl.pathname) ||
      directoryUrl.pathname.length <= bestPrefixLength) {
      continue;
    }
    bestPath = joinPath(
      dirname(path),
      decode(target.pathname.slice(directoryUrl.pathname.length))
    );
    bestPrefixLength = directoryUrl.pathname.length;
  }
  return bestPath;
}

function projectUrl(files, path) {
  const normalized = normalizePath(path);
  return sourceMapUrlForFile(files.get(normalized), virtualUrl(normalized));
}

function matchingPaths(files, stem, extensions, importOnly) {
  const matches = [];
  for (const extension of extensions) {
    if (importOnly && extension === '.css') continue;
    const path = `${stem}${importOnly ? '.import' : ''}${extension}`;
    for (const candidate of [partialPath(path), path]) {
      const normalized = normalizePath(candidate);
      if (files.has(normalized) && !matches.includes(normalized)) {
        matches.push(normalized);
      }
    }
  }
  if (matches.length > 1) {
    throw new Error(
      `It's not clear which file to import. Found:\n` +
      matches.map(path => `  ${path}`).join('\n')
    );
  }
  return matches[0] || null;
}

function resolveStem(files, stem, extension, fromImport) {
  const extensionGroups = extension
    ? [[extension]]
    : [['.sass', '.scss'], ['.css']];
  if (fromImport) {
    for (const extensions of extensionGroups) {
      const resolved = matchingPaths(files, stem, extensions, true);
      if (resolved) return resolved;
    }
  }
  for (const extensions of extensionGroups) {
    const resolved = matchingPaths(files, stem, extensions, false);
    if (resolved) return resolved;
  }
  return null;
}

function serializeSpan(span) {
  if (!span) return undefined;
  return {
    text: text(span.text),
    context: span.context === undefined ? undefined : text(span.context),
    url: span.url ? text(span.url) : '',
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

function serializeError(error) {
  const span = error && error.span;
  return {
    ok: false,
    version: DART_SASS_VERSION,
    error: {
      message: text(error && (error.sassMessage || error.message || error)),
      formatted: text(error && (error.message || error)),
      sassStack: text(error && error.sassStack) || undefined,
      stackTrace: text(error && error.stack) || undefined,
      line: span ? span.start.line + 1 : 0,
      column: span ? span.start.column + 1 : 0,
      span: serializeSpan(span)
    }
  };
}

function normalizeRequest(value) {
  const request = value && typeof value === 'object' ? value : {};
  const syntax = SUPPORTED_SYNTAXES.has(request.syntax) ? request.syntax : 'scss';
  const style = SUPPORTED_STYLES.has(request.style) ? request.style : 'expanded';
  const defaultEntry = syntax === 'indented'
    ? 'stdin.sass'
    : syntax === 'css'
      ? 'stdin.css'
      : 'stdin.scss';
  const entryPath = normalizePath(request.entryPath || defaultEntry) || defaultEntry;
  return {
    source: text(request.source),
    entryPath,
    entryUri: text(request.entryUri),
    files: Array.isArray(request.files) ? request.files : [],
    loadPaths: Array.isArray(request.loadPaths) ? request.loadPaths : [],
    nodePackageImporter: request.nodePackageImporter === true,
    packageEntryPointDirectory: normalizePath(
      request.packageEntryPointDirectory || dirname(entryPath)
    ),
    syntax,
    style,
    alertAscii: request.alertAscii === true,
    alertColor: request.alertColor === true,
    sourceMap: request.sourceMap === true,
    sourceMapIncludeSources: request.sourceMapIncludeSources === true,
    charset: request.charset !== false,
    quiet: request.quiet === true,
    quietDeps: request.quietDeps === true,
    verbose: request.verbose === true,
    errorCss: request.errorCss === true,
    fatalDeprecations: fatalDeprecationList(request.fatalDeprecations),
    futureDeprecations: stringList(request.futureDeprecations),
    silenceDeprecations: stringList(request.silenceDeprecations)
  };
}

function createProject(request) {
  const files = new Map();
  for (const candidate of request.files) {
    if (!candidate || typeof candidate !== 'object') continue;
    const path = normalizePath(candidate.path);
    if (!path) continue;
    files.set(path, {
      contents: text(candidate.contents),
      syntax: syntaxForPath(path, candidate.syntax),
      uri: text(candidate.uri)
    });
  }
  files.set(request.entryPath, {
    contents: request.source,
    syntax: request.syntax,
    uri: request.entryUri
  });
  return files;
}

function resolveCandidate(files, requestedPath, fromImport) {
  const normalized = normalizePath(requestedPath);
  const extensionMatch = normalized.match(/\.(scss|sass|css)$/);
  const extension = extensionMatch ? extensionMatch[0] : '';
  const stem = extension ? normalized.slice(0, -extension.length) : normalized;
  const direct = resolveStem(files, stem, extension, fromImport);
  if (direct || extension) return direct;
  return resolveStem(files, joinPath(stem, 'index'), '', fromImport);
}

function extension(path) {
  const name = basename(path);
  const dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.slice(dot);
}

function withoutExtension(path) {
  const suffix = extension(path);
  return suffix ? path.slice(0, -suffix.length) : path;
}

function importOnlyPath(files, path, fromImport) {
  if (!fromImport) return normalizePath(path);
  const suffix = extension(path);
  if (!STYLESHEET_EXTENSIONS.has(suffix)) return normalizePath(path);
  const importOnly = `${withoutExtension(path)}.import${suffix}`;
  return files.has(importOnly) ? importOnly : normalizePath(path);
}

function directoryExists(files, path) {
  const prefix = `${normalizePath(path)}/`;
  for (const filePath of files.keys()) {
    if (filePath.startsWith(prefix)) return true;
  }
  return false;
}

function packageNameAndSubpath(specifier) {
  const parts = specifier.split('/').filter(part => part.length > 0);
  let packageName = parts.shift() || '';
  if (packageName.startsWith('@') && parts.length > 0) {
    packageName = `${packageName}/${parts.shift()}`;
  }
  return {
    packageName,
    subpath: parts.length > 0 ? parts.join('/') : null
  };
}

function resolvePackageRoot(files, packageName, baseDirectory) {
  let directory = normalizePath(baseDirectory);
  while (true) {
    const candidate = joinPath(
      joinPath(directory, 'node_modules'),
      packageName
    );
    if (directoryExists(files, candidate)) return candidate;
    if (!directory) return null;
    directory = dirname(directory);
  }
}

function exportVariants(subpath, addIndex = false) {
  if (subpath === null && !addIndex) return [null];

  let path = subpath;
  if (path === null) {
    path = 'index';
  } else if (addIndex) {
    path = joinPath(path, 'index');
  }

  const paths = STYLESHEET_EXTENSIONS.has(extension(path))
    ? [path]
    : [path, `${path}.scss`, `${path}.sass`, `${path}.css`];
  const name = basename(path);
  if (name.startsWith('_')) return paths;
  return [
    ...paths,
    ...paths.map(candidate =>
      joinPath(dirname(candidate), `_${basename(candidate)}`)
    )
  ];
}

function compareExpansionKeys(keyA, keyB) {
  const baseLengthA = keyA.includes('*') ? keyA.indexOf('*') + 1 : keyA.length;
  const baseLengthB = keyB.includes('*') ? keyB.indexOf('*') + 1 : keyB.length;
  if (baseLengthA > baseLengthB) return -1;
  if (baseLengthB > baseLengthA) return 1;
  if (!keyA.includes('*')) return 1;
  if (!keyB.includes('*')) return -1;
  if (keyA.length > keyB.length) return -1;
  if (keyB.length > keyA.length) return 1;
  return 0;
}

function resolvePackageTarget(files, target, packageRoot, patternMatch) {
  if (typeof target === 'string') {
    if (!target.startsWith('./')) {
      throw new Error(
        `Export '${target}' must be a path relative to the package root at '${packageRoot}'.`
      );
    }
    const replaced = patternMatch === undefined
      ? target
      : target.replace('*', patternMatch);
    const path = joinPath(packageRoot, replaced.slice(2));
    return patternMatch === undefined || files.has(path) ? path : null;
  }

  if (Array.isArray(target)) {
    for (const value of target) {
      if (value === null) continue;
      const resolved = resolvePackageTarget(
        files,
        value,
        packageRoot,
        patternMatch
      );
      if (resolved) return resolved;
    }
    return null;
  }

  if (target && typeof target === 'object') {
    for (const [condition, value] of Object.entries(target)) {
      if (!['sass', 'style', 'default'].includes(condition) || value === null) {
        continue;
      }
      const resolved = resolvePackageTarget(
        files,
        value,
        packageRoot,
        patternMatch
      );
      if (resolved) return resolved;
    }
    return null;
  }

  throw new Error(
    `Invalid 'exports' value ${JSON.stringify(target)} in ${joinPath(packageRoot, 'package.json')}.`
  );
}

function mainExport(exportsValue) {
  if (typeof exportsValue === 'string') {
    return exportsValue;
  }
  if (Array.isArray(exportsValue)) {
    return exportsValue.every(value => typeof value === 'string')
      ? exportsValue
      : null;
  }
  if (!exportsValue || typeof exportsValue !== 'object') return null;
  const keys = Object.keys(exportsValue);
  if (keys.every(key => !key.startsWith('.'))) return exportsValue;
  return exportsValue['.'] ?? null;
}

function resolvePackageExportsVariants(
  files,
  packageRoot,
  variants,
  exportsValue,
  subpath,
  packageName
) {
  if (exportsValue && typeof exportsValue === 'object' &&
    !Array.isArray(exportsValue)) {
    const keys = Object.keys(exportsValue);
    if (keys.some(key => key.startsWith('.')) &&
      keys.some(key => !key.startsWith('.'))) {
      throw new Error(
        `\`exports\` in ${packageName} can not have both conditions and paths ` +
        `at the same level.\nFound ${keys.map(key => `"${key}"`).join(',')} in ` +
        `${joinPath(packageRoot, 'package.json')}.`
      );
    }
  }

  const matches = [];
  for (const variant of variants) {
    let resolved = null;
    if (variant === null) {
      const target = mainExport(exportsValue);
      if (target !== null) {
        resolved = resolvePackageTarget(files, target, packageRoot);
      }
    } else if (exportsValue && typeof exportsValue === 'object' &&
      !Array.isArray(exportsValue) &&
      Object.keys(exportsValue).some(key => key.startsWith('.'))) {
      const matchKey = `./${variant}`;
      if (Object.prototype.hasOwnProperty.call(exportsValue, matchKey) &&
        exportsValue[matchKey] !== null &&
        !matchKey.includes('*')) {
        resolved = resolvePackageTarget(
          files,
          exportsValue[matchKey],
          packageRoot
        );
      } else {
        const expansionKeys = Object.keys(exportsValue)
          .filter(key => (key.match(/\*/g) || []).length === 1)
          .sort(compareExpansionKeys);
        for (const expansionKey of expansionKeys) {
          const [patternBase, patternTrailer] = expansionKey.split('*');
          if (!matchKey.startsWith(patternBase) || matchKey === patternBase) {
            continue;
          }
          if (patternTrailer &&
            (!matchKey.endsWith(patternTrailer) ||
              matchKey.length < expansionKey.length)) {
            continue;
          }
          const target = exportsValue[expansionKey];
          if (target === null) continue;
          const patternMatch = matchKey.slice(
            patternBase.length,
            matchKey.length - patternTrailer.length
          );
          resolved = resolvePackageTarget(
            files,
            target,
            packageRoot,
            patternMatch
          );
          break;
        }
      }
    }

    if (resolved && !matches.includes(resolved)) matches.push(resolved);
  }

  if (matches.length > 1) {
    throw new Error(
      `Unable to determine which of multiple potential resolutions found for ` +
      `${subpath ?? 'root'} in ${packageName} should be used. \n\nFound:\n` +
      matches.join('\n')
    );
  }
  return matches[0] || null;
}

function resolvePackageExports(
  files,
  packageRoot,
  subpath,
  manifest,
  packageName
) {
  const exportsValue = manifest.exports;
  if (exportsValue === undefined || exportsValue === null) return null;

  const direct = resolvePackageExportsVariants(
    files,
    packageRoot,
    exportVariants(subpath),
    exportsValue,
    subpath,
    packageName
  );
  if (direct) return direct;
  if (subpath !== null && extension(subpath)) return null;
  return resolvePackageExportsVariants(
    files,
    packageRoot,
    exportVariants(subpath, true),
    exportsValue,
    subpath,
    packageName
  );
}

function resolvePackageRootValue(files, packageRoot, manifest, fromImport) {
  for (const key of ['sass', 'style']) {
    const value = manifest[key];
    if (typeof value === 'string' &&
      STYLESHEET_EXTENSIONS.has(extension(value))) {
      return importOnlyPath(files, joinPath(packageRoot, value), fromImport);
    }
  }
  return resolveCandidate(files, joinPath(packageRoot, 'index'), fromImport);
}

function createNodePackageImporter(files, entryPointDirectory) {
  return {
    nonCanonicalScheme: 'pkg',

    canonicalize(url, context) {
      if (!url.startsWith('pkg:')) {
        let requestedPath = '';
        if (url.startsWith(VIRTUAL_SCHEME)) {
          requestedPath = pathFromVirtualUrl(new URL(url));
        } else if (/^[a-z][a-z0-9+.-]*:/i.test(url)) {
          requestedPath = projectPathForImportUrl(files, url) || '';
          if (!requestedPath) return null;
        } else if (context.containingUrl) {
          const containingPath = projectPathFromUrl(
            files,
            context.containingUrl
          );
          if (!containingPath) return null;
          requestedPath = joinPath(
            dirname(containingPath),
            url
          );
        } else {
          return null;
        }
        const resolved = resolveCandidate(
          files,
          requestedPath,
          context.fromImport
        );
        return resolved ? projectUrl(files, resolved) : null;
      }

      const parsed = new URL(url);
      if (parsed.host || parsed.username || parsed.password || parsed.port) {
        throw new Error(
          'A pkg: URL must not have a host, port, username or password.'
        );
      }
      if (parsed.pathname.startsWith('/')) {
        throw new Error("A pkg: URL's path must not begin with /.");
      }
      if (!parsed.pathname) {
        throw new Error('A pkg: URL must not have an empty path.');
      }
      if (parsed.search || parsed.hash) {
        throw new Error('A pkg: URL must not have a query or fragment.');
      }

      const { packageName, subpath } = packageNameAndSubpath(parsed.pathname);
      if (packageName.startsWith('.') ||
        packageName.includes('\\') ||
        packageName.includes('%') ||
        (packageName.startsWith('@') && !packageName.includes('/'))) {
        return null;
      }

      const containingPath = context.containingUrl
        ? projectPathFromUrl(files, context.containingUrl)
        : null;
      const baseDirectory = containingPath
        ? dirname(containingPath)
        : entryPointDirectory;
      const packageRoot = resolvePackageRoot(
        files,
        packageName,
        baseDirectory
      );
      if (!packageRoot) return null;

      const manifestPath = joinPath(packageRoot, 'package.json');
      const manifestFile = files.get(manifestPath);
      if (!manifestFile) {
        throw new Error(`Failed to read ${manifestPath} for "pkg:${packageName}".`);
      }

      let manifest;
      try {
        manifest = JSON.parse(manifestFile.contents);
      } catch (error) {
        throw new Error(
          `Failed to parse ${manifestPath} for "pkg:${packageName}": ${error}`
        );
      }
      if (!manifest || typeof manifest !== 'object' || Array.isArray(manifest)) {
        throw new Error(
          `Failed to parse ${manifestPath} for "pkg:${packageName}": ` +
          'package manifest must be an object.'
        );
      }

      const fromImport = context.fromImport === true;
      const exported = resolvePackageExports(
        files,
        packageRoot,
        subpath,
        manifest,
        packageName
      );
      if (exported) {
        const suffix = extension(exported);
        if (!STYLESHEET_EXTENSIONS.has(suffix)) {
          throw new Error(
            `The export for '${subpath ?? 'root'}' in '${packageName}' resolved ` +
            `to '${exported}', which is not a '.scss', '.sass', or '.css' file.`
          );
        }
        return projectUrl(
          files,
          importOnlyPath(files, exported, fromImport)
        );
      }

      const resolved = subpath === null
        ? resolvePackageRootValue(files, packageRoot, manifest, fromImport)
        : resolveCandidate(
          files,
          joinPath(packageRoot, subpath),
          fromImport
        );
      return resolved ? projectUrl(files, resolved) : null;
    },

    load(canonicalUrl) {
      const path = projectPathFromUrl(files, canonicalUrl);
      if (!path) return null;
      const file = files.get(path);
      if (!file || !STYLESHEET_EXTENSIONS.has(extension(path))) return null;
      return {
        contents: file.contents,
        syntax: syntaxForPath(path, file.syntax),
        sourceMapUrl: projectUrl(files, path)
      };
    }
  };
}

function createImporter(files, rootsForUrl) {
  return {
    canonicalize(url, context) {
      if (url.startsWith('sass:')) return null;

      const roots = [];
      if (url.startsWith(VIRTUAL_SCHEME)) {
        const path = pathFromVirtualUrl(new URL(url));
        if (files.has(path)) return projectUrl(files, path);
        roots.push(path);
      } else if (/^[a-z][a-z0-9+.-]*:/i.test(url)) {
        const path = projectPathForImportUrl(files, url);
        if (!path) return null;
        if (files.has(path)) return projectUrl(files, path);
        roots.push(path);
      } else if (context.containingUrl) {
        const containingPath = projectPathFromUrl(
          files,
          context.containingUrl
        );
        if (!containingPath) return null;
        roots.push(joinPath(dirname(containingPath), url));
      } else {
        roots.push(normalizePath(url));
      }
      roots.push(...rootsForUrl(url));

      for (const root of roots) {
        const resolved = resolveCandidate(files, root, context.fromImport);
        if (resolved) return projectUrl(files, resolved);
      }
      return null;
    },

    load(canonicalUrl) {
      const path = projectPathFromUrl(files, canonicalUrl);
      if (!path) return null;
      const file = files.get(path);
      if (!file) return null;
      return {
        contents: file.contents,
        syntax: file.syntax,
        sourceMapUrl: projectUrl(files, path)
      };
    }
  };
}

function createRelativeImporter(files) {
  return createImporter(files, () => []);
}

function createLoadPathImporter(files, loadPaths) {
  const normalizedLoadPaths = loadPaths.map(normalizePath);
  return createImporter(
    files,
    url => normalizedLoadPaths.map(loadPath => joinPath(loadPath, url))
  );
}

function sourceMapUrlForFile(file, fallbackUrl) {
  return absoluteUrl(file && file.uri) || fallbackUrl;
}

function createCompileOptions(request, files, logger, overrides = {}) {
  const importer = createRelativeImporter(files);
  const importers = [];
  if (request.nodePackageImporter) {
    importers.push(
      createNodePackageImporter(files, request.packageEntryPointDirectory)
    );
  }
  if (request.loadPaths.length > 0) {
    importers.push(createLoadPathImporter(files, request.loadPaths));
  }
  return {
    url: projectUrl(files, request.entryPath),
    syntax: request.syntax,
    style: request.style,
    alertAscii: overrides.alertAscii ?? request.alertAscii,
    alertColor: overrides.alertColor ?? request.alertColor,
    sourceMap: request.sourceMap,
    sourceMapIncludeSources: request.sourceMapIncludeSources,
    charset: request.charset,
    quietDeps: request.quietDeps,
    verbose: request.verbose,
    fatalDeprecations: request.fatalDeprecations,
    futureDeprecations: request.futureDeprecations,
    silenceDeprecations: request.silenceDeprecations,
    importer,
    importers,
    logger
  };
}

function compileForFormattedError(request, files, alertAscii) {
  try {
    compileString(
      request.source,
      createCompileOptions(request, files, sass.Logger.silent, {
        alertAscii,
        alertColor: false
      })
    );
  } catch (error) {
    return text(error && (error.message || error));
  }
  return '';
}

function withErrorPrefix(message) {
  const value = text(message);
  return value.startsWith('Error: ') ? value : `Error: ${value}`;
}

function escapeNonAscii(value) {
  let result = '';
  for (const character of value) {
    const codePoint = character.codePointAt(0);
    result += codePoint > 0x7f
      ? `\\${codePoint.toString(16)} `
      : character;
  }
  return result;
}

function errorCssDisplayUrls(value, files) {
  let result = text(value);
  for (const file of files.values()) {
    const url = absoluteUrl(file && file.uri);
    if (!url || url.protocol !== 'file:') continue;
    const displayPath = `${url.host ? `//${url.host}` : ''}${decode(url.pathname)}`;
    result = result.replaceAll(url.toString(), displayPath);
  }
  return result;
}

function errorCssFor(request, files, fallbackError) {
  const formatted = errorCssDisplayUrls(
    compileForFormattedError(request, files, false) ||
      text(fallbackError && (fallbackError.message || fallbackError)),
    files
  );
  const asciiFormatted = errorCssDisplayUrls(
    compileForFormattedError(request, files, true) || formatted,
    files
  );
  const commentMessage = withErrorPrefix(asciiFormatted)
    .replaceAll('*/', '*∕')
    .replaceAll('\r\n', '\n');
  const stringMessage = escapeNonAscii(
    new sass.SassString(withErrorPrefix(formatted)).toString()
  );
  return `/* ${commentMessage.split('\n').join('\n * ')} */\n\n` +
    'body::before {\n' +
    '  font-family: "Source Code Pro", "SF Mono", Monaco, Inconsolata, "Fira Mono",\n' +
    '      "Droid Sans Mono", monospace, monospace;\n' +
    '  white-space: pre;\n' +
    '  display: block;\n' +
    '  padding: 1em;\n' +
    '  margin-bottom: 1em;\n' +
    '  border-bottom: 2px solid black;\n' +
    `  content: ${stringMessage};\n` +
    '}\n';
}

function createCompilationMessages(request) {
  const warnings = [];
  const debugMessages = [];
  const logger = request.quiet
    ? sass.Logger.silent
    : {
        warn(message, options) {
          warnings.push({
            message: text(message),
            deprecation: options.deprecation === true,
            deprecationType: options.deprecationType
              ? text(options.deprecationType.id)
              : undefined,
            deprecationMetadata: serializeDeprecation(
              options.deprecationType
            ),
            stack: options.stack ? text(options.stack) : undefined,
            span: serializeSpan(options.span)
          });
        },
        debug(message, options) {
          debugMessages.push({
            message: text(message),
            span: serializeSpan(options.span)
          });
        }
      };
  return { warnings, debugMessages, logger };
}

function successfulCompileResponse(result, messages) {
  return {
    ok: true,
    version: DART_SASS_VERSION,
    css: result.css,
    sourceMap: result.sourceMap ? JSON.stringify(result.sourceMap) : '',
    loadedUrls: result.loadedUrls.map(url => text(url)),
    warnings: messages.warnings,
    debugMessages: messages.debugMessages
  };
}

function failedCompileResponse(error, request, files, messages) {
  const response = serializeError(error);
  if (request.errorCss) {
    response.errorCss = errorCssFor(request, files, error);
  }
  response.warnings = messages.warnings;
  response.debugMessages = messages.debugMessages;
  return response;
}

function compileProjectResult(value) {
  const request = normalizeRequest(value);
  const files = createProject(request);
  const messages = createCompilationMessages(request);
  try {
    const result = compileString(
      request.source,
      createCompileOptions(request, files, messages.logger)
    );
    return successfulCompileResponse(result, messages);
  } catch (error) {
    return failedCompileResponse(error, request, files, messages);
  }
}

async function compileProjectResultAsync(value) {
  const request = normalizeRequest(value);
  const files = createProject(request);
  const messages = createCompilationMessages(request);
  try {
    const result = await compileStringAsync(
      request.source,
      createCompileOptions(request, files, messages.logger)
    );
    return successfulCompileResponse(result, messages);
  } catch (error) {
    return failedCompileResponse(error, request, files, messages);
  }
}

function compileProject(value) {
  return JSON.stringify(compileProjectResult(value));
}

function compileBatch(value) {
  const request = value && typeof value === 'object' ? value : {};
  const files = Array.isArray(request.files) ? request.files : [];
  const projectFiles = new Map();
  for (const candidate of files) {
    if (!candidate || typeof candidate !== 'object') continue;
    const path = normalizePath(candidate.path);
    if (!path) continue;
    projectFiles.set(path, candidate);
  }

  const results = [];
  const stopOnError = request.stopOnError === true;
  for (const requestedPath of stringList(request.entryPaths)) {
    const entryPath = normalizePath(requestedPath);
    const entry = projectFiles.get(entryPath);
    if (!entry) {
      results.push({
        entryPath,
        ok: false,
        version: DART_SASS_VERSION,
        warnings: [],
        debugMessages: [],
        error: {
          message: `Entry stylesheet "${entryPath}" was not found.`,
          formatted: `Entry stylesheet "${entryPath}" was not found.`,
          line: 0,
          column: 0
        }
      });
      if (stopOnError) break;
      continue;
    }

    results.push({
      entryPath,
      ...compileProjectResult({
        ...request,
        source: entry.contents,
        entryPath,
        entryUri: text(entry.uri),
        syntax: syntaxForPath(entryPath, entry.syntax),
        files
      })
    });
    if (stopOnError && results[results.length - 1].ok === false) break;
  }

  return JSON.stringify({
    ok: results.length > 0 && results.every(result => result.ok),
    version: DART_SASS_VERSION,
    results
  });
}

async function compileBatchResultAsync(value) {
  const request = value && typeof value === 'object' ? value : {};
  const files = Array.isArray(request.files) ? request.files : [];
  const projectFiles = new Map();
  for (const candidate of files) {
    if (!candidate || typeof candidate !== 'object') continue;
    const path = normalizePath(candidate.path);
    if (!path) continue;
    projectFiles.set(path, candidate);
  }

  const results = [];
  const stopOnError = request.stopOnError === true;
  for (const requestedPath of stringList(request.entryPaths)) {
    const entryPath = normalizePath(requestedPath);
    const entry = projectFiles.get(entryPath);
    if (!entry) {
      results.push({
        entryPath,
        ok: false,
        version: DART_SASS_VERSION,
        warnings: [],
        debugMessages: [],
        error: {
          message: `Entry stylesheet "${entryPath}" was not found.`,
          formatted: `Entry stylesheet "${entryPath}" was not found.`,
          line: 0,
          column: 0
        }
      });
      if (stopOnError) break;
      continue;
    }

    results.push({
      entryPath,
      ...await compileProjectResultAsync({
        ...request,
        source: entry.contents,
        entryPath,
        entryUri: text(entry.uri),
        syntax: syntaxForPath(entryPath, entry.syntax),
        files
      })
    });
    if (stopOnError && results[results.length - 1].ok === false) break;
  }

  return {
    ok: results.length > 0 && results.every(result => result.ok),
    version: DART_SASS_VERSION,
    results
  };
}

function startAsyncJob(task) {
  const jobId = String(nextAsyncJobId++);
  const job = {
    state: 'pending',
    payload: '',
    message: '',
    released: false
  };
  asyncJobs.set(jobId, job);
  Promise.resolve()
    .then(task)
    .then(result => {
      if (job.released) return;
      job.state = 'complete';
      job.payload = JSON.stringify(result);
    })
    .catch(error => {
      if (job.released) return;
      job.state = 'failed';
      job.message = text(error && (error.stack || error.message || error));
    });
  return JSON.stringify({ jobId });
}

function pollAsyncJob(value) {
  const jobId = text(
    value && typeof value === 'object' ? value.jobId : value
  );
  const job = asyncJobs.get(jobId);
  if (!job) {
    return JSON.stringify({
      state: 'missing',
      message: `Async compilation job "${jobId}" was not found.`
    });
  }
  if (job.state === 'pending') {
    return JSON.stringify({ state: 'pending' });
  }
  asyncJobs.delete(jobId);
  return JSON.stringify({
    state: job.state,
    payload: job.payload,
    message: job.message
  });
}

function releaseAsyncJob(value) {
  const jobId = text(
    value && typeof value === 'object' ? value.jobId : value
  );
  const job = asyncJobs.get(jobId);
  if (!job) {
    return JSON.stringify({ released: false });
  }
  job.released = true;
  asyncJobs.delete(jobId);
  return JSON.stringify({ released: true });
}

function clearAsyncJobs() {
  for (const job of asyncJobs.values()) {
    job.released = true;
  }
  asyncJobs.clear();
}

function encodedFileName(value) {
  return encodeURIComponent(basename(text(value)));
}

function relativeFileUrl(target, baseFile) {
  if (!target || !baseFile ||
    target.protocol !== 'file:' ||
    baseFile.protocol !== 'file:' ||
    target.host !== baseFile.host) {
    return null;
  }
  const targetParts = target.pathname.split('/').filter(Boolean);
  const baseParts = baseFile.pathname.split('/').filter(Boolean);
  baseParts.pop();
  let common = 0;
  while (common < targetParts.length &&
    common < baseParts.length &&
    targetParts[common] === baseParts[common]) {
    common++;
  }
  const relative = [
    ...baseParts.slice(common).map(() => '..'),
    ...targetParts.slice(common)
  ].join('/');
  return relative || basename(target.pathname);
}

function sourceMapSourceUrl(source, baseUri, mode) {
  const sourceUrl = absoluteUrl(source);
  if (!sourceUrl || sourceUrl.protocol !== 'file:') return text(source);
  if (mode !== 'relative') return sourceUrl.toString();
  const baseUrl = absoluteUrl(baseUri);
  return relativeFileUrl(sourceUrl, baseUrl) || sourceUrl.toString();
}

function sourceMappingUrl(candidate) {
  const cssUrl = absoluteUrl(candidate.cssUri);
  const mapUrl = absoluteUrl(candidate.sourceMapUri);
  const relative = relativeFileUrl(mapUrl, cssUrl);
  return relative ||
    (mapUrl ? mapUrl.toString() : encodedFileName(candidate.sourceMapFileName));
}

function encodeDataUriPayload(value) {
  return encodeURI(value)
    .replaceAll('#', '%23');
}

function sourceMapWithFile(sourceMap, cssFileName) {
  const result = {};
  let inserted = false;
  for (const [key, value] of Object.entries(sourceMap)) {
    if (key === 'file') continue;
    if (key === 'sourcesContent' && !inserted) {
      result.file = cssFileName;
      inserted = true;
    }
    result[key] = value;
  }
  if (!inserted) result.file = cssFileName;
  return result;
}

function finalizeExports(value) {
  const request = value && typeof value === 'object' ? value : {};
  const style = SUPPORTED_STYLES.has(request.style)
    ? request.style
    : 'expanded';
  const sourceMapUrls = request.sourceMapUrls === 'absolute'
    ? 'absolute'
    : 'relative';
  const embedSourceMap = request.embedSourceMap === true;
  const entries = Array.isArray(request.entries) ? request.entries : [];
  const results = entries.map(entry => {
    const candidate = entry && typeof entry === 'object' ? entry : {};
    const parsedSourceMap = JSON.parse(text(candidate.sourceMap));
    const cssFileName = encodedFileName(candidate.cssFileName);
    const sourceMap = sourceMapWithFile(parsedSourceMap, cssFileName);
    const sourceBaseUri = embedSourceMap
      ? candidate.cssUri
      : candidate.sourceMapUri || candidate.cssUri;
    if (Array.isArray(sourceMap.sources)) {
      sourceMap.sources = sourceMap.sources.map(source =>
        sourceMapSourceUrl(source, sourceBaseUri, sourceMapUrls)
      );
    }
    const sourceMapText = JSON.stringify(sourceMap);
    const mapUrl = embedSourceMap
      ? 'data:application/json;charset=utf-8,' +
        encodeDataUriPayload(sourceMapText)
      : sourceMappingUrl(candidate);
    const escapedUrl = mapUrl.replaceAll('*/', '%2A/');
    const separator = style === 'compressed' ? '' : '\n\n';
    return {
      css: `${text(candidate.css)}${separator}` +
        `/*# sourceMappingURL=${escapedUrl} */\n`,
      sourceMap: embedSourceMap ? '' : sourceMapText
    };
  });
  return JSON.stringify({ results });
}

globalThis.harmonySass = Object.freeze({
  version: DART_SASS_VERSION,
  info: DART_SASS_INFO,
  getMetadata() {
    return JSON.stringify(runtimeMetadata());
  },
  compile(source) {
    return compileProject({ source });
  },
  compileProject,
  compileBatch,
  startCompileProjectAsync(value) {
    return startAsyncJob(() => compileProjectResultAsync(value));
  },
  startCompileBatchAsync(value) {
    return startAsyncJob(() => compileBatchResultAsync(value));
  },
  pollAsyncJob,
  releaseAsyncJob,
  finalizeExports
});

if (typeof globalThis.addEventListener === 'function') {
  globalThis.addEventListener('pagehide', () => {
    clearAsyncJobs();
    compiler.dispose();
    asyncCompilerPromise.then(asyncCompiler => asyncCompiler.dispose());
  }, { once: true });
}
