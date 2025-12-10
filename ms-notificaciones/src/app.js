// ms-notificaciones/src/app.js
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

// 2. Métricas Personalizadas para el Consumidor de RabbitMQ
const rabbitMessageProcessedCounter = new client.Counter({
    name: 'rabbitmq_messages_processed_total',
    help: 'Total de mensajes de RabbitMQ procesados',
    labelNames: ['status', 'queue'], // status: 'success' | 'failure'
});
// --- FIN DE IMPLEMENTACIÓN PROMETHEUS ---


const config = require('./config');
const notificacionesRouter = require('./api/routes/notificaciones.routes');
const errorHandler = require('./api/middlewares/errorHandler'); 
const correlationIdMiddleware = require('./api/middlewares/correlationId.middleware.js');
const amqp = require('amqplib'); 
const notificacionService = require('./domain/services/notificacion.service'); 
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
            service: 'MS_Notificaciones' // Nombre del servicio para etiquetar en Prometheus
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
        console.error('Error al exponer métricas en MS_Notificaciones:', ex);
        res.status(500).end('Error al obtener métricas');
    }
});
// -----------------------------------------------------------

app.use('/notificaciones', notificacionesRouter);
app.use(errorHandler);

// --- Lógica del Consumidor de RabbitMQ (ACTUALIZADA con Métricas) ---
const startConsumer = async () => {
    let connection;
    const queueName = 'notificaciones_email_queue';
    
    try {
        connection = await amqp.connect(config.rabbitmqUrl);
        const channel = await connection.createChannel();

        await channel.assertQueue(queueName, { durable: true });

        channel.prefetch(1); 

        console.log(`[MS_Notificaciones] Esperando mensajes en la cola: ${queueName}`);

        channel.consume(queueName, async (msg) => {
            if (msg !== null) {
                let payload;
                try {
                    // 1. Parsear el mensaje
                    payload = JSON.parse(msg.content.toString());
                    console.log(`[MS_Notificaciones] Mensaje recibido de RabbitMQ:`, JSON.stringify(payload));

                    // 2. Procesar el mensaje
                    await notificacionService.enviarEmailNotificacion(payload);
                    
                    // 3. Confirmar (ack) y registrar éxito
                    channel.ack(msg);
                    rabbitMessageProcessedCounter.inc({ status: 'success', queue: queueName });
                    console.log(`[MS_Notificaciones] Mensaje procesado y confirmado (ack).`);

                } catch (error) {
                    console.error(`[MS_Notificaciones] Error al procesar mensaje: ${error.message}`, payload);
                    
                    // 4. Rechazar (nack) y registrar fallo
                    channel.nack(msg, false, false);
                    rabbitMessageProcessedCounter.inc({ status: 'failure', queue: queueName });
                    console.log(`[MS_Notificaciones] Mensaje rechazado (nack).`);
                }
            }
        }, {
            noAck: false
        });

    } catch (error) {
        console.error('[MS_Notificaciones] Error al conectar/consumir de RabbitMQ:', error.message);
        setTimeout(startConsumer, 5000); 
    }
};

// Iniciar el servidor y el consumidor de RabbitMQ
app.listen(config.port, () => {
    console.log(`MS_Notificaciones (API) escuchando en el puerto ${config.port}`);
    startConsumer();
    messageProducer.connect(); 
});