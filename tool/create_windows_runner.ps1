$ErrorActionPreference = 'Stop'

if (Test-Path (Join-Path $PSScriptRoot '..\windows\CMakeLists.txt')) {
  Write-Host 'Windows runner already exists; keeping the checked-in runner.'
  exit 0
}

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$tempRoot = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { $env:TEMP }
$tempProject = Join-Path $tempRoot 'huawei_modem_manager_windows_scaffold'

if (Test-Path $tempProject) {
  Remove-Item $tempProject -Recurse -Force
}

try {
  flutter create `
    --template=app `
    --platforms=windows `
    --project-name=huawei_modem_manager `
    --org=ru.huaweimodem `
    $tempProject

  $generatedWindows = Join-Path $tempProject 'windows'
  if (!(Test-Path (Join-Path $generatedWindows 'CMakeLists.txt'))) {
    throw 'Flutter did not create the Windows CMake project.'
  }

  Copy-Item -Path $generatedWindows -Destination (Join-Path $projectRoot 'windows') -Recurse -Force
  $appIconSrc = Join-Path $projectRoot 'assets\app_icon.ico'
  $appIconDst = Join-Path $projectRoot 'windows\runner\resources\app_icon.ico'
  if ((Test-Path $appIconSrc) -and (Test-Path (Split-Path $appIconDst))) {
    Copy-Item -Path $appIconSrc -Destination $appIconDst -Force
  }
  Write-Host 'Windows runner scaffold created.'
}
finally {
  if (Test-Path $tempProject) {
    Remove-Item $tempProject -Recurse -Force
  }
}
