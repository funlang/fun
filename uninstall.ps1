#Requires -Version 5.0
<#
.SYNOPSIS
    Uninstall Fun on Windows.

.DESCRIPTION
    Removes the PATH entry and file associations added by install.ps1, the
    Apps & Features entry, and (by default) the installed files.

.PARAMETER Dir
    Install directory. Default matches install.ps1:
      per-user: %LOCALAPPDATA%\Programs\Fun
      -AllUsers: %ProgramFiles%\Fun

.PARAMETER AllUsers
    Remove an all-users installation. Requires an elevated PowerShell.

.PARAMETER KeepFiles
    Remove registry entries and PATH but leave the files in place.

.PARAMETER Force
    Delete the directory even when it does not look like a Fun install.
#>
[CmdletBinding()]
param(
    [string]$Dir,
    [switch]$AllUsers,
    [switch]$KeepFiles,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Scope = if ($AllUsers) { 'Machine' } else { 'User' }
$script:Hive = if ($AllUsers) { 'HKLM:' } else { 'HKCU:' }

function Write-Step([string]$Message) {
    Write-Host "uninstall: $Message"
}

function Fail([string]$Message) {
    Write-Host "uninstall: error: $Message" -ForegroundColor Red
    exit 1
}

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Normalize-Dir([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    if ($full.Length -gt 3) { $full = $full.TrimEnd('\', '/') }
    return $full
}

function Remove-PathEntry([string]$BinDir) {
    $current = [Environment]::GetEnvironmentVariable('Path', $script:Scope)
    if ($null -eq $current -or $current.Length -eq 0) { return $false }
    $target = $BinDir.TrimEnd('\', '/')
    $kept = @()
    $removed = $false
    foreach ($part in ($current -split ';')) {
        if ($part -and $part.TrimEnd('\', '/') -ieq $target) {
            $removed = $true
        }
        elseif ($part) {
            $kept += $part
        }
    }
    if ($removed) {
        [Environment]::SetEnvironmentVariable('Path', ($kept -join ';'), $script:Scope)
    }
    return $removed
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
    catch { }
}

function Remove-RegistryKey([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if (-not $Dir) {
    $Dir = if ($AllUsers) { Join-Path $env:ProgramFiles 'Fun' }
           else { Join-Path $env:LOCALAPPDATA 'Programs\Fun' }
}
$Dir = Normalize-Dir $Dir

if ($AllUsers -and -not (Test-Admin)) {
    Fail '-AllUsers needs an elevated PowerShell (Run as administrator)'
}
if ($Dir.Length -le 3) {
    Fail "refusing to use '$Dir' as an install directory"
}

$bin = Join-Path $Dir 'fun'

if (Remove-PathEntry $bin) {
    Write-Step "removed $bin from the $script:Scope PATH"
    Broadcast-Change
}

foreach ($ext in @('.fun', '.foo', '.fxx')) {
    $key = "$script:Hive\Software\Classes\$ext"
    if (Test-Path -LiteralPath $key) {
        $props = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
        $default = if ($null -ne $props -and
                       $props.PSObject.Properties.Name -contains '(default)') {
            [string]$props.'(default)'
        } else { '' }
        if ($default -eq 'Fun.Script') {
            Set-ItemProperty -LiteralPath $key -Name '(default)' -Value ''
        }
        $with = "$key\OpenWithProgids"
        if (Test-Path -LiteralPath $with) {
            Remove-ItemProperty -LiteralPath $with -Name 'Fun.Script' -ErrorAction SilentlyContinue
        }
    }
}
Remove-RegistryKey "$script:Hive\Software\Classes\Fun.Script"
Remove-RegistryKey "$script:Hive\Software\Classes\Applications\fun.exe"
Remove-RegistryKey "$script:Hive\Software\Microsoft\Windows\CurrentVersion\App Paths\fun.exe"
Remove-RegistryKey "$script:Hive\Software\Microsoft\Windows\CurrentVersion\Uninstall\Fun"
Write-Step 'removed file associations and the Apps & Features entry'

if (-not $KeepFiles) {
    $looksLikeFun = (Test-Path -LiteralPath (Join-Path $Dir 'fun\fun.exe')) -or
                    (Test-Path -LiteralPath (Join-Path $Dir 'capabilities.json'))
    if (-not $looksLikeFun -and -not $Force) {
        Write-Step "warning: $Dir does not look like a Fun install; files were kept"
        Write-Step 're-run with -Force to delete it anyway'
    }
    elseif (Test-Path -LiteralPath $Dir) {
        # Do not hold the current directory inside the tree we are deleting.
        Set-Location -LiteralPath $env:TEMP -ErrorAction SilentlyContinue
        $removed = $false
        for ($i = 0; $i -lt 5 -and -not $removed; $i++) {
            try {
                Remove-Item -LiteralPath $Dir -Recurse -Force
                $removed = $true
            }
            catch {
                Start-Sleep -Milliseconds 400
            }
        }
        if ($removed) {
            Write-Step "removed $Dir"
        }
        else {
            Write-Step "warning: could not remove $Dir completely (a file may be in use)"
            Write-Step 'close any running fun process, then delete the directory manually'
        }
    }
    else {
        Write-Step "$Dir is already gone"
    }
}

Write-Step 'done'
