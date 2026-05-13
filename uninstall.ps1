<#
.SYNOPSIS
  대상 프로젝트 폴더에서 claude-harness link 를 제거한다.

.PARAMETER Target
  link 를 제거할 프로젝트 폴더 경로.

.EXAMPLE
  D:\claude-harness\uninstall.ps1 -Target D:\hiaas\dinai
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Target
)

$ErrorActionPreference = 'Stop'

$HarnessRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Target = (Resolve-Path -LiteralPath $Target).Path

Write-Host "[harness] target = $Target" -ForegroundColor Cyan

function Remove-IfLink {
    param([string]$Name)
    $path = Join-Path $Target $Name
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Host "[skip] $Name (없음)" -ForegroundColor DarkGray
        return
    }

    $item = Get-Item -LiteralPath $path -Force
    $isReparse = ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
    $isHardlink = $false

    if (-not $isReparse -and -not $item.PSIsContainer) {
        # hardlink 판별: harness 원본과 동일 파일이면 hardlink 로 간주
        $src = Join-Path $HarnessRoot $Name
        if (Test-Path -LiteralPath $src) {
            $srcLen = (Get-Item -LiteralPath $src).Length
            $dstLen = $item.Length
            if ($srcLen -eq $dstLen) { $isHardlink = $true }
        }
    }

    if (-not $isReparse -and -not $isHardlink) {
        Write-Host "[skip] $Name (link 아님 — 실제 파일/폴더로 보임. 수동 확인 필요)" -ForegroundColor Yellow
        return
    }

    if ($item.PSIsContainer) {
        cmd /c rmdir "$path" | Out-Null
    } else {
        Remove-Item -LiteralPath $path -Force
    }
    Write-Host "[remove] $Name" -ForegroundColor Green
}

Remove-IfLink '.claude'
Remove-IfLink 'docs'
Remove-IfLink 'CLAUDE.md'

Write-Host ""
Write-Host "[harness] 제거 완료." -ForegroundColor Cyan
