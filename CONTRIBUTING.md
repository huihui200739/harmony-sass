# 贡献指南

感谢参与 Harmony Sass。

## 本地要求

- DevEco Studio（HarmonyOS 6.1.1 SDK）
- Node.js 20.19 或更高版本
- 一个鸿蒙 PC、2in1 设备或对应的模拟环境

## 提交前检查

1. 为运行时桥接逻辑增加或更新 `entry/src/test` 下的单元测试。
2. 为 Sass 行为增加 `tools/test-runtime.mjs` 中的兼容性用例。
3. 运行 `bash ./scripts/verify.sh`。
4. 不提交 `build`、`.hvigor`、`oh_modules`、`.idea` 或 `local.properties`。

## 范围

编译语义以官方 [Dart Sass](https://github.com/sass/dart-sass) 为基准，不再扩展手写
SCSS 解析器。修改运行时版本时，请同步更新 `tools/package.json`、运行时版本常量、
第三方许可文件和兼容性测试。
