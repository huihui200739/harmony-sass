import * as sass from 'sass';

const DART_SASS_VERSION = '1.101.3';

function text(value) {
  return value === undefined || value === null ? '' : String(value);
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
      column: span ? span.start.column + 1 : 0
    }
  };
}

globalThis.harmonySass = Object.freeze({
  version: DART_SASS_VERSION,
  compile(source) {
    try {
      const result = sass.compileString(text(source), {
        syntax: 'scss',
        style: 'expanded',
        sourceMap: false
      });
      return JSON.stringify({
        ok: true,
        version: DART_SASS_VERSION,
        css: result.css
      });
    } catch (error) {
      return JSON.stringify(serializeError(error));
    }
  }
});
