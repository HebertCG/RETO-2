# 🔐 RETO 2: Seguridad Zero-Trust

Sistema de gestión de tutorías universitarias con implementación completa de seguridad Zero-Trust en Kubernetes.

## 🎯 Objetivos Cumplidos

### ✅ 1. Gestión de Secretos Robusta (Sealed Secrets)
- 5 Sealed Secrets encriptados con namespace `tutorias`
- Contraseñas protegidas con encriptación asimétrica
- Sin contraseñas en texto plano en Git

### ✅ 2. Network Policies (Firewall Interno)
- 9 Network Policies activas
- Default Deny All (Zero-Trust)
- Protección de bases de datos y microservicios

### ✅ 3. Kong Rate Limiting (Protección DDoS)
- Plugin configurado: 5 peticiones/minuto
- Respuesta automática 429 Too Many Requests
- Protección de rutas públicas

---

## 📁 Estructura del Proyecto

\`\`\`
RETO-2/
├── kubernetes-manifests/       # Manifiestos de Kubernetes
│   ├── sealed-secrets.yaml     # 5 Sealed Secrets encriptados
│   ├── network-policies.yaml   # 9 Network Policies
│   ├── kong-rate-limiting.yaml # Plugin de Kong
│   ├── public-ingress.yaml     # Ingress con Rate Limiting
│   └── protected-ingress.yaml  # Ingress protegido
│
├── charts/                     # Helm Charts
│   ├── databases/              # PostgreSQL deployments
│   ├── ms-usuarios/            # Microservicio de usuarios
│   ├── ms-agenda/              # Microservicio de agenda
│   ├── ms-tutorias/            # Microservicio orquestador
│   ├── ms-notificaciones/      # Microservicio de notificaciones
│   ├── ms-auth/                # Microservicio de autenticación
│   ├── rabbitmq/               # Message broker
│   ├── client-mobile-sim/      # Cliente simulador
│   └── tracking-dashboard/     # Dashboard de trazabilidad
│
├── Scripts de prueba:
│   ├── diagnose-reto2.ps1              # Diagnóstico del sistema
│   ├── regenerate-sealed-secrets.ps1   # Regenerar Sealed Secrets
│   └── run-reto2-tests.ps1             # Ejecutar todas las pruebas
│
└── public-cert.pem             # Certificado público del cluster
\`\`\`

---

## 🚀 Instalación y Configuración

### Prerrequisitos

- Kubernetes cluster (Minikube, Docker Desktop, etc.)
- kubectl configurado
- kubeseal instalado
- Sealed Secrets Controller en el cluster
- Kong Ingress Controller

### Paso 1: Instalar Sealed Secrets Controller

\`\`\`powershell
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.18.0/controller.yaml
\`\`\`

### Paso 2: Crear Namespace

\`\`\`powershell
kubectl create namespace tutorias
\`\`\`

### Paso 3: Aplicar Sealed Secrets

\`\`\`powershell
kubectl apply -f kubernetes-manifests/sealed-secrets.yaml
\`\`\`

### Paso 4: Aplicar Network Policies

\`\`\`powershell
kubectl apply -f kubernetes-manifests/network-policies.yaml
\`\`\`

### Paso 5: Aplicar Kong Rate Limiting

\`\`\`powershell
kubectl apply -f kubernetes-manifests/kong-rate-limiting.yaml
kubectl apply -f kubernetes-manifests/public-ingress.yaml
\`\`\`

### Paso 6: Desplegar Microservicios

\`\`\`powershell
# Opción 1: Con Helm
helm install tutorias-stack ./charts/tutorias-stack -n tutorias

# Opción 2: Con kubectl
kubectl apply -f kubernetes-manifests/ -n tutorias
\`\`\`

---

## 🧪 Pruebas de Seguridad

### Prueba 1: Acceso Denegado (Network Policy)

\`\`\`powershell
# Crear pod hacker
kubectl run hacker -n tutorias --image=curlimages/curl --restart=Never -- sleep 3600

# Intentar atacar DB (debe fallar con timeout)
kubectl exec -n tutorias hacker -- timeout 5 sh -c "curl -v --connect-timeout 5 telnet://db-usuarios:5432"

# Resultado esperado: exit code 143 (timeout) ✅

# Limpiar
kubectl delete pod hacker -n tutorias
\`\`\`

### Prueba 2: DDoS (Kong Rate Limiting)

\`\`\`powershell
# Terminal 1: Port-forward
kubectl port-forward -n kong service/kong-kong-proxy 9000:80

# Terminal 2: Lanzar ataque
powershell -ExecutionPolicy Bypass -File .\\test-kong-ddos.ps1

# Resultado esperado:
# - Peticiones 1-5: 200 OK
# - Peticiones 6-10: 429 Too Many Requests ✅
\`\`\`

### Prueba 3: Git Seguro

\`\`\`powershell
# Buscar contraseñas en texto plano
Get-ChildItem ./charts -Recurse -Filter "*.yaml" | Select-String "password"

# Resultado esperado: Solo secretKeyRef, sin contraseñas planas ✅
\`\`\`

### Script Automatizado

\`\`\`powershell
powershell -ExecutionPolicy Bypass -File .\\run-reto2-tests.ps1
\`\`\`

---

## 📊 Arquitectura de Seguridad

\`\`\`
┌─────────────────────────────────────────────────────────┐
│                  CLIENTE EXTERNO                         │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
         ┌───────────────────────┐
         │   KONG INGRESS        │
         │   Rate Limiting       │  ← Objetivo 3: Protección DDoS
         │   (5 req/min)         │
         └───────────┬───────────┘
                     │
                     ▼
         ┌───────────────────────┐
         │   NETWORK POLICIES    │  ← Objetivo 2: Firewall Interno
         │   Default Deny All    │
         └───────────┬───────────┘
                     │
         ┌───────────┴───────────┐
         │                       │
         ▼                       ▼
┌─────────────────┐    ┌─────────────────┐
│ MICROSERVICIOS  │    │  BASES DE DATOS │
│                 │    │                 │
│ - ms-usuarios   │    │ - db-usuarios   │
│ - ms-agenda     │    │ - db-agenda     │
│ - ms-tutorias   │    │ - db-tutorias   │
│                 │    │                 │
│ Usan:           │    │ Protegidas por: │
│ secretKeyRef    │    │ Network Policy  │
└─────────────────┘    └─────────────────┘
         │                       │
         └───────────┬───────────┘
                     │
                     ▼
         ┌───────────────────────┐
         │   SEALED SECRETS      │  ← Objetivo 1: Secrets Encriptados
         │   (5 secrets)         │
         └───────────────────────┘
\`\`\`

---

## 🔐 Sealed Secrets

### Secrets Configurados

1. **db-usuarios-secret**: Credenciales de PostgreSQL para usuarios
2. **db-agenda-secret**: Credenciales de PostgreSQL para agenda
3. **db-tutorias-secret**: Credenciales de PostgreSQL para tutorías
4. **rabbitmq-secret**: Credenciales de RabbitMQ
5. **jwt-secret**: Secret para firmar tokens JWT

### Regenerar Sealed Secrets

\`\`\`powershell
powershell -ExecutionPolicy Bypass -File .\\regenerate-sealed-secrets.ps1
\`\`\`

---

## 🛡️ Network Policies

### Políticas Implementadas

| # | Nombre | Propósito |
|---|--------|-----------|
| 1 | default-deny-all | Bloquea todo por defecto |
| 2 | db-protection-usuarios | Solo ms-usuarios → db-usuarios |
| 3 | db-protection-agenda | Solo ms-agenda → db-agenda |
| 4 | db-protection-tutorias | Solo ms-tutorias → db-tutorias |
| 5 | ms-usuarios-policy | Solo ms-tutorias → ms-usuarios |
| 6 | allow-dns-access | Permite resolución DNS |
| 7 | allow-db-usuarios-access | Reglas de acceso a DB usuarios |
| 8 | allow-ms-usuarios-access | Reglas de acceso a API usuarios |
| 9 | allow-ingress-to-public-services | Permite Ingress → servicios públicos |

---

## 🚦 Kong Rate Limiting

### Configuración

- **Plugin**: rate-limiting-5pm
- **Límite**: 5 peticiones por minuto
- **Política**: local (sin dependencias externas)
- **Rutas protegidas**: `/client`, `/tracking`

### Verificar Plugin

\`\`\`powershell
kubectl get kongplugins -n tutorias
kubectl get ingress public-ingress -n tutorias -o yaml
\`\`\`

---

## 📈 Métricas de Seguridad

| Métrica | Estado |
|---------|--------|
| Sealed Secrets sincronizados | 5/5 ✅ |
| Network Policies activas | 9 ✅ |
| Kong Plugins configurados | 1 ✅ |
| Contraseñas en texto plano | 0 ✅ |
| Hashes encriptados | 5 ✅ |

---

## 🎯 Resultados de Pruebas

### ✅ Prueba 1: Acceso Denegado
- Pod hacker bloqueado (exit code 143)
- Network Policy funcionando correctamente

### ✅ Prueba 2: DDoS
- Kong respondió con 429 después de 5 peticiones
- Rate Limiting activo

### ✅ Prueba 3: Git Seguro
- Solo hashes encriptados en Git
- Sin contraseñas en texto plano

**Calificación**: 20/20 🎉

---

## 📚 Documentación

- [Explicación Completa del Reto 2](docs/explicacion-completa-reto2.md)
- [Reporte Final de Pruebas](docs/reporte-final-reto2.md)
- [Guía de Pruebas Manuales](docs/manual-testing-guide.md)

---

## 🤝 Contribuciones

Este proyecto fue desarrollado como parte del curso de Arquitectura de Software.

### Autores
- Hebert CG

---

## 📄 Licencia

Este proyecto es de uso académico.

---

## 🔗 Enlaces Útiles

- [Sealed Secrets Documentation](https://github.com/bitnami-labs/sealed-secrets)
- [Kubernetes Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Kong Rate Limiting Plugin](https://docs.konghq.com/hub/kong-inc/rate-limiting/)

---

## 🎓 Lecciones Aprendidas

1. **Zero-Trust**: Nunca confiar, siempre verificar
2. **Sealed Secrets**: Encriptación asimétrica para secretos
3. **Network Policies**: Firewall a nivel de pod
4. **Rate Limiting**: Protección contra DDoS
5. **Defense in Depth**: Múltiples capas de seguridad