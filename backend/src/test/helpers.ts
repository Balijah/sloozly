import { vi } from 'vitest';
import { PrismaClient, PenaltyStatus, BankAccountStatus } from '@prisma/client';

/**
 * Create a mock PrismaClient with common operations stubbed.
 * Tests should override specific methods as needed.
 */
export function createMockPrisma() {
  return {
    user: {
      findUnique: vi.fn(),
      findFirst: vi.fn(),
      create: vi.fn(),
      update: vi.fn(),
      delete: vi.fn(),
    },
    bankAccount: {
      findUnique: vi.fn(),
      create: vi.fn(),
      update: vi.fn(),
      delete: vi.fn(),
      deleteMany: vi.fn(),
    },
    alarm: {
      findUnique: vi.fn(),
      findMany: vi.fn(),
      create: vi.fn(),
      update: vi.fn(),
      delete: vi.fn(),
      deleteMany: vi.fn(),
    },
    penalty: {
      findUnique: vi.fn(),
      findFirst: vi.fn(),
      findMany: vi.fn(),
      create: vi.fn(),
      update: vi.fn(),
      count: vi.fn(),
      aggregate: vi.fn(),
      groupBy: vi.fn(),
    },
    auditLog: {
      create: vi.fn(),
    },
    $transaction: vi.fn().mockImplementation((fns: any[]) =>
      Promise.all(fns)
    ),
    $connect: vi.fn(),
    $disconnect: vi.fn(),
  } as unknown as PrismaClient;
}

export function mockUser(overrides: Partial<any> = {}) {
  return {
    id: 'user-1',
    firebaseUid: 'firebase-uid-123',
    email: 'test@example.com',
    displayName: 'Test User',
    timezone: 'America/New_York',
    deletedAt: null,
    createdAt: new Date('2026-01-01'),
    updatedAt: new Date('2026-01-01'),
    ...overrides,
  };
}

export function mockBankAccount(overrides: Partial<any> = {}) {
  return {
    id: 'bank-1',
    userId: 'user-1',
    plaidAccessToken: 'access-sandbox-test',
    plaidItemId: 'item-test-123',
    plaidAccountId: 'acc-123',
    institutionName: 'Test Bank',
    accountName: 'Checking',
    accountMask: '1234',
    stripeCustomerId: 'cus_test123',
    stripeBankAccountId: 'ba_test123',
    mandateAcceptedAt: new Date('2026-01-01'),
    mandateIpAddress: '127.0.0.1',
    mandateUserAgent: 'Sloozly iOS',
    status: BankAccountStatus.ACTIVE,
    failureCount: 0,
    lastFailureReason: null,
    linkedAt: new Date('2026-01-01'),
    updatedAt: new Date('2026-01-01'),
    ...overrides,
  };
}

export function mockAlarm(overrides: Partial<any> = {}) {
  return {
    id: 'alarm-1',
    userId: 'user-1',
    hour: 7,
    minute: 0,
    isEnabled: true,
    label: 'Morning alarm',
    repeatDays: [1, 2, 3, 4, 5],
    skipPenalty: false,
    createdAt: new Date('2026-01-01'),
    updatedAt: new Date('2026-01-01'),
    ...overrides,
  };
}

export function mockPenalty(overrides: Partial<any> = {}) {
  return {
    id: 'penalty-1',
    userId: 'user-1',
    alarmId: 'alarm-1',
    occurrenceId: 'alarm-1_2026-01-15',
    amount: 500,
    snoozeNumber: 1,
    status: PenaltyStatus.PENDING,
    stripePaymentIntentId: null,
    failureReason: null,
    triggeredAt: new Date('2026-01-15T07:00:00Z'),
    processedAt: null,
    ...overrides,
  };
}
