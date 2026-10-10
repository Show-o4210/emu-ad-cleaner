param([Parameter(Mandatory = $true)][string]$OutputPath)
$ErrorActionPreference = 'Stop'
Add-Type -Path (Join-Path $PSScriptRoot 'FakeMuMu.cs') -ReferencedAssemblies System.Web.Extensions -OutputAssembly $OutputPath -OutputType ConsoleApplication
