import * as sass from 'sass';

const DART_SASS_VERSION = '1.101.3';
const VIRTUAL_SCHEME = 'harmony-sass:';
const SUPPORTED_SYNTAXES = new Set(['scss', 'indented', 'css']);
const SUPPORTED_STYLES = new Set(['expanded', 'compressed']);
const STYLESHEET_EXTENSIONS = new Set(['.scss', '.sass', '.css']);

function text(value) {
  return value === undefined || value === null ? '' : String(value);
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
    quietDeps: request.quietDeps === true,
    verbose: request.verbose === true,
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
      syntax: syntaxForPath(path, candidate.syntax)
    });
  }
  files.set(request.entryPath, {
    contents: request.source,
    syntax: request.syntax
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
          return null;
        } else if (context.containingUrl &&
          context.containingUrl.protocol === VIRTUAL_SCHEME) {
          requestedPath = joinPath(
            dirname(pathFromVirtualUrl(context.containingUrl)),
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
        return resolved ? virtualUrl(resolved) : null;
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

      const baseDirectory = context.containingUrl &&
        context.containingUrl.protocol === VIRTUAL_SCHEME
        ? dirname(pathFromVirtualUrl(context.containingUrl))
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
        return virtualUrl(importOnlyPath(files, exported, fromImport));
      }

      const resolved = subpath === null
        ? resolvePackageRootValue(files, packageRoot, manifest, fromImport)
        : resolveCandidate(
          files,
          joinPath(packageRoot, subpath),
          fromImport
        );
      return resolved ? virtualUrl(resolved) : null;
    },

    load(canonicalUrl) {
      if (canonicalUrl.protocol !== VIRTUAL_SCHEME) return null;
      const path = pathFromVirtualUrl(canonicalUrl);
      const file = files.get(path);
      if (!file || !STYLESHEET_EXTENSIONS.has(extension(path))) return null;
      return {
        contents: file.contents,
        syntax: syntaxForPath(path, file.syntax),
        sourceMapUrl: canonicalUrl
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
        if (files.has(path)) return virtualUrl(path);
        roots.push(path);
      } else if (/^[a-z][a-z0-9+.-]*:/i.test(url)) {
        return null;
      } else if (
        context.containingUrl &&
        context.containingUrl.protocol === VIRTUAL_SCHEME
      ) {
        roots.push(
          joinPath(dirname(pathFromVirtualUrl(context.containingUrl)), url)
        );
      } else {
        roots.push(normalizePath(url));
      }
      roots.push(...rootsForUrl(url));

      for (const root of roots) {
        const resolved = resolveCandidate(files, root, context.fromImport);
        if (resolved) return virtualUrl(resolved);
      }
      return null;
    },

    load(canonicalUrl) {
      if (canonicalUrl.protocol !== VIRTUAL_SCHEME) return null;
      const path = pathFromVirtualUrl(canonicalUrl);
      const file = files.get(path);
      if (!file) return null;
      return {
        contents: file.contents,
        syntax: file.syntax,
        sourceMapUrl: canonicalUrl
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

function compileProjectResult(value) {
  const request = normalizeRequest(value);
  const files = createProject(request);
  const warnings = [];
  const debugMessages = [];
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

  try {
    const result = sass.compileString(request.source, {
      url: virtualUrl(request.entryPath),
      syntax: request.syntax,
      style: request.style,
      alertAscii: request.alertAscii,
      alertColor: request.alertColor,
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
      logger: {
        warn(message, options) {
          warnings.push({
            message: text(message),
            deprecation: options.deprecation === true,
            deprecationType: options.deprecationType
              ? text(options.deprecationType.id)
              : undefined,
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
      }
    });

    return {
      ok: true,
      version: DART_SASS_VERSION,
      css: result.css,
      sourceMap: result.sourceMap ? JSON.stringify(result.sourceMap) : '',
      loadedUrls: result.loadedUrls.map(url => text(url)),
      warnings,
      debugMessages
    };
  } catch (error) {
    const response = serializeError(error);
    response.warnings = warnings;
    response.debugMessages = debugMessages;
    return response;
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
      continue;
    }

    results.push({
      entryPath,
      ...compileProjectResult({
        ...request,
        source: entry.contents,
        entryPath,
        syntax: syntaxForPath(entryPath, entry.syntax),
        files
      })
    });
  }

  return JSON.stringify({
    ok: results.length > 0 && results.every(result => result.ok),
    version: DART_SASS_VERSION,
    results
  });
}

function encodedFileName(value) {
  return encodeURIComponent(basename(text(value)));
}

function finalizeExports(value) {
  const request = value && typeof value === 'object' ? value : {};
  const style = SUPPORTED_STYLES.has(request.style)
    ? request.style
    : 'expanded';
  const entries = Array.isArray(request.entries) ? request.entries : [];
  const results = entries.map(entry => {
    const candidate = entry && typeof entry === 'object' ? entry : {};
    const sourceMap = JSON.parse(text(candidate.sourceMap));
    const cssFileName = encodedFileName(candidate.cssFileName);
    const sourceMapFileName = encodedFileName(candidate.sourceMapFileName);
    sourceMap.file = cssFileName;
    const separator = style === 'compressed' ? '' : '\n\n';
    return {
      css: `${text(candidate.css)}${separator}` +
        `/*# sourceMappingURL=${sourceMapFileName} */\n`,
      sourceMap: JSON.stringify(sourceMap)
    };
  });
  return JSON.stringify({ results });
}

globalThis.harmonySass = Object.freeze({
  version: DART_SASS_VERSION,
  compile(source) {
    return compileProject({ source });
  },
  compileProject,
  compileBatch,
  finalizeExports
});
