import 'dotenv/config';
import app from './app.js';
import { config } from './config/index.js';
import { logger } from './utils/logger.js';
import { prisma } from './config/database.js';

const PORT = config.port;

async function main() {
  try {
    // Test database connection
    await prisma.$connect();
    logger.info('✅ Database connected');

    // Start server
    app.listen(PORT, () => {
      logger.info(`🚀 Server running on port ${PORT}`);
      logger.info(`📍 Environment: ${config.nodeEnv}`);
    });
  } catch (error) {
    logger.error('❌ Failed to start server:', error);
    process.exit(1);
  }
}

// Graceful shutdown
process.on('SIGINT', async () => {
  logger.info('Shutting down gracefully...');
  await prisma.$disconnect();
  process.exit(0);
});

process.on('SIGTERM', async () => {
  logger.info('Shutting down gracefully...');
  await prisma.$disconnect();
  process.exit(0);
});

main();
