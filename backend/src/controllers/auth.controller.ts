import { Request, Response, NextFunction } from 'express';
import { z } from 'zod';
import { prisma } from '../config/database.js';
import { firebaseAuth } from '../config/firebase.js';
import { BadRequestError, NotFoundError } from '../utils/errors.js';
import { logger } from '../utils/logger.js';

// ===========================================
// Validation Schemas
// ===========================================

const registerSchema = z.object({
  firebaseToken: z.string(),
  timezone: z.string().optional().default('America/New_York'),
});

const updateMeSchema = z.object({
  displayName: z.string().min(1).max(100).optional(),
  timezone: z.string().optional(),
});

// ===========================================
// Controllers
// ===========================================

/**
 * POST /api/auth/register
 * Create user in database after Firebase signup
 */
export const register = async (
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> => {
  try {
    const { firebaseToken, timezone } = registerSchema.parse(req.body);

    // Verify Firebase token
    const decodedToken = await firebaseAuth.verifyIdToken(firebaseToken);

    // Check if user already exists
    const existingUser = await prisma.user.findUnique({
      where: { firebaseUid: decodedToken.uid },
    });

    if (existingUser) {
      throw new BadRequestError('User already registered');
    }

    // Create user
    const user = await prisma.user.create({
      data: {
        firebaseUid: decodedToken.uid,
        email: decodedToken.email || '',
        displayName: decodedToken.name || null,
        timezone,
      },
    });

    // Log audit
    await prisma.auditLog.create({
      data: {
        userId: user.id,
        action: 'USER_REGISTERED',
        details: { email: user.email },
      },
    });

    logger.info(`User registered: ${user.id}`);

    res.status(201).json({
      status: 'success',
      data: {
        id: user.id,
        email: user.email,
        displayName: user.displayName,
        timezone: user.timezone,
        createdAt: user.createdAt,
      },
    });
  } catch (error) {
    next(error);
  }
};

/**
 * GET /api/auth/me
 * Get current user profile
 */
export const getMe = async (
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> => {
  try {
    const userId = req.user!.id;

    const user = await prisma.user.findUnique({
      where: { id: userId },
      include: {
        bankAccount: {
          select: {
            id: true,
            institutionName: true,
            accountName: true,
            accountMask: true,
            status: true,
          },
        },
        _count: {
          select: {
            alarms: true,
            penalties: true,
          },
        },
      },
    });

    if (!user) {
      throw new NotFoundError('User not found');
    }

    res.json({
      status: 'success',
      data: {
        id: user.id,
        email: user.email,
        displayName: user.displayName,
        timezone: user.timezone,
        createdAt: user.createdAt,
        bankAccount: user.bankAccount,
        counts: {
          alarms: user._count.alarms,
          penalties: user._count.penalties,
        },
      },
    });
  } catch (error) {
    next(error);
  }
};

/**
 * PUT /api/auth/me
 * Update current user profile
 */
export const updateMe = async (
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> => {
  try {
    const userId = req.user!.id;
    const data = updateMeSchema.parse(req.body);

    const user = await prisma.user.update({
      where: { id: userId },
      data,
    });

    res.json({
      status: 'success',
      data: {
        id: user.id,
        email: user.email,
        displayName: user.displayName,
        timezone: user.timezone,
        updatedAt: user.updatedAt,
      },
    });
  } catch (error) {
    next(error);
  }
};

/**
 * DELETE /api/auth/me
 * Delete user account
 */
export const deleteMe = async (
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> => {
  try {
    const userId = req.user!.id;
    const firebaseUid = req.user!.firebaseUid;

    // Delete from database (cascade will handle related records)
    await prisma.user.delete({
      where: { id: userId },
    });

    // Delete from Firebase
    await firebaseAuth.deleteUser(firebaseUid);

    logger.info(`User deleted: ${userId}`);

    res.json({
      status: 'success',
      message: 'Account deleted successfully',
    });
  } catch (error) {
    next(error);
  }
};
