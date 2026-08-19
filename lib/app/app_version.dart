/// 应用版本号，需与 pubspec.yaml 的 version 保持同步（用于检查更新比较）。
///
/// 比较算法见 `UpdateService.compareVersions`：按点分整数比较，**不支持**
/// 语义化版本的预发布标签（`2.0.0-beta.1` 反而会被判定为高于 `2.0.0`），
/// 因此发版时请使用纯数字版本号。
const String appVersion = '2.0.4';
