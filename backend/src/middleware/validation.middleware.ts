import { Request, Response, NextFunction } from 'express';
import { z, ZodSchema } from 'zod';
import { ValidationError } from '../utils/errors.js';

// ===========================================
// Request Validation Middleware Factory
// ===========================================

interface ValidationSchemas {
  body?: ZodSchema;
  query?: ZodSchema;
  params?: ZodSchema;
}

export const validate = (schemas: ValidationSchemas) => {
  return async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    try {
      const errors: Record<string, string[]> = {};

      // Validate body
      if (schemas.body) {
        const result = schemas.body.safeParse(req.body);
        if (!result.success) {
          errors.body = result.error.errors.map(e => `${e.path.join('.')}: ${e.message}`);
        } else {
          req.body = result.data;
        }
      }

      // Validate query
      if (schemas.query) {
        const result = schemas.query.safeParse(req.query);
        if (!result.success) {
          errors.query = result.error.errors.map(e => `${e.path.join('.')}: ${e.message}`);
        } else {
          req.query = result.data;
        }
      }

      // Validate params
      if (schemas.params) {
        const result = schemas.params.safeParse(req.params);
        if (!result.success) {
          errors.params = result.error.errors.map(e => `${e.path.join('.')}: ${e.message}`);
        } else {
          req.params = result.data;
        }
      }

      // If any validation errors, throw
      if (Object.keys(errors).length > 0) {
        throw new ValidationError('Validation failed', errors);
      }

      next();
    } catch (error) {
      next(error);
    }
  };
};

// ===========================================
// Common Validation Schemas
// ===========================================

export const commonSchemas = {
  id: z.object({
    id: z.string().cuid(),
  }),

  pagination: z.object({
    page: z.string().transform(Number).pipe(z.number().int().positive()).optional(),
    limit: z.string().transform(Number).pipe(z.number().int().min(1).max(100)).optional(),
  }),
};
