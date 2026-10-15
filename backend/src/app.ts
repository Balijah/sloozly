import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';
import { errorHandler } from './middleware/error.middleware.js';
import { notFoundHandler } from './middleware/notFound.middleware.js';
import routes from './routes/index.js';
import webhookRoutes from './routes/webhook.routes.js';
import { config } from './config/index.js';

const app = express();

app.use(helmet());
app.use(cors({
  origin: config.nodeEnv === 'production'
    ? ['https://sloozly.com']
    : '*',
  credentials: true,
}));

// Stripe webhooks need the raw body for signature verification.
// Mount this BEFORE express.json().
app.use(
  '/api/webhooks/stripe',
  express.raw({ type: 'application/json' }),
  webhookRoutes
);

app.use(express.json());
app.use(express.urlencoded({ extended: true }));

if (config.nodeEnv !== 'test') {
  app.use(morgan('combined'));
}

app.get('/health', (_req, res) => {
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    version: '0.2.0',
  });
});

app.use('/api', routes);

app.use(notFoundHandler);
app.use(errorHandler);

export default app;
