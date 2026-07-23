import {
  SassBatchCompileResponse,
  SassBatchCompileResult
} from './DartSassRuntime';
import { SassEditorFile, SassProject } from './SassProject';

export interface SassFileRename {
  oldPath: string;
  newPath: string;
}

export class SassWorkspace {
  static projectPathForLoadedUrl(
    loadedUrl: string,
    files: SassEditorFile[]
  ): string {
    const decodedUrl: string = SassWorkspace.decode(loadedUrl);
    const virtualPrefix: string = 'harmony-sass:/';
    if (decodedUrl.startsWith(virtualPrefix)) {
      return SassProject.normalizePath(decodedUrl.slice(virtualPrefix.length));
    }

    for (const file of files) {
      if (file.uri.length > 0 &&
        SassWorkspace.decode(file.uri) === decodedUrl) {
        return SassProject.normalizePath(file.path);
      }
    }

    const path: string = SassWorkspace.urlPath(decodedUrl);
    let bestMatch: string = '';
    for (const file of files) {
      const normalized: string = SassProject.normalizePath(file.path);
      if ((path === normalized || path.endsWith(`/${normalized}`)) &&
        normalized.length > bestMatch.length) {
        bestMatch = normalized;
      }
    }
    return bestMatch;
  }

  static updateDependencyGraph(
    graph: Map<string, Set<string>>,
    results: SassBatchCompileResult[],
    files: SassEditorFile[]
  ): Map<string, Set<string>> {
    const updated: Map<string, Set<string>> = new Map<string, Set<string>>();
    for (const dependencyPath of graph.keys()) {
      const entries: Set<string> | undefined = graph.get(dependencyPath);
      if (entries !== undefined) {
        updated.set(dependencyPath, new Set<string>(entries));
      }
    }

    for (const result of results) {
      const entryPath: string = SassProject.normalizePath(result.entryPath);
      for (const dependencyPath of Array.from(updated.keys())) {
        const entries: Set<string> | undefined = updated.get(dependencyPath);
        if (entries === undefined) {
          continue;
        }
        entries.delete(entryPath);
        if (entries.size === 0) {
          updated.delete(dependencyPath);
        }
      }

      SassWorkspace.addDependency(updated, entryPath, entryPath);
      for (const loadedUrl of result.loadedUrls ?? []) {
        const dependencyPath: string =
          SassWorkspace.projectPathForLoadedUrl(loadedUrl, files);
        if (dependencyPath.length > 0) {
          SassWorkspace.addDependency(updated, dependencyPath, entryPath);
        }
      }
    }
    return updated;
  }

  static affectedEntryPaths(
    changedPaths: string[],
    graph: Map<string, Set<string>>,
    allEntryPaths: string[]
  ): string[] {
    if (changedPaths.length === 0 || graph.size === 0) {
      return allEntryPaths.slice();
    }

    const affected: Set<string> = new Set<string>();
    for (const path of changedPaths) {
      const entries: Set<string> | undefined =
        graph.get(SassProject.normalizePath(path));
      if (entries === undefined) {
        return allEntryPaths.slice();
      }
      for (const entryPath of entries) {
        affected.add(entryPath);
      }
    }
    return allEntryPaths.filter(
      (entryPath: string): boolean => affected.has(entryPath)
    );
  }

  static mergeBatchResponse(
    previous: Map<string, SassBatchCompileResult>,
    response: SassBatchCompileResponse,
    allEntryPaths: string[]
  ): SassBatchCompileResponse {
    for (const result of response.results) {
      previous.set(SassProject.normalizePath(result.entryPath), result);
    }
    for (const cachedPath of Array.from(previous.keys())) {
      if (!allEntryPaths.includes(cachedPath)) {
        previous.delete(cachedPath);
      }
    }
    const results: SassBatchCompileResult[] = [];
    for (const entryPath of allEntryPaths) {
      const cached: SassBatchCompileResult | undefined = previous.get(entryPath);
      if (cached !== undefined) {
        results.push(cached);
      }
    }
    return {
      ok: results.length > 0 &&
        results.length === allEntryPaths.length &&
        results.every((result: SassBatchCompileResult): boolean => result.ok),
      version: response.version,
      results
    };
  }

  static detectRenames(
    removedFiles: SassEditorFile[],
    addedFiles: SassEditorFile[]
  ): SassFileRename[] {
    const renames: SassFileRename[] = [];
    const usedNewPaths: Set<string> = new Set<string>();
    for (const removed of removedFiles) {
      for (const added of addedFiles) {
        if (usedNewPaths.has(added.path) ||
          removed.contents !== added.contents ||
          removed.syntax !== added.syntax) {
          continue;
        }
        renames.push({
          oldPath: SassProject.normalizePath(removed.path),
          newPath: SassProject.normalizePath(added.path)
        });
        usedNewPaths.add(added.path);
        break;
      }
    }
    return renames;
  }

  private static addDependency(
    graph: Map<string, Set<string>>,
    dependencyPath: string,
    entryPath: string
  ): void {
    const normalizedDependency: string =
      SassProject.normalizePath(dependencyPath);
    const normalizedEntry: string = SassProject.normalizePath(entryPath);
    let entries: Set<string> | undefined = graph.get(normalizedDependency);
    if (entries === undefined) {
      entries = new Set<string>();
      graph.set(normalizedDependency, entries);
    }
    entries.add(normalizedEntry);
  }

  private static decode(value: string): string {
    try {
      return decodeURIComponent(value);
    } catch (_) {
      return value;
    }
  }

  private static urlPath(value: string): string {
    const schemeIndex: number = value.indexOf('://');
    const withoutScheme: string = schemeIndex >= 0
      ? value.slice(schemeIndex + 3)
      : value;
    const slashIndex: number = withoutScheme.indexOf('/');
    return SassProject.normalizePath(
      slashIndex >= 0 ? withoutScheme.slice(slashIndex + 1) : withoutScheme
    );
  }
}
