import { Request, Response, NextFunction } from 'express';
import { z } from 'zod';
import { prisma } from '../config/database.js';
import { NotFoundError, ForbiddenError } from '../utils/errors.js';
import { logger } from '../utils/logger.js';

const createAlarmSchema = z.object({
  hour: z.number().int().min(0).max(23),
  minute: z.number().int().min(0).max(59),
  label: z.string().max(100).optional(),
  isEnabled: z.boolean().optional(),
  repeatDays: z.array(z.number().int().min(0).max(6)).optional(),
});

const updateAlarmSchema = z.object({
  hour: z.number().int().min(0).max(23).optional(),
  minute: z.number().int().min(0).max(59).optional(),
  label: z.string().max(100).nullable().optional(),
  isEnabled: z.boolean().optional(),
  repeatDays: z.array(z.number().int().min(0).max(6)).optional(),
  skipPenalty: z.boolean().optional(),
});

/**
 * GET /api/alarms
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
      orderBy: [{ hour: 'asc' }, { minute: 'asc' }],
      select: {
        id: true,
        hour: true,
        minute: true,
        label: true,
        isEnabled: true,
        repeatDays: true,
        skipPenalty: true,
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
        label: data.label ?? null,
        isEnabled: data.isEnabled ?? true,
        repeatDays: data.repeatDays ?? [],
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
        createdAt: alarm.createdAt,
      },
    });
  } catch (error) {
    next(error);
  }
};

/**
 * GET /api/alarms/:id
 */
export const getAlarm = async (
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> => {
  try {
    const userId = req.user!.id;
    const alarmId = req.params['id']!;

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
 */
export const updateAlarm = async (
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> => {
  try {
    const userId = req.user!.id;
    const alarmId = req.params['id']!;
    const updates = updateAlarmSchema.parse(req.body);

    const existingAlarm = await prisma.alarm.findUnique({
      where: { id: alarmId },
    });

    if (!existingAlarm) {
      throw new NotFoundError('Alarm not found');
    }

    if (existingAlarm.userId !== userId) {
      throw new ForbiddenError('Access denied');
    }

    // Build only provided fields to avoid exactOptionalPropertyTypes issues
    const data: Record<string, unknown> = {};
    if (updates.hour !== undefined) data['hour'] = updates.hour;
    if (updates.minute !== undefined) data['minute'] = updates.minute;
    if (updates.label !== undefined) data['label'] = updates.label;
    if (updates.isEnabled !== undefined) data['isEnabled'] = updates.isEnabled;
    if (updates.repeatDays !== undefined) data['repeatDays'] = updates.repeatDays;
    if (updates.skipPenalty !== undefined) data['skipPenalty'] = updates.skipPenalty;

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
        updatedAt: alarm.updatedAt,
      },
    });
  } catch (error) {
    next(error);
  }
};

/**
 * DELETE /api/alarms/:id
 *
 * Deletes the alarm but penalties are preserved (SET NULL on alarmId).
 */
export const deleteAlarm = async (
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> => {
  try {
    const userId = req.user!.id;
    const alarmId = req.params['id']!;

    const existingAlarm = await prisma.alarm.findUnique({
      where: { id: alarmId },
    });

    if (!existingAlarm) {
      throw new NotFoundError('Alarm not found');
    }

    if (existingAlarm.userId !== userId) {
      throw new ForbiddenError('Access denied');
    }

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
