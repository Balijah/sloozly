import { Request, Response, NextFunction } from 'express';
import { z } from 'zod';
import { prisma } from '../config/database.js';
import { penaltyService } from '../services/penalty.service.js';
import { NotFoundError, BadRequestError } from '../utils/errors.js';
import { logger } from '../utils/logger.js';

// ===========================================
// Validation Schemas
// ===========================================

const triggerPenaltySchema = z.object({
  alarmId: z.string().cuid(),
  snoozeNumber: z.number().int().min(1).max(20), // Cap at 20 snoozes ($5 * 2^19 = $2.6M, but we'll cap amount too)
});

// ===========================================
// Controllers
// ===========================================

/**
 * POST /api/penalties/trigger
 * Trigger a penalty when user hits snooze
 */
export const triggerPenalty = async (
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> => {
  try {
    const userId = req.user!.id;
    const { alarmId, snoozeNumber } = triggerPenaltySchema.parse(req.body);

    // Verify alarm belongs to user
    const alarm = await prisma.alarm.findUnique({
      where: { id: alarmId },
    });

    if (!alarm) {
      throw new NotFoundError('Alarm not found');
    }

    if (alarm.userId !== userId) {
      throw new BadRequestError('Alarm does not belong to user');
    }

    // Check if penalty should be skipped
    if (alarm.skipPenalty) {
      res.json({
        status: 'success',
        data: {
          skipped: true,
          reason: 'Penalties disabled for this alarm',
        },
      });
      return;
    }

    // Check if user has linked bank account
    const bankAccount = await prisma.bankAccount.findUnique({
      where: { userId },
    });

    if (!bankAccount) {
      throw new BadRequestError('No bank account linked. Link a bank account to enable penalties.');
    }

    if (bankAccount.status !== 'ACTIVE') {
      throw new BadRequestError('Bank account is not active. Please re-link your bank account.');
    }

    // Trigger the penalty
    const penalty = await penaltyService.triggerPenalty({
      userId,
      alarmId,
      snoozeNumber,
      basePenaltyAmount: alarm.basePenaltyAmount,
      bankAccount,
    });

    res.status(201).json({
      status: 'success',
      data: {
        penaltyId: penalty.id,
        amount: penalty.amount,
        amountFormatted: `$${(penalty.amount / 100).toFixed(2)}`,
        snoozeNumber: penalty.snoozeNumber,
        status: penalty.status,
        triggeredAt: penalty.triggeredAt,
      },
    });
  } catch (error) {
    next(error);
  }
};

/**
 * GET /api/penalties/history
 * Get user's penalty history
 */
export const getHistory = async (
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> => {
  try {
    const userId = req.user!.id;
    const page = parseInt(req.query.page as string) || 1;
    const limit = Math.min(parseInt(req.query.limit as string) || 20, 100);
    const skip = (page - 1) * limit;

    const [penalties, total] = await Promise.all([
      prisma.penalty.findMany({
        where: { userId },
        orderBy: { triggeredAt: 'desc' },
        skip,
        take: limit,
        select: {
          id: true,
          amount: true,
          snoozeNumber: true,
          status: true,
          failureReason: true,
          triggeredAt: true,
          processedAt: true,
          alarm: {
            select: {
              id: true,
              label: true,
              hour: true,
              minute: true,
            },
          },
        },
      }),
      prisma.penalty.count({ where: { userId } }),
    ]);

    // Format amounts for display
    const formattedPenalties = penalties.map(p => ({
      ...p,
      amountFormatted: `$${(p.amount / 100).toFixed(2)}`,
    }));

    res.json({
      status: 'success',
      data: {
        penalties: formattedPenalties,
        pagination: {
          page,
          limit,
          total,
          totalPages: Math.ceil(total / limit),
        },
      },
    });
  } catch (error) {
    next(error);
  }
};

/**
 * GET /api/penalties/stats
 * Get penalty statistics
 */
export const getStats = async (
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> => {
  try {
    const userId = req.user!.id;

    // Get aggregate stats
    const [totalStats, statusBreakdown, recentPenalties] = await Promise.all([
      // Total amount and count
      prisma.penalty.aggregate({
        where: { 
          userId,
          status: 'COMPLETED',
        },
        _sum: { amount: true },
        _count: { id: true },
      }),

      // Breakdown by status
      prisma.penalty.groupBy({
        by: ['status'],
        where: { userId },
        _count: { id: true },
        _sum: { amount: true },
      }),

      // Last 7 days
      prisma.penalty.findMany({
        where: {
          userId,
          triggeredAt: {
            gte: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000),
          },
        },
        orderBy: { triggeredAt: 'desc' },
        select: {
          id: true,
          amount: true,
          status: true,
          triggeredAt: true,
        },
      }),
    ]);

    // Calculate streaks and patterns
    const totalAmount = totalStats._sum.amount || 0;
    const totalCount = totalStats._count.id || 0;

    // Format status breakdown
    const statusStats = statusBreakdown.reduce((acc, item) => {
      acc[item.status] = {
        count: item._count.id,
        amount: item._sum.amount || 0,
        amountFormatted: `$${((item._sum.amount || 0) / 100).toFixed(2)}`,
      };
      return acc;
    }, {} as Record<string, { count: number; amount: number; amountFormatted: string }>);

    res.json({
      status: 'success',
      data: {
        lifetime: {
          totalAmount,
          totalAmountFormatted: `$${(totalAmount / 100).toFixed(2)}`,
          totalPenalties: totalCount,
          averageAmount: totalCount > 0 ? Math.round(totalAmount / totalCount) : 0,
          averageAmountFormatted: totalCount > 0 
            ? `$${((totalAmount / totalCount) / 100).toFixed(2)}` 
            : '$0.00',
        },
        byStatus: statusStats,
        last7Days: {
          count: recentPenalties.length,
          amount: recentPenalties.reduce((sum, p) => sum + p.amount, 0),
          amountFormatted: `$${(recentPenalties.reduce((sum, p) => sum + p.amount, 0) / 100).toFixed(2)}`,
          penalties: recentPenalties.map(p => ({
            ...p,
            amountFormatted: `$${(p.amount / 100).toFixed(2)}`,
          })),
        },
      },
    });
  } catch (error) {
    next(error);
  }
};
