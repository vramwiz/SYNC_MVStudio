$ErrorActionPreference = 'Stop'

$packageName = 'SYNC_MVStudio'
$projectDir = Split-Path -Parent $PSScriptRoot
$pluginDir = 'C:\ProgramData\aviutl2\Plugin\SYNC_MVStudio'
$stagingRoot = Join-Path $PSScriptRoot ('.release-' + [guid]::NewGuid().ToString('N'))
$workDir = Join-Path $stagingRoot $packageName
$zipFile = Join-Path $PSScriptRoot "$packageName.zip"
$pendingZip = Join-Path $PSScriptRoot ('.release-' + [guid]::NewGuid().ToString('N') + '.zip')

$packageFiles = @(
  @{ Source = Join-Path $pluginDir 'SYNC_MVStudio_Filter.auf2'; Destination = 'SYNC_MVStudio_Filter.auf2' },
  @{ Source = Join-Path $pluginDir 'sk4d.dll'; Destination = 'sk4d.dll' },
  @{ Source = Join-Path $projectDir 'LICENSE'; Destination = 'LICENSE' },
  @{ Source = Join-Path $projectDir 'README.md'; Destination = 'README.md' },
  @{ Source = Join-Path $projectDir 'THIRD_PARTY_NOTICES.md'; Destination = 'THIRD_PARTY_NOTICES.md' }
)
foreach ($item in $packageFiles) {
  if (-not (Test-Path -LiteralPath $item.Source -PathType Leaf)) {
    throw "Required release file not found: $($item.Source)"
  }
}

$filterPlugin = Join-Path $pluginDir 'SYNC_MVStudio_Filter.auf2'
$unfinishedBuild = Join-Path $pluginDir 'SYNC_MVStudio_Filter.dll'
if ((Test-Path -LiteralPath $unfinishedBuild -PathType Leaf) -and
    ((Get-Item -LiteralPath $unfinishedBuild).LastWriteTimeUtc -gt
     (Get-Item -LiteralPath $filterPlugin).LastWriteTimeUtc)) {
  throw 'The Release DLL is newer than the deployed .auf2. Close AviUtl2 and finish the Release build before packaging.'
}

try {
  New-Item -ItemType Directory -Path $workDir | Out-Null
  foreach ($item in $packageFiles) {
    $destination = Join-Path $workDir $item.Destination
    $destinationDir = Split-Path -Parent $destination
    New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
    Copy-Item -LiteralPath $item.Source -Destination $destination
  }

  Compress-Archive -LiteralPath $workDir -DestinationPath $pendingZip -CompressionLevel Optimal
  if (Test-Path -LiteralPath $zipFile) {
    Remove-Item -LiteralPath $zipFile -Force
  }
  Move-Item -LiteralPath $pendingZip -Destination $zipFile
}
finally {
  if (Test-Path -LiteralPath $stagingRoot) {
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force
  }
  if (Test-Path -LiteralPath $pendingZip) {
    Remove-Item -LiteralPath $pendingZip -Force
  }
}

Write-Host "Created: $zipFile"
