$url = "http://localhost:9000/client/api/health"
Write-Host "`nPrueba 2: DDoS - Kong Rate Limiting`n" -ForegroundColor Cyan

for ($i = 1; $i -le 10; $i++) {
    try {
        $response = Invoke-WebRequest -Uri $url -Method Get -ErrorAction Stop -TimeoutSec 5
        Write-Host "Peticion $i : $($response.StatusCode) OK" -ForegroundColor Green
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 429) {
            Write-Host "Peticion $i : 429 BLOQUEADO" -ForegroundColor Red
        }
        else {
            Write-Host "Peticion $i : Error - $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    Start-Sleep -Milliseconds 100
}

Write-Host "`nPrueba completada`n" -ForegroundColor Cyan
