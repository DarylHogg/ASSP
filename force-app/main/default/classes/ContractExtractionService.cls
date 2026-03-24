/**
 * Uses the Anthropic Claude API to extract key contract terms from a document
 * (PDF or Word) provided as base64-encoded content.
 *
 * Requires a Named Credential named "ClaudeAI" configured with:
 *   - Endpoint: https://api.anthropic.com
 *   - Custom auth headers: x-api-key (your Anthropic API key)
 *                          anthropic-version: 2023-06-01
 */
public with sharing class ContractExtractionService {

    private static final String NAMED_CREDENTIAL = 'callout:ClaudeAI';
    private static final String CLAUDE_MODEL     = 'claude-opus-4-6';
    private static final Integer MAX_TOKENS      = 2048;
    private static final Integer CALLOUT_TIMEOUT = 120000; // 2 minutes

    // ─── Inner Types ────────────────────────────────────────────────────────────

    public class ContractData {
        public String  vendorName;
        public Decimal totalAmount;
        public String  currencyCode;
        public Date    startDate;
        public Date    endDate;
        public String  renewalPeriod;
        public String  renewalNoticePeriod;
        public Date    cancellationNoticeDueDate;
        public String  cancellationTerms;
        public String  contractType;
        public Boolean autoRenew;
        public String  description;
        public Boolean extractionSuccessful;
        public String  extractionError;
    }

    public class ContractExtractionException extends Exception {}

    // ─── Public Methods ──────────────────────────────────────────────────────────

    /**
     * Extracts contract data from a base64-encoded document file.
     *
     * @param fileName      Original file name (used to determine MIME type).
     * @param base64Content Base64-encoded file content.
     * @return              Populated ContractData object.
     */
    public static ContractData extractFromBase64(String fileName, String base64Content) {
        String mediaType = resolveMediaType(fileName);

        // Build the Claude API request body
        Map<String, Object> requestBody = new Map<String, Object>{
            'model'      => CLAUDE_MODEL,
            'max_tokens' => MAX_TOKENS,
            'messages'   => new List<Object>{
                new Map<String, Object>{
                    'role'    => 'user',
                    'content' => buildContentBlocks(base64Content, mediaType)
                }
            }
        };

        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CREDENTIAL + '/v1/messages');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(CALLOUT_TIMEOUT);
        req.setBody(JSON.serialize(requestBody));

        HttpResponse res = new Http().send(req);

        if (res.getStatusCode() != 200) {
            throw new ContractExtractionException(
                'Claude API error ' + res.getStatusCode() + ': ' + res.getBody()
            );
        }

        return parseClaudeResponse(res.getBody());
    }

    // ─── Private Helpers ─────────────────────────────────────────────────────────

    private static List<Object> buildContentBlocks(String base64Content, String mediaType) {
        List<Object> blocks = new List<Object>();

        // Document block (PDF supported natively; DOCX sent as base64)
        blocks.add(new Map<String, Object>{
            'type'   => 'document',
            'source' => new Map<String, Object>{
                'type'       => 'base64',
                'media_type' => mediaType,
                'data'       => base64Content
            }
        });

        // Text instruction block
        blocks.add(new Map<String, Object>{
            'type' => 'text',
            'text' => buildExtractionPrompt()
        });

        return blocks;
    }

    @TestVisible
    private static String buildExtractionPrompt() {
        return 'You are a contract analysis expert. Extract the following information from '
             + 'the contract document above and return it as a single JSON object. '
             + 'Use null for any field you cannot confidently determine.\n\n'
             + 'Required JSON structure:\n'
             + '{\n'
             + '  "vendor_name": "string — the supplier/vendor/counterparty name",\n'
             + '  "total_amount": number — total contract value (digits only, no currency symbols),\n'
             + '  "currency_code": "string — ISO 4217 code e.g. USD, EUR, GBP",\n'
             + '  "start_date": "YYYY-MM-DD",\n'
             + '  "end_date": "YYYY-MM-DD",\n'
             + '  "auto_renew": true|false,\n'
             + '  "renewal_period": "string — e.g. 1 year, 6 months",\n'
             + '  "renewal_notice_period": "string — e.g. 30 days, 60 days",\n'
             + '  "cancellation_notice_due_date": "YYYY-MM-DD — last date to give notice to cancel",\n'
             + '  "cancellation_terms": "string — summary of cancellation conditions",\n'
             + '  "contract_type": "string — e.g. SaaS / Software, Service Agreement, License",\n'
             + '  "description": "string — 1-2 sentence summary of what this contract covers"\n'
             + '}\n\n'
             + 'Return ONLY the JSON object. No explanation, no markdown, no code fences.';
    }

    @TestVisible
    private static ContractData parseClaudeResponse(String responseBody) {
        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        List<Object>        content  = (List<Object>) response.get('content');

        if (content == null || content.isEmpty()) {
            ContractData failed = new ContractData();
            failed.extractionSuccessful = false;
            failed.extractionError = 'Empty response content from Claude API';
            return failed;
        }

        Map<String, Object> firstBlock = (Map<String, Object>) content[0];
        String rawText = ((String) firstBlock.get('text')).trim();

        // Strip any accidental code fence markers
        if (rawText.startsWith('```')) {
            rawText = rawText.replaceFirst('^```[a-z]*\\n?', '').replaceAll('```$', '').trim();
        }

        try {
            Map<String, Object> extracted = (Map<String, Object>) JSON.deserializeUntyped(rawText);
            return mapToContractData(extracted);
        } catch (Exception e) {
            ContractData failed = new ContractData();
            failed.extractionSuccessful = false;
            failed.extractionError = 'JSON parse error: ' + e.getMessage() + ' | Raw: ' + rawText.left(500);
            return failed;
        }
    }

    private static ContractData mapToContractData(Map<String, Object> m) {
        ContractData d = new ContractData();
        d.extractionSuccessful = true;

        d.vendorName           = (String)  m.get('vendor_name');
        d.currencyCode         = (String)  m.get('currency_code');
        d.renewalPeriod        = (String)  m.get('renewal_period');
        d.renewalNoticePeriod  = (String)  m.get('renewal_notice_period');
        d.cancellationTerms    = (String)  m.get('cancellation_terms');
        d.contractType         = (String)  m.get('contract_type');
        d.description          = (String)  m.get('description');

        Object amtObj = m.get('total_amount');
        if (amtObj != null) {
            try { d.totalAmount = Decimal.valueOf(String.valueOf(amtObj)); } catch (Exception e) {}
        }

        Object autoRenewObj = m.get('auto_renew');
        if (autoRenewObj != null) {
            d.autoRenew = Boolean.valueOf(String.valueOf(autoRenewObj));
        }

        d.startDate                = parseDateSafe((String) m.get('start_date'));
        d.endDate                  = parseDateSafe((String) m.get('end_date'));
        d.cancellationNoticeDueDate = parseDateSafe((String) m.get('cancellation_notice_due_date'));

        return d;
    }

    private static Date parseDateSafe(String dateStr) {
        if (String.isBlank(dateStr)) return null;
        try {
            return Date.valueOf(dateStr.trim());
        } catch (Exception e) {
            return null;
        }
    }

    private static String resolveMediaType(String fileName) {
        if (String.isBlank(fileName)) return 'application/pdf';
        String lower = fileName.toLowerCase();
        if (lower.endsWith('.pdf'))  return 'application/pdf';
        if (lower.endsWith('.docx')) return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
        if (lower.endsWith('.doc'))  return 'application/msword';
        if (lower.endsWith('.txt'))  return 'text/plain';
        return 'application/pdf';
    }
}
