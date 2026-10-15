import { Router } from 'express';
import { authenticate } from '../middleware/auth.middleware.js';
import * as penaltyController from '../controllers/penalty.controller.js';

const router = Router();

// ===========================================
// Penalty Routes
// ===========================================

// POST /api/penalties/trigger - Trigger a penalty (called when user hits snooze)
router.post('/trigger', authenticate, penaltyController.triggerPenalty);

// GET /api/penalties/history - Get penalty history
router.get('/history', authenticate, penaltyController.getHistory);

// GET /api/penalties/stats - Get penalty statistics
router.get('/stats', authenticate, penaltyController.getStats);

export default router;
