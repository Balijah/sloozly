import admin from 'firebase-admin';
import { config } from './index.js';

// ===========================================
// Firebase Admin SDK Initialization
// ===========================================

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert({
      projectId: config.firebase.projectId,
      privateKey: config.firebase.privateKey,
      clientEmail: config.firebase.clientEmail,
    }),
  });
}

export const firebaseAdmin = admin;
export const firebaseAuth = admin.auth();
