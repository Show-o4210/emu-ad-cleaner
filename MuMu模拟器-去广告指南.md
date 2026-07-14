# MuMu 模拟器去广告指南

适用版本：MuMu 模拟器 12（本机实测路径 `D:\MuMu\MuMuPlayer`，Android 12 实例）  
方法与「雷电模拟器去广告」同类：**ADB 卸载/禁用内置广告应用** + **清理 Windows 端广告缓存**。  
MuMu 系统盘在 Root 开启时通常可写，**可直接删除系统分区中的应用商店 APK**（比雷电更彻底）。

---

## 一、广告从哪来

| 位置 | 组件 / 路径 | 表现 |
|------|-------------|------|
| 安卓系统内 | `com.mumu.store`（MuMu 应用中心，`/system/priv-app/com.mumu.store`） | 桌面商店图标、应用内推广 |
| 安卓系统内 | `com.nemu.oaidmanager` | OAID / 标识相关设置入口 |
| 安卓系统内 | 官方桌面（旧版常为 `com.mumu.launcher*`） | 桌面推荐位；本机已用 Lawnchair 替代 |
| Windows 客户端 | `%AppData%\Netease\MuMuPlayer\data\ProgramAds` | 程序内广告资源 |
| Windows 客户端 | `%AppData%\Netease\MuMuPlayer\data\startupImage` | 启动/换肤类图片广告 |
| Windows 客户端 | `%AppData%\Netease\MuMuPlayer\data\msgCenter` | 消息中心推送缓存 |

**建议保留（非广告主因）：**

| 包名 | 说明 |
|------|------|
| `com.netease.mumu.cloner` | 应用多开 |
| `com.mumu.shared.sdk` | 系统共享 SDK |
| `com.mumu.acc` | 账号相关组件 |
| `nemu-vinput-pack` / `com.nemu.nlp` 等 | 输入法、能力组件 |

---

## 二、准备

1. 启动要清理的 MuMu 实例（多开器用「启动」）。
2. 设置中打开 **Root 权限**（删除系统商店 APK 需要）。
3. 使用安装目录自带工具（推荐）：

```powershell
cd D:\MuMu\MuMuPlayer\nx_main
.\MuMuManager.exe info -v all
.\MuMuManager.exe adb -v 0 -c connect
```

常见 ADB 地址：`127.0.0.1:16384`（实例 0，端口以实际为准）。

```powershell
.\adb.exe connect 127.0.0.1:16384
.\adb.exe devices
```

下文用变量：

```powershell
$s = "127.0.0.1:16384"   # 按 adb devices 修改
```

查看 Root：

```powershell
.\adb.exe -s $s shell "su -c id"
# 期望：uid=0(root)
```

---

## 三、安卓侧：去掉 MuMu 应用中心（核心）

### 3.1 当前用户卸载 + 禁用 + 隐藏

```powershell
cd D:\MuMu\MuMuPlayer\nx_main
$s = "127.0.0.1:16384"

# 若有用户层更新包
.\adb.exe -s $s uninstall com.mumu.store

# 对当前用户卸载（系统应用常用）
.\adb.exe -s $s shell pm uninstall --user 0 com.mumu.store

# 禁用
.\adb.exe -s $s shell pm disable-user --user 0 com.mumu.store
.\adb.exe -s $s shell am force-stop com.mumu.store

# Root 下隐藏 + 全局禁用
.\adb.exe -s $s shell "su -c 'pm hide com.mumu.store; pm disable com.mumu.store'"
```

### 3.2 物理删除系统商店（Root + 可写系统盘，推荐）

```powershell
.\adb.exe -s $s shell "su -c 'mount -o remount,rw /system; rm -rf /system/priv-app/com.mumu.store; rm -rf /data/data/com.mumu.store /data/user/0/com.mumu.store; ls /system/priv-app | grep mumu'"
```

成功后 `ls` 中不应再有 `com.mumu.store`。

### 3.3 可选：禁用 OAID 管理（减少追踪入口）

```powershell
.\adb.exe -s $s shell pm disable-user --user 0 com.nemu.oaidmanager
.\adb.exe -s $s shell am force-stop com.nemu.oaidmanager
.\adb.exe -s $s shell "su -c 'pm hide com.nemu.oaidmanager; pm disable com.nemu.oaidmanager'"
```

### 3.4 验证

```powershell
# 启动器中不应再出现 com.mumu.store
.\adb.exe -s $s shell "cmd package query-activities -a android.intent.action.MAIN -c android.intent.category.LAUNCHER"

# 状态：installed=false / enabled 为禁用
.\adb.exe -s $s shell dumpsys package com.mumu.store

# 路径应失败或无输出
.\adb.exe -s $s shell pm path com.mumu.store
```

期望：

- 桌面无「MuMu 应用中心 / 商店」
- `User 0: ... installed=false ...`
- `/system/priv-app/` 下无 `com.mumu.store` 目录（若已做 3.2）

### 3.5 关于官方桌面广告

若仍使用官方桌面且底部有推荐位，可：

- 安装第三方桌面（如 Lawnchair）并设为默认；或  
- 参考社区方案替换 `/system/priv-app` 下桌面 APK（需 Root，有风险）。

本机实例已使用 `app.lawnchair`，桌面侧推广位问题通常已规避。

---

## 四、Windows 侧：清客户端广告缓存

### 4.1 主要目录

| 目录 | 作用 |
|------|------|
| `%AppData%\Netease\MuMuPlayer\data\ProgramAds` | 程序广告资源 |
| `%AppData%\Netease\MuMuPlayer\data\startupImage` | 启动相关图片 |
| `%AppData%\Netease\MuMuPlayer\data\msgCenter` | 消息中心缓存 |
| `%AppData%\Netease\MuMuPlayer\data\fcount\` | 统计（含 store 相关 ini） |

### 4.2 清理脚本（PowerShell）

```powershell
$base = "$env:APPDATA\Netease\MuMuPlayer\data"

foreach ($dir in @("ProgramAds", "msgCenter")) {
  $p = Join-Path $base $dir
  if (Test-Path $p) {
    Get-ChildItem $p -Recurse -File -Force -ErrorAction SilentlyContinue |
      Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Host "cleared $dir"
  }
}

$startup = Join-Path $base "startupImage"
if (Test-Path $startup) {
  Get-ChildItem $startup -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
    try { $_.Attributes = 'Normal' } catch {}
  }
  Get-ChildItem $startup -Directory -Force -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
  $im = Join-Path $startup "imageManager.json"
  if (Test-Path $im) {
    Set-ItemProperty $im -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
    Set-Content $im -Value '{"images":[],"list":[]}' -Encoding UTF8 -NoNewline
    Set-ItemProperty $im -Name IsReadOnly -Value $true
  }
  Write-Host "cleared startupImage"
}

$fstore = Join-Path $base "fcount\fcountData_store.ini"
if (Test-Path $fstore) {
  Set-Content $fstore -Value "" -Encoding ASCII -NoNewline
  Write-Host "emptied fcountData_store.ini"
}
```

说明：客户端联网后可能再次下载启动图；可重复执行本段。

---

## 五、一键脚本参考

将端口/路径按本机修改，**先启动实例 0**，再在 PowerShell 中运行：

```powershell
# MuMu 去广告脚本（示例，实例 0）
$LD_MAIN = "D:\MuMu\MuMuPlayer\nx_main"
$INDEX   = 0

Set-Location $LD_MAIN
& .\MuMuManager.exe adb -v $INDEX -c connect | Out-Null
$info = & .\MuMuManager.exe adb -v $INDEX -c connect 2>&1 | Out-String
# 默认端口（若失败请 adb devices 后手写 $s）
$s = "127.0.0.1:16384"
& .\adb.exe connect $s | Out-Null

# 安卓：应用中心
& .\adb.exe -s $s uninstall com.mumu.store 2>$null
& .\adb.exe -s $s shell pm uninstall --user 0 com.mumu.store
& .\adb.exe -s $s shell pm disable-user --user 0 com.mumu.store
& .\adb.exe -s $s shell am force-stop com.mumu.store
& .\adb.exe -s $s shell "su -c 'pm hide com.mumu.store; pm disable com.mumu.store; mount -o remount,rw /system; rm -rf /system/priv-app/com.mumu.store; rm -rf /data/data/com.mumu.store /data/user/0/com.mumu.store'" 2>$null

# 可选 OAID
& .\adb.exe -s $s shell pm disable-user --user 0 com.nemu.oaidmanager 2>$null
& .\adb.exe -s $s shell "su -c 'pm hide com.nemu.oaidmanager; pm disable com.nemu.oaidmanager'" 2>$null

# Windows 缓存
$base = "$env:APPDATA\Netease\MuMuPlayer\data"
foreach ($dir in @("ProgramAds", "msgCenter")) {
  $p = Join-Path $base $dir
  if (Test-Path $p) {
    Get-ChildItem $p -Recurse -File -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
  }
}
$startup = Join-Path $base "startupImage"
if (Test-Path $startup) {
  Get-ChildItem $startup -Directory -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
  $im = Join-Path $startup "imageManager.json"
  if (Test-Path $im) {
    Set-ItemProperty $im -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
    Set-Content $im -Value '{"images":[],"list":[]}' -Encoding UTF8 -NoNewline
    Set-ItemProperty $im -Name IsReadOnly -Value $true
  }
}

Write-Host "完成。请检查 MuMu 桌面是否已无应用中心。"
```

---

## 六、多开实例

本机存在实例 `0`、`1` 时，ADB 端口不同。对每个**已启动**实例：

```powershell
.\MuMuManager.exe adb -v 1 -c connect
.\adb.exe devices
# 对对应 127.0.0.1:端口 重复第三节
```

新建实例或重置后，系统商店可能从基础镜像恢复，需再执行第三节。

---

## 七、效果自检

- [ ] 桌面无 MuMu 应用中心 / 商店图标  
- [ ] 启动器查询无 `com.mumu.store`  
- [ ] `/system/priv-app/` 无 `com.mumu.store`（若已物理删除）  
- [ ] 多开、键位、共享文件夹等正常  
- [ ] 客户端启动图/程序广告减弱或消失（可配合第四节重复清理）  

---

## 八、常见问题

**Q：`pm uninstall` 失败 `DELETE_FAILED_INTERNAL_ERROR`？**  
A：系统应用直接 `uninstall` 常失败；用 `pm uninstall --user 0` 或 Root 删除 `/system/priv-app/com.mumu.store`。

**Q：系统盘 remount 失败？**  
A：先在 MuMu 设置中打开 Root；仍失败则至少做「当前用户卸载 + disable + hide」。

**Q：会不会影响多开 / 安装 APK？**  
A：删除商店不影响从电脑拖入 APK 或 `adb install`。保留 `com.netease.mumu.cloner` 即可继续用应用多开。

**Q：启动图又回来了？**  
A：客户端会重新拉取 `startupImage`，重复第四节即可。

**Q：如何恢复应用中心？**  
A：系统 APK 已删时，只能重装/修复 MuMu 或从备份镜像恢复；若仅禁用未删文件：

```powershell
.\adb.exe -s $s shell "su -c 'pm unhide com.mumu.store; pm enable com.mumu.store'"
.\adb.exe -s $s shell cmd package install-existing com.mumu.store
```

---

## 九、操作摘要（最短版）

1. 启动 MuMu → `MuMuManager.exe adb -v 0 -c connect` → 确认 `adb devices`  
2. `pm uninstall --user 0 com.mumu.store` + `disable-user` + Root `hide`  
3. Root：`rm -rf /system/priv-app/com.mumu.store`  
4. 可选：禁用 `com.nemu.oaidmanager`  
5. 清理 `%AppData%\Netease\MuMuPlayer\data` 下 `ProgramAds` / `startupImage` / `msgCenter`  
6. **不要**禁用 `cloner`、`shared.sdk` 等核心组件  

---

## 十、本机实测结果（参考）

| 项目 | 结果 |
|------|------|
| 实例 | MuMu 12.0 实例 0（`127.0.0.1:16384`） |
| `com.mumu.store` | 用户卸载 + 禁用隐藏；**系统目录已删除** |
| `com.nemu.oaidmanager` | 禁用 + 隐藏 |
| 桌面启动器 | 已无商店；保留应用多开等 |
| Windows | 已清 ProgramAds / startupImage / msgCenter |
| 系统盘 | Root 下 `/system` 可写，物理删除成功 |

---

*文档根据实际排障步骤整理，仅供个人学习与自用优化；Root 与删除系统应用有风险，请自行评估。*
