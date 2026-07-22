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
  deprecationType?: string;
  stack?: string;
  span?: SassSourceSpan;
}

export interface SassDebugMessage {
  message: string;
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
  alertAscii: boolean;
  alertColor: boolean;
  sourceMap: boolean;
  sourceMapIncludeSources: boolean;
  charset: boolean;
  quietDeps: boolean;
  verbose: boolean;
  fatalDeprecations: string[];
  futureDeprecations: string[];
  silenceDeprecations: string[];
}

export interface SassCompileResponse {
  ok: boolean;
  version: string;
  css?: string;
  sourceMap?: string;
  loadedUrls?: string[];
  warnings?: SassWarning[];
  debugMessages?: SassDebugMessage[];
  error?: SassCompileError;
}

export interface SassBatchCompileRequest {
  entryPaths: string[];
  files: SassProjectFile[];
  loadPaths: string[];
  style: string;
  alertAscii: boolean;
  alertColor: boolean;
  sourceMap: boolean;
  sourceMapIncludeSources: boolean;
  charset: boolean;
  quietDeps: boolean;
  verbose: boolean;
  fatalDeprecations: string[];
  futureDeprecations: string[];
  silenceDeprecations: string[];
}

export interface SassBatchCompileResult extends SassCompileResponse {
  entryPath: string;
}

export interface SassBatchCompileResponse {
  ok: boolean;
  version: string;
  results: SassBatchCompileResult[];
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
      alertAscii: false,
      alertColor: false,
      sourceMap: false,
      sourceMapIncludeSources: true,
      charset: true,
      quietDeps: false,
      verbose: false,
      fatalDeprecations: [],
      futureDeprecations: [],
      silenceDeprecations: []
    };
    return DartSassRuntime.createProjectCompileScript(request);
  }

  static createProjectCompileScript(request: SassCompileRequest): string {
    return `globalThis.harmonySass.compileProject(${JSON.stringify(request)})`;
  }

  static createBatchCompileScript(request: SassBatchCompileRequest): string {
    return `globalThis.harmonySass.compileBatch(${JSON.stringify(request)})`;
  }

  static parseResponse(payload: string): SassCompileResponse {
    const decoded: SassCompileResponse | string =
      JSON.parse(payload) as SassCompileResponse | string;
    if (typeof decoded === 'string') {
      return JSON.parse(decoded) as SassCompileResponse;
    }
    return decoded;
  }

  static parseBatchResponse(payload: string): SassBatchCompileResponse {
    const decoded: SassBatchCompileResponse | string =
      JSON.parse(payload) as SassBatchCompileResponse | string;
    if (typeof decoded === 'string') {
      return JSON.parse(decoded) as SassBatchCompileResponse;
    }
    return decoded;
  }
}
