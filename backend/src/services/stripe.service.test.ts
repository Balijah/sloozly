import { beforeEach, describe, expect, it, vi } from 'vitest';
import { stripe } from '../config/stripe.js';
import { stripeService } from './stripe.service.js';

const acceptance = { acceptedAt: new Date('2026-01-01T12:00:00Z'), ipAddress: '127.0.0.1', userAgent: 'Sloozly iOS' };
describe('Stripe payment recovery', () => {
  beforeEach(() => vi.clearAllMocks());

  it('uses the saved bank account as payment_method, without confirming', async () => {
    await stripeService.createACHPaymentIntent('cus_1', 'ba_1', 500, 'Snooze', 'key');
    const body = vi.mocked(stripe.paymentIntents.create).mock.calls[0]![0]!;
    expect(body.payment_method).toBe('ba_1');
    expect(body).not.toHaveProperty('payment_method_data');
    expect(body).not.toHaveProperty('confirm', true);
    expect(stripe.paymentIntents.confirm).not.toHaveBeenCalled();
  });

  it('confirms with the actual recorded mandate evidence', async () => {
    vi.mocked(stripe.paymentIntents.retrieve).mockResolvedValue({ id: 'pi_1', status: 'requires_confirmation' } as any);
    await stripeService.confirmACHPaymentIntent('pi_1', 'key', acceptance);
    expect(stripe.paymentIntents.confirm).toHaveBeenCalledWith('pi_1', {
      setup_future_usage: 'off_session',
      mandate_data: { customer_acceptance: { type: 'online', accepted_at: 1767268800,
        online: { ip_address: '127.0.0.1', user_agent: 'Sloozly iOS' } } },
    }, { idempotencyKey: 'key_confirm' });
  });

  it('does not reconfirm an already submitted payment', async () => {
    vi.mocked(stripe.paymentIntents.retrieve).mockResolvedValue({ id: 'pi_1', status: 'processing' } as any);
    expect((await stripeService.confirmACHPaymentIntent('pi_1', 'key', acceptance)).status).toBe('processing');
    expect(stripe.paymentIntents.confirm).not.toHaveBeenCalled();
  });
});
