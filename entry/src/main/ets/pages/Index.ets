import { webview } from '@kit.ArkWeb';
import {
  DartSassRuntime,
  SassCompileError,
  SassCompileResponse
} from '../compiler/DartSassRuntime';

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

@Entry
@Component
struct Index {
  @State private source: string = SAMPLE_SCSS;
  @State private result: string = '';
  @State private statusMessage: string = '准备就绪：输入 SCSS 后点击“编译”。';
  @State private isSuccessful: boolean = true;
  private controller: webview.WebviewController = new webview.WebviewController();
  private runtimeReady: boolean = false;
  private isCompiling: boolean = false;

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
      const script: string = DartSassRuntime.createCompileScript(this.source);
      const payload: string = await this.controller.runJavaScript(script);
      const compiled: SassCompileResponse = DartSassRuntime.parseResponse(payload);
      if (compiled.ok) {
        this.result = compiled.css ?? '';
        this.isSuccessful = true;
        this.statusMessage = `编译成功 · Dart Sass ${compiled.version}`;
      } else {
        this.showCompileError(compiled.error);
      }
    } catch (error) {
      this.result = '';
      this.isSuccessful = false;
      this.statusMessage = '编译失败 · ' + (error as Error).message;
    } finally {
      this.isCompiling = false;
    }
  }

  private showCompileError(error: SassCompileError | undefined): void {
    this.result = '';
    this.isSuccessful = false;
    if (error === undefined) {
      this.statusMessage = '编译失败 · Dart Sass 未返回错误详情。';
      return;
    }
    const location: string = error.line > 0
      ? `（第 ${error.line} 行，第 ${error.column} 列）`
      : '';
    this.statusMessage = `编译失败 ${location}· ${error.message}`;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Row() {
          Column({ space: 4 }) {
            Text('Harmony Sass').fontSize(26).fontWeight(FontWeight.Bold).fontColor('#152033')
            Text('鸿蒙 PC 原生 SCSS 编译器 · MVP').fontSize(14).fontColor('#667085')
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Button('载入示例')
            .onClick((): void => { this.source = SAMPLE_SCSS; this.compile(); })
            .backgroundColor('#EDF4FF').fontColor('#0A5FD0').margin({ right: 12 })
          Button('编译 CSS').onClick((): void => this.compile()).backgroundColor('#0A7BFF')
        }
        .width('100%').padding({ left: 28, right: 28, top: 22, bottom: 18 })

        Text(this.statusMessage).width('100%').padding({ left: 28, right: 28, bottom: 12 })
          .fontSize(13).fontColor(this.isSuccessful ? '#16803C' : '#B42318')

        Row({ space: 16 }) {
          Column({ space: 10 }) {
            Text('SCSS 输入').fontWeight(FontWeight.Medium).fontColor('#344054')
            TextArea({ text: this.source, placeholder: '在此粘贴 SCSS…' })
              .layoutWeight(1).width('100%').fontSize(15).fontFamily('monospace')
              .backgroundColor('#FFFFFF').border({ width: 1, color: '#D0D5DD', radius: 10 })
              .onChange((value: string): void => { this.source = value; })
          }.alignItems(HorizontalAlign.Start).layoutWeight(1).height('100%')

          Column({ space: 10 }) {
            Text('CSS 输出').fontWeight(FontWeight.Medium).fontColor('#344054')
            TextArea({ text: this.result, placeholder: '编译结果将显示在这里' })
              .layoutWeight(1).width('100%').fontSize(15).fontFamily('monospace')
              .backgroundColor('#F9FAFB').border({ width: 1, color: '#D0D5DD', radius: 10 })
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
  }
}
