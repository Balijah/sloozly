import Stripe from 'stripe';
import { stripe } from '../config/stripe.js';
import { plaidService } from './plaid.service.js';
import { ExternalServiceError, PaymentError } from '../utils/errors.js';
import { logger } from '../utils/logger.js';

interface CreateCustomerResult {
  customerId: string;
  bankAccountId: string;
}

interface CreatePaymentResult {
  paymentIntentId: string;
  status: string;
}

class StripeService {
  /**
   * Create a Stripe customer and attach a bank account via Plaid processor token.
   * Uses the Plaid-to-Stripe processor flow (supported in Plaid sandbox).
   */
  async createCustomerWithBankAccount(
    email: string,
    plaidAccessToken: string,
    plaidAccountId: string
  ): Promise<CreateCustomerResult> {
    try {
      const stripeBankToken = await plaidService.createStripeBankAccountToken(
        plaidAccessToken,
        plaidAccountId
      );

      const customer = await stripe.customers.create({
        email,
        description: 'Sloozly user',
        metadata: {
          source: 'sloozly',
        },
      });

      const bankAccount = await stripe.customers.createSource(customer.id, {
        source: stripeBankToken,
      }) as Stripe.BankAccount;

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
   * Create a PaymentIntent for an ACH debit.
   * The occurrenceId+snoozeNumber is used as the Stripe idempotency key
   * to prevent duplicate charges for the same snooze event.
   *
   * PaymentIntents for ACH stay in 'processing' until the bank settles,
   * so we never mark them completed until we receive a webhook.
   */
  async createACHPaymentIntent(
    customerId: string,
    bankAccountId: string,
    amountCents: number,
    description: string,
    idempotencyKey: string,
    metadata: Record<string, string> = {}
  ): Promise<CreatePaymentResult> {
    try {
      const paymentIntent = await stripe.paymentIntents.create(
        {
          amount: amountCents,
          currency: 'usd',
          customer: customerId,
          payment_method_data: {
            type: 'us_bank_account',
            us_bank_account: {
              financial_connections_account: bankAccountId,
            },
          },
          payment_method_types: ['us_bank_account'],
          description,
          metadata: {
            ...metadata,
            app: 'sloozly',
          },
          mandate_data: {
            customer_acceptance: {
              type: 'online',
              online: {
                ip_address: metadata['mandate_ip'] ?? 'unknown',
                user_agent: metadata['mandate_ua'] ?? 'Sloozly iOS',
              },
            },
          },
        },
        { idempotencyKey }
      );

      // Confirm immediately — ACH will move to 'processing'
      const confirmed = await stripe.paymentIntents.confirm(paymentIntent.id, undefined, {
        idempotencyKey: `${idempotencyKey}_confirm`,
      });

      logger.info(
        `ACH PaymentIntent created: ${confirmed.id} status=${confirmed.status} ` +
        `for $${(amountCents / 100).toFixed(2)}`
      );

      return {
        paymentIntentId: confirmed.id,
        status: confirmed.status,
      };
    } catch (error: unknown) {
      logger.error('Stripe createACHPaymentIntent error:', error);

      if (error instanceof Stripe.errors.StripeError) {
        if (error.code === 'idempotency_key_in_use') {
          throw new PaymentError('Duplicate payment request', error.code);
        }
        throw new PaymentError(
          error.message || 'Payment failed',
          error.code
        );
      }

      throw new PaymentError('Payment processing failed');
    }
  }

  async getPaymentIntentStatus(paymentIntentId: string): Promise<{
    status: string;
    failureCode: string | null;
    failureMessage: string | null;
  }> {
    try {
      const pi = await stripe.paymentIntents.retrieve(paymentIntentId);

      return {
        status: pi.status,
        failureCode: (pi.last_payment_error?.code as string) ?? null,
        failureMessage: pi.last_payment_error?.message ?? null,
      };
    } catch (error) {
      logger.error('Stripe getPaymentIntentStatus error:', error);
      throw new ExternalServiceError('Stripe', 'Failed to get payment status');
    }
  }

  async deleteCustomer(customerId: string): Promise<void> {
    try {
      await stripe.customers.del(customerId);
      logger.info(`Stripe customer deleted: ${customerId}`);
    } catch (error) {
      logger.error('Stripe deleteCustomer error:', error);
    }
  }

  async removeBankAccount(customerId: string, bankAccountId: string): Promise<void> {
    try {
      await stripe.customers.deleteSource(customerId, bankAccountId);
      logger.info(`Bank account removed from customer: ${customerId}`);
    } catch (error) {
      logger.error('Stripe removeBankAccount error:', error);
    }
  }

  /**
   * Construct and verify a Stripe webhook event from the raw body and signature.
   */
  constructWebhookEvent(
    rawBody: Buffer,
    signature: string,
    webhookSecret: string
  ): Stripe.Event {
    return stripe.webhooks.constructEvent(rawBody, signature, webhookSecret);
  }
}

export const stripeService = new StripeService();
