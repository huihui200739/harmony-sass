import * as sass from 'sass';

const DART_SASS_VERSION = '1.101.3';
const VIRTUAL_SCHEME = 'harmony-sass:';
const SUPPORTED_SYNTAXES = new Set(['scss', 'indented', 'css']);
const SUPPORTED_STYLES = new Set(['expanded', 'compressed']);

function text(value) {
  return value === undefined || value === null ? '' : String(value);
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

function candidatePaths(requestedPath, fromImport) {
  const normalized = normalizePath(requestedPath);
  const extensionMatch = normalized.match(/\.(scss|sass|css)$/);
  const extension = extensionMatch ? extensionMatch[0] : '';
  const stem = extension ? normalized.slice(0, -extension.length) : normalized;
  const extensions = extension ? [extension] : ['.scss', '.sass', '.css'];
  const candidates = [];

  for (const currentExtension of extensions) {
    if (fromImport && currentExtension !== '.css') {
      candidates.push(`${stem}.import${currentExtension}`);
      candidates.push(partialPath(`${stem}.import${currentExtension}`));
    }
    candidates.push(`${stem}${currentExtension}`);
    candidates.push(partialPath(`${stem}${currentExtension}`));
  }

  for (const currentExtension of extensions) {
    const indexStem = joinPath(stem, 'index');
    if (fromImport && currentExtension !== '.css') {
      candidates.push(`${indexStem}.import${currentExtension}`);
      candidates.push(partialPath(`${indexStem}.import${currentExtension}`));
    }
    candidates.push(`${indexStem}${currentExtension}`);
    candidates.push(partialPath(`${indexStem}${currentExtension}`));
  }

  return [...new Set(candidates.map(normalizePath))];
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
  return {
    source: text(request.source),
    entryPath: normalizePath(request.entryPath || defaultEntry) || defaultEntry,
    files: Array.isArray(request.files) ? request.files : [],
    loadPaths: Array.isArray(request.loadPaths) ? request.loadPaths : [],
    syntax,
    style,
    sourceMap: request.sourceMap === true,
    sourceMapIncludeSources: request.sourceMapIncludeSources !== false,
    charset: request.charset !== false,
    quietDeps: request.quietDeps === true,
    verbose: request.verbose === true
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
  let matches = candidatePaths(requestedPath, fromImport)
    .filter(path => files.has(path));
  if (fromImport) {
    const importOnlyMatches = matches.filter(
      path => /\.import\.(scss|sass)$/.test(path)
    );
    if (importOnlyMatches.length > 0) matches = importOnlyMatches;
  }
  if (matches.length > 1) {
    throw new Error(
      `Ambiguous stylesheet "${requestedPath}". Found: ${matches.join(', ')}`
    );
  }
  return matches[0] || null;
}

function createImporter(files, loadPaths) {
  const normalizedLoadPaths = loadPaths.map(normalizePath);
  return {
    canonicalize(url, context) {
      if (url.startsWith('sass:')) return null;

      const roots = [];
      if (url.startsWith(VIRTUAL_SCHEME)) {
        roots.push(pathFromVirtualUrl(new URL(url)));
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
        for (const loadPath of normalizedLoadPaths) {
          roots.push(joinPath(loadPath, url));
        }
      }

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

function compileProject(value) {
  const request = normalizeRequest(value);
  const files = createProject(request);
  const warnings = [];
  const importer = createImporter(files, request.loadPaths);

  try {
    const result = sass.compileString(request.source, {
      url: virtualUrl(request.entryPath),
      syntax: request.syntax,
      style: request.style,
      sourceMap: request.sourceMap,
      sourceMapIncludeSources: request.sourceMapIncludeSources,
      charset: request.charset,
      quietDeps: request.quietDeps,
      verbose: request.verbose,
      importers: [importer],
      logger: {
        warn(message, options) {
          warnings.push({
            message: text(message),
            deprecation: options.deprecation === true,
            span: serializeSpan(options.span)
          });
        },
        debug() {}
      }
    });

    return JSON.stringify({
      ok: true,
      version: DART_SASS_VERSION,
      css: result.css,
      sourceMap: result.sourceMap ? JSON.stringify(result.sourceMap) : '',
      loadedUrls: result.loadedUrls.map(url => text(url)),
      warnings
    });
  } catch (error) {
    const response = serializeError(error);
    response.warnings = warnings;
    return JSON.stringify(response);
  }
}

globalThis.harmonySass = Object.freeze({
  version: DART_SASS_VERSION,
  compile(source) {
    return compileProject({ source });
  },
  compileProject
});
