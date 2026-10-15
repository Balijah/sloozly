import { Router } from 'express';
import { authenticate } from '../middleware/auth.middleware.js';
import * as authController from '../controllers/auth.controller.js';

const router = Router();

// ===========================================
// Auth Routes
// ===========================================

// POST /api/auth/register - Create user in database after Firebase signup
router.post('/register', authController.register);

// GET /api/auth/me - Get current user profile
router.get('/me', authenticate, authController.getMe);

// PUT /api/auth/me - Update current user profile
router.put('/me', authenticate, authController.updateMe);

// DELETE /api/auth/me - Delete user account
router.delete('/me', authenticate, authController.deleteMe);

export default router;
