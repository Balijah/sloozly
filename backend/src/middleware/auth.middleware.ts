import { Request, Response, NextFunction } from 'express';
import { firebaseAuth } from '../config/firebase.js';
import { prisma } from '../config/database.js';
import { UnauthorizedError } from '../utils/errors.js';
import { logger } from '../utils/logger.js';

// ===========================================
// Extend Express Request Type
// ===========================================
declare global {
  namespace Express {
    interface Request {
      user?: {
        id: string;
        firebaseUid: string;
        email: string;
      };
    }
  }
}

// ===========================================
// Firebase Auth Middleware
// ===========================================
export const authenticate = async (
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> => {
  try {
    const authHeader = req.headers.authorization;

    if (!authHeader?.startsWith('Bearer ')) {
      throw new UnauthorizedError('No token provided');
    }

    const token = authHeader.split('Bearer ')[1];
    
    if (!token) {
      throw new UnauthorizedError('No token provided');
    }

    // Verify Firebase token
    const decodedToken = await firebaseAuth.verifyIdToken(token);
    
    // Get or create user in database
    let user = await prisma.user.findUnique({
      where: { firebaseUid: decodedToken.uid },
    });

    if (!user) {
      // Auto-create user on first authenticated request
      user = await prisma.user.create({
        data: {
          firebaseUid: decodedToken.uid,
          email: decodedToken.email || '',
          displayName: decodedToken.name || null,
        },
      });
      logger.info(`New user created: ${user.id}`);
    }

    // Attach user to request
    req.user = {
      id: user.id,
      firebaseUid: user.firebaseUid,
      email: user.email,
    };

    next();
  } catch (error) {
    if (error instanceof UnauthorizedError) {
      next(error);
    } else {
      logger.error('Authentication error:', error);
      next(new UnauthorizedError('Invalid or expired token'));
    }
  }
};

// ===========================================
// Optional Auth (for public + authenticated routes)
// ===========================================
export const optionalAuth = async (
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> => {
  const authHeader = req.headers.authorization;

  if (!authHeader?.startsWith('Bearer ')) {
    return next();
  }

  try {
    const token = authHeader.split('Bearer ')[1];
    
    if (token) {
      const decodedToken = await firebaseAuth.verifyIdToken(token);
      const user = await prisma.user.findUnique({
        where: { firebaseUid: decodedToken.uid },
      });

      if (user) {
        req.user = {
          id: user.id,
          firebaseUid: user.firebaseUid,
          email: user.email,
        };
      }
    }
  } catch {
    // Silently ignore auth errors for optional auth
  }

  next();
};
