@IsTest
private class SharePointServiceTest {

    // ─── Mock HTTP Responses ─────────────────────────────────────────────────────

    private class FileListMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"value":['
                + '{"id":"file1","name":"contract_2024.pdf","webUrl":"https://sp.example.com/contract_2024.pdf",'
                + '"lastModifiedDateTime":"2024-06-01T10:00:00Z","size":102400,'
                + '"file":{"mimeType":"application/pdf"}},'
                + '{"id":"folder1","name":"Archive","webUrl":"https://sp.example.com/Archive"}'
                + ']}');
            return res;
        }
    }

    private class DownloadFileMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBodyAsBlob(Blob.valueOf('PDF_CONTENT_BYTES'));
            return res;
        }
    }

    private class ErrorMock implements HttpCalloutMock {
        private Integer statusCode;
        ErrorMock(Integer code) { this.statusCode = code; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody('{"error":{"code":"AccessDenied","message":"Access denied"}}');
            return res;
        }
    }

    // ─── Tests ───────────────────────────────────────────────────────────────────

    @IsTest
    static void listFiles_returnsOnlyFiles() {
        Test.setMock(HttpCalloutMock.class, new FileListMock());

        Test.startTest();
        List<SharePointService.SharePointFile> files =
            SharePointService.listFiles('drive123', 'root');
        Test.stopTest();

        // Folder item should be filtered out
        System.assertEquals(1, files.size(), 'Expected 1 file (folder should be excluded)');
        System.assertEquals('file1', files[0].id);
        System.assertEquals('contract_2024.pdf', files[0].name);
        System.assertEquals(102400L, files[0].size);
        System.assertNotEquals(null, files[0].lastModifiedDateTime);
    }

    @IsTest
    static void listFiles_throwsOnApiError() {
        Test.setMock(HttpCalloutMock.class, new ErrorMock(403));

        Test.startTest();
        Boolean exThrown = false;
        try {
            SharePointService.listFiles('drive123', 'folder456');
        } catch (SharePointService.SharePointServiceException e) {
            exThrown = true;
            System.assert(e.getMessage().contains('403'));
        }
        Test.stopTest();

        System.assert(exThrown, 'Expected SharePointServiceException on 403');
    }

    @IsTest
    static void downloadFileAsBase64_returnsBase64() {
        Test.setMock(HttpCalloutMock.class, new DownloadFileMock());

        Test.startTest();
        String b64 = SharePointService.downloadFileAsBase64('drive123', 'file1');
        Test.stopTest();

        System.assertNotEquals(null, b64, 'Base64 content should not be null');
        System.assert(b64.length() > 0, 'Base64 content should not be empty');
    }

    @IsTest
    static void parseFileList_handlesEmptyValues() {
        String json = '{"value":[]}';
        List<SharePointService.SharePointFile> files = SharePointService.parseFileList(json);
        System.assertEquals(0, files.size());
    }
}
