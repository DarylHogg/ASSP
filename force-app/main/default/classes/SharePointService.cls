/**
 * Service class for interacting with the Microsoft Graph API to list and
 * retrieve files from a SharePoint document library.
 *
 * Requires a Named Credential named "MicrosoftGraph" configured with OAuth 2.0
 * (client credentials flow) against https://graph.microsoft.com.
 */
public with sharing class SharePointService {

    private static final String NAMED_CREDENTIAL = 'callout:MicrosoftGraph';
    private static final String GRAPH_VERSION    = '/v1.0';

    // ─── Inner Types ────────────────────────────────────────────────────────────

    public class SharePointFile {
        public String   id;
        public String   name;
        public String   webUrl;
        public String   downloadUrl;
        public DateTime lastModifiedDateTime;
        public Long     size;
    }

    public class SharePointServiceException extends Exception {}

    // ─── Public Methods ──────────────────────────────────────────────────────────

    /**
     * Lists all files (not folders) in a given SharePoint folder.
     *
     * @param driveId      The drive (document library) ID.
     * @param folderId     The folder item ID, or 'root' for the drive root.
     * @return             List of SharePointFile wrappers.
     */
    public static List<SharePointFile> listFiles(String driveId, String folderId) {
        String itemPath = (folderId == 'root')
            ? '/drives/' + EncodingUtil.urlEncode(driveId, 'UTF-8') + '/root/children'
            : '/drives/' + EncodingUtil.urlEncode(driveId, 'UTF-8') + '/items/' + EncodingUtil.urlEncode(folderId, 'UTF-8') + '/children';

        String endpoint = NAMED_CREDENTIAL + GRAPH_VERSION + itemPath
            + '?$select=id,name,webUrl,lastModifiedDateTime,size,file'
            + '&$filter=file ne null'
            + '&$top=200';

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(30000);

        HttpResponse res = new Http().send(req);

        if (res.getStatusCode() != 200) {
            throw new SharePointServiceException(
                'Graph API error ' + res.getStatusCode() + ': ' + res.getBody()
            );
        }

        return parseFileList(res.getBody());
    }

    /**
     * Downloads a file from SharePoint as a base64-encoded string.
     * Uses the Graph API download redirect endpoint.
     *
     * @param driveId   The drive (document library) ID.
     * @param itemId    The file item ID.
     * @return          Base64-encoded file content.
     */
    public static String downloadFileAsBase64(String driveId, String itemId) {
        String endpoint = NAMED_CREDENTIAL + GRAPH_VERSION
            + '/drives/' + EncodingUtil.urlEncode(driveId, 'UTF-8')
            + '/items/' + EncodingUtil.urlEncode(itemId, 'UTF-8')
            + '/content';

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setTimeout(60000);

        HttpResponse res = new Http().send(req);

        // Graph API returns 302 redirect to download URL; Salesforce follows it automatically.
        // Successful download returns 200 with the file bytes.
        if (res.getStatusCode() != 200) {
            throw new SharePointServiceException(
                'File download error ' + res.getStatusCode() + ': ' + res.getBody()
            );
        }

        return EncodingUtil.base64Encode(res.getBodyAsBlob());
    }

    /**
     * Returns the web (browser-viewable) URL for a SharePoint item.
     *
     * @param driveId   The drive ID.
     * @param itemId    The item ID.
     * @return          Web URL string or null on error.
     */
    public static String getItemWebUrl(String driveId, String itemId) {
        String endpoint = NAMED_CREDENTIAL + GRAPH_VERSION
            + '/drives/' + EncodingUtil.urlEncode(driveId, 'UTF-8')
            + '/items/' + EncodingUtil.urlEncode(itemId, 'UTF-8')
            + '?$select=webUrl';

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(15000);

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) return null;

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        return (String) body.get('webUrl');
    }

    // ─── Private Helpers ─────────────────────────────────────────────────────────

    @TestVisible
    private static List<SharePointFile> parseFileList(String jsonBody) {
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(jsonBody);
        List<Object>        values = (List<Object>) parsed.get('value');
        List<SharePointFile> files = new List<SharePointFile>();

        if (values == null) return files;

        for (Object v : values) {
            Map<String, Object> item = (Map<String, Object>) v;

            // Only include items that have a 'file' facet
            if (!item.containsKey('file')) continue;

            SharePointFile f = new SharePointFile();
            f.id     = (String) item.get('id');
            f.name   = (String) item.get('name');
            f.webUrl = (String) item.get('webUrl');

            Object sizeObj = item.get('size');
            if (sizeObj != null) {
                f.size = Long.valueOf(String.valueOf(sizeObj));
            }

            String lastMod = (String) item.get('lastModifiedDateTime');
            if (String.isNotBlank(lastMod)) {
                // ISO 8601 → DateTime: "2024-01-15T10:30:00Z"
                f.lastModifiedDateTime = (DateTime) JSON.deserialize('"' + lastMod + '"', DateTime.class);
            }

            files.add(f);
        }

        return files;
    }
}
