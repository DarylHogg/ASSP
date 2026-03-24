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
    private static final Integer MAX_TOKENS      = 4096;
    private static final Integer CALLOUT_TIMEOUT = 120000; // 2 minutes

    // ─── Inner Types ────────────────────────────────────────────────────────────

    public class ContractData {
        // Identity
        public String  vendorName;
        public String  contractType;
        public String  vendorContactName;
        public String  vendorContactEmail;
        public String  vendorContactPhone;
        public String  internalOwner;
        // Dates & Duration
        public Date    startDate;
        public Date    endDate;
        public Date    autoRenewalDate;
        public Boolean autoRenew;
        public String  renewalPeriod;
        public String  renewalNoticePeriod;
        public Date    cancellationNoticeDueDate;
        public String  cancellationTerms;
        // Financial
        public Decimal totalAmount;
        public String  currencyCode;
        public String  paymentTerms;
        public String  billingFrequency;
        public String  rateCard;
        // Scope & Obligations
        public String  servicesSummary;
        public String  slaTerms;
        public Decimal liabilityCap;
        public String  indemnification;
        // Risk & Compliance
        public String  governingLaw;
        public String  dataPrivacyClauses;
        public String  nonCompeteScope;
        public String  ipOwnership;
        // Execution & Notes
        public Date    signedDate;
        public String  signatories;
        public String  renewalDecision;
        public String  riskNotes;
        public String  description;
        // Meta
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

        blocks.add(new Map<String, Object>{
            'type'   => 'document',
            'source' => new Map<String, Object>{
                'type'       => 'base64',
                'media_type' => mediaType,
                'data'       => base64Content
            }
        });

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
             + 'Use null for any field you cannot confidently determine. '
             + 'All dates must be in YYYY-MM-DD format.\n\n'
             + 'Required JSON structure:\n'
             + '{\n'
             + '  "vendor_name": "string — supplier/vendor/counterparty name",\n'
             + '  "contract_type": "string — e.g. MSA, SOW, NDA, SaaS / Software, Service Agreement, License, Consulting, Subscription, Other",\n'
             + '  "vendor_contact_name": "string — vendor contact person full name",\n'
             + '  "vendor_contact_email": "string — vendor contact email address",\n'
             + '  "vendor_contact_phone": "string — vendor contact phone number",\n'
             + '  "internal_owner": "string — internal owner or contract manager name",\n'
             + '  "start_date": "YYYY-MM-DD — effective or start date",\n'
             + '  "end_date": "YYYY-MM-DD — expiration or end date",\n'
             + '  "auto_renewal_date": "YYYY-MM-DD — date contract will auto-renew if no action is taken",\n'
             + '  "auto_renew": true|false,\n'
             + '  "renewal_period": "string — auto-renewal term length, e.g. 1 year, 6 months",\n'
             + '  "renewal_notice_period": "string — notice period required to cancel, e.g. 30 days, 60 days",\n'
             + '  "cancellation_notice_due_date": "YYYY-MM-DD — last date to give cancellation notice",\n'
             + '  "cancellation_terms": "string — summary of cancellation conditions",\n'
             + '  "total_amount": number — total contract value (digits only, no symbols),\n'
             + '  "currency_code": "string — ISO 4217 code e.g. USD, EUR, GBP",\n'
             + '  "payment_terms": "string — e.g. Net 30, Net 60, upfront, monthly invoicing",\n'
             + '  "billing_frequency": "string — Monthly, Quarterly, Semi-Annual, Annual, One-time, Milestone-based, or Other",\n'
             + '  "rate_card": "string — hourly rates or rate schedule details",\n'
             + '  "services_summary": "string — summary of services, deliverables, or scope of work",\n'
             + '  "sla_terms": "string — SLA commitments and performance metrics",\n'
             + '  "liability_cap": number — limitation of liability cap amount (digits only),\n'
             + '  "indemnification": "string — indemnification obligations summary",\n'
             + '  "governing_law": "string — governing law and jurisdiction, e.g. State of California, USA",\n'
             + '  "data_privacy_clauses": "string — data privacy and security obligations summary",\n'
             + '  "non_compete_scope": "string — non-compete and non-solicitation scope and duration",\n'
             + '  "ip_ownership": "string — IP ownership and licensing terms",\n'
             + '  "signed_date": "YYYY-MM-DD — date the contract was fully executed/signed",\n'
             + '  "signatories": "string — names and titles of all signatories",\n'
             + '  "renewal_decision": "string — Renew, Renegotiate, Terminate, or TBD",\n'
             + '  "risk_notes": "string — notable risks, flags, unusual clauses, or concerns",\n'
             + '  "description": "string — 1-2 sentence executive summary of what this contract covers"\n'
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

        // Identity
        d.vendorName          = (String) m.get('vendor_name');
        d.contractType        = (String) m.get('contract_type');
        d.vendorContactName   = (String) m.get('vendor_contact_name');
        d.vendorContactEmail  = (String) m.get('vendor_contact_email');
        d.vendorContactPhone  = (String) m.get('vendor_contact_phone');
        d.internalOwner       = (String) m.get('internal_owner');

        // Dates
        d.startDate                = parseDateSafe((String) m.get('start_date'));
        d.endDate                  = parseDateSafe((String) m.get('end_date'));
        d.autoRenewalDate          = parseDateSafe((String) m.get('auto_renewal_date'));
        d.cancellationNoticeDueDate = parseDateSafe((String) m.get('cancellation_notice_due_date'));
        d.signedDate               = parseDateSafe((String) m.get('signed_date'));

        Object autoRenewObj = m.get('auto_renew');
        if (autoRenewObj != null) {
            d.autoRenew = Boolean.valueOf(String.valueOf(autoRenewObj));
        }

        d.renewalPeriod       = (String) m.get('renewal_period');
        d.renewalNoticePeriod = (String) m.get('renewal_notice_period');
        d.cancellationTerms   = (String) m.get('cancellation_terms');

        // Financial
        Object amtObj = m.get('total_amount');
        if (amtObj != null) {
            try { d.totalAmount = Decimal.valueOf(String.valueOf(amtObj)); } catch (Exception e) {}
        }
        Object liabilityObj = m.get('liability_cap');
        if (liabilityObj != null) {
            try { d.liabilityCap = Decimal.valueOf(String.valueOf(liabilityObj)); } catch (Exception e) {}
        }

        d.currencyCode    = (String) m.get('currency_code');
        d.paymentTerms    = (String) m.get('payment_terms');
        d.billingFrequency = (String) m.get('billing_frequency');
        d.rateCard        = (String) m.get('rate_card');

        // Scope & Obligations
        d.servicesSummary  = (String) m.get('services_summary');
        d.slaTerms         = (String) m.get('sla_terms');
        d.indemnification  = (String) m.get('indemnification');

        // Risk & Compliance
        d.governingLaw       = (String) m.get('governing_law');
        d.dataPrivacyClauses = (String) m.get('data_privacy_clauses');
        d.nonCompeteScope    = (String) m.get('non_compete_scope');
        d.ipOwnership        = (String) m.get('ip_ownership');

        // Execution & Notes
        d.signatories     = (String) m.get('signatories');
        d.renewalDecision = (String) m.get('renewal_decision');
        d.riskNotes       = (String) m.get('risk_notes');
        d.description     = (String) m.get('description');

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
