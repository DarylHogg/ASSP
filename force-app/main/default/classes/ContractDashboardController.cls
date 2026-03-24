/**
 * Apex controller for the contractDashboard LWC component.
 * All methods are @AuraEnabled and use with sharing to enforce record-level security.
 */
public with sharing class ContractDashboardController {

    // ─── Dashboard Summary ───────────────────────────────────────────────────────

    /**
     * Returns high-level counts for the dashboard summary tiles.
     */
    @AuraEnabled(cacheable=true)
    public static DashboardSummary getDashboardSummary() {
        DashboardSummary summary = new DashboardSummary();

        summary.totalContracts = [
            SELECT COUNT() FROM Contract_Document__c
            WHERE Status__c NOT IN ('Cancelled')
        ];

        summary.activeContracts = [
            SELECT COUNT() FROM Contract_Document__c
            WHERE Status__c = 'Active'
        ];

        summary.expiringSoon = [
            SELECT COUNT() FROM Contract_Document__c
            WHERE Is_Expiring_Soon__c = true
            AND   Status__c = 'Active'
        ];

        summary.cancellationDeadlineSoon = [
            SELECT COUNT() FROM Contract_Document__c
            WHERE Cancellation_Deadline_Alert__c = true
            AND   Status__c = 'Active'
        ];

        summary.pendingReview = [
            SELECT COUNT() FROM Contract_Document__c
            WHERE Status__c = 'Pending Review'
        ];

        summary.syncScheduled = ContractSyncScheduler.isScheduled();

        return summary;
    }

    // ─── Contract List ───────────────────────────────────────────────────────────

    /**
     * Returns a filtered and paginated list of contracts.
     *
     * @param statusFilter     'All', 'Active', 'Expiring Soon', 'Pending Review', etc.
     * @param searchTerm       Text to match against Name or Vendor_Name__c.
     * @param pageSize         Number of records per page.
     * @param pageNumber       1-based page number.
     */
    @AuraEnabled(cacheable=true)
    public static ContractPage getContracts(
        String  statusFilter,
        String  searchTerm,
        Integer pageSize,
        Integer pageNumber
    ) {
        Integer safePageSize   = (pageSize   != null && pageSize   > 0) ? Math.min(pageSize, 200)   : 20;
        Integer safePageNumber = (pageNumber != null && pageNumber > 0) ? pageNumber : 1;
        Integer offset         = (safePageNumber - 1) * safePageSize;

        String whereClause = buildWhereClause(statusFilter, searchTerm);

        String countQuery = 'SELECT COUNT() FROM Contract_Document__c' + whereClause;
        Integer totalRecords = Database.countQuery(countQuery);

        String dataQuery = 'SELECT Id, Name, Vendor_Name__c, Contract_Type__c, Status__c, '
                         + 'Total_Amount__c, Currency_Code__c, Contract_Start_Date__c, '
                         + 'Contract_End_Date__c, Auto_Renew__c, Renewal_Period__c, '
                         + 'Cancellation_Notice_Due_Date__c, Is_Expiring_Soon__c, '
                         + 'Cancellation_Deadline_Alert__c, Days_Until_Expiry__c, '
                         + 'Days_Until_Cancellation_Deadline__c, Extraction_Status__c, '
                         + 'SharePoint_URL__c, CreatedDate '
                         + 'FROM Contract_Document__c'
                         + whereClause
                         + ' ORDER BY Contract_End_Date__c ASC NULLS LAST'
                         + ' LIMIT :safePageSize OFFSET :offset';

        List<Contract_Document__c> records = Database.query(dataQuery);

        ContractPage page = new ContractPage();
        page.contracts    = records;
        page.totalRecords = totalRecords;
        page.pageSize     = safePageSize;
        page.pageNumber   = safePageNumber;
        page.totalPages   = (Integer) Math.ceil((Double) totalRecords / safePageSize);

        return page;
    }

    /**
     * Triggers an immediate (manual) SharePoint sync. Not cacheable.
     */
    @AuraEnabled
    public static String triggerSync() {
        try {
            ContractSyncScheduler.triggerImmediateSync();
            return 'Sync started successfully. New contracts will appear within a few minutes.';
        } catch (Exception e) {
            throw new AuraHandledException('Failed to trigger sync: ' + e.getMessage());
        }
    }

    /**
     * Schedules the hourly sync job. Not cacheable.
     */
    @AuraEnabled
    public static String scheduleSyncJob(String cronExpression) {
        try {
            String jobId = ContractSyncScheduler.scheduleDefault(cronExpression);
            return 'Sync job scheduled. Job ID: ' + jobId;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to schedule sync: ' + e.getMessage());
        }
    }

    // ─── Private Helpers ─────────────────────────────────────────────────────────

    private static String buildWhereClause(String statusFilter, String searchTerm) {
        List<String> conditions = new List<String>();

        if (String.isNotBlank(statusFilter) && statusFilter != 'All') {
            if (statusFilter == 'Expiring Soon') {
                conditions.add('Is_Expiring_Soon__c = true AND Status__c = \'Active\'');
            } else if (statusFilter == 'Cancellation Alert') {
                conditions.add('Cancellation_Deadline_Alert__c = true AND Status__c = \'Active\'');
            } else {
                conditions.add('Status__c = \'' + String.escapeSingleQuotes(statusFilter) + '\'');
            }
        }

        if (String.isNotBlank(searchTerm)) {
            String escaped = String.escapeSingleQuotes(searchTerm.trim());
            conditions.add(
                '(Name LIKE \'%' + escaped + '%\' OR Vendor_Name__c LIKE \'%' + escaped + '%\')'
            );
        }

        return conditions.isEmpty() ? '' : ' WHERE ' + String.join(conditions, ' AND ');
    }

    // ─── Inner Types ────────────────────────────────────────────────────────────

    public class DashboardSummary {
        @AuraEnabled public Integer totalContracts            { get; set; }
        @AuraEnabled public Integer activeContracts           { get; set; }
        @AuraEnabled public Integer expiringSoon              { get; set; }
        @AuraEnabled public Integer cancellationDeadlineSoon  { get; set; }
        @AuraEnabled public Integer pendingReview             { get; set; }
        @AuraEnabled public Boolean syncScheduled             { get; set; }
    }

    public class ContractPage {
        @AuraEnabled public List<Contract_Document__c> contracts    { get; set; }
        @AuraEnabled public Integer                    totalRecords { get; set; }
        @AuraEnabled public Integer                    pageSize     { get; set; }
        @AuraEnabled public Integer                    pageNumber   { get; set; }
        @AuraEnabled public Integer                    totalPages   { get; set; }
    }
}
