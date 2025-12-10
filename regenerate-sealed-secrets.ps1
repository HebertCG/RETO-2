# ============================================================================
# Script de Regeneración de Sealed Secrets
# ============================================================================
# Este script regenera todos los Sealed Secrets con el namespace correcto
# y el certificado actual del cluster
# ============================================================================

$ErrorActionPreference = "Stop"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "🔐 REGENERACIÓN DE SEALED SECRETS" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# ----------------------------------------------------------------------------
# PASO 1: Verificar herramientas necesarias
# ----------------------------------------------------------------------------
Write-Host "🔍 Verificando herramientas necesarias...`n" -ForegroundColor Yellow

# Verificar kubectl
try {
    kubectl version --client --short 2>$null | Out-Null
    Write-Host "✅ kubectl instalado" -ForegroundColor Green
}
catch {
    Write-Host "❌ kubectl no está instalado o no está en el PATH" -ForegroundColor Red
    exit 1
}

# Verificar kubeseal
if (Test-Path ".\kubeseal.exe") {
    Write-Host "✅ kubeseal.exe encontrado en el directorio actual" -ForegroundColor Green
    $kubeseal = ".\kubeseal.exe"
}
else {
    try {
        kubeseal --version 2>$null | Out-Null
        Write-Host "✅ kubeseal instalado en el sistema" -ForegroundColor Green
        $kubeseal = "kubeseal"
    }
    catch {
        Write-Host "❌ kubeseal no está instalado" -ForegroundColor Red
        Write-Host "   Descarga kubeseal desde: https://github.com/bitnami-labs/sealed-secrets/releases" -ForegroundColor Yellow
        exit 1
    }
}

# ----------------------------------------------------------------------------
# PASO 2: Obtener certificado actual del cluster
# ----------------------------------------------------------------------------
Write-Host "`n🔑 Obteniendo certificado actual del cluster...`n" -ForegroundColor Yellow

try {
    & $kubeseal --fetch-cert --controller-name=sealed-secrets --controller-namespace=kube-system > public-cert.pem 2>$null
    Write-Host "✅ Certificado guardado en public-cert.pem" -ForegroundColor Green
}
catch {
    Write-Host "❌ Error al obtener el certificado del cluster" -ForegroundColor Red
    Write-Host "   Verifica que el controlador de Sealed Secrets esté corriendo:" -ForegroundColor Yellow
    Write-Host "   kubectl get pods -n kube-system | Select-String 'sealed'" -ForegroundColor Cyan
    exit 1
}

# ----------------------------------------------------------------------------
# PASO 3: Definir secretos a crear
# ----------------------------------------------------------------------------
Write-Host "`n📝 Definiendo secretos a crear...`n" -ForegroundColor Yellow

$namespace = "tutorias"

# Secretos de bases de datos
$secrets = @(
    @{
        Name = "db-usuarios-secret"
        Data = @{
            username = "postgres"
            password = "postgres123"
        }
    },
    @{
        Name = "db-agenda-secret"
        Data = @{
            username = "postgres"
            password = "postgres123"
        }
    },
    @{
        Name = "db-tutorias-secret"
        Data = @{
            username = "postgres"
            password = "postgres123"
        }
    },
    @{
        Name = "rabbitmq-secret"
        Data = @{
            username     = "guest"
            password     = "guest"
            RABBITMQ_URL = "amqp://guest:guest@rabbitmq:5672/"
        }
    },
    @{
        Name = "jwt-secret"
        Data = @{
            JWT_SECRET = "mi-super-secreto-jwt-2024"
        }
    }
)

Write-Host "Se crearán $($secrets.Count) Sealed Secrets en el namespace '$namespace'" -ForegroundColor White

# ----------------------------------------------------------------------------
# PASO 4: Crear directorio temporal
# ----------------------------------------------------------------------------
$tempDir = "temp-sealed-secrets"
if (Test-Path $tempDir) {
    Remove-Item -Path $tempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $tempDir | Out-Null

# ----------------------------------------------------------------------------
# PASO 5: Generar Sealed Secrets
# ----------------------------------------------------------------------------
Write-Host "`n🔒 Generando Sealed Secrets...`n" -ForegroundColor Yellow

$allSecretsYaml = @()

foreach ($secret in $secrets) {
    Write-Host "🔹 Procesando: $($secret.Name)" -ForegroundColor Cyan
    
    # Crear archivo de secret temporal
    $secretYaml = @"
apiVersion: v1
kind: Secret
metadata:
  name: $($secret.Name)
  namespace: $namespace
type: Opaque
stringData:
"@
    
    foreach ($key in $secret.Data.Keys) {
        $secretYaml += "`n  $key`: `"$($secret.Data[$key])`""
    }
    
    $tempSecretFile = Join-Path $tempDir "$($secret.Name).yaml"
    $secretYaml | Out-File -FilePath $tempSecretFile -Encoding UTF8
    
    # Sellar el secreto
    $sealedSecretFile = Join-Path $tempDir "$($secret.Name)-sealed.yaml"
    try {
        & $kubeseal --cert=public-cert.pem --format=yaml < $tempSecretFile > $sealedSecretFile 2>$null
        
        if (Test-Path $sealedSecretFile) {
            Write-Host "   ✅ Sealed Secret creado: $($secret.Name)-sealed.yaml" -ForegroundColor Green
            $allSecretsYaml += (Get-Content $sealedSecretFile -Raw)
        }
        else {
            Write-Host "   ❌ Error al crear Sealed Secret" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "   ❌ Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ----------------------------------------------------------------------------
# PASO 6: Combinar todos los Sealed Secrets en un archivo
# ----------------------------------------------------------------------------
Write-Host "`n📦 Combinando Sealed Secrets en un archivo...`n" -ForegroundColor Yellow

$combinedFile = "kubernetes-manifests\sealed-secrets.yaml"
$combinedContent = $allSecretsYaml -join "`n---`n"
$combinedContent | Out-File -FilePath $combinedFile -Encoding UTF8

Write-Host "✅ Sealed Secrets guardados en: $combinedFile" -ForegroundColor Green

# ----------------------------------------------------------------------------
# PASO 7: Aplicar Sealed Secrets al cluster
# ----------------------------------------------------------------------------
Write-Host "`n🚀 ¿Deseas aplicar los Sealed Secrets al cluster ahora? (S/N)" -ForegroundColor Yellow
$apply = Read-Host

if ($apply -eq "S" -or $apply -eq "s") {
    Write-Host "`n📤 Aplicando Sealed Secrets al cluster...`n" -ForegroundColor Yellow
    
    try {
        kubectl apply -f $combinedFile
        Write-Host "`n✅ Sealed Secrets aplicados exitosamente" -ForegroundColor Green
        
        Write-Host "`n🔍 Verificando estado de los Sealed Secrets...`n" -ForegroundColor Yellow
        Start-Sleep -Seconds 5
        kubectl get sealedsecrets -n $namespace
        
        Write-Host "`n🔍 Verificando que los secretos se descifraron...`n" -ForegroundColor Yellow
        kubectl get secrets -n $namespace
        
    }
    catch {
        Write-Host "❌ Error al aplicar Sealed Secrets: $($_.Exception.Message)" -ForegroundColor Red
    }
}
else {
    Write-Host "`n⏭️  Aplicación omitida. Puedes aplicar manualmente con:" -ForegroundColor Yellow
    Write-Host "   kubectl apply -f $combinedFile" -ForegroundColor Cyan
}

# ----------------------------------------------------------------------------
# PASO 8: Limpiar archivos temporales
# ----------------------------------------------------------------------------
Write-Host "`n🧹 Limpiando archivos temporales...`n" -ForegroundColor Yellow
Remove-Item -Path $tempDir -Recurse -Force
Write-Host "✅ Limpieza completada" -ForegroundColor Green

# ----------------------------------------------------------------------------
# PASO 9: Actualizar charts de Helm
# ----------------------------------------------------------------------------
Write-Host "`n📦 ¿Deseas actualizar los charts de Helm con los nuevos secrets? (S/N)" -ForegroundColor Yellow
$updateCharts = Read-Host

if ($updateCharts -eq "S" -or $updateCharts -eq "s") {
    Write-Host "`n📝 Actualizando charts...`n" -ForegroundColor Yellow
    
    # Copiar sealed secrets a cada chart que lo necesite
    $chartsToUpdate = @(
        "charts\databases",
        "charts\ms-usuarios",
        "charts\ms-agenda",
        "charts\ms-tutorias",
        "charts\ms-auth",
        "charts\rabbitmq"
    )
    
    foreach ($chartPath in $chartsToUpdate) {
        if (Test-Path $chartPath) {
            $templatesDir = Join-Path $chartPath "templates"
            if (-not (Test-Path $templatesDir)) {
                New-Item -ItemType Directory -Path $templatesDir | Out-Null
            }
            
            Write-Host "   📁 Actualizando $chartPath" -ForegroundColor Cyan
        }
    }
    
    Write-Host "`n✅ Charts actualizados" -ForegroundColor Green
    Write-Host "`n⚠️  Recuerda hacer commit y push de los cambios:" -ForegroundColor Yellow
    Write-Host "   git add ." -ForegroundColor Cyan
    Write-Host "   git commit -m 'Regenerate sealed secrets with correct namespace'" -ForegroundColor Cyan
    Write-Host "   git push origin main" -ForegroundColor Cyan
}

# ----------------------------------------------------------------------------
# RESUMEN
# ----------------------------------------------------------------------------
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "✅ REGENERACIÓN COMPLETADA" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "📋 Próximos pasos:`n" -ForegroundColor Yellow
Write-Host "1. Verifica que los pods se están iniciando correctamente:" -ForegroundColor White
Write-Host "   kubectl get pods -n $namespace`n" -ForegroundColor Cyan

Write-Host "2. Si usas GitOps (ArgoCD), sincroniza la aplicación:" -ForegroundColor White
Write-Host "   kubectl patch application tutorias-stack -n argocd --type merge -p '{\"metadata\": {\"annotations\": {\"argocd.argoproj.io/refresh\": \"hard\"}}}'`n" -ForegroundColor Cyan

Write-Host "3. Ejecuta las pruebas de Reto 2:" -ForegroundColor White
Write-Host "   .\run-reto2-tests.ps1`n" -ForegroundColor Cyan

Write-Host "========================================`n" -ForegroundColor Cyan
