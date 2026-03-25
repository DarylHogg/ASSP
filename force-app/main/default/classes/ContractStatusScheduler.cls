/**
 * Scheduled job that runs nightly to automatically expire contracts
 * whose Contract_End_Date__c has passed.
 *
 * Schedule via Setup → Apex Classes → Schedule Apex, or run once in
 * Anonymous Apex to register the nightly schedule:
 *
 *   System.schedule(
 *       'Contract Status Nightly Update',
 *       '0 0 1 * * ?',
 *       new ContractStatusScheduler()
 *   );
 */
public with sharing class ContractStatusScheduler implements Schedulable {

    public void execute(SchedulableContext ctx) {
        updateExpiredContracts();
    }

    public static void updateExpiredContracts() {
        List<Contract_Document__c> toExpire = [
            SELECT Id, Status__c
            FROM   Contract_Document__c
            WHERE  Status__c = 'Active'
            AND    Contract_End_Date__c < TODAY
        ];

        if (toExpire.isEmpty()) return;

        for (Contract_Document__c c : toExpire) {
            c.Status__c = 'Expired';
        }

        update toExpire;
    }
}
