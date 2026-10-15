import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { PrismaClient } from '@prisma/client';
import { mockBankAccount } from '../test/helpers.js';

const url = process.env['TEST_DATABASE_URL'];
const db = new PrismaClient({ datasourceUrl: url ?? 'postgresql://unused:unused@localhost:1/unused' });
vi.mock('../config/database.js', () => ({ prisma: db }));
const payments = { createACHPaymentIntent: vi.fn(), confirmACHPaymentIntent: vi.fn() };
vi.mock('./stripe.service.js', () => ({ stripeService: payments }));
const { penaltyService } = await import('./penalty.service.js');
const userId = 'review-user';
const alarmId = 'review-alarm';
const params = { userId, alarmId, occurrenceId: 'same-occurrence', snoozeNumber: 1, bankAccount: mockBankAccount() };

// This URL must point at an isolated test database, never an app database.
describe.skipIf(!url)('PostgreSQL penalty reservations', () => {
  beforeAll(async () => {
    await db.user.createMany({ data: [
      { id: userId, firebaseUid: 'review-firebase', email: 'review@example.test', timezone: 'Pacific/Honolulu' },
      { id: 'review-user-2', firebaseUid: 'review-firebase-2', email: 'review2@example.test' },
    ] });
    await db.alarm.createMany({ data: [
      { id: alarmId, userId, hour: 7, minute: 0 },
      { id: 'review-alarm-2', userId: 'review-user-2', hour: 7, minute: 0 },
    ] });
  });
  beforeEach(async () => {
    await db.penalty.deleteMany({ where: { userId: { in: [userId, 'review-user-2'] } } });
    vi.resetAllMocks();
    payments.createACHPaymentIntent.mockImplementation(async (...args) => ({ paymentIntentId: `pi_${args[4]}`, status: 'requires_confirmation' }));
    payments.confirmACHPaymentIntent.mockResolvedValue({ status: 'processing' });
  });
  afterAll(async () => {
    await db.auditLog.deleteMany({ where: { userId: { in: [userId, 'review-user-2'] } } });
    await db.penalty.deleteMany({ where: { userId: { in: [userId, 'review-user-2'] } } });
    await db.alarm.deleteMany({ where: { userId: { in: [userId, 'review-user-2'] } } });
    await db.user.deleteMany({ where: { id: { in: [userId, 'review-user-2'] } } });
    await db.$disconnect();
  });

  it('serializes concurrent reservations at the cap', async () => {
    await db.penalty.create({ data: { userId, alarmId, occurrenceId: 'earlier', snoozeNumber: 1, amount: 2000, status: 'COMPLETED' } });
    const results = await Promise.all([penaltyService.triggerPenalty(params), penaltyService.triggerPenalty({ ...params, snoozeNumber: 2 })]);
    expect(results.map(p => p.amount).sort()).toEqual([0, 500]);
    expect(payments.createACHPaymentIntent).toHaveBeenCalledOnce();
  });

  it('allows two users to use the same client occurrence ID independently', async () => {
    const one = await penaltyService.triggerPenalty(params);
    const two = await penaltyService.triggerPenalty({ ...params, userId: 'review-user-2', alarmId: 'review-alarm-2' });
    expect(one.userId).toBe(userId);
    expect(two.userId).toBe('review-user-2');
    expect(one.id).not.toBe(two.id);
  });

  it('creates one record for simultaneous duplicate requests', async () => {
    const results = await Promise.all([penaltyService.triggerPenalty(params), penaltyService.triggerPenalty(params)]);
    expect(results[0]!.id).toBe(results[1]!.id);
    expect(await db.penalty.count({ where: { userId } })).toBe(1);
    expect(new Set(payments.createACHPaymentIntent.mock.calls.map(args => args[4])).size).toBeLessThanOrEqual(1);
  });

  it('recovers an intent after a timeout without creating another intent', async () => {
    payments.confirmACHPaymentIntent.mockRejectedValueOnce(new Error('network timeout'));
    await expect(penaltyService.triggerPenalty(params)).rejects.toThrow('network timeout');
    const result = await penaltyService.triggerPenalty(params);
    expect(result.status).toBe('PROCESSING');
    expect(payments.createACHPaymentIntent).toHaveBeenCalledOnce();
    expect(payments.confirmACHPaymentIntent.mock.calls[0]![0]).toBe(payments.confirmACHPaymentIntent.mock.calls[1]![0]);
  });

  it('counts the current calendar day in the user timezone', async () => {
    // Local noon yesterday is excluded even when its UTC date is today.
    await db.$executeRaw`
      INSERT INTO penalties (id, user_id, alarm_id, occurrence_id, amount, snooze_number, status, triggered_at)
      SELECT 'review-yesterday', ${userId}, ${alarmId}, 'yesterday', 2500, 1, 'COMPLETED',
        ((CURRENT_TIMESTAMP AT TIME ZONE timezone)::date - 1 + TIME '12:00') AT TIME ZONE timezone
      FROM users WHERE id = ${userId}
    `;
    expect((await penaltyService.triggerPenalty(params)).amount).toBe(500);
  });
});
