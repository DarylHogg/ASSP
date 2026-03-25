import { LightningElement, api, wire } from 'lwc';
import getContractById  from '@salesforce/apex/ContractDashboardController.getContractById';
import getLinkedFiles   from '@salesforce/apex/ContractDashboardController.getLinkedFiles';

const DATE_FORMAT = new Intl.DateTimeFormat('en-US', {
    year:     'numeric',
    month:    'short',
    day:      'numeric',
    timeZone: 'UTC'
});

const CONTRACT_TYPE_ICONS = {
    'MSA':                   'standard:contract',
    'SOW':                   'standard:work_order',
    'NDA':                   'standard:shield',
    'SaaS / Software':       'standard:product',
    'Service Agreement':     'standard:service_contract',
    'License':               'standard:approval',
    'Maintenance & Support': 'standard:maintenance_plan',
    'Consulting':            'standard:contact',
    'Lease':                 'standard:home',
    'Subscription':          'standard:subscription_management',
    'Other':                 'standard:contract'
};

const STATUS_BADGE_CLASSES = {
    'Active':         'status-active',
    'Expired':        'status-expired',
    'Cancelled':      'status-cancelled',
    'Draft':          'status-draft',
    'Pending Review': 'status-review',
    'Renewed':        'status-renewed'
};

export default class ContractRecordDetail extends LightningElement {
    @api recordId;

    contract;
    files = [];
    error;
    isLoading = true;

    @wire(getContractById, { recordId: '$recordId' })
    wiredContract({ data, error }) {
        this.isLoading = false;
        if (data) {
            this.contract = data;
            this.error    = undefined;
        } else if (error) {
            this.error    = error.body ? error.body.message : String(error);
            this.contract = undefined;
        }
    }

    @wire(getLinkedFiles, { recordId: '$recordId' })
    wiredFiles({ data }) {
        if (data) {
            this.files = data.map(f => ({
                ...f,
                icon: f.fileType === 'PDF'  ? 'doctype:pdf'
                    : f.fileType === 'DOCX' ? 'doctype:word'
                    : f.fileType === 'DOC'  ? 'doctype:word'
                    : 'doctype:unknown'
            }));
        }
    }

    get hasFiles() { return this.files && this.files.length > 0; }

    // ─── Icons / Badges ──────────────────────────────────────────────────────────
    get contractIcon() {
        return CONTRACT_TYPE_ICONS[this.contract?.Contract_Type__c] || 'standard:contract';
    }

    get statusBadgeClass() {
        return STATUS_BADGE_CLASSES[this.contract?.Status__c] || '';
    }

    get renewalDecisionClass() {
        const map = {
            'Terminate':   'field-value decision-terminate',
            'Renegotiate': 'field-value decision-renegotiate',
            'Renew':       'field-value decision-renew',
            'TBD':         'field-value decision-tbd'
        };
        return map[this.contract?.Renewal_Decision__c] || 'field-value';
    }

    get cancellationDateClass() {
        return 'field-value' + (this.contract?.Cancellation_Deadline_Alert__c ? ' text-danger' : '');
    }

    // ─── Conditional Sections ────────────────────────────────────────────────────
    get showExpiryAlert() {
        return this.contract?.Is_Expiring_Soon__c && !this.contract?.Cancellation_Deadline_Alert__c;
    }

    get showVendorContact() {
        return this.contract?.Vendor_Contact_Name__c
            || this.contract?.Vendor_Contact_Email__c
            || this.contract?.Vendor_Contact_Phone__c;
    }

    get showLegal() {
        return this.contract?.Liability_Cap__c
            || this.contract?.Signatories__c
            || this.contract?.Indemnification__c
            || this.contract?.IP_Ownership__c
            || this.contract?.Non_Compete_Scope__c
            || this.contract?.Data_Privacy_Clauses__c
            || this.contract?.SLA_Terms__c;
    }

    get showServices() {
        return this.contract?.Services_Summary__c
            || this.contract?.Description__c
            || this.contract?.Risk_Notes__c;
    }

    get autoRenewLabel() {
        return this.contract?.Auto_Renew__c ? 'Yes' : 'No';
    }

    // ─── Formatted Values ────────────────────────────────────────────────────────
    get formattedAmount() {
        if (!this.contract?.Total_Amount__c) return null;
        try {
            return new Intl.NumberFormat('en-US', {
                style:                 'currency',
                currency:              this.contract.Currency_Code__c || 'USD',
                minimumFractionDigits: 0,
                maximumFractionDigits: 2
            }).format(this.contract.Total_Amount__c);
        } catch (e) {
            return String(this.contract.Total_Amount__c);
        }
    }

    get formattedLiabilityCap() {
        if (!this.contract?.Liability_Cap__c) return null;
        try {
            return new Intl.NumberFormat('en-US', {
                style:                 'currency',
                currency:              this.contract.Currency_Code__c || 'USD',
                minimumFractionDigits: 0,
                maximumFractionDigits: 0
            }).format(this.contract.Liability_Cap__c);
        } catch (e) {
            return String(this.contract.Liability_Cap__c);
        }
    }

    get formattedStartDate()        { return this.formatDate(this.contract?.Contract_Start_Date__c); }
    get formattedEndDate()          { return this.formatDate(this.contract?.Contract_End_Date__c); }
    get formattedSignedDate()       { return this.formatDate(this.contract?.Signed_Date__c); }
    get formattedCancellationDate() { return this.formatDate(this.contract?.Cancellation_Notice_Due_Date__c); }
    get formattedAutoRenewalDate()  { return this.formatDate(this.contract?.Auto_Renewal_Date__c); }

    formatDate(dateStr) {
        if (!dateStr) return null;
        try {
            const [y, m, d] = dateStr.split('-').map(Number);
            return DATE_FORMAT.format(new Date(Date.UTC(y, m - 1, d)));
        } catch (e) {
            return dateStr;
        }
    }
}
