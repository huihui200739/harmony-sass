import { CompileResult, ScssLite } from '../compiler/ScssLite';

const compiler: ScssLite = new ScssLite();

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

  aboutToAppear(): void {
    this.compile();
  }

  private compile(): void {
    try {
      const compiled: CompileResult = compiler.compileWithMetadata(this.source);
      this.result = compiled.css;
      this.isSuccessful = true;
      this.statusMessage = `编译成功 · ${compiled.ruleCount} 条规则 · ${compiled.variableCount} 个变量`;
    } catch (error) {
      this.result = '';
      this.isSuccessful = false;
      this.statusMessage = '编译失败 · ' + (error as Error).message;
    }
  }

  build() {
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
  }
}
