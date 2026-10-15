import { z } from 'zod';

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
  PORT: z.string().transform(Number).default('3000'),

  DATABASE_URL: z.string(),

  FIREBASE_PROJECT_ID: z.string().default('test-project'),
  FIREBASE_PRIVATE_KEY: z.string().default('fake-key'),
  FIREBASE_CLIENT_EMAIL: z.string().default('test@test.iam.gserviceaccount.com'),

  PLAID_CLIENT_ID: z.string().default('test'),
  PLAID_SECRET: z.string().default('test'),
  PLAID_ENV: z.enum(['sandbox', 'development', 'production']).default('sandbox'),

  STRIPE_SECRET_KEY: z.string().default('sk_test_fake'),
  STRIPE_WEBHOOK_SECRET: z.string().optional(),

  LOG_LEVEL: z.enum(['error', 'warn', 'info', 'http', 'verbose', 'debug', 'silly']).default('info'),

  PENALTY_AMOUNT_CENTS: z.string().transform(Number).default('500'),
  PENALTY_DAILY_CAP_CENTS: z.string().transform(Number).default('2500'),
});

const parseEnv = () => {
  const result = envSchema.safeParse(process.env);

  if (!result.success) {
    console.error('Invalid environment variables:');
    console.error(result.error.format());
    process.exit(1);
  }

  return result.data;
};

const env = parseEnv();

export const config = {
  nodeEnv: env.NODE_ENV,
  port: env.PORT,
  isTest: env.NODE_ENV === 'test',

  database: {
    url: env.DATABASE_URL,
  },

  firebase: {
    projectId: env.FIREBASE_PROJECT_ID,
    privateKey: env.FIREBASE_PRIVATE_KEY.replace(/\\n/g, '\n'),
    clientEmail: env.FIREBASE_CLIENT_EMAIL,
  },

  plaid: {
    clientId: env.PLAID_CLIENT_ID,
    secret: env.PLAID_SECRET,
    env: env.PLAID_ENV,
  },

  stripe: {
    secretKey: env.STRIPE_SECRET_KEY,
    webhookSecret: env.STRIPE_WEBHOOK_SECRET,
  },

  logging: {
    level: env.LOG_LEVEL,
  },

  penalty: {
    amountCents: env.PENALTY_AMOUNT_CENTS,
    dailyCapCents: env.PENALTY_DAILY_CAP_CENTS,
  },
} as const;

export type Config = typeof config;
