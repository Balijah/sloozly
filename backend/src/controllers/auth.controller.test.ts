import { describe, it, expect, vi, beforeEach } from 'vitest';
import { Request, Response, NextFunction } from 'express';
import { PenaltyStatus } from '@prisma/client';
import { mockUser, mockBankAccount } from '../test/helpers.js';

const mockPrisma = {
  user: {
    findUnique: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
  },
  bankAccount: {
    findUnique: vi.fn(),
    deleteMany: vi.fn(),
  },
  alarm: {
    deleteMany: vi.fn(),
  },
  penalty: {
    count: vi.fn(),
  },
  auditLog: {
    create: vi.fn(),
  },
  $transaction: vi.fn().mockImplementation((fns: any[]) => Promise.all(fns)),
};

vi.mock('../config/database.js', () => ({
  prisma: mockPrisma,
}));

const mockDeleteCustomer = vi.fn();
vi.mock('../services/stripe.service.js', () => ({
  stripeService: {
    deleteCustomer: mockDeleteCustomer,
  },
}));

const mockFirebaseDeleteUser = vi.fn();
vi.mock('../config/firebase.js', () => ({
  firebaseAuth: {
    verifyIdToken: vi.fn(),
    deleteUser: mockFirebaseDeleteUser,
  },
}));

vi.mock('../utils/logger.js', () => ({
  logger: {
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
    debug: vi.fn(),
  },
}));

const { deleteMe } = await import('./auth.controller.js');

function createMockReqRes(userId = 'user-1', firebaseUid = 'firebase-uid-123') {
  const req = {
    user: { id: userId, firebaseUid, email: 'test@example.com' },
    headers: {},
    body: {},
  } as unknown as Request;

  const res = {
    json: vi.fn().mockReturnThis(),
    status: vi.fn().mockReturnThis(),
  } as unknown as Response;

  const next: NextFunction = vi.fn();
  return { req, res, next };
}

describe('deleteMe', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockPrisma.auditLog.create.mockResolvedValue({});
    mockPrisma.bankAccount.deleteMany.mockResolvedValue({});
    mockPrisma.alarm.deleteMany.mockResolvedValue({});
    mockPrisma.user.update.mockResolvedValue(mockUser({ deletedAt: new Date() }));
    mockFirebaseDeleteUser.mockResolvedValue(undefined);
  });

  it('blocks deletion when payments are pending', async () => {
    const { req, res, next } = createMockReqRes();
    mockPrisma.penalty.count.mockResolvedValue(3);

    await deleteMe(req, res, next);

    expect(next).toHaveBeenCalledWith(
      expect.objectContaining({
        message: expect.stringContaining('3 payment(s) are still processing'),
      })
    );
    expect(mockPrisma.user.update).not.toHaveBeenCalled();
  });

  it('allows deletion when no pending payments', async () => {
    const { req, res, next } = createMockReqRes();
    mockPrisma.penalty.count.mockResolvedValue(0);
    mockPrisma.bankAccount.findUnique.mockResolvedValue(mockBankAccount());

    await deleteMe(req, res, next);

    expect(mockDeleteCustomer).toHaveBeenCalledWith('cus_test123');
    expect(res.json).toHaveBeenCalledWith(
      expect.objectContaining({ status: 'success' })
    );
  });

  it('soft-deletes user (sets deletedAt) instead of hard-deleting', async () => {
    const { req, res, next } = createMockReqRes();
    mockPrisma.penalty.count.mockResolvedValue(0);
    mockPrisma.bankAccount.findUnique.mockResolvedValue(null);

    await deleteMe(req, res, next);

    expect(mockPrisma.$transaction).toHaveBeenCalled();
    expect(mockPrisma.user.update).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ deletedAt: expect.any(Date) }),
      })
    );
  });

  it('cleans up external services before local data', async () => {
    const { req, res, next } = createMockReqRes();
    mockPrisma.penalty.count.mockResolvedValue(0);
    const bank = mockBankAccount();
    mockPrisma.bankAccount.findUnique.mockResolvedValue(bank);

    const callOrder: string[] = [];
    mockDeleteCustomer.mockImplementation(async () => { callOrder.push('stripe'); });
    mockPrisma.$transaction.mockImplementation(async () => { callOrder.push('db'); return []; });

    await deleteMe(req, res, next);

    expect(callOrder).toEqual(['stripe', 'db']);
  });
});
