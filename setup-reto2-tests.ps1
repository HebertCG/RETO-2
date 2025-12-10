# ============================================================================
# Script de Configuración y Diagnóstico para Pruebas de Reto 2
# ============================================================================
# Este script escanea el proyecto, identifica problemas y configura todo
# para ejecutar las pruebas de seguridad Zero-Trust del Reto 2.
# ============================================================================

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "🔍 DIAGNÓSTICO DEL PROYECTO - RETO 2" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# ----------------------------------------------------------------------------
# PASO 1: Verificar Estado del Cluster
# ----------------------------------------------------------------------------
Write-Host "📊 PASO 1: Verificando estado del cluster..." -ForegroundColor Yellow

Write-Host "`n🔹 Pods en namespace 'tutorias':" -ForegroundColor White
kubectl get pods -n tutorias

Write-Host "`n🔹 Sealed Secrets:" -ForegroundColor White
kubectl get sealedsecrets -n tutorias

Write-Host "`n🔹 Network Policies:" -ForegroundColor White
kubectl get networkpolicies -n tutorias

Write-Host "`n🔹 Controlador de Sealed Secrets:" -ForegroundColor White
kubectl get pods -n kube-system | Select-String "sealed"

Write-Host "`n🔹 Kong Proxy:" -ForegroundColor White
kubectl get svc -n argocd | Select-String "kong"

# ----------------------------------------------------------------------------
# PASO 2: Identificar Problemas
# ----------------------------------------------------------------------------
Write-Host "`n`n========================================" -ForegroundColor Cyan
Write-Host "🔍 PASO 2: Identificando problemas..." -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$issues = @()

# Verificar Sealed Secrets
$sealedSecrets = kubectl get sealedsecrets -n tutorias -o json 2>$null | ConvertFrom-Json
if ($sealedSecrets.items) {
    foreach ($secret in $sealedSecrets.items) {
        if ($secret.status.conditions) {
            foreach ($condition in $secret.status.conditions) {
                if ($condition.type -eq "Synced" -and $condition.status -eq "False") {
                    $issues += "❌ Sealed Secret '$($secret.metadata.name)' no se puede descifrar: $($condition.message)"
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
        $issues += "❌ Hay $($failedPods.Count) pods que no están en estado Running"
    }
}

# Mostrar problemas encontrados
if ($issues.Count -gt 0) {
    Write-Host "⚠️  PROBLEMAS ENCONTRADOS:" -ForegroundColor Red
    foreach ($issue in $issues) {
        Write-Host "   $issue" -ForegroundColor Red
    }
} else {
    Write-Host "✅ No se encontraron problemas críticos" -ForegroundColor Green
}

# ----------------------------------------------------------------------------
# PASO 3: Análisis de Sealed Secrets
# ----------------------------------------------------------------------------
Write-Host "`n`n========================================" -ForegroundColor Cyan
Write-Host "🔐 PASO 3: Analizando Sealed Secrets..." -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "🔹 Verificando namespace en archivos de Sealed Secrets..." -ForegroundColor White

$sealedSecretFiles = Get-ChildItem -Path "kubernetes-manifests" -Filter "*sealed*.yaml"
foreach ($file in $sealedSecretFiles) {
    Write-Host "`n📄 Archivo: $($file.Name)" -ForegroundColor Cyan
    $content = Get-Content $file.FullName -Raw
    if ($content -match "namespace:\s*(\w+)") {
        $namespace = $matches[1]
        if ($namespace -eq "default") {
            Write-Host "   ⚠️  Namespace: $namespace (INCORRECTO - debería ser 'tutorias')" -ForegroundColor Red
        } else {
            Write-Host "   ✅ Namespace: $namespace" -ForegroundColor Green
        }
    }
}

# ----------------------------------------------------------------------------
# PASO 4: Verificar Certificado de Sealed Secrets
# ----------------------------------------------------------------------------
Write-Host "`n`n========================================" -ForegroundColor Cyan
Write-Host "🔑 PASO 4: Verificando certificado..." -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

if (Test-Path "public-cert.pem") {
    Write-Host "✅ Certificado público encontrado: public-cert.pem" -ForegroundColor Green
    
    # Verificar si el certificado es el correcto
    Write-Host "`n🔹 Obteniendo certificado actual del cluster..." -ForegroundColor White
    kubeseal --fetch-cert --controller-name=sealed-secrets --controller-namespace=kube-system > current-cert.pem 2>$null
    
    if (Test-Path "current-cert.pem") {
        $oldCert = Get-Content "public-cert.pem" -Raw
        $newCert = Get-Content "current-cert.pem" -Raw
        
        if ($oldCert -eq $newCert) {
            Write-Host "✅ El certificado local coincide con el del cluster" -ForegroundColor Green
        } else {
            Write-Host "⚠️  El certificado local NO coincide con el del cluster" -ForegroundColor Red
            Write-Host "   Se necesita regenerar los Sealed Secrets" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "⚠️  No se encontró public-cert.pem" -ForegroundColor Red
}

# ----------------------------------------------------------------------------
# PASO 5: Verificar Network Policies
# ----------------------------------------------------------------------------
Write-Host "`n`n========================================" -ForegroundColor Cyan
Write-Host "🛡️  PASO 5: Verificando Network Policies..." -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$networkPolicies = kubectl get networkpolicies -n tutorias -o json 2>$null | ConvertFrom-Json
if ($networkPolicies.items -and $networkPolicies.items.Count -gt 0) {
    Write-Host "✅ Network Policies configuradas: $($networkPolicies.items.Count)" -ForegroundColor Green
    foreach ($policy in $networkPolicies.items) {
        Write-Host "   - $($policy.metadata.name)" -ForegroundColor White
    }
} else {
    Write-Host "❌ No se encontraron Network Policies" -ForegroundColor Red
}

# ----------------------------------------------------------------------------
# PASO 6: Verificar Kong Rate Limiting
# ----------------------------------------------------------------------------
Write-Host "`n`n========================================" -ForegroundColor Cyan
Write-Host "🚦 PASO 6: Verificando Kong Rate Limiting..." -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$kongPlugins = kubectl get kongplugins -n tutorias 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Kong plugins encontrados" -ForegroundColor Green
    kubectl get kongplugins -n tutorias
} else {
    Write-Host "⚠️  No se encontraron Kong plugins o CRD no instalado" -ForegroundColor Yellow
}

# ----------------------------------------------------------------------------
# RESUMEN Y RECOMENDACIONES
# ----------------------------------------------------------------------------
Write-Host "`n`n========================================" -ForegroundColor Cyan
Write-Host "📋 RESUMEN Y RECOMENDACIONES" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "🔧 ACCIONES RECOMENDADAS:`n" -ForegroundColor Yellow

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
    Write-Host "1. 🔐 REGENERAR SEALED SECRETS:" -ForegroundColor Red
    Write-Host "   Los Sealed Secrets no se pueden descifrar." -ForegroundColor White
    Write-Host "   Esto puede deberse a:" -ForegroundColor White
    Write-Host "   - Namespace incorrecto (default vs tutorias)" -ForegroundColor White
    Write-Host "   - Certificado desactualizado" -ForegroundColor White
    Write-Host "   - Cluster reiniciado con nueva clave" -ForegroundColor White
    Write-Host "`n   Solución: Ejecutar script de regeneración de secrets" -ForegroundColor Yellow
    Write-Host "   .\regenerate-sealed-secrets.ps1`n" -ForegroundColor Cyan
}

Write-Host "2. 🧪 EJECUTAR PRUEBAS:" -ForegroundColor Green
Write-Host "   Una vez resueltos los problemas, ejecutar:" -ForegroundColor White
Write-Host "   .\run-reto2-tests.ps1`n" -ForegroundColor Cyan

Write-Host "3. 📖 DOCUMENTACIÓN:" -ForegroundColor Green
Write-Host "   Ver guía completa de pruebas en:" -ForegroundColor White
Write-Host "   RETO2_Y_RETO7_PRUEBAS.md`n" -ForegroundColor Cyan

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "✅ DIAGNÓSTICO COMPLETADO" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
