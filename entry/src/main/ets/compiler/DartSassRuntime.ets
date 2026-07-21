export interface SassCompileError {
  message: string;
  formatted: string;
  line: number;
  column: number;
}

export interface SassCompileResponse {
  ok: boolean;
  version: string;
  css?: string;
  error?: SassCompileError;
}

export class DartSassRuntime {
  static createCompileScript(source: string): string {
    return `globalThis.harmonySass.compile(${JSON.stringify(source)})`;
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
