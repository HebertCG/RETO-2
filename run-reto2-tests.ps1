# ============================================================================
# Script de Pruebas Automatizado - Reto 2 (Seguridad Zero-Trust)
# ============================================================================
# Este script ejecuta todas las pruebas de seguridad del Reto 2
# ============================================================================

param(
    [switch]$SkipCleanup = $false
)

$ErrorActionPreference = "Continue"
$testsPassed = 0
$testsFailed = 0

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "🧪 PRUEBAS DE SEGURIDAD - RETO 2" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# ----------------------------------------------------------------------------
# VERIFICACIÓN PREVIA
# ----------------------------------------------------------------------------
Write-Host "🔍 Verificando estado inicial del cluster..." -ForegroundColor Yellow
kubectl get pods -n tutorias

Write-Host "`nPresiona ENTER para continuar con las pruebas..." -ForegroundColor Yellow
Read-Host

# ============================================================================
# PRUEBA 1: SEALED SECRETS
# ============================================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "🔐 PRUEBA 1: SEALED SECRETS" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "📝 Objetivo: Verificar que los secretos están cifrados y funcionan`n" -ForegroundColor White

# 1.1 - Verificar que existen Sealed Secrets
Write-Host "🔹 Test 1.1: Verificar existencia de Sealed Secrets..." -ForegroundColor Yellow
$sealedSecrets = kubectl get sealedsecrets -n tutorias -o json 2>$null | ConvertFrom-Json
if ($sealedSecrets.items -and $sealedSecrets.items.Count -gt 0) {
    Write-Host "   ✅ PASS: Encontrados $($sealedSecrets.items.Count) Sealed Secrets" -ForegroundColor Green
    $testsPassed++
}
else {
    Write-Host "   ❌ FAIL: No se encontraron Sealed Secrets" -ForegroundColor Red
    $testsFailed++
}

# 1.2 - Verificar que los secretos se descifraron correctamente
Write-Host "`n🔹 Test 1.2: Verificar que los secretos se descifraron..." -ForegroundColor Yellow
$allSynced = $true
foreach ($secret in $sealedSecrets.items) {
    $synced = $false
    if ($secret.status.conditions) {
        foreach ($condition in $secret.status.conditions) {
            if ($condition.type -eq "Synced" -and $condition.status -eq "True") {
                $synced = $true
                break
            }
        }
    }
    
    if ($synced) {
        Write-Host "   ✅ $($secret.metadata.name): Descifrado correctamente" -ForegroundColor Green
    }
    else {
        Write-Host "   ❌ $($secret.metadata.name): Error al descifrar" -ForegroundColor Red
        $allSynced = $false
    }
}

if ($allSynced) {
    Write-Host "`n   ✅ PASS: Todos los Sealed Secrets están sincronizados" -ForegroundColor Green
    $testsPassed++
}
else {
    Write-Host "`n   ❌ FAIL: Algunos Sealed Secrets no se pudieron descifrar" -ForegroundColor Red
    $testsFailed++
}

# 1.3 - Verificar que la app tiene acceso a las credenciales
Write-Host "`n🔹 Test 1.3: Verificar acceso a credenciales desde la app..." -ForegroundColor Yellow
try {
    $dbPassword = kubectl exec -n tutorias deploy/ms-usuarios-deployment -- env 2>$null | Select-String "DB_PASSWORD"
    if ($dbPassword) {
        Write-Host "   ✅ PASS: La app tiene acceso a DB_PASSWORD" -ForegroundColor Green
        $testsPassed++
    }
    else {
        Write-Host "   ❌ FAIL: La app NO tiene acceso a DB_PASSWORD" -ForegroundColor Red
        $testsFailed++
    }
}
catch {
    Write-Host "   ❌ FAIL: Error al verificar credenciales: $($_.Exception.Message)" -ForegroundColor Red
    $testsFailed++
}

# ============================================================================
# PRUEBA 2: NETWORK POLICIES (Prueba de Acceso Denegado)
# ============================================================================
Write-Host "`n`n========================================" -ForegroundColor Cyan
Write-Host "🛡️  PRUEBA 2: NETWORK POLICIES" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "📝 Objetivo: Verificar que las Network Policies bloquean acceso no autorizado`n" -ForegroundColor White

# 2.1 - Crear pod "hacker"
Write-Host "🔹 Test 2.1: Creando pod 'hacker' para simular ataque..." -ForegroundColor Yellow
kubectl run hacker -n tutorias --image=curlimages/curl --restart=Never -- sleep 3600 2>$null
Start-Sleep -Seconds 10

$hackerPod = kubectl get pod hacker -n tutorias -o json 2>$null | ConvertFrom-Json
if ($hackerPod -and $hackerPod.status.phase -eq "Running") {
    Write-Host "   ✅ Pod 'hacker' creado y en ejecución" -ForegroundColor Green
}
else {
    Write-Host "   ⚠️  Pod 'hacker' no está listo, esperando..." -ForegroundColor Yellow
    Start-Sleep -Seconds 10
}

# 2.2 - Intentar acceder a la base de datos (debe fallar)
Write-Host "`n🔹 Test 2.2: Intento de ataque a DB Usuarios (puerto 5432)..." -ForegroundColor Yellow
Write-Host "   Esperado: TIMEOUT (conexión bloqueada por Network Policy)" -ForegroundColor White

$dbAttackBlocked = $false
try {
    $result = kubectl exec -n tutorias hacker -- timeout 5 sh -c "curl -v --connect-timeout 5 telnet://db-usuarios:5432" 2>&1
    if ($result -match "timeout|timed out|Connection timed out") {
        Write-Host "   ✅ PASS: Ataque a DB bloqueado (Timeout)" -ForegroundColor Green
        $dbAttackBlocked = $true
        $testsPassed++
    }
    else {
        Write-Host "   ❌ FAIL: Ataque a DB NO fue bloqueado" -ForegroundColor Red
        $testsFailed++
    }
}
catch {
    # Timeout es el comportamiento esperado
    if ($_.Exception.Message -match "timeout|timed out") {
        Write-Host "   ✅ PASS: Ataque a DB bloqueado (Timeout)" -ForegroundColor Green
        $dbAttackBlocked = $true
        $testsPassed++
    }
    else {
        Write-Host "   ❌ FAIL: Error inesperado: $($_.Exception.Message)" -ForegroundColor Red
        $testsFailed++
    }
}

# 2.3 - Intentar acceder a API privada (debe fallar)
Write-Host "`n🔹 Test 2.3: Intento de ataque a ms-usuarios (puerto 3001)..." -ForegroundColor Yellow
Write-Host "   Esperado: TIMEOUT (conexión bloqueada por Network Policy)" -ForegroundColor White

$apiAttackBlocked = $false
try {
    $result = kubectl exec -n tutorias hacker -- timeout 5 sh -c "curl -v --connect-timeout 5 http://ms-usuarios-service:3001" 2>&1
    if ($result -match "timeout|timed out|Connection timed out") {
        Write-Host "   ✅ PASS: Ataque a API bloqueado (Timeout)" -ForegroundColor Green
        $apiAttackBlocked = $true
        $testsPassed++
    }
    else {
        Write-Host "   ❌ FAIL: Ataque a API NO fue bloqueado" -ForegroundColor Red
        $testsFailed++
    }
}
catch {
    # Timeout es el comportamiento esperado
    if ($_.Exception.Message -match "timeout|timed out") {
        Write-Host "   ✅ PASS: Ataque a API bloqueado (Timeout)" -ForegroundColor Green
        $apiAttackBlocked = $true
        $testsPassed++
    }
    else {
        Write-Host "   ❌ FAIL: Error inesperado: $($_.Exception.Message)" -ForegroundColor Red
        $testsFailed++
    }
}

# Limpiar pod hacker
if (-not $SkipCleanup) {
    Write-Host "`n🧹 Limpiando pod 'hacker'..." -ForegroundColor Yellow
    kubectl delete pod hacker -n tutorias 2>$null
}

# ============================================================================
# PRUEBA 3: KONG RATE LIMITING (Protección DDoS)
# ============================================================================
Write-Host "`n`n========================================" -ForegroundColor Cyan
Write-Host "🚦 PRUEBA 3: KONG RATE LIMITING" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "📝 Objetivo: Verificar que Kong bloquea peticiones excesivas (DDoS)`n" -ForegroundColor White

# 3.1 - Verificar que Kong está disponible
Write-Host "🔹 Test 3.1: Verificando disponibilidad de Kong..." -ForegroundColor Yellow
$kongService = kubectl get svc -n argocd kong-kong-proxy -o json 2>$null | ConvertFrom-Json
if ($kongService) {
    Write-Host "   ✅ Kong proxy encontrado" -ForegroundColor Green
}
else {
    Write-Host "   ❌ Kong proxy NO encontrado" -ForegroundColor Red
    Write-Host "   Saltando pruebas de Rate Limiting..." -ForegroundColor Yellow
    $testsFailed++
}

# 3.2 - Iniciar port-forward en background
Write-Host "`n🔹 Test 3.2: Configurando port-forward a Kong..." -ForegroundColor Yellow
Write-Host "   Nota: Asegúrate de que NO haya otro port-forward activo en el puerto 8000" -ForegroundColor Yellow

# Matar cualquier port-forward existente
Get-Process | Where-Object { $_.ProcessName -eq "kubectl" -and $_.CommandLine -match "port-forward" } | Stop-Process -Force 2>$null

$portForwardJob = Start-Job -ScriptBlock {
    kubectl port-forward -n argocd service/kong-kong-proxy 8000:80
}

Start-Sleep -Seconds 5

# Verificar que el port-forward está activo
$portForwardActive = $false
try {
    $testConnection = Invoke-WebRequest -Uri "http://localhost:8000" -Method Get -TimeoutSec 2 -ErrorAction SilentlyContinue
    $portForwardActive = $true
    Write-Host "   ✅ Port-forward activo en puerto 8000" -ForegroundColor Green
}
catch {
    Write-Host "   ⚠️  Port-forward puede no estar listo, continuando..." -ForegroundColor Yellow
}

# 3.3 - Lanzar ataque de tráfico
Write-Host "`n🔹 Test 3.3: Lanzando ataque de tráfico (10 peticiones rápidas)..." -ForegroundColor Yellow
Write-Host "   Esperado: Primeras 5 pasan (200 OK), siguientes 5 bloqueadas (429)" -ForegroundColor White

$url = "http://localhost:8000/client/api/health"
$successCount = 0
$blockedCount = 0
$errorCount = 0

for ($i = 1; $i -le 10; $i++) {
    try {
        $response = Invoke-WebRequest -Uri $url -Method Get -ErrorAction Stop -TimeoutSec 5
        Write-Host "   Petición $i`: 200 OK (Pasó)" -ForegroundColor Green
        $successCount++
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 429) {
            Write-Host "   Petición $i`: 429 Too Many Requests (Bloqueado ✅)" -ForegroundColor Red
            $blockedCount++
        }
        else {
            Write-Host "   Petición $i`: Error - $($_.Exception.Message)" -ForegroundColor Yellow
            $errorCount++
        }
    }
    Start-Sleep -Milliseconds 100
}

Write-Host "`n   📊 Resultados:" -ForegroundColor White
Write-Host "      - Exitosas: $successCount" -ForegroundColor Green
Write-Host "      - Bloqueadas (429): $blockedCount" -ForegroundColor Red
Write-Host "      - Errores: $errorCount" -ForegroundColor Yellow

if ($blockedCount -gt 0) {
    Write-Host "`n   ✅ PASS: Kong Rate Limiting está funcionando" -ForegroundColor Green
    $testsPassed++
}
else {
    Write-Host "`n   ❌ FAIL: Kong NO bloqueó ninguna petición" -ForegroundColor Red
    $testsFailed++
}

# Detener port-forward
if ($portForwardJob) {
    Stop-Job -Job $portForwardJob 2>$null
    Remove-Job -Job $portForwardJob 2>$null
}

# ============================================================================
# PRUEBA 4: GIT SEGURO (Sin contraseñas planas)
# ============================================================================
Write-Host "`n`n========================================" -ForegroundColor Cyan
Write-Host "📁 PRUEBA 4: GIT SEGURO" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "📝 Objetivo: Verificar que no hay contraseñas planas en el repositorio`n" -ForegroundColor White

Write-Host "🔹 Test 4.1: Buscando contraseñas planas en archivos YAML..." -ForegroundColor Yellow

$plainPasswords = Get-ChildItem ./charts -Recurse -Filter "*.yaml" | Select-String "password:\s*['\"]?[^ { ]" | Where-Object { $_ -notmatch "secretKeyRef | valueFrom | #" }

    if ($plainPasswords) {
        Write-Host "   ❌ FAIL: Se encontraron posibles contraseñas planas:" -ForegroundColor Red
        $plainPasswords | ForEach-Object { Write-Host "      $_" -ForegroundColor Red }
        $testsFailed++
    } else {
        Write-Host "   ✅ PASS: No se encontraron contraseñas planas" -ForegroundColor Green
        $testsPassed++
    }

    # ============================================================================
    # RESUMEN FINAL
    # ============================================================================
    Write-Host "`n`n========================================" -ForegroundColor Cyan
    Write-Host "📊 RESUMEN DE PRUEBAS" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan

    $totalTests = $testsPassed + $testsFailed
    $successRate = if ($totalTests -gt 0) { [math]::Round(($testsPassed / $totalTests) * 100, 2) } else { 0 }

    Write-Host "Total de pruebas: $totalTests" -ForegroundColor White
    Write-Host "Pruebas exitosas: $testsPassed" -ForegroundColor Green
    Write-Host "Pruebas fallidas: $testsFailed" -ForegroundColor Red
    Write-Host "Tasa de éxito: $successRate%`n" -ForegroundColor $(if ($successRate -ge 80) { "Green" } else { "Yellow" })

    if ($testsFailed -eq 0) {
        Write-Host "🎉 ¡FELICIDADES! Todas las pruebas pasaron exitosamente" -ForegroundColor Green
        Write-Host "✅ Tu implementación de Zero-Trust está completa" -ForegroundColor Green
    }
    elseif ($successRate -ge 80) {
        Write-Host "⚠️  La mayoría de las pruebas pasaron, pero hay algunos problemas" -ForegroundColor Yellow
        Write-Host "Revisa los errores anteriores y vuelve a ejecutar" -ForegroundColor Yellow
    }
    else {
        Write-Host "❌ Varias pruebas fallaron" -ForegroundColor Red
        Write-Host "Ejecuta el script de diagnóstico para identificar problemas:" -ForegroundColor Yellow
        Write-Host ".\setup-reto2-tests.ps1" -ForegroundColor Cyan
    }

    Write-Host "`n========================================`n" -ForegroundColor Cyan
