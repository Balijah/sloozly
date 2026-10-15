import { Configuration, PlaidApi, PlaidEnvironments } from 'plaid';
import { config } from './index.js';

// ===========================================
// Plaid Client Configuration
// ===========================================

const plaidConfig = new Configuration({
  basePath: PlaidEnvironments[config.plaid.env],
  baseOptions: {
    headers: {
      'PLAID-CLIENT-ID': config.plaid.clientId,
      'PLAID-SECRET': config.plaid.secret,
    },
  },
});

export const plaidClient = new PlaidApi(plaidConfig);
