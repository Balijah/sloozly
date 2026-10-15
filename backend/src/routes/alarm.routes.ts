import { Router } from 'express';
import { authenticate } from '../middleware/auth.middleware.js';
import { validate, commonSchemas } from '../middleware/validation.middleware.js';
import * as alarmController from '../controllers/alarm.controller.js';

const router = Router();

// ===========================================
// Alarm Routes
// ===========================================

// GET /api/alarms - List user's alarms
router.get('/', authenticate, alarmController.listAlarms);

// POST /api/alarms - Create new alarm
router.post('/', authenticate, alarmController.createAlarm);

// GET /api/alarms/:id - Get single alarm
router.get(
  '/:id',
  authenticate,
  validate({ params: commonSchemas.id }),
  alarmController.getAlarm
);

// PUT /api/alarms/:id - Update alarm
router.put(
  '/:id',
  authenticate,
  validate({ params: commonSchemas.id }),
  alarmController.updateAlarm
);

// DELETE /api/alarms/:id - Delete alarm
router.delete(
  '/:id',
  authenticate,
  validate({ params: commonSchemas.id }),
  alarmController.deleteAlarm
);

export default router;
