# ASSP Contract Tracker — Salesforce Application

A Salesforce (SFDX) application that monitors a Microsoft Teams / SharePoint folder for new contract files, automatically extracts key terms using the Claude AI API, and surfaces them in a Lightning dashboard with renewal and cancellation alerts.

---

## Architecture Overview

```
SharePoint (Teams Folder)
        │
        ▼  [Microsoft Graph API — scheduled poll]
ContractProcessingQueueable
        │  downloads file, calls Claude API
        ▼
Contract_Document__c  ──▶  ContentDocumentLink (file attachment)
        │
        ▼
contractDashboard LWC  ──▶  contractCard LWC
        │
        ▼
contractRecordDetail LWC  (record detail page)
```

---

## Components

### Apex Classes

| Class | Purpose |
|-------|---------|
| `ContractExtractionService` | Calls Claude API to extract 30+ contract fields from base64-encoded PDF/DOCX files |
| `ContractProcessingQueueable` | Queueable job: reads ContentVersion, calls extraction service, creates Contract_Document__c, links file |
| `ContractDashboardController` | AuraEnabled controller for LWC: dashboard summary, contract list, search, pagination, file upload |
| `ContractStatusScheduler` | Schedulable job that runs nightly to mark expired contracts automatically |
| `ContractExtractionServiceTest` | Unit tests for extraction service (success, partial, API error scenarios) |
| `ContractDashboardControllerTest` | Unit tests for dashboard controller (summary counts, filtering, search, pagination) |

### Lightning Web Components

| Component | Purpose |
|-----------|---------|
| `contractDashboard` | Main dashboard: summary tiles, contract list with search/filter/pagination, file upload modal |
| `contractCard` | Contract card: key dates, amounts, alert banners, contract type icon |
| `contractRecordDetail` | Record detail page: full extracted data, linked files, legal clauses |

### Data Model

| Object / Metadata | Purpose |
|-------------------|---------|
| `Contract_Document__c` | Custom object storing all extracted contract data (39 fields) |
| `Contract_Config__mdt` | Custom Metadata storing API credentials (Anthropic API key) |

---

## Contract_Document__c Fields

### Identity & Classification
| Field | Type | Description |
|-------|------|-------------|
| `Name` | Text | Auto-set from filename |
| `Vendor_Name__c` | Text | Vendor / counterparty name |
| `Contract_Type__c` | Text | MSA, SOW, NDA, SaaS, Service Agreement, License, etc. |
| `Vendor_Contact_Name__c` | Text | Vendor contact person |
| `Email__c` | Text | Vendor contact email |
| `Phone__c` | Text | Vendor contact phone |
| `Internal_Owner__c` | Text | Internal contract manager |
| `Description__c` | Long Text | Executive summary of the contract |

### Dates & Renewal
| Field | Type | Description |
|-------|------|-------------|
| `Contract_Start_Date__c` | Date | Contract effective date |
| `Contract_End_Date__c` | Date | Contract expiration date |
| `Signed_Date__c` | Date | Date contract was signed |
| `Auto_Renew__c` | Checkbox | Whether contract auto-renews |
| `Auto_Renewal_Date__c` | Date | Next auto-renewal date |
| `Renewal_Period__c` | Text | Renewal term (e.g. "1 year") |
| `Renewal_Notice_Period__c` | Text | Required notice before renewal (e.g. "60 days") |
| `Cancellation_Notice_Due_Date__c` | Date | Deadline to cancel to avoid renewal |
| `Cancellation_Terms__c` | Text | Cancellation clause details |

### Financial
| Field | Type | Description |
|-------|------|-------------|
| `Total_Amount__c` | Currency | Total contract value |
| `Currency_Code__c` | Text | ISO 4217 currency code |
| `Payment_Terms__c` | Text | Payment terms (e.g. "Net 30") |
| `Billing_Frequency__c` | Picklist | Monthly, Quarterly, Annual, etc. |
| `Rate_Card__c` | Long Text | Hourly rates or pricing schedule |

### Scope & Legal
| Field | Type | Description |
|-------|------|-------------|
| `Services_Summary__c` | Long Text | Deliverables and scope of work |
| `SLA_Terms__c` | Long Text | Service level agreements |
| `Liability_Cap__c` | Currency | Maximum liability amount |
| `Indemnification__c` | Long Text | Indemnification clause |
| `Governing_Law__c` | Text | Jurisdiction / governing law |
| `Data_Privacy_Clauses__c` | Long Text | GDPR/CCPA/data privacy terms |
| `Non_Compete_Scope__c` | Long Text | Non-compete restrictions |
| `IP_Ownership__c` | Long Text | Intellectual property rights |
| `Signatories__c` | Long Text | Names and titles of signatories |

### Status & Risk
| Field | Type | Description |
|-------|------|-------------|
| `Status__c` | Picklist | Draft, Pending Review, Active, Expired, Cancelled, Renewed |
| `Extraction_Status__c` | Picklist | Completed, Failed |
| `Risk_Notes__c` | Long Text | Notable risks or flags from the contract |
| `Renewal_Decision__c` | Picklist | Renew, Renegotiate, Terminate, TBD |

### Alert Formulas (auto-calculated)
| Field | Type | Description |
|-------|------|-------------|
| `Is_Expiring_Soon__c` | Formula (Checkbox) | TRUE if end date ≤ 90 days from today |
| `Cancellation_Deadline_Alert__c` | Formula (Checkbox) | TRUE if cancellation deadline ≤ 30 days from today |
| `Days_Until_Expiry__c` | Formula (Number) | Days until contract end date |
| `Days_Until_Cancellation_Deadline__c` | Formula (Number) | Days until cancellation deadline |

### SharePoint Integration
| Field | Type | Description |
|-------|------|-------------|
| `SharePoint_URL__c` | Text | Source file URL in SharePoint |
| `SharePoint_File_Id__c` | Text | SharePoint file identifier for deduplication |

---

## Alert Logic

Dashboard cards are highlighted automatically based on formula field values:

- **Red banner** — Cancellation deadline approaching (`Cancellation_Deadline_Alert__c = true`, ≤ 30 days)
- **Orange banner** — Contract expiring soon (`Is_Expiring_Soon__c = true`, ≤ 90 days)

No scheduled jobs are required for alerts — they are formula-based and update in real time.

---

## File Support

| Extension | Support |
|-----------|---------|
| `.pdf` | Full — Claude reads PDFs natively |
| `.docx` | Partial — sent as binary; extraction quality may vary |
| `.doc` | Partial — sent as binary; extraction quality may vary |

For best results, upload contracts as PDFs.

---

## Prerequisites

- Salesforce org (Developer, Sandbox, or Production) with API access
- [Salesforce CLI (sf)](https://developer.salesforce.com/tools/salesforcecli) installed
- Microsoft Azure App Registration with Graph API permissions (see Post-Deployment Setup)
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
4. Add custom header: `x-api-key` = `<your Anthropic API key>`
5. Save

Alternatively, update the **Contract_Config__mdt** Custom Metadata record directly:

1. **Setup → Custom Metadata Types → Contract Config → Manage Records**
2. Edit the **Default** record and set `Anthropic_API_Key__c`

### B — Configure the Microsoft Graph External Credential

You need an Azure App Registration with:
- **API permissions**: `Sites.Read.All`, `Files.Read.All` (Application permissions — client credentials flow)
- A **client secret** generated

Then:

1. **Setup → Security → Named Credentials → External Credentials → Microsoft Graph**
2. Update the token endpoint to include your Tenant ID:
   ```
   https://login.microsoftonline.com/<YOUR_TENANT_ID>/oauth2/v2.0/token
   ```
3. Under **Principals**, edit `MicrosoftGraph_NamedPrincipal` and set:
   - **Client ID**: Azure app's Application (client) ID
   - **Client Secret**: Azure app's client secret
4. Save

### C — Find your SharePoint IDs

Use [Microsoft Graph Explorer](https://developer.microsoft.com/graph/graph-explorer) to retrieve:

**Site ID:**
```
GET https://graph.microsoft.com/v1.0/sites?search=<your-site-name>
```

**Drive ID** (document library, usually "Documents"):
```
GET https://graph.microsoft.com/v1.0/sites/<siteId>/drives
```

**Folder ID** (specific subfolder, or use `root`):
```
GET https://graph.microsoft.com/v1.0/drives/<driveId>/root/children
```

### D — Update Custom Metadata

1. **Setup → Custom Metadata Types → SharePoint Config → Manage Records**
2. Edit the **Default** record and fill in:
   - Site ID
   - Drive ID
   - Contracts Folder ID
   - Site Display Name
   - Is Active = `true`
3. Save

### E — Assign Permission Sets

```bash
sf org assign permset --name Contract_Document_Access --target-org myorg -o <username>
```

### F — Schedule the Nightly Status Job

Run in **Developer Console → Execute Anonymous**:

```apex
// Runs nightly at midnight
String cronExp = '0 0 0 * * ?';
System.schedule('Contract Status Scheduler', cronExp, new ContractStatusScheduler());
```

### G — Open the App

1. Click the **App Launcher** (waffle icon)
2. Search for **Contract Tracker** and open it
3. The default landing page is the **Contract Dashboard** tab

---

## Manual File Processing

To process a contract file on demand, run in **Developer Console → Execute Anonymous**:

```apex
// Replace with the ContentVersion Id of your uploaded file
Id contentVersionId = '068XXXXXXXXXXXX';
System.enqueueJob(new ContractProcessingQueueable(contentVersionId));
```

Or use the **Upload** button on the Contract Dashboard — it will enqueue processing automatically.

---

## Dashboard Features

| Feature | Details |
|---------|---------|
| Summary tiles | Total, Active, Expiring (<90 days), Cancellation Alert, Pending Review, Expired |
| Search | Full-text search on contract name and vendor name |
| Status filter | All, Active, Expiring Soon, Cancellation Alert, Pending Review, Expired, Cancelled |
| Pagination | 12 contracts per page |
| Upload | Upload PDF/DOCX directly; AI extraction runs automatically |
| Contract types | Dynamic icon per type (MSA, SOW, NDA, SaaS, Service Agreement, License, etc.) |

---

## Notes & Limitations

- **Callout size limit**: Files larger than ~5 MB may fail. Consider storing very large contracts as links only.
- **Queueable chaining**: Files are processed one at a time via self-chaining queueables. Large batches will take several minutes.
- **AI extraction accuracy**: Claude extracts fields on a best-effort basis. Always review contracts with `Extraction_Status__c = 'Completed'` for accuracy before acting on critical dates.
- **No real-time webhook**: Contracts uploaded to SharePoint are picked up on the next scheduled sync. For near-real-time, run the sync job every 15 minutes.
- **Supported file types**: PDF produces the best extraction results. DOCX/DOC are supported but may yield lower accuracy.
