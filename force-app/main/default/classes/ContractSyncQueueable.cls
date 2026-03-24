/**
 * Queueable that polls the configured SharePoint folder for new contract files,
 * creates SharePoint_File_Tracking__c records for any unprocessed files, then
 * kicks off ContractProcessingQueueable for the first pending file.
 *
 * Subsequent files are chained automatically by ContractProcessingQueueable.
 */
public class ContractSyncQueueable implements Queueable, Database.AllowsCallouts {

    // File extensions treated as potential contracts
    private static final Set<String> SUPPORTED_EXTENSIONS = new Set<String>{
        'pdf', 'docx', 'doc'
    };

    public void execute(QueueableContext ctx) {
        List<SharePoint_Config__mdt> configs = [
            SELECT  Label, Site_Id__c, Drive_Id__c, Contracts_Folder_Id__c,
                    Scan_Subfolders__c
            FROM    SharePoint_Config__mdt
            WHERE   Is_Active__c = true
            LIMIT   10
        ];

        if (configs.isEmpty()) {
            System.debug(LoggingLevel.WARN, 'ContractSyncQueueable: No active SharePoint configs found.');
            return;
        }

        // Collect all already-known item IDs to avoid duplicates
        Set<String> knownItemIds = getKnownItemIds();

        List<SharePoint_File_Tracking__c> toInsert = new List<SharePoint_File_Tracking__c>();

        for (SharePoint_Config__mdt cfg : configs) {
            try {
                List<SharePointService.SharePointFile> files =
                    SharePointService.listFiles(cfg.Drive_Id__c, cfg.Contracts_Folder_Id__c);

                for (SharePointService.SharePointFile f : files) {
                    if (knownItemIds.contains(f.id)) continue;
                    if (!isSupportedFile(f.name))    continue;

                    toInsert.add(new SharePoint_File_Tracking__c(
                        SharePoint_Item_Id__c = f.id,
                        File_Name__c          = f.name,
                        Drive_Id__c           = cfg.Drive_Id__c,
                        SharePoint_URL__c     = f.webUrl,
                        File_Size__c          = f.size,
                        Last_Modified__c      = f.lastModifiedDateTime,
                        Status__c             = 'Pending'
                    ));

                    // Track locally so we don't add dupes within this batch
                    knownItemIds.add(f.id);
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR,
                    'ContractSyncQueueable: Error listing files for config "' + cfg.Label + '": ' + e.getMessage());
            }
        }

        if (!toInsert.isEmpty()) {
            insert toInsert;
            System.debug(LoggingLevel.INFO,
                'ContractSyncQueueable: Queued ' + toInsert.size() + ' new file(s) for processing.');

            // Kick off processing for the first pending file; it will self-chain
            System.enqueueJob(new ContractProcessingQueueable(toInsert[0].Id));
        } else {
            System.debug(LoggingLevel.INFO, 'ContractSyncQueueable: No new files found.');
        }
    }

    // ─── Private Helpers ─────────────────────────────────────────────────────────

    private Set<String> getKnownItemIds() {
        Set<String> ids = new Set<String>();
        for (SharePoint_File_Tracking__c t : [
            SELECT SharePoint_Item_Id__c FROM SharePoint_File_Tracking__c
        ]) {
            ids.add(t.SharePoint_Item_Id__c);
        }
        return ids;
    }

    private Boolean isSupportedFile(String fileName) {
        if (String.isBlank(fileName)) return false;
        Integer dotIdx = fileName.lastIndexOf('.');
        if (dotIdx < 0) return false;
        String ext = fileName.substring(dotIdx + 1).toLowerCase();
        return SUPPORTED_EXTENSIONS.contains(ext);
    }
}
