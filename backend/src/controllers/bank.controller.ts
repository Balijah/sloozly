import { Request, Response, NextFunction } from 'express';
import { z } from 'zod';
import { prisma } from '../config/database.js';
import { plaidService } from '../services/plaid.service.js';
import { stripeService } from '../services/stripe.service.js';
import { NotFoundError, BadRequestError } from '../utils/errors.js';
import { logger } from '../utils/logger.js';

// ===========================================
// Validation Schemas
// ===========================================

const exchangeTokenSchema = z.object({
  publicToken: z.string(),
  accountId: z.string(),
});

// ===========================================
// Controllers
// ===========================================

/**
 * POST /api/bank/link-token
 * Generate a Plaid Link token for the client
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
      data: {
        linkToken,
      },
    });
  } catch (error) {
    next(error);
  }
};

/**
 * POST /api/bank/exchange-token
 * Exchange public token for access token and store bank account
 */
export const exchangeToken = async (
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> => {
  try {
    const userId = req.user!.id;
    const { publicToken, accountId } = exchangeTokenSchema.parse(req.body);

    // Check if user already has a linked bank account
    const existingAccount = await prisma.bankAccount.findUnique({
      where: { userId },
    });

    if (existingAccount) {
      throw new BadRequestError('Bank account already linked. Unlink first to connect a new one.');
    }

    // Exchange token via Plaid
    const plaidData = await plaidService.exchangePublicToken(publicToken, accountId);

    // Create Stripe customer and bank account for ACH transfers
    const stripeData = await stripeService.createCustomerWithBankAccount(
      req.user!.email,
      plaidData.accessToken,
      accountId
    );

    // Store bank account in database
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
        status: 'ACTIVE',
      },
    });

    // Audit log
    await prisma.auditLog.create({
      data: {
        userId,
        action: 'BANK_LINKED',
        details: {
          institutionName: plaidData.institutionName,
          accountMask: plaidData.accountMask,
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
 * Get linked bank account status
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
        data: {
          linked: false,
          account: null,
        },
      });
      return;
    }

    res.json({
      status: 'success',
      data: {
        linked: true,
        account: bankAccount,
      },
    });
  } catch (error) {
    next(error);
  }
};

/**
 * DELETE /api/bank/unlink
 * Remove linked bank account
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

    // Remove Plaid item (optional but recommended)
    try {
      await plaidService.removeItem(bankAccount.plaidAccessToken);
    } catch (error) {
      // Log but don't fail if Plaid removal fails
      logger.warn(`Failed to remove Plaid item for user ${userId}:`, error);
    }

    // Delete from database
    await prisma.bankAccount.delete({
      where: { userId },
    });

    // Audit log
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
