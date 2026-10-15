import { Configuration, PlaidApi, PlaidEnvironments } from 'plaid';
import { config } from './index.js';

const basePath = PlaidEnvironments[config.plaid.env];
if (!basePath) {
  throw new Error(`Invalid Plaid environment: ${config.plaid.env}`);
}

const plaidConfig = new Configuration({
  basePath,
  baseOptions: {
    headers: {
      'PLAID-CLIENT-ID': config.plaid.clientId,
      'PLAID-SECRET': config.plaid.secret,
    },
  },
});

export const plaidClient = new PlaidApi(plaidConfig);
