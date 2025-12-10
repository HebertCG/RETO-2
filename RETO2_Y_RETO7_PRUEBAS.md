# Guía Maestra de Pruebas: Reto 2 (Seguridad) + Reto 7 (GitOps)

Este documento unifica todas las pruebas para validar que el sistema es **Seguro (Zero-Trust)** y **Automatizado (GitOps)**.

**Estado Inicial**: Asegúrate de que todo está corriendo en el namespace `tutorias`.
```powershell
kubectl get pods -n tutorias
```

---

## 🛡️ PARTE 1: SEGURIDAD ZERO-TRUST (RETO 2)

### 1. Verificar Secretos (Sealed Secrets)
Comprobamos que no hay secretos planos y que la app puede descifrarlos.

1. **Ver que existen los tesoros sellados:**
   ```powershell
   kubectl get sealedsecrets -n tutorias
   ```
2. **Verificar que la app tiene acceso a la DB (Tiene el password):**
   ```powershell
   kubectl exec -n tutorias deploy/ms-usuarios-deployment -- env | Select-String "DB_PASSWORD"
   ```
   *Deberías ver `DB_PASSWORD=...` (el valor real), lo que confirma que el sellado funcionó.*

### 2. Verificar Network Policies (Firewall Interno)
Comprobamos que los servicios están aislados.

1. **Crear al "Hacker" (un pod malicioso dentro del cluster):**
   ```powershell
   kubectl run hacker -n tutorias --image=curlimages/curl --restart=Never -- sleep 3600
   Start-Sleep -Seconds 10
   ```
2. **Intento de Ataque a DB Usuarios (PUERTO 5432):**
   *Debe fallar (Timeout) porque el hacker no es "ms-usuarios".*
   ```powershell
   kubectl exec -n tutorias hacker -- curl -v --connect-timeout 5 telnet://db-usuarios:5432
   ```
3. **Intento de Ataque a API Privada (ms-usuarios:3001):**
   *Debe fallar (Timeout) porque el hacker no es "ms-tutorias".*
   ```powershell
   kubectl exec -n tutorias hacker -- curl -v --connect-timeout 5 http://ms-usuarios-service:3001
   ```
4. **Limpiar:**
   ```powershell
   kubectl delete pod hacker -n tutorias
   ```

### 3. Verificar Rate Limiting (Kong Ingress)
Comprobamos la protección contra ataques DDoS.

1. **Abrir túnel al Ingress (En OTRA terminal):**
   ```powershell
   kubectl port-forward -n argocd service/kong-kong-proxy 8000:80
   # Nota: Si instalaste kong en otro namespace, cambia '-n argocd' por '-n kong' o '-n tutorias'
   ```
2. **Lanzar ataque de tráfico (Script rápido):**
   *Copia y pega todo el bloque en PowerShell:*
   ```powershell
   $url = "http://localhost:8000/client/api/health" # O cualquier endpoint expuesto
   for ($i=1; $i -le 10; $i++) {
       try {
           $response = Invoke-WebRequest -Uri $url -Method Get -ErrorAction Stop
           Write-Host "Petición $i: 200 OK (Pasó)" -ForegroundColor Green
       } catch {
           if ($_.Exception.Response.StatusCode -eq [System.Net.HttpStatusCode]::TooManyRequests) {
               Write-Host "Petición $i: 429 Bloqueado (Éxito Kong)" -ForegroundColor Red
           } else {
               Write-Host "Petición $i: Error $($_.Exception.Message)" -ForegroundColor Yellow
           }
       }
   }
   ```
   *Resultado esperado: Las primeras 5 pasan (Verde), las siguientes 5 se bloquean (Rojo).*

### 4. Verificar Git Seguro
Confirmamos que no subimos passwords planos al repo.
```powershell
Get-ChildItem ./charts -Recurse -Filter "*.yaml" | Select-String "password"
```
*Solo deberías ver referencias a `secretKeyRef` o comentarios, nunca contraseñas reales como "123456".*

---

## 🚀 PARTE 2: AUTOMATIZACIÓN GITOPS (RETO 7)

### 1. Prueba de "Resurrección"
1. **Borrar todo:**
   ```powershell
   kubectl delete ns tutorias
   ```
2. **Forzar recuperación:**
   ```powershell
   kubectl patch application tutorias-stack -n argocd --type merge -p "{\"metadata\": {\"annotations\": {\"argocd.argoproj.io/refresh\": \"hard\"}}}"
   ```
3. **Ver renacer:**
   ```powershell
   kubectl get pods -n tutorias -w
   ```

### 2. Prueba de "Cambio en Vivo"
1. **Hacer el cambio en Git (Umbrella Chart):**
   ```powershell
   Add-Content -Path charts/tutorias-stack/values.yaml -Value "`nms-agenda:`n  env:`n    LOG_LEVEL: 'trace'"
   ```
2. **Push:**
   ```powershell
   git add charts/tutorias-stack/values.yaml
   git commit -m "Test: Change log level to trace"
   git push origin main
   ```
3. **Sync:**
   ```powershell
   kubectl patch application tutorias-stack -n argocd --type merge -p "{\"metadata\": {\"annotations\": {\"argocd.argoproj.io/refresh\": \"hard\"}}}"
   ```
4. **Verificar:**
   ```powershell
   kubectl get deployment ms-agenda-deployment -n tutorias -o yaml | Select-String "LOG_LEVEL" -Context 0,1
   ```

---
**✅ SI TODO ESTO FUNCIONA, TIENES UN 20/20.**
