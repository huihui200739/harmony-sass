export interface SassSourcePosition {
  line: number;
  column: number;
  offset: number;
}

export interface SassSourceSpan {
  text: string;
  context?: string;
  url: string;
  start: SassSourcePosition;
  end: SassSourcePosition;
}

export interface SassDeprecationMetadata {
  id: string;
  status: string;
  description?: string | null;
  deprecatedIn?: string;
  obsoleteIn?: string;
}

export interface SassCompileError {
  message: string;
  formatted: string;
  sassStack?: string;
  stackTrace?: string;
  line: number;
  column: number;
  span?: SassSourceSpan;
}

export interface SassWarning {
  message: string;
  deprecation: boolean;
  deprecationType?: string;
  deprecationMetadata?: SassDeprecationMetadata;
  stack?: string;
  span?: SassSourceSpan;
}

export interface SassDebugMessage {
  message: string;
  span?: SassSourceSpan;
}

export interface SassProjectFile {
  path: string;
  uri?: string;
  contents: string;
  syntax?: string;
}

export interface SassCompileRequest {
  source: string;
  entryPath: string;
  entryUri: string;
  files: SassProjectFile[];
  loadPaths: string[];
  nodePackageImporter: boolean;
  packageEntryPointDirectory: string;
  syntax: string;
  style: string;
  alertAscii: boolean;
  alertColor: boolean;
  sourceMap: boolean;
  sourceMapIncludeSources: boolean;
  charset: boolean;
  quiet: boolean;
  quietDeps: boolean;
  verbose: boolean;
  errorCss: boolean;
  fatalDeprecations: string[];
  futureDeprecations: string[];
  silenceDeprecations: string[];
}

export interface SassCompileResponse {
  ok: boolean;
  version: string;
  css?: string;
  errorCss?: string;
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
  nodePackageImporter: boolean;
  packageEntryPointDirectory: string;
  style: string;
  alertAscii: boolean;
  alertColor: boolean;
  sourceMap: boolean;
  sourceMapIncludeSources: boolean;
  charset: boolean;
  quiet: boolean;
  quietDeps: boolean;
  verbose: boolean;
  errorCss: boolean;
  stopOnError: boolean;
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

export interface SassExportFinalizeEntry {
  css: string;
  sourceMap: string;
  cssFileName: string;
  sourceMapFileName: string;
  cssUri: string;
  sourceMapUri: string;
}

export interface SassExportFinalizeRequest {
  style: string;
  sourceMapUrls: string;
  embedSourceMap: boolean;
  entries: SassExportFinalizeEntry[];
}

export interface SassFinalizedExportEntry {
  css: string;
  sourceMap: string;
}

export interface SassExportFinalizeResponse {
  results: SassFinalizedExportEntry[];
}

export interface SassRuntimeMetadata {
  version: string;
  info: string;
  compilerModes: string[];
  deprecations: SassDeprecationMetadata[];
}

export interface SassAsyncJobStartResponse {
  jobId: string;
}

export interface SassAsyncJobPollResponse {
  state: string;
  payload?: string;
  message?: string;
}

export interface SassAsyncJobReleaseResponse {
  released: boolean;
}

export class DartSassRuntime {
  static createCompileScript(source: string): string {
    const request: SassCompileRequest = {
      source,
      entryPath: 'stdin.scss',
      entryUri: '',
      files: [],
      loadPaths: [],
      nodePackageImporter: false,
      packageEntryPointDirectory: '',
      syntax: 'scss',
      style: 'expanded',
      alertAscii: false,
      alertColor: false,
      sourceMap: false,
      sourceMapIncludeSources: true,
      charset: true,
      quiet: false,
      quietDeps: false,
      verbose: false,
      errorCss: false,
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

  static createAsyncProjectCompileScript(request: SassCompileRequest): string {
    return `globalThis.harmonySass.startCompileProjectAsync(${JSON.stringify(request)})`;
  }

  static createAsyncBatchCompileScript(request: SassBatchCompileRequest): string {
    return `globalThis.harmonySass.startCompileBatchAsync(${JSON.stringify(request)})`;
  }

  static createAsyncJobPollScript(jobId: string): string {
    return `globalThis.harmonySass.pollAsyncJob(${JSON.stringify(jobId)})`;
  }

  static createAsyncJobReleaseScript(jobId: string): string {
    return `globalThis.harmonySass.releaseAsyncJob(${JSON.stringify(jobId)})`;
  }

  static createFinalizeExportsScript(request: SassExportFinalizeRequest): string {
    return `globalThis.harmonySass.finalizeExports(${JSON.stringify(request)})`;
  }

  static createMetadataScript(): string {
    return 'globalThis.harmonySass.getMetadata()';
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

  static parseAsyncJobStartResponse(payload: string): SassAsyncJobStartResponse {
    const decoded: SassAsyncJobStartResponse | string =
      JSON.parse(payload) as SassAsyncJobStartResponse | string;
    if (typeof decoded === 'string') {
      return JSON.parse(decoded) as SassAsyncJobStartResponse;
    }
    return decoded;
  }

  static parseAsyncJobPollResponse(payload: string): SassAsyncJobPollResponse {
    const decoded: SassAsyncJobPollResponse | string =
      JSON.parse(payload) as SassAsyncJobPollResponse | string;
    if (typeof decoded === 'string') {
      return JSON.parse(decoded) as SassAsyncJobPollResponse;
    }
    return decoded;
  }

  static parseAsyncJobReleaseResponse(payload: string): SassAsyncJobReleaseResponse {
    const decoded: SassAsyncJobReleaseResponse | string =
      JSON.parse(payload) as SassAsyncJobReleaseResponse | string;
    if (typeof decoded === 'string') {
      return JSON.parse(decoded) as SassAsyncJobReleaseResponse;
    }
    return decoded;
  }

  static parseFinalizeExportsResponse(payload: string): SassExportFinalizeResponse {
    const decoded: SassExportFinalizeResponse | string =
      JSON.parse(payload) as SassExportFinalizeResponse | string;
    if (typeof decoded === 'string') {
      return JSON.parse(decoded) as SassExportFinalizeResponse;
    }
    return decoded;
  }

  static parseMetadata(payload: string): SassRuntimeMetadata {
    const decoded: SassRuntimeMetadata | string =
      JSON.parse(payload) as SassRuntimeMetadata | string;
    if (typeof decoded === 'string') {
      return JSON.parse(decoded) as SassRuntimeMetadata;
    }
    return decoded;
  }
}
