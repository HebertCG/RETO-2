// ms-auth/src/app.js

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
// --- FIN DE IMPLEMENTACIÓN PROMETHEUS ---

const config = require('./config');
const authRouter = require('./api/routes/auth.routes'); 
const errorHandler = require('./api/middlewares/errorHandler');

const app = express();

app.use(express.json());

// --- Middleware para contar solicitudes HTTP (Prometheus) ---
app.use((req, res, next) => {
    res.on('finish', () => {
        // Incrementa el contador por cada solicitud finalizada
        httpRequestCounter.inc({
            method: req.method,
            route: req.route ? req.route.path : req.path,
            code: res.statusCode,
            service: 'MS_Auth' // Nombre del servicio para etiquetar en Prometheus
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
        console.error('Error al exponer métricas en MS_Auth:', ex);
        res.status(500).end('Error al obtener métricas');
    }
});
// -----------------------------------------------------------

// Aquí se usa la variable 'authRouter'. 
app.use('/auth', authRouter);

app.use(errorHandler);

app.listen(config.port, () => {
    console.log(`MS_Auth escuchando en el puerto ${config.port}`);
});