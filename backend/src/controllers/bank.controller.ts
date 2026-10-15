import { Request, Response, NextFunction } from 'express';
import { z } from 'zod';
import { prisma } from '../config/database.js';
import { plaidService } from '../services/plaid.service.js';
import { stripeService } from '../services/stripe.service.js';
import { NotFoundError, BadRequestError } from '../utils/errors.js';
import { logger } from '../utils/logger.js';

const exchangeTokenSchema = z.object({
  publicToken: z.string(),
  accountId: z.string(),
  mandateAccepted: z.boolean(),
});

/**
 * POST /api/bank/link-token
 */
export const createLinkToken = async (
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> => {
  try {
    const userId = req.user!.id;

    const linkToken = await plaidService.createLinkToken(userId);

    res.json({
      status: 'success',
      data: { linkToken },
    });
  } catch (error) {
    next(error);
  }
};

/**
 * POST /api/bank/exchange-token
 *
 * Requires mandateAccepted=true to record that the user
 * has consented to ACH debits under the snooze rules.
 */
export const exchangeToken = async (
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> => {
  try {
    const userId = req.user!.id;
    const { publicToken, accountId, mandateAccepted } = exchangeTokenSchema.parse(req.body);

    if (!mandateAccepted) {
      throw new BadRequestError(
        'You must accept the payment authorization to link a bank account.'
      );
    }

    const existingAccount = await prisma.bankAccount.findUnique({
      where: { userId },
    });

    if (existingAccount) {
      throw new BadRequestError('Bank account already linked. Unlink first to connect a new one.');
    }

    const plaidData = await plaidService.exchangePublicToken(publicToken, accountId);

    const stripeData = await stripeService.createCustomerWithBankAccount(
      req.user!.email,
      plaidData.accessToken,
      accountId
    );

    const ipAddress = req.ip ?? req.socket.remoteAddress ?? null;
    const userAgent = req.headers['user-agent'] ?? null;

    const bankAccount = await prisma.bankAccount.create({
      data: {
        userId,
        plaidAccessToken: plaidData.accessToken,
        plaidItemId: plaidData.itemId,
        plaidAccountId: accountId,
        institutionName: plaidData.institutionName,
        accountName: plaidData.accountName,
        accountMask: plaidData.accountMask,
        stripeCustomerId: stripeData.customerId,
        stripeBankAccountId: stripeData.bankAccountId,
        mandateAcceptedAt: new Date(),
        mandateIpAddress: ipAddress,
        mandateUserAgent: userAgent,
        status: 'ACTIVE',
      },
    });

    await prisma.auditLog.create({
      data: {
        userId,
        action: 'BANK_LINKED',
        details: {
          institutionName: plaidData.institutionName,
          accountMask: plaidData.accountMask,
          mandateAccepted: true,
        },
      },
    });

    logger.info(`Bank account linked for user: ${userId}`);

    res.status(201).json({
      status: 'success',
      data: {
        id: bankAccount.id,
        institutionName: bankAccount.institutionName,
        accountName: bankAccount.accountName,
        accountMask: bankAccount.accountMask,
        status: bankAccount.status,
        linkedAt: bankAccount.linkedAt,
      },
    });
  } catch (error) {
    next(error);
  }
};

/**
 * GET /api/bank/status
 */
export const getStatus = async (
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> => {
  try {
    const userId = req.user!.id;

    const bankAccount = await prisma.bankAccount.findUnique({
      where: { userId },
      select: {
        id: true,
        institutionName: true,
        accountName: true,
        accountMask: true,
        status: true,
        failureCount: true,
        linkedAt: true,
        updatedAt: true,
      },
    });

    if (!bankAccount) {
      res.json({
        status: 'success',
        data: { linked: false, account: null },
      });
      return;
    }

    res.json({
      status: 'success',
      data: { linked: true, account: bankAccount },
    });
  } catch (error) {
    next(error);
  }
};

/**
 * DELETE /api/bank/unlink
 *
 * Removes the bank account from Plaid, Stripe, and the local DB.
 */
export const unlinkAccount = async (
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> => {
  try {
    const userId = req.user!.id;

    const bankAccount = await prisma.bankAccount.findUnique({
      where: { userId },
    });

    if (!bankAccount) {
      throw new NotFoundError('No bank account linked');
    }

    // Remove from Stripe first (best-effort)
    if (bankAccount.stripeCustomerId && bankAccount.stripeBankAccountId) {
      await stripeService.removeBankAccount(
        bankAccount.stripeCustomerId,
        bankAccount.stripeBankAccountId
      );
    }

    // Remove Plaid item (best-effort)
    try {
      await plaidService.removeItem(bankAccount.plaidAccessToken);
    } catch (error) {
      logger.warn(`Failed to remove Plaid item for user ${userId}:`, error);
    }

    await prisma.bankAccount.delete({
      where: { userId },
    });

    await prisma.auditLog.create({
      data: {
        userId,
        action: 'BANK_UNLINKED',
        details: {
          institutionName: bankAccount.institutionName,
          accountMask: bankAccount.accountMask,
        },
      },
    });

    logger.info(`Bank account unlinked for user: ${userId}`);

    res.json({
      status: 'success',
      message: 'Bank account unlinked successfully',
    });
  } catch (error) {
    next(error);
  }
};
