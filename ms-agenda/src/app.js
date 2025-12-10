// ms-agenda/src/app.js
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
const agendaRouter = require('./api/routes/agenda.routes');
const errorHandler = require('./api/middlewares/errorHandler');
const correlationIdMiddleware = require('./api/middlewares/correlationId.middleware.js');
const messageProducer = require('./infrastructure/messaging/message.producer'); 

const app = express();

app.use(express.json());
app.use(correlationIdMiddleware);

// --- Middleware para contar solicitudes HTTP (Prometheus) ---
app.use((req, res, next) => {
    res.on('finish', () => {
        // Incrementa el contador por cada solicitud finalizada
        httpRequestCounter.inc({
            method: req.method,
            route: req.route ? req.route.path : req.path,
            code: res.statusCode,
            service: 'MS_Agenda' // Nombre del servicio para etiquetar en Prometheus
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
        console.error('Error al exponer métricas en MS_Agenda:', ex);
        res.status(500).end('Error al obtener métricas');
    }
});
// -----------------------------------------------------------

app.use('/agenda', agendaRouter);
app.use(errorHandler);

app.listen(config.port, () => { 
    console.log(`MS_Agenda escuchando en el puerto ${config.port}`);
    messageProducer.connect(); 
});