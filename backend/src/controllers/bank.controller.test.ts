import { describe, it, expect, vi, beforeEach } from 'vitest';
import { Request, Response, NextFunction } from 'express';
import { mockBankAccount } from '../test/helpers.js';

const mockPrisma = {
  bankAccount: {
    findUnique: vi.fn(),
    create: vi.fn(),
    delete: vi.fn(),
  },
  auditLog: {
    create: vi.fn(),
  },
};

vi.mock('../config/database.js', () => ({
  prisma: mockPrisma,
}));

const mockRemoveBankAccount = vi.fn();
const mockCreateCustomerWithBankAccount = vi.fn();

vi.mock('../services/stripe.service.js', () => ({
  stripeService: {
    removeBankAccount: mockRemoveBankAccount,
    createCustomerWithBankAccount: mockCreateCustomerWithBankAccount,
  },
}));

const mockRemoveItem = vi.fn();
vi.mock('../services/plaid.service.js', () => ({
  plaidService: {
    createLinkToken: vi.fn(),
    exchangePublicToken: vi.fn(),
    removeItem: mockRemoveItem,
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

const { unlinkAccount } = await import('./bank.controller.js');

function createMockReqRes() {
  const req = {
    user: { id: 'user-1', firebaseUid: 'firebase-uid-123', email: 'test@example.com' },
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

describe('unlinkAccount', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockPrisma.auditLog.create.mockResolvedValue({});
    mockPrisma.bankAccount.delete.mockResolvedValue({});
  });

  it('calls Stripe removeBankAccount before deleting from DB', async () => {
    const { req, res, next } = createMockReqRes();
    const bank = mockBankAccount();
    mockPrisma.bankAccount.findUnique.mockResolvedValue(bank);
    mockRemoveBankAccount.mockResolvedValue(undefined);
    mockRemoveItem.mockResolvedValue(undefined);

    const callOrder: string[] = [];
    mockRemoveBankAccount.mockImplementation(async () => { callOrder.push('stripe'); });
    mockRemoveItem.mockImplementation(async () => { callOrder.push('plaid'); });
    mockPrisma.bankAccount.delete.mockImplementation(async () => { callOrder.push('db'); return {}; });

    await unlinkAccount(req, res, next);

    expect(callOrder).toEqual(['stripe', 'plaid', 'db']);
    expect(mockRemoveBankAccount).toHaveBeenCalledWith('cus_test123', 'ba_test123');
  });

  it('returns 404 when no bank account linked', async () => {
    const { req, res, next } = createMockReqRes();
    mockPrisma.bankAccount.findUnique.mockResolvedValue(null);

    await unlinkAccount(req, res, next);

    expect(next).toHaveBeenCalledWith(
      expect.objectContaining({ statusCode: 404 })
    );
  });

  it('succeeds even if Plaid removal fails', async () => {
    const { req, res, next } = createMockReqRes();
    mockPrisma.bankAccount.findUnique.mockResolvedValue(mockBankAccount());
    mockRemoveBankAccount.mockResolvedValue(undefined);
    mockRemoveItem.mockRejectedValue(new Error('Plaid error'));

    await unlinkAccount(req, res, next);

    expect(res.json).toHaveBeenCalledWith(
      expect.objectContaining({ status: 'success' })
    );
  });
});
