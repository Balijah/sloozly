import { Request, Response } from 'express';

// ===========================================
// 404 Not Found Handler
// ===========================================
export const notFoundHandler = (req: Request, res: Response): void => {
  res.status(404).json({
    status: 'error',
    message: `Route ${req.method} ${req.originalUrl} not found`,
  });
};
