@IsTest
private class ContractDashboardControllerTest {

    @TestSetup
    static void makeData() {
        List<Contract_Document__c> contracts = new List<Contract_Document__c>();

        // Active contract expiring soon
        contracts.add(new Contract_Document__c(
            Name                           = 'Acme SaaS License',
            Vendor_Name__c                 = 'Acme Corp',
            Contract_Type__c               = 'SaaS / Software',
            Status__c                      = 'Active',
            Total_Amount__c                = 12000,
            Contract_Start_Date__c         = Date.today().addDays(-180),
            Contract_End_Date__c           = Date.today().addDays(30),
            Auto_Renew__c                  = true,
            Renewal_Period__c              = '1 year',
            Cancellation_Notice_Due_Date__c = Date.today().addDays(10),
            Extraction_Status__c           = 'Completed'
        ));

        // Active contract with a long runway
        contracts.add(new Contract_Document__c(
            Name                   = 'Beta Services Agreement',
            Vendor_Name__c         = 'Beta LLC',
            Contract_Type__c       = 'Service Agreement',
            Status__c              = 'Active',
            Total_Amount__c        = 75000,
            Contract_Start_Date__c = Date.today().addDays(-30),
            Contract_End_Date__c   = Date.today().addDays(365),
            Auto_Renew__c          = false,
            Extraction_Status__c   = 'Completed'
        ));

        // Pending Review contract
        contracts.add(new Contract_Document__c(
            Name                   = 'Gamma Consulting',
            Vendor_Name__c         = 'Gamma Inc',
            Status__c              = 'Pending Review',
            Extraction_Status__c   = 'Completed'
        ));

        // Expired contract
        contracts.add(new Contract_Document__c(
            Name                   = 'Old Lease',
            Vendor_Name__c         = 'Delta Corp',
            Status__c              = 'Expired',
            Contract_End_Date__c   = Date.today().addDays(-30),
            Extraction_Status__c   = 'Completed'
        ));

        insert contracts;
    }

    @IsTest
    static void getDashboardSummary_returnsCounts() {
        Test.startTest();
        ContractDashboardController.DashboardSummary summary =
            ContractDashboardController.getDashboardSummary();
        Test.stopTest();

        System.assertEquals(3, summary.totalContracts,   'Cancelled excluded; expired+active+pending = 3');
        System.assertEquals(2, summary.activeContracts,  'Two Active contracts');
        System.assert(summary.expiringSoon >= 1,          'At least one expiring within 90 days');
        System.assert(summary.cancellationDeadlineSoon >= 1, 'At least one cancellation deadline within 30 days');
        System.assertEquals(1, summary.pendingReview,    'One pending review');
    }

    @IsTest
    static void getContracts_allFilter_returnsAll() {
        Test.startTest();
        ContractDashboardController.ContractPage page =
            ContractDashboardController.getContracts('All', null, 10, 1);
        Test.stopTest();

        System.assertEquals(4, page.totalRecords, 'Should return all 4 contracts');
        System.assert(!page.contracts.isEmpty());
    }

    @IsTest
    static void getContracts_activeFilter() {
        Test.startTest();
        ContractDashboardController.ContractPage page =
            ContractDashboardController.getContracts('Active', null, 10, 1);
        Test.stopTest();

        System.assertEquals(2, page.totalRecords);
        for (Contract_Document__c c : page.contracts) {
            System.assertEquals('Active', c.Status__c);
        }
    }

    @IsTest
    static void getContracts_searchByVendor() {
        Test.startTest();
        ContractDashboardController.ContractPage page =
            ContractDashboardController.getContracts('All', 'Acme', 10, 1);
        Test.stopTest();

        System.assertEquals(1, page.totalRecords, 'Search for Acme should return 1 result');
        System.assertEquals('Acme Corp', page.contracts[0].Vendor_Name__c);
    }

    @IsTest
    static void getContracts_pagination() {
        Test.startTest();
        ContractDashboardController.ContractPage page =
            ContractDashboardController.getContracts('All', null, 2, 1);
        Test.stopTest();

        System.assertEquals(4, page.totalRecords);
        System.assertEquals(2, page.pageSize);
        System.assertEquals(2, page.totalPages);
        System.assertEquals(2, page.contracts.size());
    }

    @IsTest
    static void getContracts_expiringSoonFilter() {
        Test.startTest();
        ContractDashboardController.ContractPage page =
            ContractDashboardController.getContracts('Expiring Soon', null, 10, 1);
        Test.stopTest();

        System.assert(page.totalRecords >= 1, 'Should find at least one expiring soon');
    }
}
