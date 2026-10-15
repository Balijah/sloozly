import { 
  CountryCode, 
  Products,
  LinkTokenCreateRequest,
} from 'plaid';
import { plaidClient } from '../config/plaid.js';
import { config } from '../config/index.js';
import { ExternalServiceError } from '../utils/errors.js';
import { logger } from '../utils/logger.js';

// ===========================================
// Plaid Service
// ===========================================

interface ExchangeTokenResult {
  accessToken: string;
  itemId: string;
  institutionName: string;
  accountName: string;
  accountMask: string;
}

class PlaidService {
  /**
   * Create a Link token for Plaid Link initialization
   */
  async createLinkToken(userId: string): Promise<string> {
    try {
      const request: LinkTokenCreateRequest = {
        user: {
          client_user_id: userId,
        },
        client_name: 'Sloozly',
        products: [Products.Auth], // Auth for ACH account/routing numbers
        country_codes: [CountryCode.Us],
        language: 'en',
        // Webhook for real-time updates (MMF feature)
        // webhook: `${config.apiBaseUrl}/webhooks/plaid`,
      };

      const response = await plaidClient.linkTokenCreate(request);
      
      logger.debug(`Plaid Link token created for user: ${userId}`);
      
      return response.data.link_token;
    } catch (error) {
      logger.error('Plaid createLinkToken error:', error);
      throw new ExternalServiceError('Plaid', 'Failed to create link token');
    }
  }

  /**
   * Exchange public token for access token and get account details
   */
  async exchangePublicToken(
    publicToken: string, 
    accountId: string
  ): Promise<ExchangeTokenResult> {
    try {
      // Exchange public token for access token
      const exchangeResponse = await plaidClient.itemPublicTokenExchange({
        public_token: publicToken,
      });

      const accessToken = exchangeResponse.data.access_token;
      const itemId = exchangeResponse.data.item_id;

      // Get account details
      const accountsResponse = await plaidClient.accountsGet({
        access_token: accessToken,
      });

      const account = accountsResponse.data.accounts.find(
        (acc) => acc.account_id === accountId
      );

      if (!account) {
        throw new Error('Selected account not found');
      }

      // Get institution details
      const item = await plaidClient.itemGet({
        access_token: accessToken,
      });

      let institutionName = 'Unknown Bank';
      if (item.data.item.institution_id) {
        try {
          const institutionResponse = await plaidClient.institutionsGetById({
            institution_id: item.data.item.institution_id,
            country_codes: [CountryCode.Us],
          });
          institutionName = institutionResponse.data.institution.name;
        } catch {
          // Use default if institution lookup fails
          logger.warn('Failed to get institution name');
        }
      }

      logger.info(`Plaid token exchanged for item: ${itemId}`);

      return {
        accessToken,
        itemId,
        institutionName,
        accountName: account.name,
        accountMask: account.mask || '****',
      };
    } catch (error) {
      logger.error('Plaid exchangePublicToken error:', error);
      throw new ExternalServiceError('Plaid', 'Failed to link bank account');
    }
  }

  /**
   * Get Auth data (account and routing numbers) for ACH transfers
   */
  async getAuthData(accessToken: string, accountId: string): Promise<{
    accountNumber: string;
    routingNumber: string;
  }> {
    try {
      const response = await plaidClient.authGet({
        access_token: accessToken,
      });

      const numbers = response.data.numbers.ach.find(
        (n) => n.account_id === accountId
      );

      if (!numbers) {
        throw new Error('ACH numbers not found for account');
      }

      return {
        accountNumber: numbers.account,
        routingNumber: numbers.routing,
      };
    } catch (error) {
      logger.error('Plaid getAuthData error:', error);
      throw new ExternalServiceError('Plaid', 'Failed to get bank account details');
    }
  }

  /**
   * Remove a Plaid item (when user unlinks bank account)
   */
  async removeItem(accessToken: string): Promise<void> {
    try {
      await plaidClient.itemRemove({
        access_token: accessToken,
      });
      logger.info('Plaid item removed');
    } catch (error) {
      logger.error('Plaid removeItem error:', error);
      // Don't throw - this is best-effort cleanup
    }
  }

  /**
   * Create a Stripe bank account token from Plaid
   * This allows us to use Plaid-linked accounts with Stripe for ACH
   */
  async createStripeBankAccountToken(
    accessToken: string,
    accountId: string
  ): Promise<string> {
    try {
      const response = await plaidClient.processorStripeBankAccountTokenCreate({
        access_token: accessToken,
        account_id: accountId,
      });

      return response.data.stripe_bank_account_token;
    } catch (error) {
      logger.error('Plaid createStripeBankAccountToken error:', error);
      throw new ExternalServiceError('Plaid', 'Failed to create Stripe bank token');
    }
  }
}

export const plaidService = new PlaidService();
