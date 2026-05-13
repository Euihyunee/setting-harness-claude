<#
.SYNOPSIS
  claude-harness 를 대상 프로젝트 폴더에 link 한다.

.PARAMETER Target
  link 를 설치할 프로젝트 폴더 경로.

.EXAMPLE
  D:\claude-harness\install.ps1 -Target D:\hiaas\dinai
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Target
)

$ErrorActionPreference = 'Stop'

$HarnessRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Target = (Resolve-Path -LiteralPath $Target).Path

Write-Host "[harness] root   = $HarnessRoot" -ForegroundColor Cyan
Write-Host "[harness] target = $Target"      -ForegroundColor Cyan

# 같은 볼륨 여부 (hardlink 가능한지)
$harnessDrive = (Get-Item $HarnessRoot).PSDrive.Name
$targetDrive  = (Get-Item $Target).PSDrive.Name
$sameVolume   = ($harnessDrive -eq $targetDrive)

# 백업 폴더 (기존 파일 있을 경우)
$backupDir = $null

function Ensure-Backup {
    if (-not $script:backupDir) {
        $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
        $script:backupDir = Join-Path $Target ".harness-backup-$ts"
        New-Item -ItemType Directory -Force -Path $script:backupDir | Out-Null
        Write-Host "[harness] backup = $script:backupDir" -ForegroundColor Yellow
    }
}

function Install-Junction {
    param([string]$Name)
    $srcPath = Join-Path $HarnessRoot $Name
    $dstPath = Join-Path $Target     $Name

    if (-not (Test-Path -LiteralPath $srcPath)) {
        Write-Host "[skip] $Name (harness 에 존재하지 않음)" -ForegroundColor DarkGray
        return
    }

    if (Test-Path -LiteralPath $dstPath) {
        Ensure-Backup
        Write-Host "[backup] $Name -> $script:backupDir" -ForegroundColor Yellow
        Move-Item -LiteralPath $dstPath -Destination (Join-Path $script:backupDir $Name)
    }

    cmd /c mklink /J "$dstPath" "$srcPath" | Out-Null
    Write-Host "[link/J] $Name" -ForegroundColor Green
}

function Install-FileLink {
    param([string]$Name)
    $srcPath = Join-Path $HarnessRoot $Name
    $dstPath = Join-Path $Target     $Name

    if (-not (Test-Path -LiteralPath $srcPath)) {
        Write-Host "[skip] $Name (harness 에 존재하지 않음)" -ForegroundColor DarkGray
        return
    }

    if (Test-Path -LiteralPath $dstPath) {
        Ensure-Backup
        Write-Host "[backup] $Name -> $script:backupDir" -ForegroundColor Yellow
        Move-Item -LiteralPath $dstPath -Destination (Join-Path $script:backupDir $Name)
    }

    if ($sameVolume) {
        cmd /c mklink /H "$dstPath" "$srcPath" | Out-Null
        Write-Host "[link/H] $Name" -ForegroundColor Green
    } else {
        cmd /c mklink "$dstPath" "$srcPath" | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "[harness] symbolic link 생성 실패 — 개발자 모드 또는 관리자 권한이 필요할 수 있습니다."
        }
        Write-Host "[link/D] $Name (symbolic — 볼륨 다름)" -ForegroundColor Green
    }
}

Install-Junction '.claude'
Install-Junction 'docs'
Install-FileLink 'CLAUDE.md'

Write-Host ""
Write-Host "[harness] 설치 완료." -ForegroundColor Cyan
if ($script:backupDir) {
    Write-Host "[harness] 기존 파일 백업: $script:backupDir" -ForegroundColor Yellow
    Write-Host "          검증 후 수동으로 정리하세요." -ForegroundColor Yellow
}
