import { BankAccount, Penalty, PenaltyStatus, Prisma } from '@prisma/client';
import { prisma } from '../config/database.js';
import { config } from '../config/index.js';
import { stripeService } from './stripe.service.js';
import { ConflictError } from '../utils/errors.js';
import { logger } from '../utils/logger.js';

interface TriggerPenaltyParams {
  userId: string;
  alarmId: string;
  occurrenceId: string;
  snoozeNumber: number;
  bankAccount: BankAccount;
}

class PenaltyService {
  /**
   * Return the flat penalty amount from server config.
   * Amount is NOT trusted from the client or computed per-alarm.
   */
  getPenaltyAmount(): number {
    return config.penalty.amountCents;
  }

  /**
   * Sum the amounts already charged (PENDING/PROCESSING/COMPLETED)
   * for the given user on a calendar day in the user's local timezone.
   */
  async getDayTotal(userId: string, date: Date): Promise<number> {
    const dayStart = new Date(date);
    dayStart.setHours(0, 0, 0, 0);
    const dayEnd = new Date(date);
    dayEnd.setHours(23, 59, 59, 999);

    const result = await prisma.penalty.aggregate({
      where: {
        userId,
        triggeredAt: { gte: dayStart, lte: dayEnd },
        status: { in: [PenaltyStatus.PENDING, PenaltyStatus.PROCESSING, PenaltyStatus.COMPLETED] },
      },
      _sum: { amount: true },
    });

    return result._sum.amount ?? 0;
  }

  /**
   * Trigger a penalty for a snooze event.
   *
   * Idempotency: the (occurrenceId, snoozeNumber) pair has a unique DB constraint.
   * If a penalty already exists for this pair, we return it instead of creating a duplicate.
   * The same occurrenceId+snoozeNumber is used as the Stripe idempotency key.
   *
   * Daily cap: if the user has already been charged up to the daily cap,
   * we skip creating a new penalty.
   */
  async triggerPenalty(params: TriggerPenaltyParams): Promise<Penalty & { capped?: boolean }> {
    const { userId, alarmId, occurrenceId, snoozeNumber, bankAccount } = params;
    const amount = this.getPenaltyAmount();

    const dayTotal = await this.getDayTotal(userId, new Date());
    if (dayTotal + amount > config.penalty.dailyCapCents) {
      logger.info(
        `Daily cap reached for user ${userId}: ` +
        `today=${dayTotal}c, would be ${dayTotal + amount}c, cap=${config.penalty.dailyCapCents}c`
      );

      const existing = await prisma.penalty.findUnique({
        where: { unique_snooze_per_occurrence: { occurrenceId, snoozeNumber } },
      });
      if (existing) return existing;

      const capped = await prisma.penalty.create({
        data: {
          userId,
          alarmId,
          occurrenceId,
          snoozeNumber,
          amount: 0,
          status: PenaltyStatus.COMPLETED,
          processedAt: new Date(),
          failureReason: 'Daily cap reached',
        },
      });
      return { ...capped, capped: true };
    }

    let penalty: Penalty;
    try {
      penalty = await prisma.penalty.create({
        data: {
          userId,
          alarmId,
          occurrenceId,
          snoozeNumber,
          amount,
          status: PenaltyStatus.PENDING,
        },
      });
    } catch (error) {
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === 'P2002'
      ) {
        const existing = await prisma.penalty.findUnique({
          where: { unique_snooze_per_occurrence: { occurrenceId, snoozeNumber } },
        });
        if (existing) {
          logger.info(`Duplicate snooze ignored: ${occurrenceId}#${snoozeNumber}`);
          return existing;
        }
        throw new ConflictError('Duplicate penalty');
      }
      throw error;
    }

    logger.info(`Penalty created: ${penalty.id} for $${(amount / 100).toFixed(2)}`);

    try {
      await prisma.penalty.update({
        where: { id: penalty.id },
        data: { status: PenaltyStatus.PROCESSING },
      });

      const idempotencyKey = `sloozly_${occurrenceId}_${snoozeNumber}`;

      const result = await stripeService.createACHPaymentIntent(
        bankAccount.stripeCustomerId!,
        bankAccount.stripeBankAccountId!,
        amount,
        `Sloozly snooze penalty – occurrence ${occurrenceId} #${snoozeNumber}`,
        idempotencyKey,
        {
          penaltyId: penalty.id,
          alarmId,
          occurrenceId,
          snoozeNumber: snoozeNumber.toString(),
        }
      );

      // ACH stays in 'processing' — do NOT mark COMPLETED here.
      // The webhook will resolve the final status.
      const updatedPenalty = await prisma.penalty.update({
        where: { id: penalty.id },
        data: {
          status: PenaltyStatus.PROCESSING,
          stripePaymentIntentId: result.paymentIntentId,
        },
      });

      await prisma.auditLog.create({
        data: {
          userId,
          action: 'PENALTY_PROCESSING',
          details: {
            penaltyId: penalty.id,
            amount,
            snoozeNumber,
            paymentIntentId: result.paymentIntentId,
            occurrenceId,
          },
        },
      });

      logger.info(`Penalty submitted for processing: ${penalty.id}`);

      return updatedPenalty;
    } catch (error: unknown) {
      const failureReason = error instanceof Error
        ? error.message
        : 'Payment processing failed';

      const failedPenalty = await prisma.penalty.update({
        where: { id: penalty.id },
        data: {
          status: PenaltyStatus.FAILED,
          failureReason,
          processedAt: new Date(),
        },
      });

      await prisma.bankAccount.update({
        where: { id: bankAccount.id },
        data: {
          failureCount: { increment: 1 },
          lastFailureReason: failureReason,
          status: bankAccount.failureCount >= 2 ? 'NEEDS_RELINK' : 'ACTIVE',
        },
      });

      await prisma.auditLog.create({
        data: {
          userId,
          action: 'PENALTY_FAILED',
          details: {
            penaltyId: penalty.id,
            amount,
            snoozeNumber,
            failureReason,
            occurrenceId,
          },
        },
      });

      logger.warn(`Penalty processing failed: ${penalty.id} – ${failureReason}`);

      return failedPenalty;
    }
  }

  /**
   * Resolve a payment based on a Stripe webhook event.
   * Called from the webhook handler.
   */
  async resolvePayment(
    paymentIntentId: string,
    succeeded: boolean,
    failureReason?: string
  ): Promise<Penalty | null> {
    const penalty = await prisma.penalty.findFirst({
      where: { stripePaymentIntentId: paymentIntentId },
    });

    if (!penalty) {
      logger.warn(`No penalty found for PaymentIntent: ${paymentIntentId}`);
      return null;
    }

    if (penalty.status === PenaltyStatus.COMPLETED || penalty.status === PenaltyStatus.FAILED) {
      logger.info(`Penalty ${penalty.id} already resolved as ${penalty.status}, skipping`);
      return penalty;
    }

    const newStatus = succeeded ? PenaltyStatus.COMPLETED : PenaltyStatus.FAILED;

    const updated = await prisma.penalty.update({
      where: { id: penalty.id },
      data: {
        status: newStatus,
        processedAt: new Date(),
        failureReason: failureReason ?? null,
      },
    });

    await prisma.auditLog.create({
      data: {
        userId: penalty.userId,
        action: succeeded ? 'PENALTY_COMPLETED' : 'PENALTY_WEBHOOK_FAILED',
        details: {
          penaltyId: penalty.id,
          paymentIntentId,
          finalStatus: newStatus,
          failureReason: failureReason ?? null,
        },
      },
    });

    logger.info(`Penalty ${penalty.id} resolved via webhook: ${newStatus}`);

    return updated;
  }

  async getUserStats(userId: string) {
    const stats = await prisma.penalty.groupBy({
      by: ['status'],
      where: { userId },
      _count: { id: true },
      _sum: { amount: true },
    });

    let totalPenalties = 0;
    let totalAmount = 0;
    let completedCount = 0;
    let failedCount = 0;

    for (const stat of stats) {
      totalPenalties += stat._count.id;
      totalAmount += stat._sum.amount ?? 0;

      if (stat.status === PenaltyStatus.COMPLETED) {
        completedCount = stat._count.id;
      } else if (stat.status === PenaltyStatus.FAILED) {
        failedCount = stat._count.id;
      }
    }

    return { totalPenalties, totalAmount, completedCount, failedCount };
  }
}

export const penaltyService = new PenaltyService();
