param([ValidateRange(1024,65535)][int]$Port = 8001)
$ErrorActionPreference = 'Stop'
$backendRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../backend')).Path
$pythonExe = Join-Path $backendRoot '.venv/Scripts/python.exe'
if (!(Test-Path -LiteralPath $pythonExe)) { throw 'Falta el entorno Python del backend.' }
$logsRoot = Join-Path $backendRoot 'logs'
New-Item -ItemType Directory -Path $logsRoot -Force | Out-Null
$running = $false
try {
    Invoke-WebRequest -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 2 | Out-Null
    $running = $true
} catch {
    if ($_.Exception.Response) { $running = $true }
}
if (!$running) {
    Start-Process -FilePath $pythonExe -ArgumentList @('-m','uvicorn','app.main:app','--host','127.0.0.1','--port',"$Port") -WorkingDirectory $backendRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $logsRoot 'workflows-out.log') -RedirectStandardError (Join-Path $logsRoot 'workflows-error.log') | Out-Null
}
for ($attempt = 0; $attempt -lt 10; $attempt++) {
    try {
        $ready = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/ready" -TimeoutSec 5
        if ($ready.workflow_version -ne 1) { throw 'El servidor conectado no tiene la ampliación de operadores.' }
        Write-Output "Backend listo en localhost:$Port. Conecta el celular con connect-phone.ps1 -Port $Port."
        exit 0
    } catch {
        if ($attempt -eq 9) { throw 'El backend no quedó listo. Revisa los registros workflows-error.log y la conexión a Supabase.' }
        Start-Sleep -Seconds 2
    }
}
