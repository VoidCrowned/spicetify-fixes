# manage.ps1 - installs, updates or uninstalls spicetifyFixes.js.
# Called by install.cmd, update.cmd and uninstall.cmd in the repo root.
# Keep this file ASCII-only: Windows PowerShell 5.1 misreads BOM-less UTF-8.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Install', 'Update', 'Uninstall', 'LinkOnly')]
    [string]$Action,

    # Only for -Action LinkOnly: the link to create. The elevated prompt
    # can't ask Spicetify for it, because Spicetify refuses to run as admin.
    [string]$LinkPath
)

$ErrorActionPreference = 'Continue'

$FileName = 'spicetifyFixes.js'
$RepoDir = Split-Path -Parent $PSScriptRoot
$Source = Join-Path $RepoDir $FileName
$DocsUrl = 'https://spicetify.app/docs/getting-started'

# --- Output -------------------------------------------------------------------

function Write-Step([int]$Number, [int]$Total, [string]$Text) {
    Write-Host ''
    Write-Host "[$Number/$Total] $Text"
}

function Write-Ok([string]$Text) { Write-Host "  OK    $Text" -ForegroundColor Green }
function Write-Warn([string]$Text) { Write-Host "  WARN  $Text" -ForegroundColor Yellow }
function Write-Err([string]$Text) { Write-Host "  ERROR $Text" -ForegroundColor Red }
function Write-Info([string]$Text) { Write-Host "        $Text" }

function Stop-WithError([string]$Text, [string]$Next) {
    Write-Err $Text
    Write-Info "Next step: $Next"
    exit 1
}

# Returns $true for yes. An empty answer picks the default.
function Read-YesNo([string]$Question, [bool]$Default) {
    $hint = if ($Default) { '[Y/n]' } else { '[y/N]' }
    $answer = (Read-Host "$Question $hint").Trim()
    if ($answer -eq '') { return $Default }
    return $answer -match '^(y|yes)$'
}

# --- Checks -------------------------------------------------------------------

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal $identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-NotAdmin([string]$Wrapper) {
    if (Test-Admin) {
        Stop-WithError "Don't run this as administrator. Spicetify refuses to run as admin." "Double-click $Wrapper normally."
    }
}

function Test-Spicetify {
    return [bool](Get-Command spicetify -ErrorAction SilentlyContinue)
}

function Assert-Spicetify {
    if (-not (Test-Spicetify)) {
        Stop-WithError 'Spicetify was not found.' "Install Spicetify first: $DocsUrl . Then open a new window and try again."
    }
}

function Remove-Ansi([string]$Text) {
    return ($Text -replace "\x1b\[[0-9;]*m", '').Trim()
}

# With -Soft, returns $null instead of stopping when Spicetify gives no folder.
function Get-ExtensionsDir([switch]$NoCreate, [switch]$Soft) {
    $userData = $null
    foreach ($line in @(& spicetify path userdata)) {
        $candidate = Remove-Ansi $line
        if (-not $candidate) { continue }
        try {
            if (Test-Path -LiteralPath $candidate -PathType Container) { $userData = $candidate }
        } catch {
            # Not a path; Spicetify sometimes prints notices too.
        }
    }
    if (-not $userData) {
        if ($Soft) { return $null }
        Stop-WithError "'spicetify path userdata' didn't return a folder." "Run 'spicetify path userdata' in a terminal and check that Spicetify works: $DocsUrl"
    }
    $dir = Join-Path $userData 'Extensions'
    if (-not $NoCreate -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Info "Created $dir"
    }
    return $dir
}

# Where Spicetify keeps extensions by default, for when Spicetify can't tell us.
function Get-DefaultExtensionsDir {
    if ($env:SPICETIFY_CONFIG) { return Join-Path $env:SPICETIFY_CONFIG 'Extensions' }
    return Join-Path $env:APPDATA 'spicetify\Extensions'
}

# The names in Spicetify's extensions list, one per line of
# 'spicetify config extensions'.
function Get-SpicetifyExtensions {
    $names = @()
    foreach ($line in @(& spicetify config extensions)) {
        $name = Remove-Ansi $line
        if ($name) { $names += $name }
    }
    if ($LASTEXITCODE -ne 0) {
        Stop-WithError "'spicetify config extensions' failed (exit code $LASTEXITCODE)." "Run 'spicetify config extensions' in a terminal and read the message."
    }
    return $names
}

function Test-InSpicetifyList {
    return @(Get-SpicetifyExtensions) -contains $FileName
}

# --- Files and links ----------------------------------------------------------

function Test-SamePath([string]$A, [string]$B) {
    try {
        return [string]::Equals([IO.Path]::GetFullPath($A), [IO.Path]::GetFullPath($B), [StringComparison]::OrdinalIgnoreCase)
    } catch {
        return $false
    }
}

# Where a symlink points, as a full path, or $null.
function Get-LinkTarget([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -eq $item -or $item.LinkType -ne 'SymbolicLink') { return $null }
    $linkTarget = @($item.Target)[0]
    if ($linkTarget -and -not [IO.Path]::IsPathRooted($linkTarget)) {
        $linkTarget = Join-Path (Split-Path -Parent $Path) $linkTarget
    }
    return $linkTarget
}

# Returns missing, our-link, other-link, copy or folder.
function Get-TargetState([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) { return 'missing' }
    if ($item.LinkType -eq 'SymbolicLink') {
        $linkTarget = Get-LinkTarget $Path
        if ($linkTarget -and (Test-SamePath $linkTarget $Source)) { return 'our-link' }
        return 'other-link'
    }
    if ($item.PSIsContainer) { return 'folder' }
    return 'copy'
}

# Deletes the file or the link itself, never what a link points to,
# and never the repo's own spicetifyFixes.js.
function Remove-Target([string]$Path) {
    if (Test-SamePath $Path $Source) { throw "refusing to delete the repo's own $FileName" }
    [IO.File]::Delete($Path)
}

# Returns ok, privilege, or an error message.
function New-Link([string]$Path) {
    try {
        New-Item -ItemType SymbolicLink -Path $Path -Target $Source -ErrorAction Stop | Out-Null
        return 'ok'
    } catch {
        $elevation = $_.FullyQualifiedErrorId -like '*ElevationRequired*' -or $_.Exception -is [UnauthorizedAccessException]
        if (-not $elevation) { return $_.Exception.Message }
    }
    # Windows PowerShell 5.1 ignores Developer Mode for symlinks; mklink honours it.
    $null = & cmd.exe /d /c mklink $Path $Source 2>$null
    if ((Get-TargetState $Path) -eq 'our-link') { return 'ok' }
    return 'privilege'
}

function Copy-Fallback([string]$Path) {
    try {
        Copy-Item -LiteralPath $Source -Destination $Path -Force -ErrorAction Stop
    } catch {
        Stop-WithError "Couldn't copy $FileName to $Path : $($_.Exception.Message)" 'Close Spotify, then double-click install.cmd again.'
    }
    Write-Warn 'Copied instead of linked. Run update.cmd after every git pull so Spotify gets the new version.'
}

# --- Spicetify ----------------------------------------------------------------

function Invoke-Spicetify([string[]]$Arguments) {
    $exe = (Get-Command spicetify -ErrorAction SilentlyContinue).Source
    if ($exe -like '*.exe') {
        # Not Start-Process -Wait: in 5.1 it also waits for Spotify, which apply starts.
        $process = Start-Process -FilePath $exe -ArgumentList $Arguments -NoNewWindow -PassThru
        $null = $process.Handle
        $process.WaitForExit()
        return $process.ExitCode
    }
    & spicetify @Arguments | Out-Host
    return $LASTEXITCODE
}

# Stops on failure; with -Soft, returns $false instead.
function Invoke-Apply([switch]$Soft) {
    $code = Invoke-Spicetify @('apply')
    if ($code -eq 0) {
        Write-Ok 'Spicetify applied. Spotify restarts by itself.'
        return $true
    }
    Write-Warn "spicetify apply failed (exit code $code)."
    Write-Info 'Trying spicetify backup apply once (the usual fix after a Spotify update) ...'
    $code = Invoke-Spicetify @('backup', 'apply')
    if ($code -eq 0) {
        Write-Ok 'spicetify backup apply worked. Spotify restarts by itself.'
        return $true
    }
    $text = "spicetify backup apply failed too (exit code $code)."
    $next = "Read Spicetify's messages above. Often 'spicetify restore backup apply' in a terminal fixes it."
    if (-not $Soft) { Stop-WithError $text $next }
    Write-Err $text
    Write-Info "Next step: $next"
    return $false
}

# --- Actions ------------------------------------------------------------------

function Invoke-LinkOnly {
    if (-not $LinkPath) {
        Write-Err '-LinkPath is missing.'
        exit 1
    }
    $state = Get-TargetState $LinkPath
    if ($state -eq 'our-link') { exit 0 }
    if ($state -eq 'copy' -or $state -eq 'other-link') { Remove-Target $LinkPath }
    $result = New-Link $LinkPath
    if ($result -eq 'ok') {
        Write-Ok "Linked $LinkPath"
        exit 0
    }
    Write-Err "Couldn't create the link: $result"
    Start-Sleep -Seconds 5
    exit 1
}

function Invoke-Install {
    Assert-NotAdmin 'install.cmd'

    Write-Step 1 4 'Checking Spicetify ...'
    Assert-Spicetify
    $version = (@(& spicetify -v) | Select-Object -Last 1)
    Write-Ok "Spicetify $version found."

    Write-Step 2 4 "Linking $FileName ..."
    if (-not (Test-Path -LiteralPath $Source)) {
        Stop-WithError "$Source is missing." 'Clone the repo again: git clone https://github.com/VoidCrowned/spicetify-fixes'
    }
    $target = Join-Path (Get-ExtensionsDir) $FileName
    $state = Get-TargetState $target
    if ($state -eq 'our-link') {
        Write-Ok "Already linked: $target"
    } else {
        if ($state -eq 'folder') {
            Stop-WithError "$target is a folder." 'Delete or rename that folder, then double-click install.cmd again.'
        }
        if ($state -eq 'copy' -or $state -eq 'other-link') {
            try {
                Remove-Target $target
            } catch {
                Stop-WithError "Couldn't remove the old $target : $($_.Exception.Message)" 'Close Spotify, then double-click install.cmd again.'
            }
            Write-Info "Removed the old $FileName ($state)."
        }

        $result = New-Link $target
        if ($result -eq 'ok') {
            Write-Ok "Linked $target"
        } elseif ($result -eq 'privilege') {
            Write-Warn 'Creating a symlink needs Windows Developer Mode or admin rights.'
            Write-Info 'Developer Mode: Settings > System > For developers. Then no admin prompt is needed.'
            if (Read-YesNo '        Create the link with an admin prompt?' $true) {
                $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Action LinkOnly -LinkPath `"$target`""
                try {
                    Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -ArgumentList $arguments -ErrorAction Stop
                } catch {
                    Write-Warn 'The admin prompt was cancelled or failed.'
                }
            }
            if ((Get-TargetState $target) -eq 'our-link') {
                Write-Ok "Linked $target"
            } else {
                Copy-Fallback $target
            }
        } else {
            Write-Warn "Couldn't create the link: $result"
            Copy-Fallback $target
        }
    }

    Write-Step 3 4 "Adding $FileName to Spicetify's extensions ..."
    if (Test-InSpicetifyList) {
        Write-Ok "Already in Spicetify's list."
    } else {
        $code = Invoke-Spicetify @('config', 'extensions', $FileName)
        if ($code -ne 0) {
            Stop-WithError "spicetify config failed (exit code $code)." "Run 'spicetify config extensions $FileName' in a terminal and read the message."
        }
        if (-not (Test-InSpicetifyList)) {
            Stop-WithError "$FileName is still not in Spicetify's list." "Run 'spicetify config extensions $FileName' in a terminal, then 'spicetify config extensions' to check the list."
        }
        Write-Ok 'Added.'
    }

    Write-Step 4 4 'Running spicetify apply ...'
    $null = Invoke-Apply

    Write-Host ''
    Write-Host 'Done. To check it works:' -ForegroundColor Green
    Write-Info '1. Run: spicetify enable-devtools'
    Write-Info '2. In Spotify, press Ctrl+Shift+I and open the Console tab.'
    Write-Info '3. Type: __fixes.status()'
}

function Invoke-Update {
    Assert-NotAdmin 'update.cmd'

    Write-Step 1 3 'Getting the latest version ...'
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Warn 'Git was not found, so nothing was downloaded. Install Git from https://git-scm.com to update automatically.'
    } elseif (-not (Test-Path -LiteralPath (Join-Path $RepoDir '.git'))) {
        Write-Warn 'This folder is not a git clone, so nothing was downloaded. Clone the repo to update automatically.'
    } else {
        & git -C $RepoDir pull --ff-only | Out-Host
        if ($LASTEXITCODE -eq 0) {
            Write-Ok 'Up to date.'
        } else {
            Write-Warn "git pull failed (exit code $LASTEXITCODE). Continuing with the version you have."
            Write-Info "To see why, run in a terminal: git -C `"$RepoDir`" status"
        }
    }

    Write-Step 2 3 "Checking the installed $FileName ..."
    Assert-Spicetify
    $target = Join-Path (Get-ExtensionsDir) $FileName
    switch (Get-TargetState $target) {
        'our-link' { Write-Ok 'Linked, so it already uses the new version.' }
        'copy' {
            try {
                Copy-Item -LiteralPath $Source -Destination $target -Force -ErrorAction Stop
            } catch {
                Stop-WithError "Couldn't copy the new version: $($_.Exception.Message)" 'Close Spotify, then double-click update.cmd again.'
            }
            Write-Ok 'Copied the new version.'
        }
        'other-link' { Write-Warn "$target links to another folder. Left as it is. Double-click install.cmd to link this folder instead." }
        default { Stop-WithError "$FileName is not installed." 'Double-click install.cmd first.' }
    }

    Write-Step 3 3 'Running spicetify apply ...'
    $null = Invoke-Apply

    Write-Host ''
    Write-Host 'Done.' -ForegroundColor Green
}

# Warns when the repo folder has work that isn't on GitHub yet.
function Write-LocalChangesWarning {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return }
    if (-not (Test-Path -LiteralPath (Join-Path $RepoDir '.git'))) { return }
    $changes = @(& git -C $RepoDir status --porcelain 2>$null)
    $unpushed = 0
    $count = (& git -C $RepoDir rev-list --count '@{u}..HEAD' 2>$null | Select-Object -First 1)
    if ($LASTEXITCODE -eq 0) { [void][int]::TryParse([string]$count, [ref]$unpushed) }
    if ($changes.Count -eq 0 -and $unpushed -eq 0) { return }
    Write-Warn "This folder has local changes that aren't on GitHub."
    foreach ($line in ($changes | Select-Object -First 10)) { Write-Info $line }
    if ($changes.Count -gt 10) { Write-Info "... and $($changes.Count - 10) more." }
    if ($unpushed -gt 0) { Write-Info "$unpushed commit(s) not pushed." }
}

function Invoke-Uninstall {
    Assert-NotAdmin 'uninstall.cmd'

    Write-Host 'This removes spicetify-fixes from Spicetify:'
    Write-Info "- takes $FileName off Spicetify's extensions list"
    Write-Info "- deletes the installed $FileName (a link or a copy) from Spicetify's Extensions folder"
    Write-Info '- runs spicetify apply, so Spotify restarts'
    Write-Info "It doesn't touch Spicetify itself, other extensions, themes, or this folder."
    Write-Host ''
    if (-not (Read-YesNo 'Remove spicetify-fixes from Spicetify?' $true)) {
        Write-Host ''
        Write-Ok 'Stopped. Nothing was changed.'
        return
    }

    Write-Step 1 5 'Checking Spicetify ...'
    $hasSpicetify = Test-Spicetify
    $extDir = $null
    if ($hasSpicetify) {
        Write-Ok 'Spicetify found.'
        $extDir = Get-ExtensionsDir -NoCreate -Soft
    } else {
        Write-Warn "Spicetify was not found. Skipping its list and spicetify apply; only the file is removed."
    }
    if (-not $extDir) { $extDir = Get-DefaultExtensionsDir }
    Write-Info "Extensions folder: $extDir"
    $target = Join-Path $extDir $FileName

    Write-Step 2 5 "Removing $FileName from Spicetify's list ..."
    if (-not $hasSpicetify) {
        Write-Info 'Skipped (Spicetify not found).'
    } elseif (-not (Test-InSpicetifyList)) {
        Write-Ok "Not in Spicetify's list, nothing to remove."
    } else {
        $code = Invoke-Spicetify @('config', 'extensions', "$FileName-")
        if ($code -ne 0) {
            Write-Err "spicetify config failed (exit code $code)."
        } elseif (Test-InSpicetifyList) {
            Write-Err "$FileName is still in Spicetify's list."
        } else {
            Write-Ok "Removed from Spicetify's list."
        }
    }

    Write-Step 3 5 'Removing the installed file ...'
    $state = Get-TargetState $target
    if ($state -eq 'missing') {
        Write-Ok "No $FileName in $extDir, nothing to remove."
    } elseif ($state -eq 'folder') {
        Write-Warn "Not ours (folder): $target is a folder. Left as it is."
    } else {
        if ($state -eq 'other-link') { Write-Info "It linked to another clone: $(Get-LinkTarget $target)" }
        try {
            Remove-Target $target
            $label = if ($state -eq 'copy') { 'the old copy' } else { 'the link' }
            Write-Ok "Removed $label $target"
        } catch {
            Write-Err "Couldn't remove $target : $($_.Exception.Message)"
        }
    }

    Write-Step 4 5 'Running spicetify apply ...'
    $applied = $false
    if ($hasSpicetify) {
        $applied = Invoke-Apply -Soft
    } else {
        Write-Info 'Skipped (Spicetify not found).'
    }

    Write-Step 5 5 'Checking the result ...'
    $problems = 0
    if ($hasSpicetify) {
        if (Test-InSpicetifyList) {
            $problems++
            Write-Err "$FileName is still in Spicetify's list."
            Write-Info "Next step: run 'spicetify config extensions $FileName-', then 'spicetify apply'."
        } else {
            Write-Ok "$FileName is no longer in Spicetify's list."
        }
    }
    $state = Get-TargetState $target
    if ($state -eq 'missing') {
        Write-Ok "The file is gone from $extDir"
    } elseif ($state -eq 'folder') {
        Write-Warn "A folder named $FileName is still in $extDir. It isn't ours, so it was left."
    } else {
        $problems++
        Write-Err "$FileName is still in $extDir"
        Write-Info 'Next step: close Spotify and double-click uninstall.cmd again, or delete the file by hand.'
    }
    if ($hasSpicetify -and -not $applied) {
        $problems++
        Write-Err 'spicetify apply failed, so Spotify still runs the fixes until it works.'
        Write-Info "Next step: run 'spicetify apply' in a terminal and read the message."
    }

    Write-Host ''
    if ($problems -gt 0) {
        Write-Host 'Not finished. Fix the problems above, then double-click uninstall.cmd again.' -ForegroundColor Red
        exit 1
    }
    Write-Host 'Done. The fixes are off, so the bugs come back:' -ForegroundColor Green
    Write-Info "- With extension entries in the profile menu, the profile menu won't open."
    Write-Info '- Top-bar buttons from extensions and themes disappear.'
    Write-Info '- The Marketplace tab bar goes missing.'
    Write-Info 'Nothing of spicetify-fixes is left in Spicetify. Only this folder is still there.'

    Write-Host ''
    Write-LocalChangesWarning
    if (Read-YesNo 'Open this folder in Explorer so you can delete it?' $false) {
        Start-Process -FilePath 'explorer.exe' -ArgumentList "/select,`"$RepoDir`""
        Write-Info "Close this window, then delete the $(Split-Path -Leaf $RepoDir) folder."
    }
}

switch ($Action) {
    'Install' { Invoke-Install }
    'Update' { Invoke-Update }
    'Uninstall' { Invoke-Uninstall }
    'LinkOnly' { Invoke-LinkOnly }
}
exit 0
