import { Request, Response, NextFunction } from 'express';
import Stripe from 'stripe';
import { config } from '../config/index.js';
import { stripeService } from '../services/stripe.service.js';
import { penaltyService } from '../services/penalty.service.js';
import { logger } from '../utils/logger.js';
import { BadRequestError } from '../utils/errors.js';

/**
 * POST /api/webhooks/stripe
 *
 * Stripe sends payment_intent.succeeded / payment_intent.payment_failed
 * after ACH debit settles. We resolve the penalty status here.
 *
 * The route must receive the raw body (not JSON-parsed).
 */
export const handleStripeWebhook = async (
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> => {
  try {
    const sig = req.headers['stripe-signature'];
    if (!sig || typeof sig !== 'string') {
      throw new BadRequestError('Missing stripe-signature header');
    }

    if (!config.stripe.webhookSecret) {
      logger.error('STRIPE_WEBHOOK_SECRET not configured');
      res.status(500).json({ error: 'Webhook secret not configured' });
      return;
    }

    let event: Stripe.Event;
    try {
      event = stripeService.constructWebhookEvent(
        req.body as Buffer,
        sig,
        config.stripe.webhookSecret
      );
    } catch (err) {
      logger.warn('Webhook signature verification failed:', err);
      res.status(400).json({ error: 'Invalid signature' });
      return;
    }

    logger.info(`Stripe webhook received: ${event.type} (${event.id})`);

    switch (event.type) {
      case 'payment_intent.succeeded': {
        const pi = event.data.object as Stripe.PaymentIntent;
        await penaltyService.resolvePayment(pi.id, true);
        break;
      }

      case 'payment_intent.payment_failed': {
        const pi = event.data.object as Stripe.PaymentIntent;
        const reason =
          pi.last_payment_error?.message ?? 'Payment failed';
        await penaltyService.resolvePayment(pi.id, false, reason);
        break;
      }

      default:
        logger.debug(`Unhandled webhook event type: ${event.type}`);
    }

    res.json({ received: true });
  } catch (error) {
    next(error);
  }
};
