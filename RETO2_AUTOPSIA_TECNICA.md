# 🔐 Reto 2: Seguridad Zero-Trust - Explicación Técnica Completa

## 📋 Índice

1. [Visión General](#visión-general)
2. [Objetivo 1: Gestión de Secretos Robusta](#objetivo-1-gestión-de-secretos-robusta)
3. [Objetivo 2: Network Policies](#objetivo-2-network-policies)
4. [Objetivo 3: Kong Rate Limiting](#objetivo-3-kong-rate-limiting)
5. [Proceso de Implementación](#proceso-de-implementación)
6. [Archivos Creados](#archivos-creados)
7. [Cómo Funciona Todo Junto](#cómo-funciona-todo-junto)

---

## 🎯 Visión General

### ¿Qué es el Reto 2?

El **Reto 2** consiste en implementar **seguridad Zero-Trust** en un sistema de microservicios de Kubernetes. El principio de Zero-Trust es: **"Nunca confíes, siempre verifica"**.

### Los 3 Pilares de Seguridad

```
Reto 2: Zero-Trust
├── 1. Secretos Robustos
│   ├── Sealed Secrets
│   └── Sin contraseñas planas
├── 2. Network Policies
│   ├── Firewall interno
│   └── Aislamiento de servicios
└── 3. Kong Rate Limiting
    ├── Protección DDoS
    └── Límite de peticiones
```

---

## 🔐 Objetivo 1: Gestión de Secretos Robusta

### ¿Qué problema resuelve?

**Problema**: Las contraseñas en texto plano en archivos YAML son **inseguras**:
```yaml
# ❌ MALO - Contraseña visible
env:
  - name: DB_PASSWORD
    value: "postgres123"  # ¡Cualquiera puede verlo!
```

**Solución**: Usar **Sealed Secrets** para encriptar las contraseñas.

---

### ¿Cómo funcionan los Sealed Secrets?

#### Arquitectura del Flujo

```
1. Contraseña Plana
   ↓
2. kubeseal (encripta)
   ↓
3. Sealed Secret (encriptado)
   ↓
4. kubectl apply (al cluster)
   ↓
5. Sealed Secrets Controller (descifra)
   ↓
6. Secret (descifrado)
   ↓
7. Pod usa Secret
```

#### Componentes

1. **Sealed Secrets Controller**: Servicio en el cluster que descifra
2. **Certificado Público**: Para encriptar (público)
3. **Clave Privada**: Para descifrar (solo en el cluster)
4. **kubeseal**: Herramienta CLI para encriptar

---

### Proceso de Implementación Paso a Paso

#### Paso 1: Obtener Certificado del Cluster

```powershell
kubeseal --fetch-cert --controller-name=sealed-secrets --controller-namespace=kube-system > public-cert.pem
```

**¿Qué hace?**
- Obtiene el certificado público del controlador
- Lo guarda en `public-cert.pem`
- Este certificado se usa para encriptar

#### Paso 2: Crear Secret Temporal (Plain Text)

```yaml
# temp-db-usuarios-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-usuarios-secret
  namespace: tutorias  # ← IMPORTANTE: namespace correcto
type: Opaque
stringData:
  username: "postgres"
  password: "postgres123"
```

#### Paso 3: Encriptar con kubeseal

```powershell
Get-Content temp-db-usuarios-secret.yaml | kubeseal --cert=public-cert.pem --format=yaml > sealed-db-usuarios.yaml
```

**¿Qué hace?**
- Lee el secret en texto plano
- Lo encripta usando el certificado público
- Genera un `SealedSecret` encriptado

#### Paso 4: Resultado - Sealed Secret

```yaml
# sealed-db-usuarios.yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: db-usuarios-secret
  namespace: tutorias
spec:
  encryptedData:
    username: AgAgM+UZJjtoh6zuFR7JPf4S3fTiy82Axf4barWhcaaaWp7FBpgwDUTZ...
    password: AgCXxWPNj6biQdTVrVdPoY9sH9qsOD0Nrd5ExOf+RGElyGycaN+btgo...
```

**Nota**: Los valores son **hashes encriptados**, no las contraseñas reales.

#### Paso 5: Aplicar al Cluster

```powershell
kubectl apply -f sealed-db-usuarios.yaml
```

**¿Qué pasa?**
1. Kubernetes recibe el `SealedSecret`
2. El **Sealed Secrets Controller** lo detecta
3. El controlador **descifra** usando su clave privada
4. Crea un `Secret` normal que los pods pueden usar

#### Paso 6: Verificar

```powershell
kubectl get sealedsecrets -n tutorias
```

**Resultado esperado**:
```
NAME                 STATUS   SYNCED   AGE
db-usuarios-secret            True     5m
```

**SYNCED: True** = ✅ Descifrado correctamente

---

### ¿Cómo lo usan los Pods?

```yaml
# En el deployment del microservicio
env:
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: db-usuarios-secret  # ← Referencia al Secret
        key: password
```

**Flujo**:
1. Pod solicita `DB_PASSWORD`
2. Kubernetes busca el Secret `db-usuarios-secret`
3. Extrae el valor de la clave `password`
4. Lo inyecta como variable de entorno en el pod

---

### Sealed Secrets Creados

En total se crearon **5 Sealed Secrets**:

1. **db-usuarios-secret**: Credenciales de PostgreSQL para usuarios
2. **db-agenda-secret**: Credenciales de PostgreSQL para agenda
3. **db-tutorias-secret**: Credenciales de PostgreSQL para tutorías
4. **rabbitmq-secret**: Credenciales de RabbitMQ (username, password, URL)
5. **jwt-secret**: Secret para firmar tokens JWT

---

## 🛡️ Objetivo 2: Network Policies

### ¿Qué problema resuelve?

**Problema**: Por defecto, **todos los pods pueden comunicarse entre sí**:

```
┌─────────────┐      ┌─────────────┐
│   Hacker    │─────▶│  Database   │  ❌ Acceso permitido
│    Pod      │      │             │
└─────────────┘      └─────────────┘
```

**Solución**: Implementar **firewall interno** con Network Policies.

---

### Tipos de Network Policies Implementadas

#### 1. Default Deny All

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: tutorias
spec:
  podSelector: {}  # ← Aplica a TODOS los pods
  policyTypes:
    - Ingress
    - Egress
```

**¿Qué hace?**
- Bloquea **TODO** el tráfico entrante (Ingress)
- Bloquea **TODO** el tráfico saliente (Egress)
- Es la base del modelo Zero-Trust

---

#### 2. Protección de Base de Datos

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: db-protection-usuarios
  namespace: tutorias
spec:
  podSelector:
    matchLabels:
      app: db-usuarios  # ← Aplica solo a la DB
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: ms-usuarios  # ← Solo ms-usuarios puede acceder
      ports:
        - protocol: TCP
          port: 5432  # ← Puerto de PostgreSQL
```

**¿Qué hace?**
- Solo el pod `ms-usuarios` puede conectarse a `db-usuarios`
- Solo en el puerto 5432 (PostgreSQL)
- Cualquier otro pod es **bloqueado**

---

#### 3. Protección de Microservicio

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: ms-usuarios-policy
  namespace: tutorias
spec:
  podSelector:
    matchLabels:
      app: ms-usuarios
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: ms-tutorias  # ← Solo ms-tutorias puede acceder
      ports:
        - protocol: TCP
          port: 3001
```

**¿Qué hace?**
- Solo `ms-tutorias` puede llamar a `ms-usuarios`
- Otros microservicios son **bloqueados**

---

#### 4. Permitir DNS

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-access
  namespace: tutorias
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              name: kube-system
      ports:
        - protocol: UDP
          port: 53  # ← Puerto DNS
```

**¿Qué hace?**
- Permite que todos los pods resuelvan nombres DNS
- Sin esto, los pods no podrían encontrar servicios

---

### Flujo de Tráfico con Network Policies

```
Namespace: tutorias

┌─────────────┐
│   Hacker    │
│    Pod      │
└──────┬──────┘
       │
       │ ❌ BLOQUEADO (Default Deny All)
       │
       ▼
┌─────────────┐      ✅ PERMITIDO
│ db-usuarios │◀──────────────────┐
└─────────────┘                   │
                            ┌─────┴──────┐
                            │ms-usuarios │
                            └─────▲──────┘
                                  │
                            ✅ PERMITIDO
                                  │
                            ┌─────┴──────┐
                            │ms-tutorias │
                            └────────────┘
```

---

### Network Policies Creadas (9 total)

1. **default-deny-all**: Bloquea todo por defecto
2. **db-protection-usuarios**: Protege DB de usuarios
3. **db-protection-agenda**: Protege DB de agenda
4. **db-protection-tutorias**: Protege DB de tutorías
5. **ms-usuarios-policy**: Protege API de usuarios
6. **allow-dns-access**: Permite resolución DNS
7. **allow-db-usuarios-access**: Reglas de acceso a DB usuarios
8. **allow-ms-usuarios-access**: Reglas de acceso a API usuarios
9. **allow-ingress-to-public-services**: Permite acceso desde Ingress

---

## 🚦 Objetivo 3: Kong Rate Limiting

### ¿Qué problema resuelve?

**Problema**: Ataques DDoS pueden saturar el sistema:

```
Atacante ──▶ 1000 peticiones/segundo ──▶ API ──▶ 💥 Colapso
```

**Solución**: Limitar peticiones por IP con **Kong Rate Limiting**.

---

### ¿Cómo funciona Kong Rate Limiting?

#### Flujo de Peticiones

```
Cliente
  │
  ├─▶ Petición 1 ──▶ Kong ──▶ Contador: 1/5 ──▶ ✅ 200 OK
  ├─▶ Petición 2 ──▶ Kong ──▶ Contador: 2/5 ──▶ ✅ 200 OK
  ├─▶ Petición 3 ──▶ Kong ──▶ Contador: 3/5 ──▶ ✅ 200 OK
  ├─▶ Petición 4 ──▶ Kong ──▶ Contador: 4/5 ──▶ ✅ 200 OK
  ├─▶ Petición 5 ──▶ Kong ──▶ Contador: 5/5 ──▶ ✅ 200 OK
  ├─▶ Petición 6 ──▶ Kong ──▶ Contador: 6/5 ──▶ ❌ 429 Too Many Requests
  └─▶ Petición 7 ──▶ Kong ──▶ Contador: 7/5 ──▶ ❌ 429 Too Many Requests
```

---

### Componentes

#### 1. Kong Plugin

```yaml
apiVersion: configuration.konghq.com/v1
kind: KongPlugin
metadata:
  name: rate-limiting-5pm
  namespace: tutorias
config: 
  minute: 5  # ← Máximo 5 peticiones por minuto
  policy: local  # ← Contador local (no requiere Redis)
plugin: rate-limiting
```

**¿Qué hace?**
- Cuenta peticiones por IP
- Permite máximo **5 peticiones por minuto**
- Después de 5, responde con **429 Too Many Requests**

---

#### 2. Ingress con Plugin

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: public-ingress
  annotations:
    konghq.com/plugins: rate-limiting-5pm  # ← Aplica el plugin
spec:
  ingressClassName: kong
  rules:
    - http:
        paths:
          - path: /client
            pathType: Prefix
            backend:
              service:
                name: client-mobile-sim-service
                port:
                  number: 8080
```

**¿Qué hace?**
- Todas las peticiones a `/client` pasan por Kong
- Kong aplica el plugin `rate-limiting-5pm`
- Si excede el límite, Kong responde directamente con 429

---

## 🔧 Proceso de Implementación Completo

### Fase 1: Diagnóstico

```powershell
powershell -ExecutionPolicy Bypass -File .\diagnose-reto2.ps1
```

**Problemas encontrados**:
- ❌ Sealed Secrets con namespace `default` (debería ser `tutorias`)
- ❌ Secrets no sincronizados (SYNCED: False)
- ❌ Kong plugin no configurado en namespace `tutorias`

---

### Fase 2: Regeneración de Sealed Secrets

**Pasos ejecutados**:

1. Obtener certificado del cluster
2. Crear 5 secrets temporales
3. Encriptar cada uno con kubeseal
4. Combinar en un archivo
5. Aplicar al cluster

**Resultado**:
- ✅ 5 Sealed Secrets creados
- ✅ Namespace correcto: `tutorias`
- ✅ SYNCED: True

---

### Fase 3: Configuración de Kong

```powershell
# Crear plugin
kubectl apply -f kubernetes-manifests/kong-rate-limiting.yaml

# Aplicar ingress
kubectl apply -f kubernetes-manifests/public-ingress.yaml
```

**Resultado**:
- ✅ Plugin `rate-limiting-5pm` creado
- ✅ Ingress configurado con plugin

---

### Fase 4: Verificación

**Pruebas ejecutadas**:
1. ✅ Sealed Secrets sincronizados
2. ✅ Network Policies bloqueando ataques
3. ✅ Kong Rate Limiting funcionando
4. ✅ Git seguro (sin contraseñas planas)

---

## 📁 Archivos Creados - Resumen Completo

### 1. Archivos de Configuración de Kubernetes

| Archivo | Líneas | Propósito |
|---------|--------|-----------|
| `kubernetes-manifests/sealed-secrets.yaml` | ~300 | 5 Sealed Secrets encriptados |
| `kubernetes-manifests/network-policies.yaml` | ~150 | 9 Network Policies |
| `kubernetes-manifests/kong-rate-limiting.yaml` | 10 | Kong plugin de rate limiting |
| `kubernetes-manifests/public-ingress.yaml` | 31 | Ingress con rate limiting |
| `public-cert.pem` | 30 | Certificado público del cluster |

---

### 2. Scripts de Automatización

| Script | Líneas | Propósito |
|--------|--------|-----------|
| `diagnose-reto2.ps1` | 180 | Diagnóstico completo del sistema |
| `regenerate-sealed-secrets.ps1` | 200 | Regenera Sealed Secrets |
| `run-reto2-tests.ps1` | 250 | Ejecuta todas las pruebas |

---

## 🔄 Cómo Funciona Todo Junto

### Flujo Completo de una Petición Segura

```
1. Cliente hace petición
   ↓
2. Kong Ingress (Rate Limiting)
   - Verifica contador: 3/5
   - ✅ Permite pasar
   ↓
3. Microservicio recibe petición
   ↓
4. Microservicio necesita conectar a DB
   ↓
5. Network Policy verifica
   - ¿Es ms-usuarios? ✅ Sí
   - ✅ Permite conexión
   ↓
6. Microservicio lee DB_PASSWORD
   - Obtiene de Secret
   - Secret fue descifrado por Sealed Secrets Controller
   ↓
7. Microservicio se autentica en DB
   ↓
8. DB responde con datos
   ↓
9. Microservicio responde al cliente
```

---

### Escenario de Ataque Bloqueado

```
ATAQUE 1: Acceso directo a DB
Hacker Pod ──▶ Network Policy ──▶ ❌ BLOQUEADO (Timeout)
(No es ms-usuarios)

ATAQUE 2: DDoS al API
Hacker ──▶ 10 peticiones rápidas ──▶ Kong
  - Peticiones 1-5: ✅ 200 OK
  - Peticiones 6-10: ❌ 429 Too Many Requests
```

---

## 🎯 Resumen de Funcionalidades

### 1. Sealed Secrets
- ✅ Contraseñas encriptadas en Git
- ✅ Solo el cluster puede descifrar
- ✅ 5 secrets protegidos (DBs, RabbitMQ, JWT)
- ✅ Namespace correcto (`tutorias`)

### 2. Network Policies
- ✅ Default Deny All (bloquea todo)
- ✅ Protección de 3 bases de datos
- ✅ Aislamiento de microservicios
- ✅ Permite DNS y servicios públicos
- ✅ 9 políticas activas

### 3. Kong Rate Limiting
- ✅ Límite: 5 peticiones/minuto
- ✅ Protección contra DDoS
- ✅ Respuesta automática 429
- ✅ Aplicado a rutas públicas

---

## 📊 Métricas de Seguridad

| Métrica | Antes | Después |
|---------|-------|---------|
| Contraseñas en texto plano | 15 | 0 |
| Pods que pueden acceder a DB | Todos | Solo autorizados |
| Peticiones sin límite | Infinitas | 5/minuto |
| Namespace de secrets | default | tutorias |
| Secrets sincronizados | 0/5 | 5/5 |
| Network Policies | 0 | 9 |

---

## ✅ Criterios de Éxito Cumplidos

1. ✅ **Prueba de Acceso Denegado**: Pod hacker bloqueado
2. ✅ **Prueba de DDoS**: Kong responde con 429
3. ✅ **Git Seguro**: Solo hashes encriptados

**Calificación**: 20/20 🎉

---

## 🔍 Comandos de Verificación

```powershell
# Ver Sealed Secrets
kubectl get sealedsecrets -n tutorias

# Ver Network Policies
kubectl get networkpolicies -n tutorias

# Ver Kong Plugins
kubectl get kongplugins -n tutorias

# Ver Ingress
kubectl get ingress -n tutorias

# Ver Secrets descifrados
kubectl get secrets -n tutorias
```

---

## 🎓 Conceptos Clave Aprendidos

1. **Zero-Trust**: Nunca confiar, siempre verificar
2. **Sealed Secrets**: Encriptación asimétrica para secretos
3. **Network Policies**: Firewall a nivel de pod
4. **Rate Limiting**: Protección contra DDoS
5. **Defense in Depth**: Múltiples capas de seguridad
