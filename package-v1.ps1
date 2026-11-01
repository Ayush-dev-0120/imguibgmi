param(
    [string]$Source = (Join-Path $PSScriptRoot 'libs\arm64-v8a\v1.so'),
    [string]$Destination = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
    throw "Source library not found: $Source"
}

$sevenZip = Get-Command 7z.exe, 7za.exe, 7z -ErrorAction SilentlyContinue |
    Select-Object -First 1 -ExpandProperty Source
if (-not $sevenZip) {
    $knownLocations = @(
        (Join-Path $env:ProgramFiles '7-Zip\7z.exe'),
        (Join-Path ${env:ProgramFiles(x86)} '7-Zip\7z.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\7-Zip\7z.exe')
    )
    $sevenZip = $knownLocations | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } |
        Select-Object -First 1
}
if (-not $sevenZip) {
    throw '7-Zip was not found. Install 7-Zip and rerun this script.'
}

New-Item -ItemType Directory -Path $Destination -Force | Out-Null
$archive = Join-Path $Destination 'v1.zip'
$temporaryArchive = Join-Path $Destination 'v1.pending.zip'
$workDirectory = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $workDirectory | Out-Null

try {
    Copy-Item -LiteralPath $Source -Destination (Join-Path $workDirectory 'v1.so')
    Push-Location $workDirectory
    try {
        & $sevenZip a -tzip -mem=AES256 '-pBabaTillu' $temporaryArchive 'v1.so' | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "7-Zip failed with exit code $LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }

    Move-Item -LiteralPath $temporaryArchive -Destination $archive -Force
}
finally {
    Remove-Item -LiteralPath $workDirectory, $temporaryArchive -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output "Created encrypted archive: $archive"
Write-Output 'Archive contains v1.so; the original source library remains unchanged.'

$git = Get-Command git.exe, git -ErrorAction SilentlyContinue |
    Select-Object -First 1 -ExpandProperty Source
if (-not $git) {
    throw 'The ZIP was created, but Git was not found.'
}

& $git -C $Destination add -- 'package-v1.ps1' 'v1.zip'
if ($LASTEXITCODE -ne 0) {
    throw "git add failed with exit code $LASTEXITCODE"
}

& $git -C $Destination diff --cached --quiet -- 'package-v1.ps1' 'v1.zip'
if ($LASTEXITCODE -eq 1) {
    & $git -C $Destination commit -m 'Add packaged v1 native library' -- 'package-v1.ps1' 'v1.zip'
    if ($LASTEXITCODE -ne 0) {
        throw "git commit failed with exit code $LASTEXITCODE"
    }
}
elseif ($LASTEXITCODE -ne 0) {
    throw "git diff failed with exit code $LASTEXITCODE"
}

& $git -C $Destination push origin HEAD
if ($LASTEXITCODE -ne 0) {
    throw "git push failed with exit code $LASTEXITCODE"
}

Write-Output 'Pushed the package script and v1.zip to origin.'
