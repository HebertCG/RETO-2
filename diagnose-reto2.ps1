# Script de Diagnóstico - Reto 2
# Escanea el proyecto e identifica problemas

Write-Host ""
Write-Host "========================================"
Write-Host "DIAGNOSTICO DEL PROYECTO - RETO 2"
Write-Host "========================================"
Write-Host ""

# PASO 1: Verificar Estado del Cluster
Write-Host "PASO 1: Verificando estado del cluster..."
Write-Host ""

Write-Host "Pods en namespace 'tutorias':"
kubectl get pods -n tutorias
Write-Host ""

Write-Host "Sealed Secrets:"
kubectl get sealedsecrets -n tutorias
Write-Host ""

Write-Host "Network Policies:"
kubectl get networkpolicies -n tutorias
Write-Host ""

Write-Host "Controlador de Sealed Secrets:"
kubectl get pods -n kube-system | Select-String "sealed"
Write-Host ""

Write-Host "Kong Proxy:"
kubectl get svc -n argocd | Select-String "kong"
Write-Host ""

# PASO 2: Identificar Problemas
Write-Host ""
Write-Host "========================================"
Write-Host "PASO 2: Identificando problemas..."
Write-Host "========================================"
Write-Host ""

$issues = @()

# Verificar Sealed Secrets
$sealedSecrets = kubectl get sealedsecrets -n tutorias -o json 2>$null | ConvertFrom-Json
if ($sealedSecrets.items) {
    foreach ($secret in $sealedSecrets.items) {
        if ($secret.status.conditions) {
            foreach ($condition in $secret.status.conditions) {
                if ($condition.type -eq "Synced" -and $condition.status -eq "False") {
                    $issues += "Sealed Secret '$($secret.metadata.name)' no se puede descifrar"
                }
            }
        }
    }
}

# Verificar Pods
$pods = kubectl get pods -n tutorias -o json 2>$null | ConvertFrom-Json
if ($pods.items) {
    $failedPods = $pods.items | Where-Object { $_.status.phase -ne "Running" }
    if ($failedPods) {
        $issues += "Hay $($failedPods.Count) pods que no estan en estado Running"
    }
}

# Mostrar problemas encontrados
if ($issues.Count -gt 0) {
    Write-Host "PROBLEMAS ENCONTRADOS:" -ForegroundColor Red
    foreach ($issue in $issues) {
        Write-Host "  - $issue" -ForegroundColor Red
    }
}
else {
    Write-Host "No se encontraron problemas criticos" -ForegroundColor Green
}
Write-Host ""

# PASO 3: Análisis de Sealed Secrets
Write-Host ""
Write-Host "========================================"
Write-Host "PASO 3: Analizando Sealed Secrets..."
Write-Host "========================================"
Write-Host ""

Write-Host "Verificando namespace en archivos de Sealed Secrets..."
Write-Host ""

$sealedSecretFiles = Get-ChildItem -Path "kubernetes-manifests" -Filter "*sealed*.yaml"
foreach ($file in $sealedSecretFiles) {
    Write-Host "Archivo: $($file.Name)"
    $content = Get-Content $file.FullName -Raw
    if ($content -match "namespace:\s*(\w+)") {
        $namespace = $matches[1]
        if ($namespace -eq "default") {
            Write-Host "  Namespace: $namespace (INCORRECTO - deberia ser 'tutorias')" -ForegroundColor Red
        }
        else {
            Write-Host "  Namespace: $namespace (OK)" -ForegroundColor Green
        }
    }
}
Write-Host ""

# PASO 4: Verificar Network Policies
Write-Host ""
Write-Host "========================================"
Write-Host "PASO 4: Verificando Network Policies..."
Write-Host "========================================"
Write-Host ""

$networkPolicies = kubectl get networkpolicies -n tutorias -o json 2>$null | ConvertFrom-Json
if ($networkPolicies.items -and $networkPolicies.items.Count -gt 0) {
    Write-Host "Network Policies configuradas: $($networkPolicies.items.Count)" -ForegroundColor Green
    foreach ($policy in $networkPolicies.items) {
        Write-Host "  - $($policy.metadata.name)"
    }
}
else {
    Write-Host "No se encontraron Network Policies" -ForegroundColor Red
}
Write-Host ""

# PASO 5: Verificar Kong Rate Limiting
Write-Host ""
Write-Host "========================================"
Write-Host "PASO 5: Verificando Kong Rate Limiting..."
Write-Host "========================================"
Write-Host ""

$kongPlugins = kubectl get kongplugins -n tutorias 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "Kong plugins encontrados:" -ForegroundColor Green
    kubectl get kongplugins -n tutorias
}
else {
    Write-Host "No se encontraron Kong plugins o CRD no instalado" -ForegroundColor Yellow
}
Write-Host ""

# RESUMEN Y RECOMENDACIONES
Write-Host ""
Write-Host "========================================"
Write-Host "RESUMEN Y RECOMENDACIONES"
Write-Host "========================================"
Write-Host ""

Write-Host "ACCIONES RECOMENDADAS:" -ForegroundColor Yellow
Write-Host ""

# Verificar si hay problemas con Sealed Secrets
$sealedSecretsOk = $true
if ($sealedSecrets.items) {
    foreach ($secret in $sealedSecrets.items) {
        if ($secret.status.conditions) {
            foreach ($condition in $secret.status.conditions) {
                if ($condition.type -eq "Synced" -and $condition.status -eq "False") {
                    $sealedSecretsOk = $false
                    break
                }
            }
        }
    }
}

if (-not $sealedSecretsOk) {
    Write-Host "1. REGENERAR SEALED SECRETS:" -ForegroundColor Red
    Write-Host "   Los Sealed Secrets no se pueden descifrar."
    Write-Host "   Esto puede deberse a:"
    Write-Host "   - Namespace incorrecto (default vs tutorias)"
    Write-Host "   - Certificado desactualizado"
    Write-Host "   - Cluster reiniciado con nueva clave"
    Write-Host ""
    Write-Host "   Solucion: Ejecutar script de regeneracion de secrets"
    Write-Host "   powershell -ExecutionPolicy Bypass -File .\regenerate-sealed-secrets.ps1"
    Write-Host ""
}

Write-Host "2. EJECUTAR PRUEBAS:" -ForegroundColor Green
Write-Host "   Una vez resueltos los problemas, ejecutar:"
Write-Host "   powershell -ExecutionPolicy Bypass -File .\run-reto2-tests.ps1"
Write-Host ""

Write-Host "3. DOCUMENTACION:" -ForegroundColor Green
Write-Host "   Ver guia completa de pruebas en:"
Write-Host "   RETO2_Y_RETO7_PRUEBAS.md"
Write-Host ""

Write-Host "========================================"
Write-Host "DIAGNOSTICO COMPLETADO"
Write-Host "========================================"
Write-Host ""
