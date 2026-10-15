import { vi } from 'vitest';

// Set test environment variables before any imports
process.env['NODE_ENV'] = 'test';
process.env['DATABASE_URL'] = 'postgresql://fake:fake@localhost:5432/test';
process.env['FIREBASE_PROJECT_ID'] = 'test-project';
process.env['FIREBASE_PRIVATE_KEY'] = 'fake-key';
process.env['FIREBASE_CLIENT_EMAIL'] = 'test@test.iam.gserviceaccount.com';
process.env['PLAID_CLIENT_ID'] = 'test';
process.env['PLAID_SECRET'] = 'test';
process.env['STRIPE_SECRET_KEY'] = 'sk_test_fake';
process.env['STRIPE_WEBHOOK_SECRET'] = 'whsec_test';
process.env['LOG_LEVEL'] = 'error';
process.env['PENALTY_AMOUNT_CENTS'] = '500';
process.env['PENALTY_DAILY_CAP_CENTS'] = '2500';

// Mock firebase-admin before anything else imports it
vi.mock('firebase-admin', () => {
  const mockAuth = {
    verifyIdToken: vi.fn().mockResolvedValue({
      uid: 'firebase-uid-123',
      email: 'test@example.com',
      name: 'Test User',
    }),
    deleteUser: vi.fn().mockResolvedValue(undefined),
  };

  const mockApp = {
    auth: () => mockAuth,
  };

  return {
    default: {
      apps: [mockApp],
      initializeApp: vi.fn().mockReturnValue(mockApp),
      credential: {
        cert: vi.fn(),
      },
      auth: () => mockAuth,
    },
  };
});

// Mock the Stripe constructor and its methods
vi.mock('stripe', () => {
  const mockStripe = {
    customers: {
      create: vi.fn().mockResolvedValue({ id: 'cus_test123' }),
      createSource: vi.fn().mockResolvedValue({ id: 'ba_test123' }),
      del: vi.fn().mockResolvedValue({ id: 'cus_test123', deleted: true }),
      deleteSource: vi.fn().mockResolvedValue({ id: 'ba_test123', deleted: true }),
    },
    paymentIntents: {
      create: vi.fn().mockResolvedValue({
        id: 'pi_test123',
        status: 'processing',
      }),
      confirm: vi.fn().mockResolvedValue({
        id: 'pi_test123',
        status: 'processing',
      }),
      retrieve: vi.fn().mockResolvedValue({
        id: 'pi_test123',
        status: 'processing',
        last_payment_error: null,
      }),
    },
    webhooks: {
      constructEvent: vi.fn(),
    },
    errors: {
      StripeError: class StripeError extends Error {
        type: string;
        code?: string;
        constructor(msg: string) {
          super(msg);
          this.type = 'StripeError';
        }
      },
    },
  };

  const StripeClass = vi.fn(() => mockStripe);
  (StripeClass as any).errors = mockStripe.errors;

  return { default: StripeClass };
});

// Mock plaid
vi.mock('plaid', () => ({
  Configuration: vi.fn(),
  PlaidApi: vi.fn().mockImplementation(() => ({
    linkTokenCreate: vi.fn().mockResolvedValue({
      data: { link_token: 'link-sandbox-test-token' },
    }),
    itemPublicTokenExchange: vi.fn().mockResolvedValue({
      data: { access_token: 'access-sandbox-test', item_id: 'item-test-123' },
    }),
    accountsGet: vi.fn().mockResolvedValue({
      data: {
        accounts: [
          { account_id: 'acc-123', name: 'Checking', mask: '1234' },
        ],
      },
    }),
    itemGet: vi.fn().mockResolvedValue({
      data: { item: { institution_id: 'ins_1' } },
    }),
    institutionsGetById: vi.fn().mockResolvedValue({
      data: { institution: { name: 'Test Bank' } },
    }),
    authGet: vi.fn().mockResolvedValue({
      data: {
        numbers: {
          ach: [
            { account_id: 'acc-123', account: '111222333', routing: '021000021' },
          ],
        },
      },
    }),
    itemRemove: vi.fn().mockResolvedValue({}),
    processorStripeBankAccountTokenCreate: vi.fn().mockResolvedValue({
      data: { stripe_bank_account_token: 'btok_test123' },
    }),
  })),
  PlaidEnvironments: { sandbox: 'https://sandbox.plaid.com' },
  CountryCode: { Us: 'US' },
  Products: { Auth: 'auth' },
}));
