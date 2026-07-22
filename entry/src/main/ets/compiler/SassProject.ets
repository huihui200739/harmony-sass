import { SassProjectFile } from './DartSassRuntime';

export interface SassEditorFile {
  path: string;
  uri: string;
  contents: string;
  syntax: string;
}

export class SassProject {
  static normalizePath(value: string): string {
    const normalized: string[] = [];
    const parts: string[] = value.replaceAll('\\', '/').split('/');
    for (const part of parts) {
      if (part.length === 0 || part === '.') {
        continue;
      }
      if (part === '..') {
        normalized.pop();
        continue;
      }
      normalized.push(part);
    }
    return normalized.join('/');
  }

  static syntaxForPath(path: string): string {
    const lowerPath: string = path.toLowerCase();
    if (lowerPath.endsWith('.sass')) {
      return 'indented';
    }
    if (lowerPath.endsWith('.css')) {
      return 'css';
    }
    if (SassProject.isPackageManifestPath(path)) {
      return 'json';
    }
    return 'scss';
  }

  static isStylesheetPath(path: string): boolean {
    const lowerPath: string = SassProject.normalizePath(path).toLowerCase();
    return lowerPath.endsWith('.scss') ||
      lowerPath.endsWith('.sass') ||
      lowerPath.endsWith('.css');
  }

  static isPackageManifestPath(path: string): boolean {
    const normalized: string = SassProject.normalizePath(path);
    const name: string = normalized.split('/').pop() ?? normalized;
    return name.toLowerCase() === 'package.json';
  }

  static isProjectFilePath(path: string): boolean {
    return SassProject.isStylesheetPath(path) ||
      SassProject.isPackageManifestPath(path);
  }

  static editableStylesheetFiles(files: SassEditorFile[]): SassEditorFile[] {
    return files.filter((file: SassEditorFile): boolean =>
      SassProject.isStylesheetPath(file.path)
    );
  }

  static fileNameFromUri(uri: string): string {
    const segments: string[] = SassProject.uriSegments(uri);
    return segments.length > 0 ? segments[segments.length - 1] : 'untitled.scss';
  }

  static deriveVirtualPaths(uris: string[]): string[] {
    if (uris.length === 0) {
      return [];
    }

    const allSegments: string[][] = uris.map((uri: string): string[] => SassProject.uriSegments(uri));
    if (uris.length === 1) {
      const segments: string[] = allSegments[0];
      return [segments.length > 0 ? segments[segments.length - 1] : 'untitled.scss'];
    }

    let commonLength: number = allSegments[0].length - 1;
    for (let index: number = 1; index < allSegments.length; index++) {
      commonLength = Math.min(commonLength, allSegments[index].length - 1);
      for (let segmentIndex: number = 0; segmentIndex < commonLength; segmentIndex++) {
        if (allSegments[index][segmentIndex] !== allSegments[0][segmentIndex]) {
          commonLength = segmentIndex;
          break;
        }
      }
    }

    return allSegments.map((segments: string[], index: number): string => {
      const relative: string = SassProject.normalizePath(segments.slice(commonLength).join('/'));
      return relative.length > 0 ? relative : `file-${index + 1}.scss`;
    });
  }

  static mergeFiles(existing: SassEditorFile[], incoming: SassEditorFile[]): SassEditorFile[] {
    const merged: SassEditorFile[] = existing.slice();
    for (const file of incoming) {
      let replacementIndex: number = -1;
      for (let index: number = 0; index < merged.length; index++) {
        if ((file.uri.length > 0 && merged[index].uri === file.uri) || merged[index].path === file.path) {
          replacementIndex = index;
          break;
        }
      }
      if (replacementIndex >= 0) {
        merged[replacementIndex] = file;
      } else {
        merged.push(file);
      }
    }
    return merged;
  }

  static withoutUntouchedPlaceholder(
    files: SassEditorFile[],
    placeholderPath: string,
    placeholderContents: string,
    dirtyPaths: string[]
  ): SassEditorFile[] {
    if (files.length !== 1) {
      return files;
    }
    const file: SassEditorFile = files[0];
    if (file.uri.length > 0 ||
      file.path !== placeholderPath ||
      file.contents !== placeholderContents ||
      dirtyPaths.includes(file.path)) {
      return files;
    }
    return [];
  }

  static uniqueUris(uris: string[]): string[] {
    const unique: string[] = [];
    for (const uri of uris) {
      if (uri.length > 0 && !unique.includes(uri)) {
        unique.push(uri);
      }
    }
    return unique;
  }

  static rebaseUriFiles(files: SassEditorFile[]): SassEditorFile[] {
    const uris: string[] = [];
    for (const file of files) {
      if (file.uri.length > 0) {
        uris.push(file.uri);
      }
    }
    const rebasedPaths: string[] = SassProject.deriveVirtualPaths(uris);
    let uriIndex: number = 0;
    return files.map((file: SassEditorFile): SassEditorFile => {
      if (file.uri.length === 0) {
        return file;
      }
      const rebased: SassEditorFile = {
        path: rebasedPaths[uriIndex],
        uri: file.uri,
        contents: file.contents,
        syntax: file.syntax
      };
      uriIndex++;
      return rebased;
    });
  }

  static updateContents(files: SassEditorFile[], path: string, contents: string): SassEditorFile[] {
    return files.map((file: SassEditorFile): SassEditorFile => {
      if (file.path !== path) {
        return file;
      }
      return {
        path: file.path,
        uri: file.uri,
        contents,
        syntax: file.syntax
      };
    });
  }

  static updateSyntax(files: SassEditorFile[], path: string, syntax: string): SassEditorFile[] {
    return files.map((file: SassEditorFile): SassEditorFile => {
      if (file.path !== path) {
        return file;
      }
      return {
        path: file.path,
        uri: file.uri,
        contents: file.contents,
        syntax
      };
    });
  }

  static compilerFiles(files: SassEditorFile[], entryPath: string): SassProjectFile[] {
    const compilerFiles: SassProjectFile[] = [];
    for (const file of files) {
      if (file.path === entryPath) {
        continue;
      }
      compilerFiles.push({
        path: file.path,
        contents: file.contents,
        syntax: file.syntax
      });
    }
    return compilerFiles;
  }

  static entryPaths(files: SassEditorFile[], fallbackPath: string = ''): string[] {
    const entries: string[] = [];
    for (const file of files) {
      const normalized: string = SassProject.normalizePath(file.path);
      const name: string = normalized.split('/').pop() ?? normalized;
      if (name.startsWith('_') ||
        !SassProject.isStylesheetPath(normalized)) {
        continue;
      }
      entries.push(normalized);
    }
    if (entries.length === 0 && fallbackPath.length > 0) {
      entries.push(SassProject.normalizePath(fallbackPath));
    }
    return entries;
  }

  static outputFileNames(entryPaths: string[], suffix: string): string[] {
    const stems: string[] = entryPaths.map((path: string): string => {
      const normalized: string = SassProject.normalizePath(path);
      const name: string = normalized.split('/').pop() ?? normalized;
      const dotIndex: number = name.lastIndexOf('.');
      return dotIndex > 0 ? name.slice(0, dotIndex) : name;
    });
    const names: string[] = [];
    for (let index: number = 0; index < entryPaths.length; index++) {
      let stem: string = stems[index];
      let duplicateCount: number = 0;
      for (const candidate of stems) {
        if (candidate === stem) {
          duplicateCount++;
        }
      }
      if (duplicateCount > 1) {
        const normalized: string = SassProject.normalizePath(entryPaths[index]);
        const segments: string[] = normalized.split('/');
        segments.pop();
        if (segments.length > 0) {
          stem = `${segments.join('-')}-${stem}`;
        }
      }
      let outputName: string = stem + suffix;
      let counter: number = 2;
      while (names.includes(outputName)) {
        outputName = `${stem}-${counter}${suffix}`;
        counter++;
      }
      names.push(outputName);
    }
    return names;
  }

  static replaceUri(files: SassEditorFile[], path: string, uri: string): SassEditorFile[] {
    return files.map((file: SassEditorFile): SassEditorFile => {
      if (file.path !== path) {
        return file;
      }
      return {
        path: file.path,
        uri,
        contents: file.contents,
        syntax: file.syntax
      };
    });
  }

  private static uriSegments(uri: string): string[] {
    let decoded: string = uri;
    try {
      decoded = decodeURIComponent(uri);
    } catch (_) {
      decoded = uri;
    }
    const queryIndex: number = decoded.indexOf('?');
    if (queryIndex >= 0) {
      decoded = decoded.slice(0, queryIndex);
    }
    const fragmentIndex: number = decoded.indexOf('#');
    if (fragmentIndex >= 0) {
      decoded = decoded.slice(0, fragmentIndex);
    }
    const schemeIndex: number = decoded.indexOf('://');
    if (schemeIndex >= 0) {
      decoded = decoded.slice(schemeIndex + 3);
    }
    return SassProject.normalizePath(decoded).split('/').filter((part: string): boolean => part.length > 0);
  }
}
