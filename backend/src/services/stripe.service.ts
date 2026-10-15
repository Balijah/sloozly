import { stripe } from '../config/stripe.js';
import { plaidService } from './plaid.service.js';
import { ExternalServiceError, PaymentError } from '../utils/errors.js';
import { logger } from '../utils/logger.js';

// ===========================================
// Stripe Service
// ===========================================

interface CreateCustomerResult {
  customerId: string;
  bankAccountId: string;
}

class StripeService {
  /**
   * Create a Stripe customer with a bank account from Plaid
   */
  async createCustomerWithBankAccount(
    email: string,
    plaidAccessToken: string,
    plaidAccountId: string
  ): Promise<CreateCustomerResult> {
    try {
      // Get Stripe bank account token from Plaid
      const stripeBankToken = await plaidService.createStripeBankAccountToken(
        plaidAccessToken,
        plaidAccountId
      );

      // Create Stripe customer
      const customer = await stripe.customers.create({
        email,
        description: 'Sloozly user',
        metadata: {
          source: 'sloozly',
        },
      });

      // Attach bank account to customer
      const bankAccount = await stripe.customers.createSource(customer.id, {
        source: stripeBankToken,
      });

      logger.info(`Stripe customer created: ${customer.id}`);

      return {
        customerId: customer.id,
        bankAccountId: bankAccount.id,
      };
    } catch (error) {
      logger.error('Stripe createCustomerWithBankAccount error:', error);
      throw new ExternalServiceError('Stripe', 'Failed to setup payment account');
    }
  }

  /**
   * Create an ACH charge (debit) from a customer's bank account
   * Returns the charge ID for tracking
   */
  async createACHCharge(
    customerId: string,
    bankAccountId: string,
    amountCents: number,
    description: string,
    metadata: Record<string, string> = {}
  ): Promise<{
    chargeId: string;
    status: string;
  }> {
    try {
      const charge = await stripe.charges.create({
        amount: amountCents,
        currency: 'usd',
        customer: customerId,
        source: bankAccountId,
        description,
        metadata: {
          ...metadata,
          app: 'sloozly',
        },
        // ACH charges are not instant - they process over 1-5 business days
        // Status will be 'pending' initially
      });

      logger.info(`ACH charge created: ${charge.id} for $${(amountCents / 100).toFixed(2)}`);

      return {
        chargeId: charge.id,
        status: charge.status,
      };
    } catch (error: any) {
      logger.error('Stripe createACHCharge error:', error);
      
      // Handle specific Stripe errors
      if (error.type === 'StripeCardError') {
        throw new PaymentError(
          error.message || 'Payment failed',
          error.code
        );
      }
      
      if (error.type === 'StripeInvalidRequestError') {
        throw new PaymentError(
          'Invalid payment request',
          error.code
        );
      }

      throw new PaymentError('Payment processing failed');
    }
  }

  /**
   * Get charge status (for checking if ACH transfer completed)
   */
  async getChargeStatus(chargeId: string): Promise<{
    status: string;
    failureCode?: string;
    failureMessage?: string;
  }> {
    try {
      const charge = await stripe.charges.retrieve(chargeId);

      return {
        status: charge.status,
        failureCode: charge.failure_code || undefined,
        failureMessage: charge.failure_message || undefined,
      };
    } catch (error) {
      logger.error('Stripe getChargeStatus error:', error);
      throw new ExternalServiceError('Stripe', 'Failed to get payment status');
    }
  }

  /**
   * Delete a customer (when user deletes account)
   */
  async deleteCustomer(customerId: string): Promise<void> {
    try {
      await stripe.customers.del(customerId);
      logger.info(`Stripe customer deleted: ${customerId}`);
    } catch (error) {
      logger.error('Stripe deleteCustomer error:', error);
      // Don't throw - this is cleanup
    }
  }

  /**
   * Remove a bank account from a customer
   */
  async removeBankAccount(customerId: string, bankAccountId: string): Promise<void> {
    try {
      await stripe.customers.deleteSource(customerId, bankAccountId);
      logger.info(`Bank account removed from customer: ${customerId}`);
    } catch (error) {
      logger.error('Stripe removeBankAccount error:', error);
      // Don't throw - this is cleanup
    }
  }
}

export const stripeService = new StripeService();
