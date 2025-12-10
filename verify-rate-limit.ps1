# verify-rate-limit.ps1
$url = "http://localhost:8000/client/test" 

Write-Host "Sending requests to $url..."

for ($i = 1; $i -le 10; $i++) {
    try {
        $response = Invoke-WebRequest -Uri $url -Method Get -ErrorAction Stop
        # Safer header access
        $headers = $response.Headers
        $remaining = if ($headers) { $headers["X-RateLimit-Remaining-Minute"] } else { "?" }
        Write-Host "Request $i : $($response.StatusCode) - OK (Remaining: $remaining)" -ForegroundColor Green
    }
    catch {
        $ex = $_.Exception
        $resp = $null
        if ($ex.Response) {
            $resp = $ex.Response
        }
        
        $statusCode = "Unknown"
        if ($resp) { 
            # Cast to int for comparison
            $statusCode = [int]$resp.StatusCode 
        }

        if ($statusCode -eq 429) {
            # Rate Limit Exceeded
            $remaining = "?"
            if ($resp.Headers) {
                $remaining = $resp.Headers["X-RateLimit-Remaining-Minute"]
            }
            Write-Host "Request $i : 429 - Rate Limit Exceeded (Remaining: $remaining)" -ForegroundColor Green -BackgroundColor DarkRed
        }
        elseif ($statusCode -eq 404) {
            # 404 means Kong let it through, but the app didn't find the page. 
            # For Rate Limiting test, this is a PASS (Access Allowed).
            $remaining = "?"
            if ($resp.Headers) {
                $remaining = $resp.Headers["X-RateLimit-Remaining-Minute"]
            }
            Write-Host "Request $i : 404 - Allowed (Not Found) (Remaining: $remaining)" -ForegroundColor Green
        }
        else {
            Write-Host "Request $i : Error $statusCode - $($ex.Message)" -ForegroundColor Red
        }
    }
    Start-Sleep -Milliseconds 200 
}
