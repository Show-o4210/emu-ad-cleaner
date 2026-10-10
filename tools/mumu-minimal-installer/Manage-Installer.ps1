param(
    [ValidateSet('Check', 'Install', 'Restore')][string]$Action = 'Check',
    [string]$MuMuPath,
    [int]$Index = -1
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding
$packageName = 'com.mumu.store'
$apkPath = Join-Path $PSScriptRoot 'build\mumu-minimal-installer-0.1.apk'
$expectedApkHash = 'a03ba9b5286402b4db0df9796a3bcbb82785cd49ac92f5c2ad4638235c63b43a'

function Find-MuMuPath {
    foreach ($process in @(Get-Process -Name MuMuNxDevice, MuMu, MuMuManager -ErrorAction SilentlyContinue)) {
        if (-not $process.Path) { continue }
        $directory = Split-Path -Parent $process.Path
        for ($level = 0; $level -lt 5 -and $directory; $level++) {
            if (Test-Path -LiteralPath (Join-Path $directory 'nx_main\MuMuManager.exe')) { return $directory }
            $directory = Split-Path -Parent $directory
        }
    }
    return $null
}
function Invoke-Native([string]$Executable, [string[]]$Arguments) {
    # Windows PowerShell 5.1 treats redirected stderr as ErrorRecord. A daemon
    # startup notice must not throw before we can inspect the actual exit code.
    $ErrorActionPreference = 'Continue'
    $PSNativeCommandUseErrorActionPreference = $false
    $global:LASTEXITCODE = $null
    $lines = @(& $Executable @Arguments 2>&1)
    $code = $global:LASTEXITCODE
    if ($null -eq $code) { throw "无法启动命令：$Executable。$($lines -join "`n")" }
    $stdout = @($lines | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } | ForEach-Object { [string]$_ }) -join "`n"
    $text = @($lines | ForEach-Object {
        if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { [string]$_ }
    }) -join "`n"
    return @{ ExitCode = $code; StdOut = $stdout.Trim(); Text = $text.Trim() }
}
function Invoke-Manager([string[]]$Arguments) {
    $result = Invoke-Native -Executable $script:managerPath -Arguments $Arguments
    if ($result.ExitCode -ne 0) { throw "MuMuManager 执行失败（退出码 $($result.ExitCode)）：$($result.Text)" }
    try { return ($result.StdOut | ConvertFrom-Json) } catch { throw "MuMuManager 返回的实例信息无法解析：$($result.Text)" }
}
function Assert-Target {
    $info = Invoke-Manager -Arguments @('info', '-v', 'all')
    $current = @($info.PSObject.Properties | ForEach-Object { $_.Value } | Where-Object { [string]$_.index -eq [string]$script:Index })
    if ($current.Count -ne 1 -or -not $current[0].is_android_started) { throw '目标实例已停止或不存在，请启动原实例后重新运行。不会改选其他实例。' }
    $target = $current[0]
    if ($target.adb_host_ip -ne '127.0.0.1' -or [string]$target.adb_port -ne [string]$script:player.adb_port -or
        $target.android_version -ne $script:player.android_version -or
        [string]$target.created_timestamp -ne [string]$script:player.created_timestamp -or
        [string]$target.pid -ne [string]$script:player.pid) {
        throw '目标实例的身份、进程或 ADB 地址已变化，请重新运行并确认编号。未连接其他端口。'
    }
}
function Get-AdbFailure([hashtable]$Result, [string]$Stage) {
    $text = $Result.Text
    $kind = '输出或命令错误'
    $retry = $false
    if ($text -match '(?i)\boffline\b') { $kind = '设备 offline'; $retry = $true }
    elseif ($text -match '(?i)\bunauthorized\b') { $kind = '设备未授权' }
    elseif ($text -match '(?i)cannot connect to daemon|cannot connect to (?:adb )?server|could not (?:read|connect).*server|failed to (?:start|check).*daemon|daemon not running|ADB server didn.t ACK|server (?:is out of date|version)|tcp:5037|127\.0\.0\.1:5037') { $kind = 'ADB Server 连接异常'; $retry = $true }
    elseif ($Stage -eq 'connect' -and $text -match '(?i)cannot connect|failed to connect|unable to connect|refused|timed? out|10060|10061|unreachable') { $kind = '模拟器本地端口不可达'; $retry = $true }
    elseif ($text -match '(?i)device .*not found|no devices/emulators found|transport (?:error|.*closed)|error: (?:closed|disconnected)|connection (?:reset|closed)|protocol fault|broken pipe') { $kind = '设备连接中断'; $retry = $true }
    return @{ Result = $Result; Stage = $Stage; Kind = $kind; Retry = $retry }
}
function Write-AdbFailure([hashtable]$Failure) {
    Write-Host ("ADB 诊断 [{0}]：{1}，退出码 {2}" -f $Failure.Stage, $Failure.Kind, $Failure.Result.ExitCode)
    if ($Failure.Result.Text) { Write-Host $Failure.Result.Text } else { Write-Host '（没有输出）' }
}
function Get-ConnectionFailure {
    Assert-Target
    $result = Invoke-Native -Executable $script:adbPath -Arguments @('connect', $script:serial)
    $expected = '(?m)^(?:already )?connected to ' + [regex]::Escape($script:serial) + '\r?$'
    if ($result.ExitCode -ne 0 -or $result.StdOut -notmatch $expected -or $result.Text -match '(?i)cannot connect|failed to connect|unable to connect|refused') {
        return (Get-AdbFailure -Result $result -Stage 'connect')
    }
    if ($result.Text -ne $result.StdOut) { Write-Host "ADB 连接提示：$($result.Text)" }
    $result = Invoke-Native -Executable $script:adbPath -Arguments @('-s', $script:serial, 'get-state')
    if ($result.ExitCode -ne 0 -or $result.StdOut -ne 'device') { return (Get-AdbFailure -Result $result -Stage 'get-state') }
    return $null
}
function Connect-Target {
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        if ($attempt -gt 1) { Start-Sleep -Seconds 1 }
        $failure = Get-ConnectionFailure
        if ($null -eq $failure) { Write-Host "ADB 状态：device（$script:serial）"; return }
        Write-AdbFailure -Failure $failure
        if (-not $failure.Retry -or $attempt -eq 3) { throw "连接检查失败：$($failure.Kind)。请确认目标实例已启动、ADB 调试为本地连接，并保存上方诊断。" }
        Write-Host "连接暂未就绪，准备重试（$attempt/3）。"
    }
}
function Invoke-Adb([string[]]$Arguments, [switch]$ReadOnly, [switch]$PermitUninstallSuccess) {
    # Only these exact queries can be repeated. Changes are always sent once.
    $query = $Arguments -join ' '
    if ($ReadOnly -and $query -notin @('shell dumpsys package com.mumu.store',
        'shell ls /system/priv-app/com.mumu.store/com.mumu.store.apk', 'shell pm path com.mumu.store')) {
        throw '脚本错误：此命令不在可重试的只读查询列表中。'
    }
    $limit = 1
    if ($ReadOnly) { $limit = 3 }
    for ($attempt = 1; $attempt -le $limit; $attempt++) {
        $failure = $null
        if ($attempt -gt 1) {
            Start-Sleep -Seconds 1
            $failure = Get-ConnectionFailure
        }
        if ($null -eq $failure) {
            $result = Invoke-Native -Executable $script:adbPath -Arguments (@('-s', $script:serial) + $Arguments)
            if ($result.ExitCode -eq 0) { return $result.StdOut }
            # This MuMu pm command returns 1 even after a successful system-update rollback.
            # Permit only this exact operation; its resulting version and path are checked below.
            $knownRollback = $query -eq 'shell pm uninstall-system-updates com.mumu.store'
            if ($PermitUninstallSuccess -and $knownRollback -and $result.ExitCode -eq 1 -and $result.StdOut -eq 'Success') {
                Write-Host 'MuMu 回退命令返回 Success / 退出码 1，继续核对实际版本和 APK 路径。'
                return $result.StdOut
            }
            $failure = Get-AdbFailure -Result $result -Stage $query
        }
        Write-AdbFailure -Failure $failure
        if (-not $failure.Retry -or $attempt -eq $limit) { throw "ADB 执行失败：$($failure.Kind)；退出码 $($failure.Result.ExitCode)。$($failure.Result.Text)" }
        Write-Host "只读查询连接中断，准备重新连接并查询（$attempt/3）。"
    }
}
function Invoke-AdbChange([string[]]$Arguments, [switch]$PermitUninstallSuccess) {
    Assert-Target
    try {
        $text = Invoke-Adb -Arguments $Arguments -PermitUninstallSuccess:$PermitUninstallSuccess
        Write-Host '修改命令已执行，随后核对状态；若核对失败，请先确认当前状态，不要盲目重复操作。'
        return $text
    }
    catch {
        $originalFailure = $_
        Write-Host '修改命令没有自动重试，也没有自动回退。正在只读核对当前商店状态；命令失败不代表修改一定未生效。'
        try {
            $current = Get-StoreState
            Write-Host "当前商店版本号：$($current.Version)；User 0：$($current.User.Trim())"
        } catch { Write-Host "当前状态无法确认：$($_.Exception.Message)" }
        throw $originalFailure
    }
}
function Get-StoreState {
    $dump = Invoke-Adb -Arguments @('shell', 'dumpsys', 'package', $packageName) -ReadOnly
    $version = [regex]::Match($dump, 'versionCode=(\d+)')
    $state = [regex]::Match($dump, 'User 0:([^\r\n]+)')
    if (-not $version.Success -or -not $state.Success) {
        $preview = (@($dump -split '\r?\n' | Select-Object -First 20) -join "`n")
        if ($preview.Length -gt 1000) { $preview = $preview.Substring(0, 1000) + '…' }
        throw "商店版本/用户状态检查失败（dumpsys package，ADB 退出码 0）。没有找到预期系统商店信息，未继续修改。输出摘录：$preview"
    }
    return @{ Version = [int]$version.Groups[1].Value; User = $state.Groups[1].Value; Dump = $dump }
}

try {
    if (-not $MuMuPath) { $MuMuPath = Find-MuMuPath }
    if (-not $MuMuPath) { $MuMuPath = Read-Host '请输入 MuMu 安装目录（里面应有 nx_main 文件夹）' }
    $MuMuPath = $MuMuPath.Trim().Trim('"')
    if ((Split-Path -Leaf $MuMuPath) -eq 'nx_main') { $MuMuPath = Split-Path -Parent $MuMuPath }
    $script:managerPath = Join-Path $MuMuPath 'nx_main\MuMuManager.exe'
    $script:adbPath = Join-Path $MuMuPath 'nx_main\adb.exe'
    if (-not (Test-Path -LiteralPath $managerPath) -or -not (Test-Path -LiteralPath $adbPath)) { throw '安装目录不正确：找不到 MuMuManager.exe 或 adb.exe。' }

    $info = Invoke-Manager -Arguments @('info', '-v', 'all')
    $players = @($info.PSObject.Properties | ForEach-Object { $_.Value } | Where-Object { $_.is_android_started })
    if ($players.Count -eq 0) { throw '请先启动要处理的 MuMu 实例，等到安卓桌面出现后再运行。' }
    Write-Host '已启动的实例：'
    foreach ($player in $players) { Write-Host ("  编号 {0}：{1}（Android {2}）" -f $player.index, $player.name, $player.android_version) }
    if ($Index -lt 0) {
        $chosen = Read-Host '请输入要处理的实例编号'
        $parsed = 0
        if (-not [int]::TryParse($chosen, [ref]$parsed)) { throw '实例编号必须是列表中的数字。' }
        $Index = $parsed
    }
    $selected = @($players | Where-Object { [string]$_.index -eq [string]$Index })
    if ($selected.Count -ne 1) { throw '该编号不在已启动实例列表中。' }
    $player = $selected[0]
    if ($player.android_version -notmatch '^(12|15)(?:\.|$)') { throw '这个部署包仅验证过 Android 12 / 15 实例。请阅读文档中的临时安装方法。' }
    if ($player.adb_host_ip -ne '127.0.0.1' -or [int]$player.adb_port -lt 1024 -or [int]$player.adb_port -gt 65535) { throw '实例的本地 ADB 地址无效。' }
    $script:serial = '127.0.0.1:' + $player.adb_port
    Write-Host "ADB 路径：$adbPath"
    $client = Invoke-Native -Executable $adbPath -Arguments @('version')
    if ($client.ExitCode -ne 0 -or $client.StdOut -notmatch '(?m)^Android Debug Bridge version \d+\.\d+\.\d+') { throw "ADB 客户端版本检查失败（退出码 $($client.ExitCode)），未连接设备：$($client.Text)" }
    Write-Host $client.Text
    Write-Host ("目标：编号 {0}，{1}，ADB {2}" -f $Index, $player.name, $serial)
    Connect-Target

    $systemApk = Invoke-Adb -Arguments @('shell', 'ls', '/system/priv-app/com.mumu.store/com.mumu.store.apk') -ReadOnly
    if ($systemApk -ne '/system/priv-app/com.mumu.store/com.mumu.store.apk') { throw '原系统商店 APK 不完整。不要继续：请备份实例，再修复或使用新实例。' }
    $state = Get-StoreState
    if ($state.Version -notin @(1225, 1226)) { throw "商店版本号为 $($state.Version)，本工具只验证过 1225 / 本原型 1226，未执行修改。" }
    if ($state.Dump -notmatch 'android\.uid\.system/1000') { throw '商店不是预期的系统共享 UID，未执行修改。' }
    if ($state.User -match 'hidden=true') { throw '原商店仍处于隐藏状态，请先按文档恢复隐藏，再运行本工具。' }
    Write-Host "当前商店版本号：$($state.Version)"
    if ($Action -eq 'Check') {
        Write-Host '检查通过。本次没有更新、启用或卸载商店。'
        exit 0
    }

    if ($Action -eq 'Install') {
        if (-not (Test-Path -LiteralPath $apkPath)) { throw '缺少 APK。请下载 Release 中的完整工具 ZIP 并解压，不要只下载仓库源码。' }
        $hashAlgorithm = [System.Security.Cryptography.SHA256]::Create()
        $apkStream = [IO.File]::OpenRead($apkPath)
        try {
            $hash = [BitConverter]::ToString($hashAlgorithm.ComputeHash($apkStream)).Replace('-', '').ToLowerInvariant()
        } finally {
            $apkStream.Dispose()
            $hashAlgorithm.Dispose()
        }
        if ($hash -ne $expectedApkHash) { throw 'APK 校验失败，请重新下载该版本的完整工具 ZIP。' }
        if ($state.Version -eq 1226 -and $state.Dump -notmatch 'versionName=minimal-prototype-0\.1') { throw '版本号 1226 已被其他商店版本使用，未执行修改。' }
        if ($state.User -match 'installed=false') { Invoke-AdbChange -Arguments @('shell', 'cmd', 'package', 'install-existing', '--user', '0', $packageName) | Write-Host }
        if ($state.User -notmatch 'enabled=0(?:\s|$)') { Invoke-AdbChange -Arguments @('shell', 'pm', 'default-state', '--user', '0', $packageName) | Write-Host }
        $ready = Get-StoreState
        if ($ready.User -notmatch 'installed=true' -or $ready.User -match 'hidden=true' -or $ready.User -notmatch 'enabled=0(?:\s|$)') { throw '商店用户状态恢复失败，未安装替代包。' }
        Invoke-AdbChange -Arguments @('install', '--no-incremental', '-r', $apkPath) | Write-Host
        $after = Get-StoreState
        if ($after.Version -ne 1226 -or $after.Dump -notmatch 'versionName=minimal-prototype-0\.1') { throw '安装后的版本校验失败，请保存窗口输出并反馈。' }
        Write-Host '最小安装器已安装。请重启这个实例，再拖入一个普通 APK 测试。'
        Write-Host '不要再禁用、隐藏或删除 com.mumu.store。需要恢复原商店时双击 Restore.cmd。'
    } else {
        if ($state.Version -eq 1225) { Write-Host '当前已是原商店，无需恢复。'; exit 0 }
        if ($state.Dump -notmatch 'versionName=minimal-prototype-0\.1') { throw '当前更新包不是本原型，未卸载它。' }
        Invoke-AdbChange -Arguments @('shell', 'pm', 'uninstall-system-updates', $packageName) -PermitUninstallSuccess | Write-Host
        $after = Get-StoreState
        if ($after.Version -ne 1225) { throw '回退后的版本不是预期值，请保存窗口输出并反馈。' }
        $restoredPath = Invoke-Adb -Arguments @('shell', 'pm', 'path', $packageName) -ReadOnly
        if ($restoredPath -ne 'package:/system/priv-app/com.mumu.store/com.mumu.store.apk') { throw '回退后没有使用原系统 APK，请保存窗口输出并反馈。' }
        Write-Host '原商店已恢复。请重启这个实例。'
    }
} catch {
    Write-Host ("操作停止：{0}" -f $_.Exception.Message) -ForegroundColor Red
    exit 1
}
