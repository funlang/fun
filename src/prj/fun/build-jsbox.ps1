# ============================================================
# Fun - build fun-jsbox on Windows with MSVC.
#
# Usage (from a Visual Studio developer prompt):
#   powershell -ExecutionPolicy Bypass -File src\prj\fun\build-jsbox.ps1
#
# The script fetches QuickJS-ng v0.18.0 into src\3rd\quickjs-ng when needed
# and verifies the tarball SHA256. It builds the same four engine sources plus
# jsbox\main.c as the POSIX script, with no quickjs-libc.
# ============================================================
param(
    [string]$QjsSrc = "",
    [string]$Out = "",
    [string]$Obj = ""
)

$ErrorActionPreference = "Stop"

$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = (Resolve-Path (Join-Path $Here "..\..\..")).Path
$Third = Join-Path $Root "src\3rd"

$QjsVersion = "v0.18.0"
$QjsUrl = "https://github.com/quickjs-ng/quickjs/archive/refs/tags/$QjsVersion.tar.gz"
$QjsSha256 = "28bcd89aa3683fd2a946537e5ce3f11cc46b5cbf3383c7561aaef3df5ff9f1dd"

if (-not $QjsSrc) { $QjsSrc = Join-Path $Third "quickjs-ng" }
if (-not $Out) { $Out = Join-Path $Root "fun\fun-jsbox.exe" }
if (-not $Obj) { $Obj = Join-Path $Here ".jsbox-obj-win" }

function Find-Cl {
    $cmd = Get-Command cl.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw "cl.exe not found. Run this from a Visual Studio developer prompt."
}

function Fetch-QuickJS {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("fun-qjs-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    try {
        $archive = Join-Path $tmp "quickjs-ng.tar.gz"
        Write-Host "fetch   $QjsUrl"
        Invoke-WebRequest -UseBasicParsing -Uri $QjsUrl -OutFile $archive
        $actual = (Get-FileHash -Algorithm SHA256 -Path $archive).Hash.ToLowerInvariant()
        if ($actual -ne $QjsSha256) {
            throw "SHA256 mismatch for QuickJS-ng: expected $QjsSha256, got $actual"
        }
        Write-Host "extract $QjsVersion"
        tar -xzf $archive -C $tmp
        if ($LASTEXITCODE -ne 0) { throw "tar failed" }
        $src = Get-ChildItem -Path $tmp -Directory |
            Where-Object { Test-Path (Join-Path $_.FullName "quickjs.c") } |
            Select-Object -First 1
        if (-not $src) { throw "unexpected QuickJS-ng archive layout" }
        if (Test-Path $QjsSrc) { Remove-Item -Recurse -Force $QjsSrc }
        New-Item -ItemType Directory -Force -Path $Third | Out-Null
        Move-Item -Path $src.FullName -Destination $QjsSrc
        Write-Host "done    src\3rd\quickjs-ng"
    } finally {
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    }
}

if (-not (Test-Path (Join-Path $QjsSrc "quickjs.c"))) {
    if ($QjsSrc -ne (Join-Path $Third "quickjs-ng")) {
        throw "QjsSrc=$QjsSrc does not contain quickjs.c"
    }
    Fetch-QuickJS
}

$cl = Find-Cl
New-Item -ItemType Directory -Force -Path $Obj | Out-Null
$OutDir = Split-Path -Parent $Out
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$Define = @(
    "/D_CRT_SECURE_NO_WARNINGS",
    "/D_CRT_NONSTDC_NO_DEPRECATE",
    "/D_GNU_SOURCE"
)
$Flags = @(
    "/nologo", "/c", "/O2", "/W3", "/std:c11", "/experimental:c11atomics"
) + $Define + @("/I$QjsSrc")

$Sources = @(
    (Join-Path $QjsSrc "quickjs.c"),
    (Join-Path $QjsSrc "libregexp.c"),
    (Join-Path $QjsSrc "libunicode.c"),
    (Join-Path $QjsSrc "dtoa.c"),
    (Join-Path $Here "jsbox\main.c")
)

$Objs = @()
Write-Host "Building fun-jsbox from $QjsSrc"
foreach ($src in $Sources) {
    $name = [IO.Path]::GetFileNameWithoutExtension($src)
    $obj = Join-Path $Obj "$name.obj"
    Write-Host "  cc    $name.c"
    & $cl @Flags "/Fo$obj" $src
    if ($LASTEXITCODE -ne 0) { throw "compile failed: $src" }
    $Objs += $obj
}

Write-Host "  link  $Out"
$link = Get-Command link.exe -ErrorAction SilentlyContinue
if (-not $link) { throw "link.exe not found" }
& $link.Source /nologo /OUT:"$Out" /STACK:8388608 @Objs
if ($LASTEXITCODE -ne 0) { throw "link failed" }
Write-Host "built $Out"
