import { Router } from 'express';
import { authenticate } from '../middleware/auth.middleware.js';
import * as bankController from '../controllers/bank.controller.js';

const router = Router();

// ===========================================
// Bank Routes (Plaid Integration)
// ===========================================

// POST /api/bank/link-token - Generate Plaid Link token
router.post('/link-token', authenticate, bankController.createLinkToken);

// POST /api/bank/exchange-token - Exchange public token for access token
router.post('/exchange-token', authenticate, bankController.exchangeToken);

// GET /api/bank/status - Get linked bank account status
router.get('/status', authenticate, bankController.getStatus);

// DELETE /api/bank/unlink - Remove linked bank account
router.delete('/unlink', authenticate, bankController.unlinkAccount);

export default router;
