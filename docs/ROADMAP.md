# 兼容状态

## 已实现

- [x] 原生 HarmonyOS PC 双栏编辑器界面
- [x] 官方 Dart Sass `1.101.6` 浏览器运行时
- [x] 在 ArkWeb 页面生命周期内复用官方 `sass.Compiler` 和
      `sass.AsyncCompiler`
- [x] 通过官方 `AsyncCompiler.compileStringAsync()` 实现编辑器及批量编译，
      并提供兼容的同步运行时桥接
- [x] 在超时和页面退出时主动释放废弃的异步桥接任务
- [x] 桥接官方 `sass.info`、结构化编译器版本及完整的可空弃用版本元数据
- [x] 支持 SCSS、缩进式 Sass 和 CSS 输入
- [x] 由 Dart Sass 提供完整 Sass 语言语义
- [x] 支持内置 `sass:*` 模块和 Sass `@function`
- [x] 支持展开及压缩 CSS
- [x] 支持官方 API 默认选项的 Source Map，并可选择嵌入源文件
- [x] 与官方 CLI 兼容的 CSS 和 Source Map 成对导出
- [x] 相对/绝对 Source Map 源 URL 和内嵌 Source Map 数据 URI
- [x] 对包含及不包含嵌入源文件的 Source Map 进行官方 CLI 对比
- [x] 在已加载 URL、诊断和 Source Map 中保留真实 HarmonyOS 文档 URI
- [x] 虚拟多文件项目和加载路径
- [x] 相对路径 `@use`、`@forward` 和传统 `@import`
- [x] 分部文件、目录索引、仅供导入文件和歧义错误
- [x] 官方分部文件优先歧义诊断
- [x] 官方兼容的直接文件/目录索引及 Sass/CSS 解析优先级
- [x] 结构化错误、警告、逐警告完整弃用元数据、完整源码范围、
      警告/错误 Sass 调用栈、JavaScript 运行时堆栈和 `@debug`
- [x] 按弃用 ID 或 Dart Sass 版本设置致命弃用项
- [x] 对字符集输出、ASCII/彩色诊断、详细警告、严格语法/格式错误和未经修改的
      弃用选项进行同步/异步一致性检查
- [x] 相对文件和加载路径文件的官方 `quietDeps` 行为
- [x] 虚拟项目 `NodePackageImporter`、`pkg:` URL、最近的 `node_modules`、
      package exports 条件、数组回退、通配符优先级、嵌套包依赖、
      百分号编码包路径及官方非法 URL 校验
- [x] 多入口批量 CSS 和 Source Map 导出
- [x] 官方 `quiet`、Error CSS 和批量编译 `stopOnError`
- [x] 打开、保存、另存为、保存全部、复制和快捷键工作流
- [x] 正确处理包含编码 `#` 或 `?` 的文档提供器文件名
- [x] 自动编译和已授权外部文件重新加载
- [x] 递归发现及去重，不设置应用层文件数量限制
- [x] 依赖图和受影响入口增量编译
- [x] 输入/输出目录映射及登记的 CSS/Source Map 清理
- [x] 重命名识别、忽略规则、权限恢复和休眠恢复
- [x] 大型项目文件读取和签名分批处理
- [x] 项目及编译器选项会话恢复
- [x] ArkTS 测试、官方运行时对比及未签名 HAP 构建

## 需要目标设备验证

- [ ] 在鸿蒙 PC 真机上确认递归文档提供器子 URI
- [ ] 在不同目标 PC 设备上确认文件/文件夹混合选择支持
- [ ] 在鸿蒙 PC 真机上完成长时间监视、目录权限、休眠恢复和大型项目回归

应用商店发布、发布签名和上架不属于当前项目目标。

## 当前运行环境无法完整移植

- [ ] 通过 `Options.functions` 传入宿主 JavaScript 回调
- [ ] 外部 JavaScript `Importer` 和 `FileImporter` 回调对象
- [ ] 外部 JavaScript `Logger` 回调对象
- [ ] 访问虚拟项目之外文件的文件系统 `NodePackageImporter`
- [ ] Dart Sass Embedded Protocol
- [ ] 完整 Dart Sass CLI stdin/stdout、全部 CLI 参数、CLI 监视模式和
      `--update` 目标/依赖时间戳图
- [ ] 文件系统入口 npm API（`compile()` 和 `compileAsync()`）、
      JavaScript 回调/值对象 API 及传统 JavaScript API

这些能力依赖 Node.js 文件系统/进程环境或回调对象，无法通过当前 ArkTS 到 ArkWeb
的 JSON 桥接传递。已加载到虚拟项目中的文件可以使用可移植的包解析行为。

应用已经实现已授权文件轮询、自动重新编译、独立的依赖感知监视和输出同步，但不会
将其描述为 CLI `--update`，因为 CLI 还依赖输出文件和传递依赖的时间戳。

官方浏览器构建在只提供 `data` 字符串时同样会拒绝传统 `render()` 和
`renderSync()`。
