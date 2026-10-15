import { Request, Response, NextFunction } from 'express';
import { AppError, ValidationError } from '../utils/errors.js';
import { logger } from '../utils/logger.js';
import { config } from '../config/index.js';

// ===========================================
// Global Error Handler
// ===========================================
export const errorHandler = (
  err: Error,
  req: Request,
  res: Response,
  _next: NextFunction
): void => {
  // Log the error
  logger.error(err);

  // Handle known operational errors
  if (err instanceof AppError) {
    const response: Record<string, unknown> = {
      status: 'error',
      message: err.message,
    };

    // Include validation errors if present
    if (err instanceof ValidationError) {
      response.errors = err.errors;
    }

    // Include stack trace in development
    if (config.nodeEnv === 'development') {
      response.stack = err.stack;
    }

    res.status(err.statusCode).json(response);
    return;
  }

  // Handle unknown errors
  const statusCode = 500;
  const message = config.nodeEnv === 'production' 
    ? 'Internal server error' 
    : err.message;

  res.status(statusCode).json({
    status: 'error',
    message,
    ...(config.nodeEnv === 'development' && { stack: err.stack }),
  });
};
