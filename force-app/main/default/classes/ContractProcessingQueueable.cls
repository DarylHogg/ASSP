/**
 * Queueable that processes a single SharePoint file: downloads the content,
 * runs AI extraction, and creates a Contract_Document__c record.
 *
 * Each instance handles one file. After completion it chains the next pending
 * file automatically, allowing the scheduler to enqueue just the first item.
 */
public class ContractProcessingQueueable implements Queueable, Database.AllowsCallouts {

    private Id trackingId;

    public ContractProcessingQueueable(Id trackingId) {
        this.trackingId = trackingId;
    }

    public void execute(QueueableContext ctx) {
        SharePoint_File_Tracking__c tracking = queryTracking(trackingId);
        if (tracking == null) return;

        // Mark as Processing
        tracking.Status__c = 'Processing';
        update tracking;

        try {
            processFile(tracking);
        } catch (Exception e) {
            markError(tracking, e.getMessage() + '\n' + e.getStackTraceString());
        }

        // Chain next pending file (if any)
        List<SharePoint_File_Tracking__c> next = [
            SELECT Id
            FROM   SharePoint_File_Tracking__c
            WHERE  Status__c = 'Pending'
            ORDER BY CreatedDate ASC
            LIMIT  1
        ];
        if (!next.isEmpty()) {
            System.enqueueJob(new ContractProcessingQueueable(next[0].Id));
        }
    }

    // ─── Private Helpers ─────────────────────────────────────────────────────────

    private void processFile(SharePoint_File_Tracking__c tracking) {
        // 1. Download file from SharePoint
        String base64Content = SharePointService.downloadFileAsBase64(
            tracking.Drive_Id__c,
            tracking.SharePoint_Item_Id__c
        );

        // 2. Extract contract data via Claude API
        ContractExtractionService.ContractData contractData =
            ContractExtractionService.extractFromBase64(tracking.File_Name__c, base64Content);

        // 3. Determine extraction status
        String extractionStatus = (contractData.extractionSuccessful == true)
            ? 'Completed'
            : 'Failed';

        // 4. Upsert Contract_Document__c using SharePoint file ID as external key
        Contract_Document__c doc = new Contract_Document__c(
            Name                          = stripExtension(tracking.File_Name__c),
            SharePoint_File_Id__c         = tracking.SharePoint_Item_Id__c,
            SharePoint_URL__c             = tracking.SharePoint_URL__c,
            Extraction_Status__c          = extractionStatus,
            Status__c                     = 'Pending Review'
        );

        if (contractData.extractionSuccessful == true) {
            doc.Vendor_Name__c                 = contractData.vendorName;
            doc.Total_Amount__c                = contractData.totalAmount;
            doc.Currency_Code__c               = contractData.currencyCode;
            doc.Contract_Start_Date__c         = contractData.startDate;
            doc.Contract_End_Date__c           = contractData.endDate;
            doc.Auto_Renew__c                  = contractData.autoRenew != null ? contractData.autoRenew : false;
            doc.Renewal_Period__c              = contractData.renewalPeriod;
            doc.Renewal_Notice_Period__c       = contractData.renewalNoticePeriod;
            doc.Cancellation_Notice_Due_Date__c = contractData.cancellationNoticeDueDate;
            doc.Cancellation_Terms__c          = contractData.cancellationTerms;
            doc.Contract_Type__c               = contractData.contractType;
            doc.Description__c                 = contractData.description;
            doc.Status__c                      = 'Active';
        }

        Database.UpsertResult upsertResult = Database.upsert(doc, Contract_Document__c.SharePoint_File_Id__c, false);

        if (!upsertResult.isSuccess()) {
            List<String> errors = new List<String>();
            for (Database.Error err : upsertResult.getErrors()) {
                errors.add(err.getMessage());
            }
            throw new ContractProcessingException('Upsert failed: ' + String.join(errors, '; '));
        }

        // 5. Link tracking record to Contract_Document__c
        tracking.Status__c          = 'Processed';
        tracking.Contract_Document__c = upsertResult.getId();
        tracking.Processed_Date__c  = DateTime.now();
        if (contractData.extractionSuccessful != true) {
            tracking.Error_Message__c = contractData.extractionError;
        }
        update tracking;
    }

    private SharePoint_File_Tracking__c queryTracking(Id tid) {
        List<SharePoint_File_Tracking__c> records = [
            SELECT Id, SharePoint_Item_Id__c, File_Name__c, Drive_Id__c,
                   SharePoint_URL__c, Status__c
            FROM   SharePoint_File_Tracking__c
            WHERE  Id = :tid
            AND    Status__c IN ('Pending', 'Processing')
            LIMIT  1
        ];
        return records.isEmpty() ? null : records[0];
    }

    private void markError(SharePoint_File_Tracking__c tracking, String msg) {
        tracking.Status__c     = 'Error';
        tracking.Error_Message__c = msg.left(32000);
        update tracking;
    }

    private String stripExtension(String fileName) {
        if (String.isBlank(fileName)) return fileName;
        Integer dotIdx = fileName.lastIndexOf('.');
        return (dotIdx > 0) ? fileName.substring(0, dotIdx) : fileName;
    }

    public class ContractProcessingException extends Exception {}
}
