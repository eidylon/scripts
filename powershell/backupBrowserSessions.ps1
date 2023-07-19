
Add-Type -assembly "system.io.compression.filesystem"

$now = "{0:yyyyMMdd.HHmmss}" -f (Get-Date)

function processBrowser ($srcdir, $backupdir) {
    if (-not (Test-Path $backupdir)) { New-Item -Path $backupdir -ItemType Directory }
 
    $zip = [system.io.path]::Combine($backupdir, "session." + $now + ".zip")
    [system.io.compression.zipfile]::CreateFromDirectory($srcdir, $zip)

    $zips = [system.io.path]::Combine($backupdir, "*.zip")
    Get-ChildItem $zips | Sort-Object CreationTime -Descending | Select-Object -Skip 5 | Remove-Item -Force    
}

$srcdir = "$env:APPDATA\Mozilla\Firefox\Profiles\jg8nw3rp.default\sessionstore-backups"
$backupdir = "$PSScriptRoot\Firefox"
processBrowser $srcdir $backupdir
"Backed up Firefox"
""

$srcdir = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Sessions"
$backupdir = "$PSScriptRoot\Edge"
processBrowser $srcdir $backupdir
"Backed up Edge"
""

""
