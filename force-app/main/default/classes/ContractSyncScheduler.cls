/**
 * Scheduled Apex class that triggers a SharePoint sync on a recurring basis.
 *
 * To schedule from Developer Console / Setup:
 *   System.schedule('ASSP Contract Sync - Hourly', '0 0 * * * ?', new ContractSyncScheduler());
 *
 * Or use the ContractSyncScheduler.scheduleDefault() method for a quick setup.
 */
public with sharing class ContractSyncScheduler implements Schedulable {

    /** Default cron: runs at the top of every hour */
    public static final String DEFAULT_CRON = '0 0 * * * ?';
    public static final String JOB_NAME     = 'ASSP Contract Sync';

    public void execute(SchedulableContext ctx) {
        System.enqueueJob(new ContractSyncQueueable());
    }

    /**
     * Schedules the default hourly sync job.
     * Safe to call multiple times; aborts any existing job with the same name first.
     *
     * @param cronExpression  Optional custom cron. Defaults to hourly if blank.
     * @return                Job ID of the newly scheduled job.
     */
    public static String scheduleDefault(String cronExpression) {
        // Abort existing job if one already exists
        for (CronTrigger existing : [
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name = :JOB_NAME
            AND   State NOT IN ('DELETED', 'COMPLETE', 'ERROR')
        ]) {
            System.abortJob(existing.Id);
        }

        String cron = String.isNotBlank(cronExpression) ? cronExpression : DEFAULT_CRON;
        return System.schedule(JOB_NAME, cron, new ContractSyncScheduler());
    }

    /**
     * Immediately triggers a one-off sync without waiting for the schedule.
     * Useful for manual syncs from the UI or Anonymous Apex.
     */
    public static void triggerImmediateSync() {
        System.enqueueJob(new ContractSyncQueueable());
    }

    /**
     * Returns whether the sync job is currently scheduled.
     */
    public static Boolean isScheduled() {
        return ![
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name = :JOB_NAME
            AND   State NOT IN ('DELETED', 'COMPLETE', 'ERROR')
        ].isEmpty();
    }
}
