/**
 * Queueable that processes an uploaded contract file: reads the ContentVersion body,
 * runs AI extraction, creates a Contract_Document__c record, and links the file to it.
 */
public class ContractProcessingQueueable implements Queueable, Database.AllowsCallouts {

    private Id contentVersionId;

    public ContractProcessingQueueable(Id contentVersionId) {
        this.contentVersionId = contentVersionId;
    }

    public void execute(QueueableContext ctx) {
        List<ContentVersion> cvs = [
            SELECT Id, Title, FileExtension, VersionData, ContentDocumentId
            FROM   ContentVersion
            WHERE  Id = :contentVersionId
            LIMIT  1
        ];
        if (cvs.isEmpty()) return;

        try {
            processFile(cvs[0]);
        } catch (Exception e) {
            System.debug('Contract processing error: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }
    }

    // ─── Private Helpers ─────────────────────────────────────────────────────────

    private void processFile(ContentVersion cv) {
        String fileName    = cv.Title + (String.isNotBlank(cv.FileExtension) ? '.' + cv.FileExtension : '');
        String base64Data  = EncodingUtil.base64Encode(cv.VersionData);

        // Extract contract terms via Claude AI
        ContractExtractionService.ContractData data =
            ContractExtractionService.extractFromBase64(fileName, base64Data);

        // Build the Contract_Document__c record
        Contract_Document__c doc = new Contract_Document__c(
            Name                 = cv.Title,
            Extraction_Status__c = (data.extractionSuccessful == true) ? 'Completed' : 'Failed',
            Status__c            = 'Pending Review'
        );

        if (data.extractionSuccessful == true) {
            doc.Vendor_Name__c                  = data.vendorName;
            doc.Total_Amount__c                 = data.totalAmount;
            doc.Currency_Code__c                = data.currencyCode;
            doc.Contract_Start_Date__c          = data.startDate;
            doc.Contract_End_Date__c            = data.endDate;
            doc.Auto_Renew__c                   = data.autoRenew != null ? data.autoRenew : false;
            doc.Renewal_Period__c               = data.renewalPeriod;
            doc.Renewal_Notice_Period__c        = data.renewalNoticePeriod;
            doc.Cancellation_Notice_Due_Date__c = data.cancellationNoticeDueDate;
            doc.Cancellation_Terms__c           = data.cancellationTerms;
            doc.Contract_Type__c                = data.contractType;
            doc.Description__c                  = data.description;
            doc.Status__c                       = 'Active';
        }

        insert doc;

        // Link the uploaded file to the new contract record
        ContentDocumentLink link = new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId    = doc.Id,
            ShareType         = 'V',
            Visibility        = 'AllUsers'
        );
        insert link;
    }

    public class ContractProcessingException extends Exception {}
}
