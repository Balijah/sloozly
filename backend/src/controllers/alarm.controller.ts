import { Request, Response, NextFunction } from 'express';
import { z } from 'zod';
import { prisma } from '../config/database.js';
import { NotFoundError, ForbiddenError } from '../utils/errors.js';
import { logger } from '../utils/logger.js';

// ===========================================
// Validation Schemas
// ===========================================

const createAlarmSchema = z.object({
  hour: z.number().int().min(0).max(23),
  minute: z.number().int().min(0).max(59),
  label: z.string().max(100).optional(),
  isEnabled: z.boolean().optional().default(true),
  repeatDays: z.array(z.number().int().min(0).max(6)).optional().default([]),
  basePenaltyAmount: z.number().int().min(100).max(10000).optional().default(500), // $1-$100, default $5
});

const updateAlarmSchema = z.object({
  hour: z.number().int().min(0).max(23).optional(),
  minute: z.number().int().min(0).max(59).optional(),
  label: z.string().max(100).nullable().optional(),
  isEnabled: z.boolean().optional(),
  repeatDays: z.array(z.number().int().min(0).max(6)).optional(),
  skipPenalty: z.boolean().optional(),
  basePenaltyAmount: z.number().int().min(100).max(10000).optional(),
});

// ===========================================
// Controllers
// ===========================================

/**
 * GET /api/alarms
 * List user's alarms
 */
export const listAlarms = async (
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> => {
  try {
    const userId = req.user!.id;

    const alarms = await prisma.alarm.findMany({
      where: { userId },
      orderBy: [
        { hour: 'asc' },
        { minute: 'asc' },
      ],
      select: {
        id: true,
        hour: true,
        minute: true,
        label: true,
        isEnabled: true,
        repeatDays: true,
        skipPenalty: true,
        basePenaltyAmount: true,
        createdAt: true,
        updatedAt: true,
      },
    });

    res.json({
      status: 'success',
      data: {
        alarms,
        count: alarms.length,
      },
    });
  } catch (error) {
    next(error);
  }
};

/**
 * POST /api/alarms
 * Create a new alarm
 */
export const createAlarm = async (
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> => {
  try {
    const userId = req.user!.id;
    const data = createAlarmSchema.parse(req.body);

    const alarm = await prisma.alarm.create({
      data: {
        userId,
        hour: data.hour,
        minute: data.minute,
        label: data.label,
        isEnabled: data.isEnabled,
        repeatDays: data.repeatDays,
        basePenaltyAmount: data.basePenaltyAmount,
      },
    });

    logger.info(`Alarm created: ${alarm.id} for user: ${userId}`);

    res.status(201).json({
      status: 'success',
      data: {
        id: alarm.id,
        hour: alarm.hour,
        minute: alarm.minute,
        label: alarm.label,
        isEnabled: alarm.isEnabled,
        repeatDays: alarm.repeatDays,
        skipPenalty: alarm.skipPenalty,
        basePenaltyAmount: alarm.basePenaltyAmount,
        createdAt: alarm.createdAt,
      },
    });
  } catch (error) {
    next(error);
  }
};

/**
 * GET /api/alarms/:id
 * Get a single alarm
 */
export const getAlarm = async (
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> => {
  try {
    const userId = req.user!.id;
    const alarmId = req.params.id;

    const alarm = await prisma.alarm.findUnique({
      where: { id: alarmId },
      include: {
        penalties: {
          orderBy: { triggeredAt: 'desc' },
          take: 10,
          select: {
            id: true,
            amount: true,
            snoozeNumber: true,
            status: true,
            triggeredAt: true,
          },
        },
      },
    });

    if (!alarm) {
      throw new NotFoundError('Alarm not found');
    }

    if (alarm.userId !== userId) {
      throw new ForbiddenError('Access denied');
    }

    res.json({
      status: 'success',
      data: alarm,
    });
  } catch (error) {
    next(error);
  }
};

/**
 * PUT /api/alarms/:id
 * Update an alarm
 */
export const updateAlarm = async (
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> => {
  try {
    const userId = req.user!.id;
    const alarmId = req.params.id;
    const data = updateAlarmSchema.parse(req.body);

    // Check ownership
    const existingAlarm = await prisma.alarm.findUnique({
      where: { id: alarmId },
    });

    if (!existingAlarm) {
      throw new NotFoundError('Alarm not found');
    }

    if (existingAlarm.userId !== userId) {
      throw new ForbiddenError('Access denied');
    }

    // Update alarm
    const alarm = await prisma.alarm.update({
      where: { id: alarmId },
      data,
    });

    logger.info(`Alarm updated: ${alarm.id}`);

    res.json({
      status: 'success',
      data: {
        id: alarm.id,
        hour: alarm.hour,
        minute: alarm.minute,
        label: alarm.label,
        isEnabled: alarm.isEnabled,
        repeatDays: alarm.repeatDays,
        skipPenalty: alarm.skipPenalty,
        basePenaltyAmount: alarm.basePenaltyAmount,
        updatedAt: alarm.updatedAt,
      },
    });
  } catch (error) {
    next(error);
  }
};

/**
 * DELETE /api/alarms/:id
 * Delete an alarm
 */
export const deleteAlarm = async (
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> => {
  try {
    const userId = req.user!.id;
    const alarmId = req.params.id;

    // Check ownership
    const existingAlarm = await prisma.alarm.findUnique({
      where: { id: alarmId },
    });

    if (!existingAlarm) {
      throw new NotFoundError('Alarm not found');
    }

    if (existingAlarm.userId !== userId) {
      throw new ForbiddenError('Access denied');
    }

    // Delete alarm (penalties will cascade)
    await prisma.alarm.delete({
      where: { id: alarmId },
    });

    logger.info(`Alarm deleted: ${alarmId}`);

    res.json({
      status: 'success',
      message: 'Alarm deleted successfully',
    });
  } catch (error) {
    next(error);
  }
};
