import { describe, it, expect, vi, beforeEach } from 'vitest';
import { PenaltyStatus } from '@prisma/client';
import { mockBankAccount, mockPenalty } from '../test/helpers.js';
import { ExternalServiceError } from '../utils/errors.js';

const db = {
  $queryRaw: vi.fn(),
  $transaction: vi.fn(),
  penalty: { findUnique: vi.fn(), findUniqueOrThrow: vi.fn(), create: vi.fn(), updateMany: vi.fn(), findFirst: vi.fn(), update: vi.fn() },
  auditLog: { create: vi.fn() },
};
vi.mock('../config/database.js', () => ({ prisma: db }));
const payments = { createACHPaymentIntent: vi.fn(), confirmACHPaymentIntent: vi.fn() };
vi.mock('./stripe.service.js', () => ({ stripeService: payments }));
const { penaltyService } = await import('./penalty.service.js');
const params = { userId: 'user-1', alarmId: 'alarm-1', occurrenceId: 'alarm-1_2026-01-15', snoozeNumber: 1, bankAccount: mockBankAccount() };

describe('PenaltyService', () => {
  beforeEach(() => {
    vi.resetAllMocks();
    db.$transaction.mockImplementation(fn => fn(db));
    db.$queryRaw.mockResolvedValue([{ total: 0 }]);
    db.penalty.findUnique.mockResolvedValue(null);
    db.penalty.create.mockImplementation(async ({ data }) => mockPenalty(data));
    db.penalty.findUniqueOrThrow.mockResolvedValue(mockPenalty({ status: PenaltyStatus.PROCESSING, stripePaymentIntentId: 'pi_test123' }));
    payments.createACHPaymentIntent.mockResolvedValue({ paymentIntentId: 'pi_test123', status: 'requires_confirmation' });
    payments.confirmACHPaymentIntent.mockResolvedValue({ paymentIntentId: 'pi_test123', status: 'processing' });
  });

  it('reserves under a row lock and saves the intent before confirming', async () => {
    const result = await penaltyService.triggerPenalty(params);
    expect(db.$queryRaw.mock.calls[0]![0].join('')).toContain('FOR UPDATE');
    expect(db.penalty.findUnique).toHaveBeenCalledWith({ where: { unique_snooze_per_occurrence: {
      userId: params.userId, occurrenceId: params.occurrenceId, snoozeNumber: 1,
    } } });
    expect(db.penalty.updateMany.mock.invocationCallOrder[0]).toBeLessThan(payments.confirmACHPaymentIntent.mock.invocationCallOrder[0]!);
    expect(result.status).toBe(PenaltyStatus.PROCESSING);
    expect(payments.createACHPaymentIntent).toHaveBeenCalledWith('cus_test123', 'ba_test123', 500, expect.any(String), 'sloozly_penalty-1', expect.objectContaining({ userId: 'user-1' }));
  });

  it('records zero at the daily cap without calling Stripe', async () => {
    db.$queryRaw.mockResolvedValue([{ total: 2500 }]);
    const result = await penaltyService.triggerPenalty(params);
    expect(result.amount).toBe(0);
    expect(payments.createACHPaymentIntent).not.toHaveBeenCalled();
    expect(payments.confirmACHPaymentIntent).not.toHaveBeenCalled();
  });

  it('resumes an existing pending record after a crash before Stripe', async () => {
    db.penalty.findUnique.mockResolvedValue(mockPenalty());
    await penaltyService.triggerPenalty(params);
    expect(db.penalty.create).not.toHaveBeenCalled();
    expect(payments.createACHPaymentIntent).toHaveBeenCalledOnce();
  });

  it('reuses a saved intent after a crash before or after confirmation', async () => {
    db.penalty.findUnique.mockResolvedValue(mockPenalty({ status: PenaltyStatus.PROCESSING, stripePaymentIntentId: 'pi_saved' }));
    await penaltyService.triggerPenalty(params);
    expect(payments.createACHPaymentIntent).not.toHaveBeenCalled();
    expect(payments.confirmACHPaymentIntent).toHaveBeenCalledWith('pi_saved', 'sloozly_penalty-1', {
      acceptedAt: params.bankAccount.mandateAcceptedAt, ipAddress: '127.0.0.1', userAgent: 'Sloozly iOS',
    });
  });

  it('does not confirm if persisting the intent fails', async () => {
    db.penalty.updateMany.mockRejectedValueOnce(new Error('database unavailable'));
    await expect(penaltyService.triggerPenalty(params)).rejects.toThrow('database unavailable');
    expect(payments.confirmACHPaymentIntent).not.toHaveBeenCalled();
  });

  it('keeps an uncertain Stripe result reserved for retry', async () => {
    payments.confirmACHPaymentIntent.mockRejectedValue(new ExternalServiceError('Stripe'));
    await expect(penaltyService.triggerPenalty(params)).rejects.toThrow();
    expect(db.penalty.updateMany).not.toHaveBeenCalledWith(expect.objectContaining({ data: expect.objectContaining({ status: 'FAILED' }) }));
  });

  it('does not submit terminal duplicates again', async () => {
    db.penalty.findUnique.mockResolvedValue(mockPenalty({ status: PenaltyStatus.COMPLETED }));
    await penaltyService.triggerPenalty(params);
    expect(payments.createACHPaymentIntent).not.toHaveBeenCalled();
    expect(payments.confirmACHPaymentIntent).not.toHaveBeenCalled();
  });

  it('rejects an occurrence reused for a different alarm', async () => {
    db.penalty.findUnique.mockResolvedValue(mockPenalty({ alarmId: 'other-alarm' }));
    await expect(penaltyService.triggerPenalty(params)).rejects.toThrow('another alarm');
  });

  it('resolves a processing payment from its webhook', async () => {
    db.penalty.findFirst.mockResolvedValue(mockPenalty({ status: PenaltyStatus.PROCESSING }));
    db.penalty.update.mockResolvedValue(mockPenalty({ status: PenaltyStatus.COMPLETED }));
    expect((await penaltyService.resolvePayment('pi_test123', true))?.status).toBe('COMPLETED');
  });

  it('does not resolve a terminal payment twice', async () => {
    db.penalty.findFirst.mockResolvedValue(mockPenalty({ status: PenaltyStatus.COMPLETED }));
    await penaltyService.resolvePayment('pi_test123', true);
    expect(db.penalty.update).not.toHaveBeenCalled();
  });
});
