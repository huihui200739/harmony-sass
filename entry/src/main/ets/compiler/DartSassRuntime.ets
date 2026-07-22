export interface SassSourcePosition {
  line: number;
  column: number;
  offset: number;
}

export interface SassSourceSpan {
  text: string;
  url: string;
  start: SassSourcePosition;
  end: SassSourcePosition;
}

export interface SassCompileError {
  message: string;
  formatted: string;
  line: number;
  column: number;
  span?: SassSourceSpan;
}

export interface SassWarning {
  message: string;
  deprecation: boolean;
  span?: SassSourceSpan;
}

export interface SassProjectFile {
  path: string;
  contents: string;
  syntax?: string;
}

export interface SassCompileRequest {
  source: string;
  entryPath: string;
  files: SassProjectFile[];
  loadPaths: string[];
  syntax: string;
  style: string;
  sourceMap: boolean;
  sourceMapIncludeSources: boolean;
  charset: boolean;
  quietDeps: boolean;
  verbose: boolean;
}

export interface SassCompileResponse {
  ok: boolean;
  version: string;
  css?: string;
  sourceMap?: string;
  loadedUrls?: string[];
  warnings?: SassWarning[];
  error?: SassCompileError;
}

export class DartSassRuntime {
  static createCompileScript(source: string): string {
    const request: SassCompileRequest = {
      source,
      entryPath: 'stdin.scss',
      files: [],
      loadPaths: [],
      syntax: 'scss',
      style: 'expanded',
      sourceMap: false,
      sourceMapIncludeSources: true,
      charset: true,
      quietDeps: false,
      verbose: false
    };
    return DartSassRuntime.createProjectCompileScript(request);
  }

  static createProjectCompileScript(request: SassCompileRequest): string {
    return `globalThis.harmonySass.compileProject(${JSON.stringify(request)})`;
  }

  static parseResponse(payload: string): SassCompileResponse {
    const decoded: SassCompileResponse | string =
      JSON.parse(payload) as SassCompileResponse | string;
    if (typeof decoded === 'string') {
      return JSON.parse(decoded) as SassCompileResponse;
    }
    return decoded;
  }
}
