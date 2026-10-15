import { Request, Response, NextFunction } from 'express';
import { z } from 'zod';
import { PenaltyStatus } from '@prisma/client';
import { prisma } from '../config/database.js';
import { firebaseAuth } from '../config/firebase.js';
import { stripeService } from '../services/stripe.service.js';
import { BadRequestError, NotFoundError } from '../utils/errors.js';
import { logger } from '../utils/logger.js';

const registerSchema = z.object({
  firebaseToken: z.string(),
  timezone: z.string().optional(),
});

const updateMeSchema = z.object({
  displayName: z.string().min(1).max(100).optional(),
  timezone: z.string().optional(),
});

/**
 * POST /api/auth/register
 */
export const register = async (
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> => {
  try {
    const { firebaseToken, timezone } = registerSchema.parse(req.body);

    const decodedToken = await firebaseAuth.verifyIdToken(firebaseToken);

    const existingUser = await prisma.user.findUnique({
      where: { firebaseUid: decodedToken.uid },
    });

    if (existingUser) {
      throw new BadRequestError('User already registered');
    }

    const user = await prisma.user.create({
      data: {
        firebaseUid: decodedToken.uid,
        email: decodedToken.email ?? '',
        displayName: decodedToken['name'] as string | undefined ?? null,
        timezone: timezone ?? 'America/New_York',
      },
    });

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
 */
export const updateMe = async (
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> => {
  try {
    const userId = req.user!.id;
    const updates = updateMeSchema.parse(req.body);

    // Build only the fields that were actually provided
    const data: Record<string, unknown> = {};
    if (updates.displayName !== undefined) data['displayName'] = updates.displayName;
    if (updates.timezone !== undefined) data['timezone'] = updates.timezone;

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
 *
 * Soft-delete: marks deletedAt, then does external cleanup.
 * Refuses if there are pending/processing payments — those must settle first.
 * Local records (penalties, audit logs) are preserved for compliance.
 */
export const deleteMe = async (
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> => {
  try {
    const userId = req.user!.id;
    const firebaseUid = req.user!.firebaseUid;

    const pendingPayments = await prisma.penalty.count({
      where: {
        userId,
        status: { in: [PenaltyStatus.PENDING, PenaltyStatus.PROCESSING, PenaltyStatus.REQUIRES_ACTION] },
      },
    });

    if (pendingPayments > 0) {
      throw new BadRequestError(
        `Cannot delete account while ${pendingPayments} payment(s) are still processing. ` +
        'Please wait for all payments to settle.'
      );
    }

    // Clean up external services first, before modifying local data
    const bankAccount = await prisma.bankAccount.findUnique({
      where: { userId },
    });

    if (bankAccount?.stripeCustomerId) {
      await stripeService.deleteCustomer(bankAccount.stripeCustomerId);
    }

    // Soft-delete: set deletedAt, remove bank account link
    await prisma.$transaction([
      prisma.bankAccount.deleteMany({ where: { userId } }),
      prisma.alarm.deleteMany({ where: { userId } }),
      prisma.user.update({
        where: { id: userId },
        data: { deletedAt: new Date() },
      }),
    ]);

    // Delete from Firebase last — if this fails, the user can still log in
    // and we can retry, but their data is already cleaned up.
    try {
      await firebaseAuth.deleteUser(firebaseUid);
    } catch (error) {
      logger.error(`Failed to delete Firebase user ${firebaseUid}:`, error);
    }

    await prisma.auditLog.create({
      data: {
        userId,
        action: 'USER_DELETED',
        details: { soft: true },
      },
    });

    logger.info(`User soft-deleted: ${userId}`);

    res.json({
      status: 'success',
      message: 'Account deleted successfully',
    });
  } catch (error) {
    next(error);
  }
};
