#Requires -Version 5.0
<#
.SYNOPSIS
    Install Fun for the current user (or all users) on Windows.

.DESCRIPTION
    Run this from the extracted release archive. It copies the runtime tree,
    adds <Dir>\fun to PATH, registers .fun/.foo/.fxx file associations under
    HKCU (or HKLM with -AllUsers), and adds an entry to Apps & Features.

    No administrator rights are needed for the default per-user install.

.PARAMETER Dir
    Install directory. Default:
      per-user: %LOCALAPPDATA%\Programs\Fun
      -AllUsers: %ProgramFiles%\Fun

.PARAMETER AllUsers
    Install for every user. Requires an elevated PowerShell and writes the
    PATH value and file associations under HKLM.

.PARAMETER NoPath
    Do not add <Dir>\fun to PATH.

.PARAMETER NoAssoc
    Do not register .fun/.foo/.fxx file associations.

.PARAMETER NoUninstallEntry
    Do not add an Apps & Features entry.

.PARAMETER Portable
    Skip PATH, file associations and the uninstall entry. Useful for a
    shared/portable tree that is launched by full path.

.EXAMPLE
    .\install.cmd

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -AllUsers

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Dir D:\Fun -Portable
#>
[CmdletBinding()]
param(
    [string]$Dir,
    [switch]$AllUsers,
    [switch]$NoPath,
    [switch]$NoAssoc,
    [switch]$NoUninstallEntry,
    [switch]$Portable
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
$script:Scope = if ($AllUsers) { 'Machine' } else { 'User' }
$script:Hive = if ($AllUsers) { 'HKLM:' } else { 'HKCU:' }

function Write-Step([string]$Message) {
    Write-Host "install: $Message"
}

function Fail([string]$Message) {
    Write-Host "install: error: $Message" -ForegroundColor Red
    exit 1
}

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Normalize-Dir([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    # Keep a drive root ("C:\") intact.
    if ($full.Length -gt 3) { $full = $full.TrimEnd('\', '/') }
    return $full
}

function Set-RegValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$Name = '(default)',
        [Parameter(Mandatory = $true)][AllowEmptyString()][AllowNull()][object]$Value,
        [string]$Type = 'String'
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value `
        -PropertyType $Type -Force | Out-Null
}

function Broadcast-Change {
    try {
        if (-not ('FunInstaller.Native' -as [type])) {
            Add-Type -Namespace FunInstaller -Name Native -MemberDefinition @'
[DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam,
    string lParam, uint flags, uint timeout, out UIntPtr result);

[DllImport("shell32.dll", CharSet = CharSet.Auto)]
public static extern void SHChangeNotify(int eventId, uint flags, IntPtr item1, IntPtr item2);
'@
        }
        $result = [UIntPtr]::Zero
        [void][FunInstaller.Native]::SendMessageTimeout(
            [IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$result)
        [FunInstaller.Native]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)
    }
    catch {
        # The registry and PATH values are already written; Explorer will pick
        # them up on the next sign-in even when the broadcast is unavailable.
    }
}

function Add-PathEntry([string]$BinDir) {
    $current = [Environment]::GetEnvironmentVariable('Path', $script:Scope)
    if ($null -eq $current) { $current = '' }
    $target = $BinDir.TrimEnd('\', '/')
    foreach ($part in ($current -split ';')) {
        if ($part -and $part.TrimEnd('\', '/') -ieq $target) {
            Write-Step "PATH already contains $BinDir"
            return $false
        }
    }
    $new = if ($current.Length -eq 0) { $BinDir }
           elseif ($current.EndsWith(';')) { $current + $BinDir }
           else { $current + ';' + $BinDir }
    [Environment]::SetEnvironmentVariable('Path', $new, $script:Scope)
    Write-Step "added $BinDir to the $script:Scope PATH"
    return $true
}

function Register-Associations([string]$Exe) {
    $classes = "$script:Hive\Software\Classes"
    $progId = 'Fun.Script'
    $command = "`"$Exe`" `"%1`""

    Set-RegValue -Path "$classes\$progId" -Value 'Fun Script'
    Set-RegValue -Path "$classes\$progId\DefaultIcon" -Value "`"$Exe`",0"
    Set-RegValue -Path "$classes\$progId\shell\open\command" -Value $command

    # Also register the executable as an "Open with" candidate.
    Set-RegValue -Path "$classes\Applications\fun.exe" -Value 'Fun Script'
    Set-RegValue -Path "$classes\Applications\fun.exe\DefaultIcon" -Value "`"$Exe`",0"
    Set-RegValue -Path "$classes\Applications\fun.exe\shell\open\command" -Value $command
    $types = "$classes\Applications\fun.exe\SupportedTypes"
    if (-not (Test-Path -LiteralPath $types)) { New-Item -Path $types -Force | Out-Null }

    foreach ($ext in @('.fun', '.foo', '.fxx')) {
        $key = "$classes\$ext"
        if (-not (Test-Path -LiteralPath $key)) { New-Item -Path $key -Force | Out-Null }
        Set-RegValue -Path $key -Value $progId
        Set-RegValue -Path "$key\OpenWithProgids" -Name $progId -Value ''
        Set-RegValue -Path $types -Name $ext -Value ''
    }

    Write-Step 'registered .fun, .foo and .fxx with Fun (per-user choice may win)'
}

if ($Portable) {
    $NoPath = $true
    $NoAssoc = $true
    $NoUninstallEntry = $true
}

if (-not $Dir) {
    $Dir = if ($AllUsers) { Join-Path $env:ProgramFiles 'Fun' }
           else { Join-Path $env:LOCALAPPDATA 'Programs\Fun' }
}
$Dir = Normalize-Dir $Dir

if ($AllUsers -and -not (Test-Admin)) {
    Fail '-AllUsers needs an elevated PowerShell (Run as administrator)'
}

$Source = Join-Path $Here 'fun'
if (-not (Test-Path -LiteralPath (Join-Path $Source 'fun.exe'))) {
    Fail "fun\fun.exe was not found next to install.ps1. Extract the whole archive first."
}

$exe = Join-Path $Dir 'fun\fun.exe'
$bin = Join-Path $Dir 'fun'

$version = ''
$capsPath = Join-Path $Here 'capabilities.json'
if (Test-Path -LiteralPath $capsPath) {
    try {
        $caps = Get-Content -LiteralPath $capsPath -Raw | ConvertFrom-Json
        if ($caps.PSObject.Properties.Name -contains 'version') { $version = [string]$caps.version }
    }
    catch {
        Write-Step "warning: could not read capabilities.json ($($_.Exception.Message))"
    }
}

# Stage next to the target so the final swap stays on one volume. Copy only
# the files the archive is documented to contain; this also avoids recursing
# into a target directory the user may have placed inside the extraction tree.
$parent = Split-Path -Parent $Dir
if (-not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
}
$stage = Join-Path $parent ('.fun-install-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage -Force | Out-Null

$payload = @(
    'fun',
    'README.md', 'SAFETY.zh.md',
    'LICENSE', 'LICENSE.custom', 'LICENSE.dll',
    'capabilities.json', 'RUNNING.txt',
    'install.ps1', 'install.cmd', 'uninstall.ps1', 'uninstall.cmd'
)

$old = $null
try {
    foreach ($name in $payload) {
        $item = Join-Path $Here $name
        if (Test-Path -LiteralPath $item) {
            Copy-Item -LiteralPath $item -Destination $stage -Recurse -Force
        }
    }

    if (Test-Path -LiteralPath $Dir) {
        if (-not (Test-Path -LiteralPath $Dir -PathType Container)) {
            Fail "$Dir exists and is not a directory"
        }
        $old = Join-Path $parent ('.fun-old-' + [guid]::NewGuid().ToString('N'))
        try {
            Move-Item -LiteralPath $Dir -Destination $old -Force
        }
        catch {
            Write-Step "existing install is in use; updating in place"
            $old = $null
        }
    }

    if ($old) {
        try {
            Move-Item -LiteralPath $stage -Destination $Dir -Force
        }
        catch {
            # Never leave the user without a working installation just because
            # the final rename lost a race with antivirus or an open handle.
            if (-not (Test-Path -LiteralPath $Dir) -and (Test-Path -LiteralPath $old)) {
                try {
                    Move-Item -LiteralPath $old -Destination $Dir -Force
                }
                catch {
                    Write-Step "previous install preserved at $old"
                }
            }
            # Keep whatever remains of the backup: never delete it in finally
            # after a failed final rename.
            $old = $null
            throw
        }
    }
    else {
        if (Test-Path -LiteralPath $bin) {
            Remove-Item -LiteralPath $bin -Recurse -Force
        }
        foreach ($name in $payload) {
            $item = Join-Path $stage $name
            if (Test-Path -LiteralPath $item) {
                Copy-Item -LiteralPath $item -Destination $Dir -Recurse -Force
            }
        }
    }
}
finally {
    if (Test-Path -LiteralPath $stage) {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($old -and (Test-Path -LiteralPath $old)) {
        Remove-Item -LiteralPath $old -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if (-not (Test-Path -LiteralPath $exe)) {
    Fail "installation finished but $exe is missing"
}

# Prevent SmartScreen from blocking a freshly extracted script tree.
try {
    Get-ChildItem -LiteralPath $Dir -Recurse -File -ErrorAction SilentlyContinue |
        Unblock-File -ErrorAction SilentlyContinue
}
catch { }

if (-not $NoPath) {
    if (Add-PathEntry $bin) { Broadcast-Change }
}

if (-not $NoAssoc) {
    Register-Associations $exe
    Broadcast-Change
}

if (-not $NoUninstallEntry) {
    $uninstallRoot = "$script:Hive\Software\Microsoft\Windows\CurrentVersion\Uninstall"
    $uninstallKey = "$uninstallRoot\Fun"
    $uninstallScript = Join-Path $Dir 'uninstall.ps1'
    $uninstallCmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$uninstallScript`" -Dir `"$Dir`""
    if ($AllUsers) { $uninstallCmd += ' -AllUsers' }

    $sizeKb = 0
    try {
        $bytes = (Get-ChildItem -LiteralPath $Dir -Recurse -File |
                  Measure-Object -Property Length -Sum).Sum
        $sizeKb = [int][Math]::Ceiling($bytes / 1KB)
    }
    catch { }

    Set-RegValue -Path $uninstallKey -Name 'DisplayName' -Value 'Fun'
    Set-RegValue -Path $uninstallKey -Name 'DisplayVersion' `
        -Value $(if ($version) { $version } else { 'unknown' })
    Set-RegValue -Path $uninstallKey -Name 'Publisher' -Value 'Fun Language'
    Set-RegValue -Path $uninstallKey -Name 'URLInfoAbout' -Value 'https://funlang.org'
    Set-RegValue -Path $uninstallKey -Name 'InstallLocation' -Value $Dir
    Set-RegValue -Path $uninstallKey -Name 'DisplayIcon' -Value "`"$exe`",0"
    Set-RegValue -Path $uninstallKey -Name 'UninstallString' -Value $uninstallCmd
    Set-RegValue -Path $uninstallKey -Name 'QuietUninstallString' -Value $uninstallCmd
    Set-RegValue -Path $uninstallKey -Name 'NoModify' -Value 1 -Type DWord
    Set-RegValue -Path $uninstallKey -Name 'NoRepair' -Value 1 -Type DWord
    if ($sizeKb -gt 0) {
        Set-RegValue -Path $uninstallKey -Name 'EstimatedSize' -Value $sizeKb -Type DWord
    }
}

# App Paths lets Win+R and the Run dialog resolve "fun" without a full path.
if (-not $NoUninstallEntry) {
    $appPathKey = "$script:Hive\Software\Microsoft\Windows\CurrentVersion\App Paths\fun.exe"
    Set-RegValue -Path $appPathKey -Value $exe
    Set-RegValue -Path $appPathKey -Name 'Path' -Value $bin
}

Write-Host ''
$label = if ($version) { "Fun $version" } else { 'Fun' }
Write-Step "installed $label to $Dir"
Write-Step "binary: $exe"
if ($NoPath) {
    Write-Step 'PATH was not changed (-NoPath/-Portable)'
}
else {
    Write-Step 'open a new terminal to use "fun" from PATH'
}
if ($NoAssoc) {
    Write-Step 'file associations were not changed (-NoAssoc/-Portable)'
}
else {
    Write-Step 'double-click a .fun/.foo/.fxx script, or run: fun script.fun'
}
if (-not $NoUninstallEntry) {
    Write-Step "uninstall from Settings > Apps, or run: $Dir\uninstall.cmd"
}
Write-Step 'the binaries are unsigned; SmartScreen may ask for confirmation'
