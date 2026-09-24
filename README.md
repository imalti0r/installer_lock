# Installer Lock - HyperOS 安装器锁定 Magisk 模块

## 概述

将 HyperOS 自带的系统包安装器 (PackageInstaller) 锁定为自定义版本 (InstallerX-Revived)，防止重启后系统还原原版安装器。

- **目标包名**: `com.miui.packageinstaller`
- **源APK**: `InstallerX-Revived-online-26.05.01_clone.apk`
- **创建日期**: 2026-09-24

## 文件清单

| 文件 | 用途 |
|------|------|
| `installer_lock_hyperos.zip` | **可刷入的 Magisk 模块 zip**（最终产物） |
| `custom_installer.apk` | 自定义安装器 APK（包名已改为 com.miui.packageinstaller） |
| `module.prop` | Magisk 模块元数据 |
| `customize.sh` | 安装时脚本：自动查找系统安装器路径并创建 systemless 覆盖 |
| `post-fs-data.sh` | 开机早期脚本：bind mount 备份机制 |
| `service.sh` | 开机后脚本：pm install 兜底重装 |
| `install.sh` | Magisk 安装框架脚本 |
| `META-INF/com/google/android/update-binary` | Magisk 模块安装器入口 |
| `META-INF/com/google/android/updater-script` | 空占位文件 |
| `agent.md` | 任务Agent状态文件（跨会话进度持久化） |
| `README.md` | 本说明文件 |

## 工作原理（三层保障）

### 第一层：Systemless 覆盖（主机制，不依赖 Xposed）
`customize.sh` 在安装时通过 `pm path` + 常见路径 + `find` 三重查找定位系统安装器 APK，将自定义 APK 复制到模块的 `system/` 对应路径。Magisk 在每次开机时自动覆盖，包管理器读到的就是自定义版本。**文件级替换，完全绕过签名校验。**

### 第二层：post-fs-data 绑定挂载（备份）
`post-fs-data.sh` 在包管理器初始化前执行 `mount --bind`，即使 systemless 覆盖因 SELinux 等原因失效也能绑定挂载。

### 第三层：service.sh pm install（兜底，依赖 Xposed）
开机完成后等待 10 秒，通过 `pm install -r -d` 重新安装。此层需要 Xposed 核心破解禁用签名校验才能成功，但即使失败也不影响前两层。

## 日志功能

所有脚本运行日志统一写入 `/data/adb/modules/installer_lock/module.log`，格式：`[时间戳] [级别] 消息`

- **INFO**: 正常流程信息
- **WARN**: 非致命问题
- **ERROR**: 错误
- **STEP**: 关键步骤标记

查看日志：`cat /data/adb/modules/installer_lock/module.log`

## 安装方法

1. 将 `installer_lock_hyperos.zip` 传到手机
2. 打开 Magisk → 模块 → 从存储安装 → 选择该 zip
3. 重启
