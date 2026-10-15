import { describe, it, expect, vi, beforeEach } from 'vitest';
import { PenaltyStatus, Prisma } from '@prisma/client';
import { mockBankAccount, mockPenalty } from '../test/helpers.js';

// Mock prisma before importing the service
const mockPrisma = {
  penalty: {
    create: vi.fn(),
    findUnique: vi.fn(),
    findFirst: vi.fn(),
    update: vi.fn(),
    aggregate: vi.fn(),
  },
  bankAccount: {
    update: vi.fn(),
  },
  auditLog: {
    create: vi.fn(),
  },
};

vi.mock('../config/database.js', () => ({
  prisma: mockPrisma,
}));

const mockStripeService = {
  createACHPaymentIntent: vi.fn(),
};

vi.mock('./stripe.service.js', () => ({
  stripeService: mockStripeService,
}));

// Import after mocks
const { penaltyService } = await import('./penalty.service.js');

describe('PenaltyService', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockPrisma.penalty.aggregate.mockResolvedValue({ _sum: { amount: 0 } });
    mockPrisma.auditLog.create.mockResolvedValue({});
  });

  describe('getPenaltyAmount', () => {
    it('returns the flat penalty amount from config', () => {
      const amount = penaltyService.getPenaltyAmount();
      expect(amount).toBe(500);
    });
  });

  describe('triggerPenalty', () => {
    const baseParams = {
      userId: 'user-1',
      alarmId: 'alarm-1',
      occurrenceId: 'alarm-1_2026-01-15',
      snoozeNumber: 1,
      bankAccount: mockBankAccount(),
    };

    it('creates a penalty and submits it for processing', async () => {
      const createdPenalty = mockPenalty({ status: PenaltyStatus.PENDING });
      const processingPenalty = mockPenalty({ status: PenaltyStatus.PROCESSING, stripePaymentIntentId: 'pi_test123' });

      mockPrisma.penalty.create.mockResolvedValue(createdPenalty);
      mockPrisma.penalty.update
        .mockResolvedValueOnce(mockPenalty({ status: PenaltyStatus.PROCESSING }))
        .mockResolvedValueOnce(processingPenalty);
      mockStripeService.createACHPaymentIntent.mockResolvedValue({
        paymentIntentId: 'pi_test123',
        status: 'processing',
      });

      const result = await penaltyService.triggerPenalty(baseParams);

      expect(result.status).toBe(PenaltyStatus.PROCESSING);
      expect(result.stripePaymentIntentId).toBe('pi_test123');
      expect(mockStripeService.createACHPaymentIntent).toHaveBeenCalledWith(
        'cus_test123',
        'ba_test123',
        500,
        expect.stringContaining('alarm-1_2026-01-15'),
        'sloozly_alarm-1_2026-01-15_1',
        expect.objectContaining({ penaltyId: 'penalty-1' })
      );
    });

    it('does NOT mark penalty as COMPLETED — leaves it PROCESSING for webhook', async () => {
      const createdPenalty = mockPenalty({ status: PenaltyStatus.PENDING });
      mockPrisma.penalty.create.mockResolvedValue(createdPenalty);
      mockPrisma.penalty.update.mockImplementation(async ({ data }: any) => {
        return mockPenalty({ ...data });
      });
      mockStripeService.createACHPaymentIntent.mockResolvedValue({
        paymentIntentId: 'pi_test123',
        status: 'processing',
      });

      const result = await penaltyService.triggerPenalty(baseParams);

      expect(result.status).toBe(PenaltyStatus.PROCESSING);
      expect(result.status).not.toBe(PenaltyStatus.COMPLETED);
    });

    it('returns existing penalty on duplicate snooze (idempotent)', async () => {
      const existingPenalty = mockPenalty({ status: PenaltyStatus.PROCESSING });

      const prismaError = new Prisma.PrismaClientKnownRequestError(
        'Unique constraint failed',
        { code: 'P2002', clientVersion: '5.0.0', meta: {} }
      );
      mockPrisma.penalty.create.mockRejectedValue(prismaError);
      mockPrisma.penalty.findUnique.mockResolvedValue(existingPenalty);

      const result = await penaltyService.triggerPenalty(baseParams);

      expect(result).toEqual(existingPenalty);
      expect(mockStripeService.createACHPaymentIntent).not.toHaveBeenCalled();
    });

    it('marks penalty FAILED when Stripe rejects', async () => {
      const createdPenalty = mockPenalty({ status: PenaltyStatus.PENDING });
      const failedPenalty = mockPenalty({
        status: PenaltyStatus.FAILED,
        failureReason: 'Card declined',
      });

      mockPrisma.penalty.create.mockResolvedValue(createdPenalty);
      mockPrisma.penalty.update
        .mockResolvedValueOnce(mockPenalty({ status: PenaltyStatus.PROCESSING }))
        .mockResolvedValueOnce(failedPenalty);
      mockPrisma.bankAccount.update.mockResolvedValue({});
      mockStripeService.createACHPaymentIntent.mockRejectedValue(
        new Error('Card declined')
      );

      const result = await penaltyService.triggerPenalty(baseParams);

      expect(result.status).toBe(PenaltyStatus.FAILED);
      expect(result.failureReason).toBe('Card declined');
    });

    it('enforces daily cap', async () => {
      mockPrisma.penalty.aggregate.mockResolvedValue({ _sum: { amount: 2200 } });
      mockPrisma.penalty.findUnique.mockResolvedValue(null);
      mockPrisma.penalty.create.mockResolvedValue(
        mockPenalty({ amount: 0, status: PenaltyStatus.COMPLETED, failureReason: 'Daily cap reached' })
      );

      const result = await penaltyService.triggerPenalty(baseParams);

      expect(result.amount).toBe(0);
      expect(mockStripeService.createACHPaymentIntent).not.toHaveBeenCalled();
    });

    it('allows penalty when under daily cap', async () => {
      mockPrisma.penalty.aggregate.mockResolvedValue({ _sum: { amount: 1500 } });

      const createdPenalty = mockPenalty({ status: PenaltyStatus.PENDING });
      mockPrisma.penalty.create.mockResolvedValue(createdPenalty);
      mockPrisma.penalty.update.mockResolvedValue(
        mockPenalty({ status: PenaltyStatus.PROCESSING, stripePaymentIntentId: 'pi_test123' })
      );
      mockStripeService.createACHPaymentIntent.mockResolvedValue({
        paymentIntentId: 'pi_test123',
        status: 'processing',
      });

      const result = await penaltyService.triggerPenalty(baseParams);

      expect(result.status).toBe(PenaltyStatus.PROCESSING);
      expect(mockStripeService.createACHPaymentIntent).toHaveBeenCalled();
    });
  });

  describe('resolvePayment', () => {
    it('marks a PROCESSING penalty as COMPLETED on success', async () => {
      const processingPenalty = mockPenalty({
        status: PenaltyStatus.PROCESSING,
        stripePaymentIntentId: 'pi_test123',
      });
      const completedPenalty = mockPenalty({
        status: PenaltyStatus.COMPLETED,
        processedAt: new Date(),
      });

      mockPrisma.penalty.findFirst.mockResolvedValue(processingPenalty);
      mockPrisma.penalty.update.mockResolvedValue(completedPenalty);
      mockPrisma.auditLog.create.mockResolvedValue({});

      const result = await penaltyService.resolvePayment('pi_test123', true);

      expect(result?.status).toBe(PenaltyStatus.COMPLETED);
    });

    it('marks a PROCESSING penalty as FAILED on failure', async () => {
      const processingPenalty = mockPenalty({
        status: PenaltyStatus.PROCESSING,
        stripePaymentIntentId: 'pi_test123',
      });
      const failedPenalty = mockPenalty({
        status: PenaltyStatus.FAILED,
        failureReason: 'Insufficient funds',
      });

      mockPrisma.penalty.findFirst.mockResolvedValue(processingPenalty);
      mockPrisma.penalty.update.mockResolvedValue(failedPenalty);
      mockPrisma.auditLog.create.mockResolvedValue({});

      const result = await penaltyService.resolvePayment('pi_test123', false, 'Insufficient funds');

      expect(result?.status).toBe(PenaltyStatus.FAILED);
    });

    it('does not re-resolve an already completed penalty', async () => {
      const completedPenalty = mockPenalty({ status: PenaltyStatus.COMPLETED });
      mockPrisma.penalty.findFirst.mockResolvedValue(completedPenalty);

      const result = await penaltyService.resolvePayment('pi_test123', true);

      expect(result).toEqual(completedPenalty);
      expect(mockPrisma.penalty.update).not.toHaveBeenCalled();
    });

    it('returns null for unknown payment intent', async () => {
      mockPrisma.penalty.findFirst.mockResolvedValue(null);

      const result = await penaltyService.resolvePayment('pi_unknown', true);

      expect(result).toBeNull();
    });
  });
});
