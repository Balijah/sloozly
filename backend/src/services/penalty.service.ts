import { BankAccount, Penalty, PenaltyStatus } from '@prisma/client';
import { prisma } from '../config/database.js';
import { stripeService } from './stripe.service.js';
import { logger } from '../utils/logger.js';

// ===========================================
// Penalty Service
// ===========================================

interface TriggerPenaltyParams {
  userId: string;
  alarmId: string;
  snoozeNumber: number;
  basePenaltyAmount: number; // In cents
  bankAccount: BankAccount;
}

// Maximum penalty cap to prevent runaway amounts
const MAX_PENALTY_CENTS = 5000; // $50 max per snooze (safety cap)

class PenaltyService {
  /**
   * Calculate penalty amount based on snooze number
   * Escalating: $5 -> $10 -> $20 -> $40 (doubles each time)
   * Capped at MAX_PENALTY_CENTS
   */
  calculatePenaltyAmount(basePenaltyAmount: number, snoozeNumber: number): number {
    // For MVP: flat $5 (snooze number 1)
    // For MMF: escalating (2^(snoozeNumber-1) * base)
    const multiplier = Math.pow(2, snoozeNumber - 1);
    const calculatedAmount = basePenaltyAmount * multiplier;
    
    // Cap at maximum
    return Math.min(calculatedAmount, MAX_PENALTY_CENTS);
  }

  /**
   * Trigger a penalty when user snoozes
   */
  async triggerPenalty(params: TriggerPenaltyParams): Promise<Penalty> {
    const { userId, alarmId, snoozeNumber, basePenaltyAmount, bankAccount } = params;

    // Calculate amount
    const amount = this.calculatePenaltyAmount(basePenaltyAmount, snoozeNumber);

    // Create penalty record in PENDING state
    const penalty = await prisma.penalty.create({
      data: {
        userId,
        alarmId,
        amount,
        snoozeNumber,
        status: PenaltyStatus.PENDING,
      },
    });

    logger.info(`Penalty created: ${penalty.id} for $${(amount / 100).toFixed(2)}`);

    // Attempt to process payment
    try {
      // Update to PROCESSING
      await prisma.penalty.update({
        where: { id: penalty.id },
        data: { status: PenaltyStatus.PROCESSING },
      });

      // Create ACH charge via Stripe
      const charge = await stripeService.createACHCharge(
        bankAccount.stripeCustomerId!,
        bankAccount.stripeBankAccountId!,
        amount,
        `Sloozly snooze penalty #${snoozeNumber}`,
        {
          penaltyId: penalty.id,
          alarmId,
          snoozeNumber: snoozeNumber.toString(),
        }
      );

      // Update penalty with successful charge
      const updatedPenalty = await prisma.penalty.update({
        where: { id: penalty.id },
        data: {
          status: PenaltyStatus.COMPLETED,
          stripeTransferId: charge.chargeId,
          processedAt: new Date(),
        },
      });

      // Audit log
      await prisma.auditLog.create({
        data: {
          userId,
          action: 'PENALTY_PROCESSED',
          details: {
            penaltyId: penalty.id,
            amount,
            snoozeNumber,
            chargeId: charge.chargeId,
          },
        },
      });

      logger.info(`Penalty processed successfully: ${penalty.id}`);

      return updatedPenalty;
    } catch (error: any) {
      // Payment failed - update penalty status
      const failureReason = error.message || 'Payment processing failed';

      const failedPenalty = await prisma.penalty.update({
        where: { id: penalty.id },
        data: {
          status: PenaltyStatus.FAILED,
          failureReason,
          processedAt: new Date(),
        },
      });

      // Increment failure count on bank account
      await prisma.bankAccount.update({
        where: { id: bankAccount.id },
        data: {
          failureCount: { increment: 1 },
          lastFailureReason: failureReason,
          // If too many failures, mark account as needing relink
          status: bankAccount.failureCount >= 2 ? 'NEEDS_RELINK' : 'ACTIVE',
        },
      });

      // Audit log
      await prisma.auditLog.create({
        data: {
          userId,
          action: 'PENALTY_FAILED',
          details: {
            penaltyId: penalty.id,
            amount,
            snoozeNumber,
            failureReason,
          },
        },
      });

      logger.warn(`Penalty processing failed: ${penalty.id} - ${failureReason}`);

      // Return the failed penalty (per our protocol: log, notify, don't retry)
      return failedPenalty;
    }
  }

  /**
   * Get penalty statistics for a user
   */
  async getUserStats(userId: string): Promise<{
    totalPenalties: number;
    totalAmount: number;
    completedCount: number;
    failedCount: number;
  }> {
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
      totalAmount += stat._sum.amount || 0;
      
      if (stat.status === PenaltyStatus.COMPLETED) {
        completedCount = stat._count.id;
      } else if (stat.status === PenaltyStatus.FAILED) {
        failedCount = stat._count.id;
      }
    }

    return {
      totalPenalties,
      totalAmount,
      completedCount,
      failedCount,
    };
  }
}

export const penaltyService = new PenaltyService();
