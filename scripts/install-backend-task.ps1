$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$pythonPath = Join-Path $projectRoot 'backend\.venv\Scripts\pythonw.exe'
$runnerPath = Join-Path $projectRoot 'backend\run_server.py'
if (!(Test-Path -LiteralPath $pythonPath)) { throw 'Falta el entorno Python backend/.venv.' }
$taskName = 'Trujillo360-FastAPI'
$account = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing -and $existing.Description -ne 'Servidor local administrado de Trujillo 360') {
    throw 'Ya existe una tarea con ese nombre y otro propietario. No se modificó.'
}
$action = New-ScheduledTaskAction -Execute $pythonPath -Argument ('"' + $runnerPath + '"') -WorkingDirectory (Join-Path $projectRoot 'backend')
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $account
$principal = New-ScheduledTaskPrincipal -UserId $account -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'Servidor local administrado de Trujillo 360' -Force | Out-Null
Start-ScheduledTask -TaskName $taskName
Write-Output 'Tarea Trujillo360-FastAPI instalada e iniciada. Arrancará al iniciar sesión en Windows.'
