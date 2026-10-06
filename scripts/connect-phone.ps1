param([string]$DeviceId)
$ErrorActionPreference = 'Stop'
$adbPath = Join-Path $env:LOCALAPPDATA 'Android\sdk\platform-tools\adb.exe'
if (!(Test-Path -LiteralPath $adbPath)) { throw 'No se encontró adb en el SDK de Android.' }
if (!$DeviceId) {
    $devices = @(& $adbPath devices | Where-Object { $_ -match '^\S+\s+device$' } | ForEach-Object { ($_ -split '\s+')[0] })
    if ($devices.Count -ne 1) { throw 'Conecta y autoriza un celular, o indica -DeviceId si tienes varios.' }
    $DeviceId = $devices[0]
}
& $adbPath -s $DeviceId reverse tcp:8000 tcp:8000
if ($LASTEXITCODE -ne 0) { throw 'No se pudo establecer el enlace USB.' }
try {
    $result = Invoke-RestMethod -Uri 'http://127.0.0.1:8000/ready' -TimeoutSec 20
    Write-Output "Celular $DeviceId conectado. FastAPI: $($result.status)."
} catch {
    Write-Warning 'USB conectado, pero FastAPI o Supabase no están listos. Revisa backend/logs/server.log.'
}
