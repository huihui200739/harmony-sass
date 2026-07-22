import { pasteboard } from '@kit.BasicServicesKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { KeyCode } from '@kit.InputKit';
import { webview } from '@kit.ArkWeb';
import {
  DartSassRuntime,
  SassCompileError,
  SassCompileRequest,
  SassCompileResponse,
  SassWarning
} from '../compiler/DartSassRuntime';
import { SassEditorFile, SassProject } from '../compiler/SassProject';

const SAMPLE_SCSS: string = `$brand: #0A7BFF;
$radius: 12px;

.card {
  padding: 20px;
  border-radius: $radius;
  background: #fff;

  .title {
    color: $brand;
    font-weight: 700;
  }

  &:hover {
    box-shadow: 0 8px 24px rgba(10, 123, 255, 0.18);
  }
}`;

const SAMPLE_FILE: SassEditorFile = {
  path: 'untitled.scss',
  uri: '',
  contents: SAMPLE_SCSS,
  syntax: 'scss'
};

@Entry
@Component
struct Index {
  @State private source: string = SAMPLE_SCSS;
  @State private result: string = '';
  @State private sourceMapText: string = '';
  @State private files: SassEditorFile[] = [SAMPLE_FILE];
  @State private activePath: string = SAMPLE_FILE.path;
  @State private syntax: string = 'scss';
  @State private outputStyle: string = 'expanded';
  @State private loadPathsText: string = '';
  @State private sourceMapEnabled: boolean = false;
  @State private autoCompile: boolean = false;
  @State private statusMessage: string = '准备就绪：输入 SCSS 后点击“编译”。';
  @State private isSuccessful: boolean = true;
  private controller: webview.WebviewController = new webview.WebviewController();
  private runtimeReady: boolean = false;
  private isCompiling: boolean = false;
  private compileTimer: number = -1;
  private fileWatchTimer: number = -1;
  private isCheckingFiles: boolean = false;
  private fileSignatures: Map<string, string> = new Map<string, string>();
  private dirtyPaths: Set<string> = new Set<string>();

  aboutToDisappear(): void {
    if (this.compileTimer >= 0) {
      clearTimeout(this.compileTimer);
      this.compileTimer = -1;
    }
    this.stopFileWatch();
  }

  private compile(): void {
    if (!this.runtimeReady) {
      this.statusMessage = '正在初始化 Dart Sass 编译器…';
      return;
    }
    if (this.isCompiling) {
      return;
    }
    this.isCompiling = true;
    this.compileWithDartSass();
  }

  private async compileWithDartSass(): Promise<void> {
    try {
      this.syncActiveSource();
      const request: SassCompileRequest = {
        source: this.source,
        entryPath: this.activePath,
        files: SassProject.compilerFiles(this.files, this.activePath),
        loadPaths: this.loadPaths(),
        syntax: this.syntax,
        style: this.outputStyle,
        sourceMap: this.sourceMapEnabled,
        sourceMapIncludeSources: true,
        charset: true,
        quietDeps: false,
        verbose: false,
        fatalDeprecations: [],
        futureDeprecations: [],
        silenceDeprecations: []
      };
      const script: string = DartSassRuntime.createProjectCompileScript(request);
      const payload: string = await this.controller.runJavaScript(script);
      const compiled: SassCompileResponse = DartSassRuntime.parseResponse(payload);
      if (compiled.ok) {
        this.result = compiled.css ?? '';
        this.sourceMapText = compiled.sourceMap ?? '';
        this.isSuccessful = true;
        this.statusMessage = this.successMessage(compiled);
      } else {
        this.sourceMapText = '';
        this.showCompileError(compiled.error, compiled.warnings ?? []);
      }
    } catch (error) {
      this.result = '';
      this.sourceMapText = '';
      this.isSuccessful = false;
      this.statusMessage = '编译失败 · ' + (error as Error).message;
    } finally {
      this.isCompiling = false;
    }
  }

  private successMessage(compiled: SassCompileResponse): string {
    const warnings: SassWarning[] = compiled.warnings ?? [];
    const debugCount: number = compiled.debugMessages?.length ?? 0;
    const loadedCount: number = compiled.loadedUrls?.length ?? 1;
    if (warnings.length === 0 && debugCount === 0) {
      return `编译成功 · Dart Sass ${compiled.version} · 已载入 ${loadedCount} 个文件`;
    }
    if (warnings.length > 0) {
      return `编译成功 · ${warnings.length} 条警告 · ${warnings[0].message}`;
    }
    return `编译成功 · ${debugCount} 条调试信息 · ${compiled.debugMessages?.[0].message}`;
  }

  private showCompileError(error: SassCompileError | undefined, warnings: SassWarning[]): void {
    this.isSuccessful = false;
    if (error === undefined) {
      this.result = '';
      this.statusMessage = '编译失败 · Dart Sass 未返回错误详情。';
      return;
    }
    this.result = error.formatted;
    const location: string = error.line > 0
      ? `（第 ${error.line} 行，第 ${error.column} 列）`
      : '';
    const warningText: string = warnings.length > 0 ? ` · ${warnings.length} 条警告` : '';
    this.statusMessage = `编译失败 ${location}· ${error.message}${warningText}`;
  }

  private loadPaths(): string[] {
    return this.loadPathsText.split(',')
      .map((path: string): string => SassProject.normalizePath(path.trim()))
      .filter((path: string): boolean => path.length > 0);
  }

  private scheduleCompile(): void {
    if (!this.autoCompile || !this.runtimeReady) {
      return;
    }
    if (this.compileTimer >= 0) {
      clearTimeout(this.compileTimer);
    }
    this.compileTimer = setTimeout((): void => {
      this.compileTimer = -1;
      this.compile();
    }, 350);
  }

  private startFileWatch(): void {
    if (!this.autoCompile || this.fileWatchTimer >= 0) {
      return;
    }
    this.fileWatchTimer = setInterval((): void => {
      this.checkExternalFiles();
    }, 1200);
    this.checkExternalFiles();
  }

  private stopFileWatch(): void {
    if (this.fileWatchTimer >= 0) {
      clearInterval(this.fileWatchTimer);
      this.fileWatchTimer = -1;
    }
  }

  private async fileSignature(uri: string): Promise<string> {
    try {
      const stat: fileIo.Stat = await fileIo.stat(uri);
      return `${stat.mtime}:${stat.size}`;
    } catch (_) {
      return '';
    }
  }

  private async rememberFileSignatures(): Promise<void> {
    for (const file of this.files) {
      if (file.uri.length === 0) {
        continue;
      }
      try {
        const signature: string = await this.fileSignature(file.uri);
        if (signature.length > 0) {
          this.fileSignatures.set(file.uri, signature);
        }
      } catch (_) {
      }
    }
  }

  private async refreshFileSignature(uri: string): Promise<void> {
    if (uri.length === 0) {
      return;
    }
    try {
      const signature: string = await this.fileSignature(uri);
      if (signature.length > 0) {
        this.fileSignatures.set(uri, signature);
      } else {
        this.fileSignatures.delete(uri);
      }
    } catch (_) {
      this.fileSignatures.delete(uri);
    }
  }

  private async checkExternalFiles(): Promise<void> {
    if (!this.autoCompile || this.isCheckingFiles) {
      return;
    }
    this.isCheckingFiles = true;
    const changedPaths: string[] = [];
    const conflictPaths: string[] = [];
    try {
      const observedFiles: SassEditorFile[] = this.files.slice();
      for (const file of observedFiles) {
        if (file.uri.length === 0) {
          continue;
        }
        try {
          const signature: string = await this.fileSignature(file.uri);
          if (signature.length === 0) {
            continue;
          }
          const previous: string | undefined = this.fileSignatures.get(file.uri);
          this.fileSignatures.set(file.uri, signature);
          if (previous === undefined || previous === signature) {
            continue;
          }
          if (this.dirtyPaths.has(file.path)) {
            conflictPaths.push(file.path);
            continue;
          }
          const contents: string = await fileIo.readText(file.uri);
          this.files = SassProject.updateContents(this.files, file.path, contents);
          if (file.path === this.activePath) {
            this.source = contents;
          }
          changedPaths.push(file.path);
        } catch (_) {
        }
      }
    } finally {
      this.isCheckingFiles = false;
    }

    if (conflictPaths.length > 0) {
      this.isSuccessful = false;
      this.statusMessage = `检测到外部修改冲突 · ${conflictPaths[0]} 尚未保存`;
      return;
    }
    if (changedPaths.length > 0) {
      this.isSuccessful = true;
      this.statusMessage = `已重新载入外部修改 · ${changedPaths.length} 个文件`;
      this.scheduleCompile();
    }
  }

  private syncActiveSource(): void {
    this.files = SassProject.updateContents(this.files, this.activePath, this.source);
  }

  private activeFileIndex(): number {
    for (let index: number = 0; index < this.files.length; index++) {
      if (this.files[index].path === this.activePath) {
        return index;
      }
    }
    return 0;
  }

  private activeFile(): SassEditorFile {
    const index: number = this.activeFileIndex();
    return this.files[index] ?? SAMPLE_FILE;
  }

  private fileOptions(): SelectOption[] {
    return this.files.map((file: SassEditorFile): SelectOption => ({ value: file.path }));
  }

  private selectFile(index: number): void {
    if (index < 0 || index >= this.files.length) {
      return;
    }
    this.syncActiveSource();
    const file: SassEditorFile = this.files[index];
    this.activePath = file.path;
    this.source = file.contents;
    this.syntax = file.syntax;
    this.statusMessage = `当前入口 · ${file.path}`;
    this.isSuccessful = true;
    this.scheduleCompile();
  }

  private async openSource(): Promise<void> {
    try {
      const uris: string[] = await this.selectDocuments(1);
      if (uris.length === 0) {
        return;
      }
      const contents: string = await fileIo.readText(uris[0]);
      const path: string = SassProject.fileNameFromUri(uris[0]);
      const file: SassEditorFile = {
        path,
        uri: uris[0],
        contents,
        syntax: SassProject.syntaxForPath(path)
      };
      this.files = [file];
      this.activePath = file.path;
      this.source = file.contents;
      this.syntax = file.syntax;
      this.result = '';
      this.sourceMapText = '';
      this.dirtyPaths.clear();
      this.fileSignatures.clear();
      await this.rememberFileSignatures();
      this.statusMessage = `已打开 · ${file.path}`;
      this.isSuccessful = true;
      this.scheduleCompile();
    } catch (error) {
      this.showActionError('打开失败', error);
    }
  }

  private async addProjectFiles(): Promise<void> {
    try {
      const uris: string[] = await this.selectDocuments(500);
      if (uris.length === 0) {
        return;
      }
      this.syncActiveSource();
      const dirtyUris: Set<string> = new Set<string>();
      const dirtyVirtualPaths: Set<string> = new Set<string>();
      for (const file of this.files) {
        if (!this.dirtyPaths.has(file.path)) {
          continue;
        }
        if (file.uri.length > 0) {
          dirtyUris.add(file.uri);
        } else {
          dirtyVirtualPaths.add(file.path);
        }
      }
      const paths: string[] = SassProject.deriveVirtualPaths(uris);
      const incoming: SassEditorFile[] = [];
      for (let index: number = 0; index < uris.length; index++) {
        const contents: string = await fileIo.readText(uris[index]);
        incoming.push({
          path: paths[index],
          uri: uris[index],
          contents,
          syntax: SassProject.syntaxForPath(paths[index])
        });
      }
      const activeUri: string = this.activeFile().uri;
      this.files = SassProject.rebaseUriFiles(SassProject.mergeFiles(this.files, incoming));
      const rebasedDirtyPaths: Set<string> = new Set<string>();
      for (const file of this.files) {
        if ((file.uri.length > 0 && dirtyUris.has(file.uri)) ||
          (file.uri.length === 0 && dirtyVirtualPaths.has(file.path))) {
          rebasedDirtyPaths.add(file.path);
        }
      }
      this.dirtyPaths = rebasedDirtyPaths;
      if (activeUri.length > 0) {
        for (const file of this.files) {
          if (file.uri === activeUri) {
            this.activePath = file.path;
            this.source = file.contents;
            this.syntax = file.syntax;
            break;
          }
        }
      }
      this.statusMessage = `已载入项目 · 共 ${this.files.length} 个 Sass/CSS 文件`;
      this.isSuccessful = true;
      await this.rememberFileSignatures();
      this.scheduleCompile();
    } catch (error) {
      this.showActionError('载入项目失败', error);
    }
  }

  private async selectDocuments(maxSelectNumber: number): Promise<string[]> {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      throw new Error('无法获取当前窗口上下文。');
    }
    const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
    const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
    options.fileSuffixFilters = ['Sass/CSS|.scss,.sass,.css'];
    options.maxSelectNumber = maxSelectNumber;
    return await documentPicker.select(options);
  }

  private async saveSource(forcePicker: boolean = false): Promise<void> {
    try {
      this.syncActiveSource();
      if (forcePicker) {
        const previousUri: string = this.activeFile().uri;
        const uri: string = await this.chooseSaveUri(this.activePath, 'Sass/CSS|.scss,.sass,.css');
        if (uri.length === 0) {
          return;
        }
        this.files = SassProject.replaceUri(this.files, this.activePath, uri);
        await this.writeText(uri, this.source);
        this.dirtyPaths.delete(this.activePath);
        if (previousUri.length > 0 && previousUri !== uri) {
          this.fileSignatures.delete(previousUri);
        }
        await this.refreshFileSignature(uri);
        this.statusMessage = `已另存为 · ${this.activePath}`;
        this.isSuccessful = true;
        return;
      }

      let activeUri: string = this.activeFile().uri;
      if (activeUri.length === 0) {
        activeUri = await this.chooseSaveUri(this.activePath, 'Sass/CSS|.scss,.sass,.css');
        if (activeUri.length === 0) {
          return;
        }
        this.files = SassProject.replaceUri(this.files, this.activePath, activeUri);
      }

      let savedCount: number = 0;
      for (const file of this.files) {
        if (file.uri.length === 0 ||
          (file.path !== this.activePath && !this.dirtyPaths.has(file.path))) {
          continue;
        }
        await this.writeText(file.uri, file.contents);
        this.dirtyPaths.delete(file.path);
        await this.refreshFileSignature(file.uri);
        savedCount++;
      }
      this.statusMessage = savedCount > 1
        ? `已保存全部修改 · ${savedCount} 个文件`
        : `已保存 · ${this.activePath}`;
      this.isSuccessful = true;
    } catch (error) {
      this.showActionError('保存失败', error);
    }
  }

  private async exportCss(): Promise<void> {
    if (this.result.length === 0 || !this.isSuccessful) {
      this.statusMessage = '没有可导出的 CSS，请先成功编译。';
      this.isSuccessful = false;
      return;
    }
    try {
      const uri: string = await this.chooseSaveUri(this.outputFileName('.css'), 'CSS|.css');
      if (uri.length === 0) {
        return;
      }
      await this.writeText(uri, this.result);
      this.statusMessage = `CSS 已导出 · ${this.outputFileName('.css')}`;
      this.isSuccessful = true;
    } catch (error) {
      this.showActionError('导出 CSS 失败', error);
    }
  }

  private async exportSourceMap(): Promise<void> {
    if (!this.sourceMapEnabled || this.sourceMapText.length === 0) {
      this.statusMessage = '没有可导出的 Source Map，请启用后重新编译。';
      this.isSuccessful = false;
      return;
    }
    try {
      const uri: string = await this.chooseSaveUri(this.outputFileName('.css.map'), 'Source Map|.map');
      if (uri.length === 0) {
        return;
      }
      await this.writeText(uri, this.sourceMapText);
      this.statusMessage = `Source Map 已导出 · ${this.outputFileName('.css.map')}`;
      this.isSuccessful = true;
    } catch (error) {
      this.showActionError('导出 Source Map 失败', error);
    }
  }

  private async chooseSaveUri(fileName: string, suffixChoice: string): Promise<string> {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      throw new Error('无法获取当前窗口上下文。');
    }
    const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
    const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
    options.newFileNames = [fileName];
    options.fileSuffixChoices = [suffixChoice];
    const uris: string[] = await documentPicker.save(options);
    return uris.length > 0 ? uris[0] : '';
  }

  private async writeText(uri: string, text: string): Promise<void> {
    let file: fileIo.File | undefined = undefined;
    try {
      file = await fileIo.open(
        uri,
        fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC
      );
      await fileIo.write(file.fd, text);
    } catch (error) {
      throw new Error((error as Error).message);
    } finally {
      if (file !== undefined) {
        try {
          await fileIo.close(file);
        } catch (_) {
        }
      }
    }
  }

  private async copyCss(): Promise<void> {
    if (this.result.length === 0 || !this.isSuccessful) {
      this.statusMessage = '没有可复制的 CSS，请先成功编译。';
      this.isSuccessful = false;
      return;
    }
    try {
      const data: pasteboard.PasteData = pasteboard.createData(
        pasteboard.MIMETYPE_TEXT_PLAIN,
        this.result
      );
      await pasteboard.getSystemPasteboard().setData(data);
      this.statusMessage = 'CSS 已复制到剪贴板。';
      this.isSuccessful = true;
    } catch (error) {
      this.showActionError('复制失败', error);
    }
  }

  private outputFileName(suffix: string): string {
    const name: string = this.activePath.split('/').pop() ?? 'output.scss';
    const dotIndex: number = name.lastIndexOf('.');
    const stem: string = dotIndex > 0 ? name.slice(0, dotIndex) : name;
    return stem + suffix;
  }

  private loadSample(): void {
    this.files = [SAMPLE_FILE];
    this.activePath = SAMPLE_FILE.path;
    this.source = SAMPLE_SCSS;
    this.syntax = 'scss';
    this.result = '';
    this.sourceMapText = '';
    this.dirtyPaths.clear();
    this.fileSignatures.clear();
    this.statusMessage = '已载入示例。';
    this.isSuccessful = true;
    this.compile();
  }

  private showActionError(action: string, error: Object): void {
    this.isSuccessful = false;
    this.statusMessage = `${action} · ${(error as Error).message}`;
  }

  private handleKeyEvent(event: KeyEvent): boolean {
    if (event.type !== KeyType.Down ||
      event.getModifierKeyState === undefined ||
      !event.getModifierKeyState(['ctrl'])) {
      return false;
    }
    if (event.keyCode === KeyCode.KEYCODE_O) {
      this.openSource();
      return true;
    }
    if (event.keyCode === KeyCode.KEYCODE_S) {
      const saveAs: boolean = event.getModifierKeyState(['shift']);
      this.saveSource(saveAs);
      return true;
    }
    if (event.keyCode === KeyCode.KEYCODE_ENTER) {
      this.compile();
      return true;
    }
    return false;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Row() {
          Column({ space: 4 }) {
            Text('Harmony Sass').fontSize(26).fontWeight(FontWeight.Bold).fontColor('#152033')
            Text('鸿蒙 PC 原生 Sass 编译器 · Dart Sass 1.101.3').fontSize(14).fontColor('#667085')
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Button('载入示例')
            .onClick((): void => this.loadSample())
            .backgroundColor('#EDF4FF').fontColor('#0A5FD0').margin({ right: 12 })
          Button('编译 CSS').onClick((): void => this.compile()).backgroundColor('#0A7BFF')
        }
        .width('100%').padding({ left: 28, right: 28, top: 22, bottom: 12 })

        Row({ space: 8 }) {
          Button('打开').onClick((): void => { this.openSource(); }).height(34)
          Button('添加项目文件').onClick((): void => { this.addProjectFiles(); }).height(34)
          Select(this.fileOptions())
            .selected(this.activeFileIndex())
            .value(this.activePath)
            .onSelect((index: number): void => this.selectFile(index))
            .width(190).height(34)
          Button('保存').onClick((): void => { this.saveSource(); }).height(34)
          Button('另存为').onClick((): void => { this.saveSource(true); }).height(34)
          Blank().layoutWeight(1)
          Button('复制 CSS').onClick((): void => { this.copyCss(); }).height(34)
          Button('导出 CSS').onClick((): void => { this.exportCss(); }).height(34)
          Button('导出 Map').onClick((): void => { this.exportSourceMap(); }).height(34)
        }
        .width('100%').padding({ left: 28, right: 28, bottom: 8 })

        Row({ space: 10 }) {
          Text('语法').fontSize(13).fontColor('#667085')
          Select([{ value: 'SCSS' }, { value: 'Sass' }, { value: 'CSS' }])
            .selected(this.syntax === 'indented' ? 1 : this.syntax === 'css' ? 2 : 0)
            .onSelect((index: number): void => {
              this.syntax = index === 1 ? 'indented' : index === 2 ? 'css' : 'scss';
              this.scheduleCompile();
            })
            .width(92).height(32)
          Text('输出').fontSize(13).fontColor('#667085')
          Select([{ value: '展开' }, { value: '压缩' }])
            .selected(this.outputStyle === 'compressed' ? 1 : 0)
            .onSelect((index: number): void => {
              this.outputStyle = index === 1 ? 'compressed' : 'expanded';
              this.scheduleCompile();
            })
            .width(92).height(32)
          TextInput({ text: this.loadPathsText, placeholder: '载入路径，用逗号分隔' })
            .onChange((value: string): void => {
              this.loadPathsText = value;
              this.scheduleCompile();
            })
            .width(210).height(32).fontSize(13)
          Text('Source Map').fontSize(13).fontColor('#667085')
          Toggle({ type: ToggleType.Switch, isOn: this.sourceMapEnabled })
            .onChange((isOn: boolean): void => {
              this.sourceMapEnabled = isOn;
              this.scheduleCompile();
            })
          Text('自动编译').fontSize(13).fontColor('#667085')
          Toggle({ type: ToggleType.Switch, isOn: this.autoCompile })
            .onChange((isOn: boolean): void => {
              this.autoCompile = isOn;
              if (isOn) {
                this.startFileWatch();
                this.scheduleCompile();
              } else {
                this.stopFileWatch();
              }
            })
          Blank().layoutWeight(1)
          Text(`${this.files.length} 个文件`).fontSize(13).fontColor('#667085')
        }
        .width('100%').padding({ left: 28, right: 28, bottom: 10 })

        Text(this.statusMessage).width('100%').padding({ left: 28, right: 28, bottom: 12 })
          .fontSize(13).fontColor(this.isSuccessful ? '#16803C' : '#B42318')
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })

        Row({ space: 16 }) {
          Column({ space: 10 }) {
            Text(`SCSS 输入 · ${this.activePath}`).fontWeight(FontWeight.Medium).fontColor('#344054')
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            TextArea({ text: this.source, placeholder: '在此粘贴 Sass/SCSS/CSS…' })
              .layoutWeight(1).width('100%').fontSize(15).fontFamily('monospace')
              .backgroundColor('#FFFFFF').border({ width: 1, color: '#D0D5DD', radius: 8 })
              .onChange((value: string): void => {
                this.source = value;
                this.syncActiveSource();
                this.dirtyPaths.add(this.activePath);
                this.scheduleCompile();
              })
          }.alignItems(HorizontalAlign.Start).layoutWeight(1).height('100%')

          Column({ space: 10 }) {
            Text(this.isSuccessful ? 'CSS 输出' : '编译错误')
              .fontWeight(FontWeight.Medium).fontColor('#344054')
            TextArea({ text: this.result, placeholder: '编译结果将显示在这里' })
              .layoutWeight(1).width('100%').fontSize(15).fontFamily('monospace')
              .backgroundColor('#F9FAFB').border({ width: 1, color: '#D0D5DD', radius: 8 })
              .enabled(false)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1).height('100%')
        }
        .layoutWeight(1).width('100%').padding({ left: 28, right: 28, bottom: 24 })
      }
      .width('100%').height('100%').backgroundColor('#F4F7FB')

      Web({
        src: $rawfile('sass-runtime.html'),
        controller: this.controller
      })
        .javaScriptAccess(true)
        .width(1)
        .height(1)
        .opacity(0)
        .enabled(false)
        .onPageEnd((): void => {
          this.runtimeReady = true;
          this.compile();
        })
    }
    .width('100%').height('100%').backgroundColor('#F4F7FB')
    .focusable(true)
    .onKeyEvent((event: KeyEvent): boolean => this.handleKeyEvent(event))
  }
}
