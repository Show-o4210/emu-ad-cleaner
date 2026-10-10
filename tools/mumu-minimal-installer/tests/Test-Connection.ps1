param(
    [string]$ShellPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe",
    [string]$ApkPath = (Join-Path $PSScriptRoot '..\build\mumu-minimal-installer-0.1.apk')
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $ApkPath)) { throw '请先将已验证的 0.1 APK 放到 build 目录（或通过 -ApkPath 指定）。测试不会重建 APK。' }
$project = Split-Path -Parent $PSScriptRoot
$work = Join-Path ([IO.Path]::GetTempPath()) ('mumu-adb-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
function Run-Script([string]$Shell, [string]$Script, [string]$Extra) {
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Shell
    $start.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $Script + '" ' + $Extra
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($start)
    $out = $process.StandardOutput.ReadToEndAsync()
    $err = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(30000)) { $process.Kill(); throw '测试子进程超时（仅结束此测试子进程）。' }
    $result = @{ Code = $process.ExitCode; Text = $out.Result + $err.Result }
    $process.Dispose()
    return $result
}
function Assert([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
$exe = Join-Path $work 'fake.exe'
$build = Run-Script -Shell "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Script (Join-Path $PSScriptRoot 'Build-FakeMuMu.ps1') -Extra ('-OutputPath "' + $exe + '"')
Assert ($build.Code -eq 0) $build.Text
function Player([int]$Index, [int]$Port) {
    return @{ index = "$Index"; name = "Test-$Index"; android_version = '15.0'; is_android_started = $true; adb_host_ip = '127.0.0.1'; adb_port = $Port; created_timestamp = 100 + $Index; pid = 900 + $Index }
}
function Response([int]$Code, [string]$Text, [switch]$Stderr) {
    $r = @{ exit = $Code; stdout = ''; stderr = '' }
    if ($Stderr) { $r.stderr = $Text } else { $r.stdout = $Text }
    return $r
}
$cases = @(
    @{ Name = 'normal-check'; Action = 'Check'; Code = 0 },
    @{ Name = 'normal-install-user-recovery'; Action = 'Install'; Code = 0; Scenario = @{ installed = 'false'; enabled = 3 }; Mutations = 3 },
    @{ Name = 'normal-restore-known-exit-1'; Action = 'Restore'; Code = 0; Scenario = @{ version = 1226 }; Mutations = 1 },
    @{ Name = 'daemon-startup-stderr'; Code = 0; Responses = @{ 'connect 127.0.0.1:16384' = @(@{ exit = 0; stdout = 'connected to 127.0.0.1:16384'; stderr = '* daemon not running; starting now at tcp:5037' }) }; Connects = 1 },
    @{ Name = 'server-temporarily-unavailable'; Code = 0; Responses = @{ 'connect 127.0.0.1:16384' = @((Response 1 'cannot connect to daemon at tcp:5037' -Stderr), (Response 0 'connected to 127.0.0.1:16384')) }; Connects = 2; Contains = 'ADB Server' },
    @{ Name = 'server-restarted-during-query'; Code = 0; Responses = @{ 'shell dumpsys package com.mumu.store' = @((Response 1 'error: closed' -Stderr), (Response 0 "versionCode=1225`nsharedUser=android.uid.system/1000`nUser 0: installed=true hidden=false enabled=0")) }; Connects = 2 },
    @{ Name = 'port-unreachable-exit-zero'; Action = 'Install'; Code = 1; Responses = @{ 'connect 127.0.0.1:16384' = @((Response 0 'cannot connect to 127.0.0.1:16384: refused (10061)')) }; Connects = 3; Contains = '模拟器本地端口不可达' },
    @{ Name = 'offline'; Action = 'Restore'; Code = 1; Scenario = @{ version = 1226 }; Responses = @{ 'get-state' = @((Response 1 'error: device offline' -Stderr)) }; Connects = 3; Contains = '设备 offline' },
    @{ Name = 'offline-recovers'; Code = 0; Responses = @{ 'get-state' = @((Response 1 'error: device offline' -Stderr), (Response 0 'device')) }; Connects = 2 },
    @{ Name = 'unknown-nonzero'; Code = 1; Responses = @{ 'connect 127.0.0.1:16384' = @((Response 7 'fixture unusual failure' -Stderr)) }; Connects = 1; Contains = '退出码 7' },
    @{ Name = 'abnormal-connect-output'; Code = 1; Responses = @{ 'connect 127.0.0.1:16384' = @((Response 0 'unexpected output')) }; Connects = 1; Contains = 'unexpected output' },
    @{ Name = 'abnormal-device-state'; Code = 1; Responses = @{ 'get-state' = @((Response 0 'unauthorized')) }; Connects = 1 },
    @{ Name = 'version-command-fails'; Code = 1; Responses = @{ version = @((Response 2 'cannot inspect version' -Stderr)) }; Connects = 0; Contains = '版本检查失败' },
    @{ Name = 'version-output-invalid'; Code = 1; Responses = @{ version = @((Response 0 'not adb')) }; Connects = 0 },
    @{ Name = 'store-version-unsupported'; Action = 'Install'; Code = 1; Scenario = @{ version = 1227 }; Connects = 1 },
    @{ Name = 'query-output-invalid'; Action = 'Install'; Code = 1; Responses = @{ 'shell dumpsys package com.mumu.store' = @((Response 0 'invalid package output')) }; Connects = 1 },
    @{ Name = 'query-error-not-connection'; Action = 'Install'; Code = 1; Responses = @{ 'shell dumpsys package com.mumu.store' = @((Response 4 'Permission denied' -Stderr)) }; Connects = 1; Contains = 'Permission denied' },
    @{ Name = 'multiple-instances'; Code = 0; Index = 1; Scenario = @{ players = @{ '0' = (Player 0 16384); '1' = (Player 1 16416) } }; Serial = '127.0.0.1:16416' },
    @{ Name = 'port-changes-during-retry'; Action = 'Install'; Code = 1; Scenario = @{ change_on = 3; change_field = 'adb_port'; change_value = 16416 }; Responses = @{ 'connect 127.0.0.1:16384' = @((Response 1 'cannot connect: refused' -Stderr)) }; Connects = 1; Contains = '地址已变化' },
    @{ Name = 'instance-restarts-before-change'; Action = 'Install'; Code = 1; Scenario = @{ change_on = 3; change_field = 'pid'; change_value = 999 }; Connects = 1; Contains = '进程或 ADB 地址已变化' },
    @{ Name = 'invalid-index'; Action = 'Install'; Code = 1; Index = 99; Connects = 0 },
    @{ Name = 'invalid-local-address'; Action = 'Restore'; Code = 1; Scenario = @{ players = @{ '0' = (@{ index = '0'; name = 'WrongHost'; android_version = '15.0'; is_android_started = $true; adb_host_ip = '192.0.2.1'; adb_port = 16384 }) } }; Connects = 0 },
    @{ Name = 'manager-command-fails'; Action = 'Install'; Code = 1; Scenario = @{ manager_exit = 8 }; Connects = 0; Contains = '退出码 8' },
    @{ Name = 'install-reply-lost-after-applied'; Action = 'Install'; Code = 1; Responses = @{ install = @(@{ exit = 1; stderr = 'error: closed'; apply = $true }) }; Mutations = 1; After = 1226; Contains = '当前商店版本号：1226' },
    @{ Name = 'restore-reply-lost-after-applied'; Action = 'Restore'; Code = 1; Scenario = @{ version = 1226 }; Responses = @{ 'shell pm uninstall-system-updates com.mumu.store' = @(@{ exit = 1; stderr = 'error: closed'; apply = $true }) }; Mutations = 1; After = 1225; Contains = '当前商店版本号：1225' },
    @{ Name = 'user-recovery-reply-lost'; Action = 'Install'; Code = 1; Scenario = @{ installed = 'false'; enabled = 3 }; Responses = @{ 'shell cmd package install-existing --user 0 com.mumu.store' = @(@{ exit = 1; stderr = 'error: closed'; apply = $true }) }; Mutations = 1; Contains = '没有自动重试' },
    @{ Name = 'rollback-unexpected-exit'; Action = 'Restore'; Code = 1; Scenario = @{ version = 1226 }; Responses = @{ 'shell pm uninstall-system-updates com.mumu.store' = @((Response 7 'Success')) }; Mutations = 1; After = 1226; Contains = '退出码 7' },
    @{ Name = 'rollback-path-invalid'; Action = 'Restore'; Code = 1; Scenario = @{ version = 1226 }; Responses = @{ 'shell pm path com.mumu.store' = @((Response 0 'package:/data/app/wrong.apk')) }; Mutations = 1; Contains = '没有使用原系统 APK' },
    @{ Name = 'server-persistent-restore-blocked'; Action = 'Restore'; Code = 1; Scenario = @{ version = 1226 }; Responses = @{ 'connect 127.0.0.1:16384' = @((Response 1 'ADB server didn''t ACK' -Stderr)) }; Connects = 3; Contains = 'ADB Server' },
    @{ Name = 'query-offline-persistent-install-blocked'; Action = 'Install'; Code = 1; Responses = @{ 'shell dumpsys package com.mumu.store' = @((Response 1 'error: device offline' -Stderr)) }; Connects = 3 },
    @{ Name = 'server-version-mismatch-recovers'; Code = 0; Responses = @{ 'connect 127.0.0.1:16384' = @(@{ exit = 0; stdout = 'connected to 127.0.0.1:16384'; stderr = 'adb server version (40) doesn''t match this client (41); killing...' }) }; Connects = 1; Contains = 'server version (40)' },
    @{ Name = 'restore-original-no-change'; Action = 'Restore'; Code = 0; Connects = 1; Contains = '无需恢复' },
    @{ Name = 'state-query-lost-after-install'; Action = 'Install'; Code = 1; Responses = @{ 'shell dumpsys package com.mumu.store' = @((Response 0 "versionCode=1225`nsharedUser=android.uid.system/1000`nUser 0: installed=true hidden=false enabled=0"), (Response 0 "versionCode=1225`nsharedUser=android.uid.system/1000`nUser 0: installed=true hidden=false enabled=0"), (Response 1 'error: device offline' -Stderr)) }; Mutations = 1; After = 1226; Connects = 3; Contains = '修改命令已执行' },
    @{ Name = 'unsupported-readonly-retry-error'; Action = 'Install'; Code = 1; Responses = @{ 'shell ls /system/priv-app/com.mumu.store/com.mumu.store.apk' = @((Response 3 'Permission denied' -Stderr)) }; Connects = 1; Contains = '退出码 3' }
)
$passed = 0
foreach ($case in $cases) {
    $root = Join-Path $work $case.Name
    $bin = Join-Path $root 'nx_main'
    New-Item -ItemType Directory -Path $bin, (Join-Path $root 'build') | Out-Null
    Copy-Item -LiteralPath $exe -Destination (Join-Path $bin 'adb.exe')
    Copy-Item -LiteralPath $exe -Destination (Join-Path $bin 'MuMuManager.exe')
    Copy-Item -LiteralPath (Join-Path $project 'Manage-Installer.ps1') -Destination $root
    Copy-Item -LiteralPath $ApkPath -Destination (Join-Path $root 'build\mumu-minimal-installer-0.1.apk')
    $scenario = @{ players = @{ '0' = (Player 0 16384) } }
    if ($case.Scenario) { foreach ($key in $case.Scenario.Keys) { $scenario[$key] = $case.Scenario[$key] } }
    if ($case.Responses) { $scenario.responses = $case.Responses }
    $scenario | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $root 'scenario.json') -Encoding UTF8
    $action = 'Check'; if ($case.Action) { $action = $case.Action }
    $index = 0; if ($case.ContainsKey('Index')) { $index = $case.Index }
    $serial = '127.0.0.1:16384'; if ($case.Serial) { $serial = $case.Serial }
    $run = Run-Script -Shell $ShellPath -Script (Join-Path $root 'Manage-Installer.ps1') -Extra ('-MuMuPath "' + $root + '" -Index ' + $index + ' -Action ' + $action)
    $run.Text | Set-Content -LiteralPath (Join-Path $root 'output.txt') -Encoding UTF8
    $calls = @(Get-Content -LiteralPath (Join-Path $root 'calls.jsonl') | ForEach-Object { $_ | ConvertFrom-Json })
    $adbCalls = @($calls | Where-Object { $_.tool -eq 'adb' })
    $mutations = @($adbCalls | Where-Object { ($_.args -join ' ') -match ' install |install-existing|default-state|uninstall-system-updates' })
    try {
        Assert ($run.Code -eq $case.Code) "exit=$($run.Code), expected=$($case.Code)"
        $expectedChanges = 0; if ($case.Mutations) { $expectedChanges = $case.Mutations }
        Assert ($mutations.Count -eq $expectedChanges) "mutation count=$($mutations.Count), expected=$expectedChanges"
        if ($case.ContainsKey('Connects')) { Assert (@($adbCalls | Where-Object { $_.args[0] -eq 'connect' }).Count -eq $case.Connects) 'unexpected connect attempt count' }
        if ($case.ContainsKey('Contains')) { Assert ($run.Text.Contains($case['Contains'])) "missing diagnostic: $($case['Contains'])" }
        foreach ($call in $adbCalls) {
            Assert ($call.args[0] -notin @('kill-server', 'start-server', 'devices')) 'global server/device operation forbidden'
            if ($call.args[0] -eq '-s') { Assert ($call.args[1] -eq $serial) 'wrong target serial' }
            elseif ($call.args[0] -eq 'connect') { Assert ($call.args[1] -eq $serial) 'wrong connection port' }
        }
        if ($case.After) { $state = Get-Content -LiteralPath (Join-Path $root 'state.json') -Raw | ConvertFrom-Json; Assert ($state.version -eq $case.After) 'unexpected final store version' }
        if ($mutations.Count -gt 0) {
            foreach ($group in @($mutations | Group-Object { $_.args -join ' ' })) { Assert ($group.Count -eq 1) 'mutation repeated' }
            if ($run.Code -ne 0) {
                Assert (-not $run.Text.Contains('最小安装器已安装。')) 'failed command reported installation success'
                Assert (-not $run.Text.Contains('原商店已恢复。')) 'failed command reported restore success'
            }
        }
    } catch { throw "$($case.Name): $($_.Exception.Message)`n$($run.Text)`nArtifacts: $root" }
    $passed++
    Write-Host "PASS $($case.Name)"
}
Write-Host "$passed/$($cases.Count) passed; shell=$ShellPath; artifacts=$work"
