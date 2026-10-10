# MuMu：去掉商店广告，同时保留拖入 APK 安装

## 一、直接照做

本工具已验证 **MuMu 6.8.2.0 下的 Android 12（SDK 32）和 Android 15，原商店均为 9.2.25（版本号 1225）**。这不代表兼容所有历史 MuMu 12 客户端；其他商店版本仍会停止。只支持普通 `.apk`。安装脚本会检查 Android 与商店版本，版本不符会停止。**不要先删除系统商店，也不要再执行旧指南的商店禁用、隐藏或删除步骤。**

### 1. 下载并解压

1. 打开 [部署包 0.1.1 下载页](https://github.com/Show-o4210/emu-ad-cleaner/releases/tag/mumu-minimal-installer-v0.1.1)。
2. 在 Assets 中下载 **`mumu-minimal-installer-0.1.1-windows.zip`**。
3. 右键 ZIP，选择“全部解压”。不要在压缩包内直接运行，也不要下载页面底部的 `Source code` 代替工具包。

0.1.1 更新了 Windows 部署脚本以支持已验证的 Android 12；安装器 APK 仍是同一份 0.1，源码与散列不变。

仓库中的 Windows 部署脚本已更新到 **0.1.2（尚未发布 Release）**，增加连接诊断与有限重试。上面的下载链接仍是已发布的 0.1.1，不包含这些新改动。0.1.2 继续使用同一份 0.1 APK。

解压后应该能看到 `Install.cmd`、`Restore.cmd` 和 `build` 文件夹。

### 2. 准备实例

1. 打开 MuMu 多开器，先备份要操作的实例。
2. 启动这个实例，等到安卓桌面出现。
3. 在 MuMu 设置中打开 **ADB 调试 → 本地连接**。Root 开关可以保持关闭。
4. 如果之前按旧指南清理过商店，先看下方“先前已经清理过商店”。

### 3. 安装工具

1. 双击解压目录中的 **`Install.cmd`**。
2. 窗口会列出已启动实例的编号和名称。输入要操作的实例编号，按回车；不要直接照抄别人机器的编号。
3. 如果没有自动找到 MuMu，输入 MuMu 安装目录，例如 `D:\Program Files\Netease\MuMu`。该目录内应有 `nx_main` 文件夹。
4. 等到窗口显示 **“最小安装器已安装”**。
5. 重启刚才选择的实例。

若窗口显示“操作停止”，按提示处理，不要继续执行删除商店的旧命令。

### 4. 验证

1. 找一个普通 `.apk` 文件，从资源管理器拖入该 MuMu 窗口。
2. 应看到安装提示，随后应用出现在桌面或应用列表中。
3. 商店图标、大幅商店广告和“每日新发现”小部件应不再出现。
4. **不要再禁用、隐藏或删除 `com.mumu.store`**：这个包名现在承载的是最小安装器。

顶部推广搜索栏属于 MuMu 定制桌面的独立模块；本工具不保证它或 Windows 启动广告永久消失。APKS、XAPK、OBB 暂不支持，会明确报错。

### 5. 恢复原商店

1. 保持实例启动，并打开 ADB 本地连接。
2. 双击同一目录中的 **`Restore.cmd`**。
3. 输入该实例编号，等到 **“原商店已恢复”**。
4. 重启实例。

恢复可能重置商店自己的数据。本次实验中，恢复没有删除已安装的测试时钟。

## 二、先前已经清理过商店

### 只做过用户卸载或禁用，没有隐藏或删除系统 APK

直接运行 `Install.cmd`。脚本会先恢复当前用户的商店安装/启用状态，再安装替代包。

### 用 Root 隐藏过商店

先恢复隐藏状态。打开 MuMu 安装目录下的 `nx_main` 文件夹，在地址栏输入 `powershell` 并回车：

```powershell
.\MuMuManager.exe info -v all
```

找到目标实例的 `adb_port`。下面以 `16384` 为例，换成自己的端口：

```powershell
$s = '127.0.0.1:16384'
.\adb.exe connect $s
.\adb.exe -s $s shell "su -c 'pm unhide com.mumu.store'"
.\adb.exe -s $s shell cmd package install-existing --user 0 com.mumu.store
.\adb.exe -s $s shell pm default-state --user 0 com.mumu.store
```

这条 `su` 命令需要当初隐藏商店时使用的 Root 权限。若报权限错误，先停止，备份实例后修复或改用新实例；不要为了恢复拖拽继续删系统目录。恢复后再运行 `Install.cmd`。

### 已经删除 `/system/priv-app/com.mumu.store`

先备份原实例。使用 MuMu 的修复功能恢复原系统包，或在多开器中新建实例，再执行第一节。不要把这个工具当成一个普通用户应用直接安装到“系统商店已经消失”的环境中。

## 三、遇到问题就按这里处理

| 窗口提示 / 现象 | 操作 |
|---|---|
| 模拟器本地端口不可达 / ADB 连接失败 | 打开 ADB 调试的“本地连接”；启动目标实例并等待安卓桌面，再运行工具 |
| ADB Server 连接异常 / 设备 offline | 等待实例就绪后重试；若持续失败，保存窗口中的 ADB 路径、版本、目标端口、命令阶段、退出码和原始输出 |
| 设备未授权 / 输出或命令错误 | 保存窗口输出反馈；工具不会用无限重试掩盖问题 |
| 实例身份、进程或 ADB 地址已变化 | 重新运行并核对实例编号；工具不会自动改选其他实例或端口 |
| 修改命令报错，随后显示当前商店状态 | 修改可能已生效；先保存输出并核对状态，不要连续盲点安装或恢复 |
| 没有找到 MuMu | 输入包含 `nx_main` 文件夹的安装目录 |
| 版本不支持 | 不要绕过检查；暂时使用下面的 ADB 安装命令 |
| APK 校验失败 / 缺少 APK | 重新下载完整工具 ZIP 并解压；不要混用源码包或其他版本的 APK |
| 原系统 APK 不完整 | 备份实例，再修复或新建实例 |
| 安装了工具但拖入无反应 | 确认操作的是同一实例，重启后重试；不要禁用 `com.mumu.store` |
| 拖入 APKS / XAPK 失败 | 当前版本只支持普通 APK；不要把文件改后缀伪装成 APK |
| 更新 MuMu 后广告或商店恢复 | 更新可能覆盖替代包；先重新检查版本，兼容后再运行工具 |

0.1.2 会对明确的临时连接故障最多尝试 3 次，并在重试前重新检查同一实例的身份、进程与端口。安装、启用商店、回退系统更新只执行一次；报错后只读核对状态并停止。商店版本、签名条件或目录不符时不会反复尝试。

### 临时用 ADB 安装应用

在 `nx_main` 文件夹打开 PowerShell，端口和 APK 路径换成自己的：

```powershell
$s = '127.0.0.1:16384'
.\adb.exe connect $s
.\adb.exe -s $s install --no-incremental -r 'C:\Users\你的用户名\Downloads\应用.apk'
```

旧版 ADB 若不认识 `--no-incremental`，去掉该选项。这个方法可以临时安装应用，不会恢复原生拖拽。每个多开实例要单独操作。

---

**到这里已经完成操作。下面是原理、验证记录与开发者构建方法，不影响日常使用。**

## 四、为什么原来会坏，为什么这个工具能保留拖拽

在本次 Android 12 和 Android 15 环境中，原生拖拽都依赖以下服务入口：

```text
Windows 拖入 APK
  → MuMu /apps 接口（origin=shell）
  → com.mumu.store/.install.InstallLocalApkService
  → 原商店安装逻辑
  → Android 包安装
```

整包禁用或删除 `com.mumu.store` 会让宿主指定的服务消失。失败日志为：

```text
Unable to start service Intent { cmp=com.mumu.store/.install.InstallLocalApkService (has extras) } U=0: not found
```

旧文档“删除商店不影响从电脑拖入 APK”的说法已纠正；Android 12 的独立实测见 [图文验证记录](MuMu-Android12验证记录.md)，不能据此倒推所有历史客户端版本。

本工具是独立编写的兼容服务，不是对原商店 APK 的广告代码打补丁。它保留包名、服务名和原 Binder 接口，接收 `apk_path`，或 `mount_name` + `apk_name`，然后在 Android 内完成共享目录挂载和 `pm install`。

它没有原商店的广告小部件、商店界面、初始化、渠道推荐、联网与统计代码，因此原商店功能也不可用。桌面搜索广告属于定制 `app.lawnchair` 的另外一部分，不能把“安装了 Lawnchair”直接当成“桌面没有广告”。

安装以系统商店的**更新包**形式进入 `/data/app`，不改 Windows 宿主程序，也不删除 `/system` 的原 APK。原系统包、平台签名和 UID 1000 是这个方案成立的条件。原 APK 和原型的证书 SHA-256 均为：

```text
c8a2e9bccf597c2fb6dc66bee293fc13f2fc47ec77bc6b2b0d52c11f51192ab8
```

该证书与 [AOSP 公开测试平台证书](https://raw.githubusercontent.com/aosp-mirror/platform_build/master/target/product/security/platform.x509.pem) 一致。公开测试签名材料的用途参见 [AOSP 签名说明](https://source.android.com/docs/core/ota/sign_builds)。Android 15 对新加入平台共享 UID 的非系统包还有额外限制，因此“随便换一个包名安装”不能替代本方案。[共享 UID 规则](https://source.android.com/docs/core/permissions/platform-signed-shared-uid-allowlist)

运行时安装代码不调用宿主 ADB；ADB 用于部署和排障。**关闭 MuMu ADB 开关后的实际拖拽尚未单独测试**，不要据此承诺所有版本都能关闭它。

## 五、验证记录（2026-10-04 / 2026-10-05）

Android 15 使用新建隔离实例，Android 12 使用用户启动的独立实例，两者 Root 开关均关闭。Android 12 的过程截图、日志摘录和包状态见 [图文验证记录](MuMu-Android12验证记录.md)。

| 检查 | 结果 |
|---|---|
| 原商店启用 → 禁用 → 恢复后的真实拖拽 | 成功 → 失败 → 成功 |
| 原型完整签名、APK 对齐 | 通过 |
| 原型作为系统包更新安装、UID 1000、安装权限 | 通过 |
| 用户真实拖入 `org.fossify.clock_10.apk` | 用户确认成功；Android 与宿主日志均确认成功 |
| 动态共享目录挂载 | 通过 |
| 重启后安装 | 通过 |
| 损坏 APK、非法挂载名 | 明确拒绝 |
| 回退原商店 9.2.25 | 通过；测试时钟仍保留 |
| 商店广告小部件注册消失 | 通过 |
| Windows PowerShell 5.1 安装、检查、恢复、重装入口 | 通过 |
| 旧禁用 / 用户卸载状态自动恢复后安装 | 通过 |
| Android 12 原商店启用 / 禁用 / 恢复后的真实拖拽 | 成功 / 失败 / 成功 |
| Android 12 最小安装器真实拖拽、重启后真实拖拽、回退原商店 | 通过；附图文记录 |
| 其他历史客户端、次用户、关闭 ADB 开关、搜索广告永久清除 | 未验证 |

原型 APK 大小为 16,787 字节，SHA-256：

```text
a03ba9b5286402b4db0df9796a3bcbb82785cd49ac92f5c2ad4638235c63b43a
```

机器可读记录：[verification.json](tools/mumu-minimal-installer/verification.json)。问题来源：[issue #1](https://github.com/Show-o4210/emu-ad-cleaner/issues/1)。

## 六、开发者构建

### Windows ADB 兼容性（部署脚本 0.1.2）

[issue #2](https://github.com/Show-o4210/emu-ad-cleaner/issues/2) 中的 TCP 报错目前无法复现。不同 ADB 客户端共存、其他程序重启 Server 是潜在风险，**尚未证实为该 issue 的根因**，也不能据此断定游戏闪退由本工具导致。

审查确认旧脚本只连接一次，失败时丢失原始 ADB 输出；Windows PowerShell 5.1 还会因原生命令的 stderr 提示提前抛出异常。0.1.2 保留 MuMu 自带 ADB、实例选择和原商店安全检查，按退出码判断原生命令，显示客户端版本和连接状态，只对明确的连接中断重复连接或查询。查询恢复与连接检查各有最多 3 次的上限，不设无限循环。

脚本不执行 `adb kill-server`、不结束其他进程、不更换 ADB，也不针对 MAA 做特殊判断。不过，ADB 客户端自身存在 Server 协议版本不匹配时重启 Server 的行为；这不等于任何两份不同发行版本的 ADB 都会冲突。本次改动减少短暂故障，不能保证共享 Server 的所有程序完全互不影响。[ADB 客户端源码](https://android.googlesource.com/platform/packages/modules/adb/+/refs/tags/android-14.0.0_r27/client/adb_client.cpp)、[PowerShell 原生命令 stderr 说明](https://devblogs.microsoft.com/powershell/powershell-7-1-preview-6/)

连接专项验证记录与测试范围见 [connection-verification.json](tools/mumu-minimal-installer/connection-verification.json)。原有 APK / 拖拽实机记录仍保存在 `verification.json`，不能将历史记录当成本次部署脚本的实机安装、恢复验证。

2026-10-10 的连接专项测试结果：Windows PowerShell 5.1 与 PowerShell 7.6.5 各 **34/34 项模拟测试通过**；当前 Android 15 实例的 `Check` 只读检查通过，ADB 自动启动 Server 时的提示也正常处理。本次未对真实设备安装、启用或恢复商店，未测试 Android 12 的 0.1.2 部署，也未复现真实 MAA 共存故障。

模拟测试使用独立的原生 `adb.exe` / `MuMuManager.exe` 测试替身，完整运行部署脚本，并检查命令日志、目标端口与修改次数；不会向真实 MuMu 转发命令。不需要 Pester 或 Android SDK。先将已验证的 0.1 APK 放到工具 `build` 目录，在工具目录运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Connection.ps1
# 可选：用已有 PowerShell 7 再运行同一组测试
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Connection.ps1 -ShellPath 'C:\你的路径\pwsh.exe'
```

测试目录与原始输出会保留在系统临时目录，末尾显示路径。测试替身由 Windows PowerShell 5.1 的内置 C# 编译器生成；不修改系统 PATH 或真实模拟器。

### APK 构建（本次无需重新构建）

源码在 [tools/mumu-minimal-installer](tools/mumu-minimal-installer)。需要 Python 3、JDK 和官方 Android SDK；普通使用者直接下载 Release，无需构建。

在该目录的 PowerShell 中运行：

```powershell
$env:MUMU_ANDROID_SDK_ROOT = 'F:\Tools\.agent\tools\android-sdk\35'
$env:MUMU_SDK_CACHE = 'F:\Tools\.agent\cache\android-sdk'
$env:MUMU_TEST_KEY_DIR = 'F:\Tools\.agent\tools\aosp-test-platform-key\public-test-key'
python .\prepare_sdk.py
python .\build.py
```

路径可自行修改，变量只对当前进程有效。脚本使用固定的 Build Tools 35.0.0 / API 35，并校验官方 SDK 下载散列；签名材料来自公开 AOSP 测试平台密钥。

`package.py` 只打包已验证的 0.1 APK，包含安装/恢复入口、源码与验证摘要，不包含 SDK、签名文件或调查日志。重新构建的 APK 因 ZIP 元数据等原因可能产生不同散列；发布新的构建前，需重新验证并更新脚本和验证记录中的散列，不能直接沿用本次记录。
