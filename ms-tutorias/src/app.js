// ms-tutorias/src/app.js

const express = require('express');

// --- INICIO DE IMPLEMENTACIÓN PROMETHEUS ---
const client = require('prom-client'); 

// 1. Configurar Métricas Prom-Client
const register = client.register;
// Habilitar métricas por defecto (CPU, Memoria, NodeJS)
client.collectDefaultMetrics({ register });

// Crear un contador para solicitudes HTTP
const httpRequestCounter = new client.Counter({
    name: 'http_requests_total',
    help: 'Total de solicitudes HTTP recibidas',
    labelNames: ['method', 'route', 'code', 'service'],
});

// 2. Histograma para medir la latencia de las peticiones (CRÍTICO para la Saga)
const httpRequestDurationSeconds = new client.Histogram({
    name: 'http_request_duration_seconds',
    help: 'Duración de la solicitud HTTP en segundos',
    labelNames: ['method', 'route', 'code', 'service'],
    // Define los intervalos de tiempo a medir (ej. 10ms, 50ms, 100ms, 200ms, 500ms, 1s, 2s)
    buckets: [0.01, 0.05, 0.1, 0.2, 0.5, 1, 2, 5] 
});
// --- FIN DE IMPLEMENTACIÓN PROMETHEUS ---


const config = require('./config'); 
const tutoriasRouter = require('./api/routes/tutorias.routes');
const errorHandler = require('./api/middlewares/errorHandler'); 
const correlationIdMiddleware = require('./api/middlewares/correlationId.middleware.js');

const app = express();

// Middlewares esenciales
app.use(express.json()); 
app.use(correlationIdMiddleware); 

// --- Middleware para medir la duración de la solicitud (Prometheus) ---
app.use((req, res, next) => {
    // Inicia el temporizador
    const end = httpRequestDurationSeconds.startTimer();
    
    res.on('finish', () => {
        const routePath = req.route ? req.route.path : req.path;
        const statusCode = res.statusCode;

        // 1. Incrementar el Contador
        httpRequestCounter.inc({
            method: req.method,
            route: routePath,
            code: statusCode,
            service: 'MS_Tutorias' 
        });

        // 2. Detener el Histograma (registra la duración)
        end({ 
            method: req.method, 
            route: routePath, 
            code: statusCode,
            service: 'MS_Tutorias' 
        });
    });
    next();
});

// --- Endpoint de métricas para que Prometheus lo scrapeé ---
app.get('/metrics', async (req, res) => {
    try {
        res.set('Content-Type', register.contentType);
        // Exponer todas las métricas registradas
        res.end(await register.metrics());
    } catch (ex) {
        console.error('Error al exponer métricas en MS_Tutorias:', ex);
        res.status(500).end('Error al obtener métricas');
    }
});
// -----------------------------------------------------------

// Enrutamiento principal
app.use('/tutorias', tutoriasRouter);

// Middleware de manejo de errores
app.use(errorHandler);

// Iniciar el servidor
app.listen(config.port, () => {
    console.log(`MS_Tutorias (Orquestador) escuchando en el puerto ${config.port}`);
});