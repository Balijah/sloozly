import { Router } from 'express';
import * as webhookController from '../controllers/webhook.controller.js';

const router = Router();

router.post('/stripe', webhookController.handleStripeWebhook);

export default router;
