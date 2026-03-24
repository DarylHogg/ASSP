@IsTest
private class ContractExtractionServiceTest {

    // ─── Mock HTTP Responses ─────────────────────────────────────────────────────

    private class SuccessfulExtractionMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            String responseJson = '{'
                + '"id":"msg_01","type":"message","role":"assistant",'
                + '"content":[{"type":"text","text":"{'
                + '\\\"vendor_name\\\":\\\"Acme Corp\\\",'
                + '\\\"total_amount\\\":50000,'
                + '\\\"currency_code\\\":\\\"USD\\\",'
                + '\\\"start_date\\\":\\\"2024-01-01\\\",'
                + '\\\"end_date\\\":\\\"2025-12-31\\\",'
                + '\\\"auto_renew\\\":true,'
                + '\\\"renewal_period\\\":\\\"1 year\\\",'
                + '\\\"renewal_notice_period\\\":\\\"60 days\\\",'
                + '\\\"cancellation_notice_due_date\\\":\\\"2025-11-01\\\",'
                + '\\\"cancellation_terms\\\":\\\"30 days written notice required\\\",'
                + '\\\"contract_type\\\":\\\"SaaS / Software\\\",'
                + '\\\"description\\\":\\\"Annual SaaS subscription for CRM software\\\"'
                + '}"}],'
                + '"model":"claude-opus-4-6","stop_reason":"end_turn",'
                + '"usage":{"input_tokens":1000,"output_tokens":200}'
                + '}';

            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(responseJson);
            return res;
        }
    }

    private class PartialExtractionMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            String responseJson = '{'
                + '"id":"msg_02","type":"message","role":"assistant",'
                + '"content":[{"type":"text","text":"{'
                + '\\\"vendor_name\\\":\\\"Beta LLC\\\",'
                + '\\\"total_amount\\\":null,'
                + '\\\"currency_code\\\":null,'
                + '\\\"start_date\\\":null,'
                + '\\\"end_date\\\":\\\"2026-06-30\\\",'
                + '\\\"auto_renew\\\":false,'
                + '\\\"renewal_period\\\":null,'
                + '\\\"renewal_notice_period\\\":null,'
                + '\\\"cancellation_notice_due_date\\\":null,'
                + '\\\"cancellation_terms\\\":null,'
                + '\\\"contract_type\\\":\\\"Service Agreement\\\",'
                + '\\\"description\\\":\\\"Consulting services agreement\\\"'
                + '}"}],'
                + '"model":"claude-opus-4-6","stop_reason":"end_turn",'
                + '"usage":{"input_tokens":500,"output_tokens":100}'
                + '}';

            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(responseJson);
            return res;
        }
    }

    private class ApiErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(429);
            res.setBody('{"type":"error","error":{"type":"rate_limit_error","message":"Rate limit exceeded"}}');
            return res;
        }
    }

    // ─── Tests ───────────────────────────────────────────────────────────────────

    @IsTest
    static void extractFromBase64_successfulExtraction() {
        Test.setMock(HttpCalloutMock.class, new SuccessfulExtractionMock());
        String fakeBase64 = EncodingUtil.base64Encode(Blob.valueOf('fake pdf content'));

        Test.startTest();
        ContractExtractionService.ContractData data =
            ContractExtractionService.extractFromBase64('contract.pdf', fakeBase64);
        Test.stopTest();

        System.assertEquals(true, data.extractionSuccessful);
        System.assertEquals('Acme Corp', data.vendorName);
        System.assertEquals(50000, data.totalAmount);
        System.assertEquals('USD', data.currencyCode);
        System.assertEquals(Date.newInstance(2024, 1, 1), data.startDate);
        System.assertEquals(Date.newInstance(2025, 12, 31), data.endDate);
        System.assertEquals(true, data.autoRenew);
        System.assertEquals('1 year', data.renewalPeriod);
        System.assertEquals('60 days', data.renewalNoticePeriod);
        System.assertEquals(Date.newInstance(2025, 11, 1), data.cancellationNoticeDueDate);
        System.assertEquals('SaaS / Software', data.contractType);
        System.assertNotEquals(null, data.description);
    }

    @IsTest
    static void extractFromBase64_partialDataHandled() {
        Test.setMock(HttpCalloutMock.class, new PartialExtractionMock());
        String fakeBase64 = EncodingUtil.base64Encode(Blob.valueOf('fake docx content'));

        Test.startTest();
        ContractExtractionService.ContractData data =
            ContractExtractionService.extractFromBase64('contract.docx', fakeBase64);
        Test.stopTest();

        System.assertEquals(true, data.extractionSuccessful);
        System.assertEquals('Beta LLC', data.vendorName);
        System.assertEquals(null, data.totalAmount, 'Null amount should be handled gracefully');
        System.assertEquals(false, data.autoRenew);
        System.assertEquals(Date.newInstance(2026, 6, 30), data.endDate);
    }

    @IsTest
    static void extractFromBase64_throwsOnApiError() {
        Test.setMock(HttpCalloutMock.class, new ApiErrorMock());
        String fakeBase64 = EncodingUtil.base64Encode(Blob.valueOf('content'));

        Test.startTest();
        Boolean exThrown = false;
        try {
            ContractExtractionService.extractFromBase64('doc.pdf', fakeBase64);
        } catch (ContractExtractionService.ContractExtractionException e) {
            exThrown = true;
            System.assert(e.getMessage().contains('429'));
        }
        Test.stopTest();

        System.assert(exThrown, 'Expected ContractExtractionException on 429 response');
    }

    @IsTest
    static void buildExtractionPrompt_containsRequiredKeys() {
        String prompt = ContractExtractionService.buildExtractionPrompt();
        System.assert(prompt.contains('vendor_name'));
        System.assert(prompt.contains('total_amount'));
        System.assert(prompt.contains('start_date'));
        System.assert(prompt.contains('end_date'));
        System.assert(prompt.contains('cancellation'));
        System.assert(prompt.contains('renewal_period'));
    }
}
