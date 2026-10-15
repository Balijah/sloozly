import { describe, it, expect, vi, beforeEach } from 'vitest';
import request from 'supertest';
import express from 'express';
import type Stripe from 'stripe';

const mockResolvePayment = vi.fn();
const mockConstructWebhookEvent = vi.fn();

vi.mock('../services/penalty.service.js', () => ({
  penaltyService: {
    resolvePayment: mockResolvePayment,
  },
}));

vi.mock('../services/stripe.service.js', () => ({
  stripeService: {
    constructWebhookEvent: mockConstructWebhookEvent,
  },
}));

vi.mock('../config/index.js', () => ({
  config: {
    stripe: { webhookSecret: 'whsec_test' },
    nodeEnv: 'test',
    logging: { level: 'error' },
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

const { handleStripeWebhook } = await import('./webhook.controller.js');

function createApp() {
  const app = express();
  app.post('/webhook', express.raw({ type: 'application/json' }), handleStripeWebhook);
  return app;
}

describe('Stripe Webhook Controller', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('returns 400 without stripe-signature header', async () => {
    const app = createApp();
    const res = await request(app)
      .post('/webhook')
      .set('Content-Type', 'application/json')
      .send(JSON.stringify({ type: 'test' }));

    expect(res.status).toBe(400);
  });

  it('returns 400 for invalid signature', async () => {
    const app = createApp();
    mockConstructWebhookEvent.mockImplementation(() => {
      throw new Error('Invalid signature');
    });

    const res = await request(app)
      .post('/webhook')
      .set('Content-Type', 'application/json')
      .set('stripe-signature', 'bad_sig')
      .send(JSON.stringify({ type: 'test' }));

    expect(res.status).toBe(400);
    expect(res.body.error).toBe('Invalid signature');
  });

  it('resolves payment on payment_intent.succeeded', async () => {
    const app = createApp();
    const event: Partial<Stripe.Event> = {
      id: 'evt_test123',
      type: 'payment_intent.succeeded',
      data: {
        object: { id: 'pi_test123' } as Stripe.PaymentIntent,
        previous_attributes: undefined,
      },
    };

    mockConstructWebhookEvent.mockReturnValue(event);
    mockResolvePayment.mockResolvedValue({ id: 'penalty-1', status: 'COMPLETED' });

    const res = await request(app)
      .post('/webhook')
      .set('Content-Type', 'application/json')
      .set('stripe-signature', 'valid_sig')
      .send(JSON.stringify(event));

    expect(res.status).toBe(200);
    expect(res.body.received).toBe(true);
    expect(mockResolvePayment).toHaveBeenCalledWith('pi_test123', true);
  });

  it('resolves payment as failed on payment_intent.payment_failed', async () => {
    const app = createApp();
    const event: Partial<Stripe.Event> = {
      id: 'evt_test456',
      type: 'payment_intent.payment_failed',
      data: {
        object: {
          id: 'pi_test456',
          last_payment_error: { message: 'Insufficient funds' },
        } as unknown as Stripe.PaymentIntent,
        previous_attributes: undefined,
      },
    };

    mockConstructWebhookEvent.mockReturnValue(event);
    mockResolvePayment.mockResolvedValue({ id: 'penalty-2', status: 'FAILED' });

    const res = await request(app)
      .post('/webhook')
      .set('Content-Type', 'application/json')
      .set('stripe-signature', 'valid_sig')
      .send(JSON.stringify(event));

    expect(res.status).toBe(200);
    expect(mockResolvePayment).toHaveBeenCalledWith(
      'pi_test456',
      false,
      'Insufficient funds'
    );
  });

  it('acknowledges unhandled event types', async () => {
    const app = createApp();
    const event: Partial<Stripe.Event> = {
      id: 'evt_test789',
      type: 'customer.created',
      data: {
        object: {} as any,
        previous_attributes: undefined,
      },
    };

    mockConstructWebhookEvent.mockReturnValue(event);

    const res = await request(app)
      .post('/webhook')
      .set('Content-Type', 'application/json')
      .set('stripe-signature', 'valid_sig')
      .send(JSON.stringify(event));

    expect(res.status).toBe(200);
    expect(res.body.received).toBe(true);
    expect(mockResolvePayment).not.toHaveBeenCalled();
  });
});
