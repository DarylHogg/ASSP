# ASSP Contract Tracker — Salesforce Application

A Salesforce (SFDX) application that monitors a Microsoft Teams / SharePoint folder for new contract files, automatically extracts key terms using the Claude AI API, and surfaces them in a Lightning dashboard.

---

## Architecture Overview

```
SharePoint (Teams Folder)
        │
        ▼  [Microsoft Graph API — hourly poll]
ContractSyncQueueable
        │  creates
        ▼
SharePoint_File_Tracking__c  ──▶  ContractProcessingQueueable
                                          │  downloads file
                                          │  calls Claude API
                                          ▼
                                  Contract_Document__c
                                          │
                                          ▼
                                  contractDashboard LWC
```

### Key Components

| Component | Purpose |
|-----------|---------|
| `SharePointService` | Apex — calls Microsoft Graph API to list and download files |
| `ContractExtractionService` | Apex — calls Claude API to extract contract terms from PDFs/DOCX |
| `ContractSyncQueueable` | Apex Queueable — polls SharePoint, creates tracking records |
| `ContractProcessingQueueable` | Apex Queueable — downloads + processes one file at a time, self-chains |
| `ContractSyncScheduler` | Schedulable — runs hourly, enqueues `ContractSyncQueueable` |
| `ContractDashboardController` | Apex controller for the LWC |
| `contractDashboard` | LWC — main dashboard with summary tiles, search, filters |
| `contractCard` | LWC — individual contract card with alerts |
| `Contract_Document__c` | Custom object — stores extracted contract data |
| `SharePoint_File_Tracking__c` | Custom object — tracks which files have been processed |
| `SharePoint_Config__mdt` | Custom Metadata — stores SharePoint site/drive/folder IDs |

### Extracted Contract Fields

- Vendor / counterparty name
- Total contract value and currency
- Contract start and end dates
- Auto-renew flag and renewal period
- Renewal notice deadline
- Cancellation notice due date and terms
- Contract type (SaaS, Service Agreement, License, etc.)
- Description / summary

### Alert Logic (Formula Fields)

- **Expiring within 90 days** — `Is_Expiring_Soon__c` checkbox formula
- **Cancellation deadline within 30 days** — `Cancellation_Deadline_Alert__c` checkbox formula
- Cards with alerts are highlighted in the dashboard (orange = expiry, red = cancellation)

---

## Prerequisites

- Salesforce org (Developer, Sandbox, or Production) with API access
- [Salesforce CLI (sf)](https://developer.salesforce.com/tools/salesforcecli) installed
- Microsoft Azure App Registration with Graph API permissions (see below)
- Anthropic API key

---

## Deployment

### 1 — Authenticate to your org

```bash
sf org login web --alias myorg
```

### 2 — Deploy the metadata

```bash
sf project deploy start --source-dir force-app --target-org myorg
```

### 3 — Run tests

```bash
sf apex run test --target-org myorg --code-coverage --result-format human
```

---

## Post-Deployment Setup

### A — Configure the Claude AI External Credential

1. Go to **Setup → Security → Named Credentials → External Credentials**
2. Open **Claude AI**
3. Under **Principals**, click **Edit** on `ClaudeAI_NamedPrincipal`
4. Add a custom header: `x-api-key` = `<your Anthropic API key>`
5. Save

### B — Configure the Microsoft Graph External Credential

You need an Azure App Registration with:
- **API permissions**: `Sites.Read.All`, `Files.Read.All` (Application permissions — client credentials)
- **Client secret** generated

Then:

1. Go to **Setup → Security → Named Credentials → External Credentials**
2. Open **Microsoft Graph**
3. Update the `token_endpoint` to include your actual Tenant ID:
   `https://login.microsoftonline.com/<YOUR_TENANT_ID>/oauth2/v2.0/token`
4. Under **Principals**, edit `MicrosoftGraph_NamedPrincipal` and set:
   - **Client ID**: your Azure app's Application (client) ID
   - **Client Secret**: your Azure app's client secret
5. Save

### C — Find your SharePoint IDs

You need three IDs from Microsoft Graph. The easiest way is via Graph Explorer:

**Site ID** — for a Teams-connected SharePoint site:
```
GET https://graph.microsoft.com/v1.0/sites?search=<your-site-name>
```

**Drive ID** — for the document library (usually "Documents"):
```
GET https://graph.microsoft.com/v1.0/sites/<siteId>/drives
```

**Folder ID** — for a specific subfolder (or use `root` for the top of the drive):
```
GET https://graph.microsoft.com/v1.0/drives/<driveId>/root/children
```

### D — Update Custom Metadata

1. Go to **Setup → Custom Metadata Types → SharePoint Config → Manage Records**
2. Edit the **Default** record
3. Fill in your **Site ID**, **Drive ID**, **Contracts Folder ID**, and **Site Display Name**
4. Set **Is Active** = `true`
5. Save

### E — Assign Permission Sets

```bash
sf org assign permset --name Contract_Tracking_Admin --target-org myorg -o <username>
sf org assign permset --name Contract_Tracking_User  --target-org myorg -o <username>
```

### F — Schedule the Sync Job

Run in **Developer Console → Execute Anonymous**:

```apex
ContractSyncScheduler.scheduleDefault(null); // hourly
```

Or use a custom cron expression:
```apex
ContractSyncScheduler.scheduleDefault('0 0 8-18 * * ?'); // every hour, 8am–6pm
```

### G — Add the App to Navigation

1. Go to **App Launcher → Contract Tracker**
2. The default landing page is the **Contract Dashboard** tab

---

## Manual / On-Demand Sync

From the dashboard: click **Sync Now**.

From Anonymous Apex:
```apex
ContractSyncScheduler.triggerImmediateSync();
```

---

## File Support

| Extension | Support |
|-----------|---------|
| `.pdf`    | Full — Claude reads PDFs natively |
| `.docx`   | Partial — sent as binary; extraction quality may vary |
| `.doc`    | Partial — sent as binary; extraction quality may vary |

For best results, upload contracts as PDFs.

---

## Notes & Limitations

- **Salesforce callout size limit**: Files larger than ~5 MB may fail to download. Consider storing very large contracts as links only.
- **Queueable chaining**: Salesforce limits async job depth; if many files arrive simultaneously, they are processed one-at-a-time via self-chaining. Large batches will take several minutes.
- **AI extraction accuracy**: Claude extracts fields on a best-effort basis. Always review `Extraction_Status__c = 'Completed'` contracts for accuracy before taking action on critical dates.
- **No real-time webhook**: The app polls SharePoint on a schedule. For near-real-time, set the cron to run every 15 minutes (`0 0/15 * * * ?`).
