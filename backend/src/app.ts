import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';
import { errorHandler } from './middleware/error.middleware.js';
import { notFoundHandler } from './middleware/notFound.middleware.js';
import routes from './routes/index.js';
import { config } from './config/index.js';

const app = express();

// ===========================================
// Security Middleware
// ===========================================
app.use(helmet());
app.use(cors({
  origin: config.nodeEnv === 'production' 
    ? ['https://sloozly.com'] // Update with your domain
    : '*',
  credentials: true,
}));

// ===========================================
// Request Parsing
// ===========================================
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// ===========================================
// Logging
// ===========================================
if (config.nodeEnv !== 'test') {
  app.use(morgan('combined'));
}

// ===========================================
// Health Check
// ===========================================
app.get('/health', (req, res) => {
  res.json({ 
    status: 'ok', 
    timestamp: new Date().toISOString(),
    version: '0.1.0'
  });
});

// ===========================================
// API Routes
// ===========================================
app.use('/api', routes);

// ===========================================
// Error Handling
// ===========================================
app.use(notFoundHandler);
app.use(errorHandler);

export default app;
