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
        String fileName   = cv.Title + (String.isNotBlank(cv.FileExtension) ? '.' + cv.FileExtension : '');
        String base64Data = EncodingUtil.base64Encode(cv.VersionData);

        ContractExtractionService.ContractData d;
        try {
            d = ContractExtractionService.extractFromBase64(fileName, base64Data);
        } catch (Exception e) {
            d = new ContractExtractionService.ContractData();
            d.extractionSuccessful = false;
            d.extractionError = e.getMessage();
            System.debug('AI extraction failed for ' + fileName + ': ' + e.getMessage());
        }

        Contract_Document__c doc = new Contract_Document__c(
            Name                 = cv.Title,
            Extraction_Status__c = (d.extractionSuccessful == true) ? 'Completed' : 'Failed',
            Status__c            = 'Pending Review'
        );

        if (d.extractionSuccessful == true) {
            // Identity
            doc.Vendor_Name__c           = d.vendorName;
            doc.Contract_Type__c         = d.contractType;
            doc.Vendor_Contact_Name__c   = d.vendorContactName;
            doc.Vendor_Contact_Email__c  = d.vendorContactEmail;
            doc.Vendor_Contact_Phone__c  = d.vendorContactPhone;
            doc.Internal_Owner__c        = d.internalOwner;
            // Dates
            doc.Contract_Start_Date__c          = d.startDate;
            doc.Contract_End_Date__c            = d.endDate;
            doc.Auto_Renewal_Date__c            = d.autoRenewalDate;
            doc.Auto_Renew__c                   = d.autoRenew != null ? d.autoRenew : false;
            doc.Renewal_Period__c               = d.renewalPeriod;
            doc.Renewal_Notice_Period__c        = d.renewalNoticePeriod;
            doc.Cancellation_Notice_Due_Date__c = d.cancellationNoticeDueDate;
            doc.Cancellation_Terms__c           = d.cancellationTerms;
            // Financial
            doc.Total_Amount__c        = d.totalAmount;
            doc.Currency_Code__c       = d.currencyCode;
            doc.Payment_Terms__c       = d.paymentTerms;
            doc.Billing_Frequency__c   = d.billingFrequency;
            doc.Rate_Card__c           = d.rateCard;
            // Scope & Obligations
            doc.Services_Summary__c    = d.servicesSummary;
            doc.SLA_Terms__c           = d.slaTerms;
            doc.Liability_Cap__c       = d.liabilityCap;
            doc.Indemnification__c     = d.indemnification;
            // Risk & Compliance
            doc.Governing_Law__c         = d.governingLaw;
            doc.Data_Privacy_Clauses__c  = d.dataPrivacyClauses;
            doc.Non_Compete_Scope__c     = d.nonCompeteScope;
            doc.IP_Ownership__c          = d.ipOwnership;
            // Execution & Notes
            doc.Signed_Date__c       = d.signedDate;
            doc.Signatories__c       = d.signatories;
            doc.Renewal_Decision__c  = d.renewalDecision;
            doc.Risk_Notes__c        = d.riskNotes;
            doc.Description__c       = d.description;
            doc.Status__c            = 'Active';
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
