import { Router } from 'express';
import authRoutes from './auth.routes.js';
import bankRoutes from './bank.routes.js';
import alarmRoutes from './alarm.routes.js';
import penaltyRoutes from './penalty.routes.js';

const router = Router();

// ===========================================
// API Version Prefix: /api
// ===========================================

router.use('/auth', authRoutes);
router.use('/bank', bankRoutes);
router.use('/alarms', alarmRoutes);
router.use('/penalties', penaltyRoutes);

export default router;
