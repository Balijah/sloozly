import { BankAccount, Penalty, PenaltyStatus } from '@prisma/client';
import { prisma } from '../config/database.js';
import { config } from '../config/index.js';
import { stripeService } from './stripe.service.js';
import { ConflictError, PaymentError } from '../utils/errors.js';
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

  async triggerPenalty(params: TriggerPenaltyParams): Promise<Penalty> {
    const { userId, alarmId, occurrenceId, snoozeNumber, bankAccount } = params;
    const key = { userId, occurrenceId, snoozeNumber };

    const penalty = await prisma.$transaction(async tx => {
      // Serialize reservations for this user across all server processes.
      await tx.$queryRaw`SELECT id FROM users WHERE id = ${userId} FOR UPDATE`;
      const existing = await tx.penalty.findUnique({
        where: { unique_snooze_per_occurrence: key },
      });
      if (existing) {
        if (existing.alarmId !== alarmId) throw new ConflictError('Occurrence belongs to another alarm');
        return existing;
      }

      const [day] = await tx.$queryRaw<{ total: number }[]>`
        SELECT COALESCE(SUM(p.amount), 0)::int AS total
        FROM penalties p JOIN users u ON u.id = p.user_id
        WHERE p.user_id = ${userId}
          AND p.status IN ('PENDING', 'PROCESSING', 'COMPLETED', 'REQUIRES_ACTION')
          AND (p.triggered_at AT TIME ZONE 'UTC' AT TIME ZONE u.timezone)::date =
              (CURRENT_TIMESTAMP AT TIME ZONE u.timezone)::date
      `;
      const capped = (day?.total ?? 0) + this.getPenaltyAmount() > config.penalty.dailyCapCents;
      return tx.penalty.create({
        data: {
          userId, alarmId, occurrenceId, snoozeNumber,
          amount: capped ? 0 : this.getPenaltyAmount(),
          status: capped ? PenaltyStatus.COMPLETED : PenaltyStatus.PENDING,
          processedAt: capped ? new Date() : null,
          failureReason: capped ? 'Daily cap reached' : null,
        },
      });
    });

    if (penalty.status === PenaltyStatus.COMPLETED || penalty.status === PenaltyStatus.FAILED) {
      return penalty;
    }

    if (!bankAccount.stripeCustomerId || !bankAccount.stripeBankAccountId ||
        !bankAccount.mandateAcceptedAt || !bankAccount.mandateIpAddress || !bankAccount.mandateUserAgent) {
      throw new ConflictError('Bank account must be relinked with payment authorization');
    }

    const idempotencyKey = `sloozly_${penalty.id}`;
    let paymentIntentId = penalty.stripePaymentIntentId;
    if (!paymentIntentId) {
      let result;
      try {
        result = await stripeService.createACHPaymentIntent(
          bankAccount.stripeCustomerId,
          bankAccount.stripeBankAccountId,
          penalty.amount,
          `Sloozly snooze penalty – occurrence ${occurrenceId} #${snoozeNumber}`,
          idempotencyKey,
          { penaltyId: penalty.id, userId, alarmId, occurrenceId, snoozeNumber: snoozeNumber.toString() }
        );
      } catch (error) {
        if (error instanceof PaymentError) {
          await prisma.penalty.updateMany({
            where: { id: penalty.id, status: PenaltyStatus.PENDING, stripePaymentIntentId: null },
            data: { status: PenaltyStatus.FAILED, failureReason: error.message, processedAt: new Date() },
          });
        }
        throw error;
      }
      paymentIntentId = result.paymentIntentId;
      // Never confirm (move money) until the recovery ID is durable.
      await prisma.penalty.updateMany({
        where: { id: penalty.id, stripePaymentIntentId: null },
        data: { stripePaymentIntentId: paymentIntentId, status: PenaltyStatus.PROCESSING },
      });
      const saved = await prisma.penalty.findUniqueOrThrow({ where: { id: penalty.id } });
      paymentIntentId = saved.stripePaymentIntentId!;
    }

    // Unknown/network failures stay reserved and are retried with the same intent.
    const result = await stripeService.confirmACHPaymentIntent(paymentIntentId, idempotencyKey, {
      acceptedAt: bankAccount.mandateAcceptedAt,
      ipAddress: bankAccount.mandateIpAddress,
      userAgent: bankAccount.mandateUserAgent,
    });
    if (result.status === 'succeeded' || result.status === 'canceled') {
      await this.resolvePayment(paymentIntentId, result.status === 'succeeded');
    } else {
      await prisma.penalty.updateMany({
        where: { id: penalty.id, status: { in: [PenaltyStatus.PENDING, PenaltyStatus.PROCESSING, PenaltyStatus.REQUIRES_ACTION] } },
        data: { status: result.status === 'requires_action' ? PenaltyStatus.REQUIRES_ACTION : PenaltyStatus.PROCESSING },
      });
    }
    return prisma.penalty.findUniqueOrThrow({ where: { id: penalty.id } });
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
