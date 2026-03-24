import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

const CURRENCY_FORMAT = new Intl.NumberFormat('en-US', {
    style:    'currency',
    currency: 'USD',
    minimumFractionDigits: 0,
    maximumFractionDigits: 2
});

const DATE_FORMAT = new Intl.DateTimeFormat('en-US', {
    year:  'numeric',
    month: 'short',
    day:   'numeric',
    timeZone: 'UTC'
});

const CONTRACT_TYPE_ICONS = {
    'SaaS / Software':         'standard:product',
    'Service Agreement':       'standard:service_contract',
    'License':                 'standard:approval',
    'Maintenance & Support':   'standard:maintenance_plan',
    'Consulting':              'standard:contact',
    'Lease':                   'standard:home',
    'Subscription':            'standard:subscription_management',
    'Other':                   'standard:contract'
};

const STATUS_BADGE_CLASSES = {
    'Active':         'status-active',
    'Expired':        'status-expired',
    'Cancelled':      'status-cancelled',
    'Pending Review': 'status-review',
    'Renewed':        'status-renewed'
};

export default class ContractCard extends NavigationMixin(LightningElement) {

    @api contract;

    // ─── Computed Getters ────────────────────────────────────────────────────────
    get contractIcon() {
        return CONTRACT_TYPE_ICONS[this.contract.Contract_Type__c] || 'standard:contract';
    }

    get statusBadgeClass() {
        return STATUS_BADGE_CLASSES[this.contract.Status__c] || '';
    }

    get cardClass() {
        let classes = 'contract-card';
        if (this.contract.Cancellation_Deadline_Alert__c) classes += ' card-alert-high';
        else if (this.contract.Is_Expiring_Soon__c)       classes += ' card-alert-medium';
        return classes;
    }

    get showCancellationAlert() {
        return this.contract.Cancellation_Deadline_Alert__c === true;
    }

    get showExpiryAlert() {
        return this.contract.Is_Expiring_Soon__c === true
            && !this.contract.Cancellation_Deadline_Alert__c;
    }

    get formattedAmount() {
        if (!this.contract.Total_Amount__c) return null;
        const currency = this.contract.Currency_Code__c || 'USD';
        try {
            const fmt = new Intl.NumberFormat('en-US', {
                style: 'currency',
                currency: currency,
                minimumFractionDigits: 0,
                maximumFractionDigits: 2
            });
            return fmt.format(this.contract.Total_Amount__c);
        } catch (e) {
            return currency + ' ' + this.contract.Total_Amount__c.toLocaleString();
        }
    }

    get formattedStartDate() {
        return this.formatDate(this.contract.Contract_Start_Date__c);
    }

    get formattedEndDate() {
        return this.formatDate(this.contract.Contract_End_Date__c);
    }

    get formattedCancellationDate() {
        return this.formatDate(this.contract.Cancellation_Notice_Due_Date__c);
    }

    get cancellationDateClass() {
        return 'detail-value' + (this.contract.Cancellation_Deadline_Alert__c ? ' text-danger' : '');
    }

    // ─── Event Handlers ──────────────────────────────────────────────────────────
    handleViewRecord() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId:   this.contract.Id,
                actionName: 'view'
            }
        });
    }

    // ─── Utilities ───────────────────────────────────────────────────────────────
    formatDate(dateStr) {
        if (!dateStr) return null;
        try {
            // Salesforce date fields come as 'YYYY-MM-DD'
            const [year, month, day] = dateStr.split('-').map(Number);
            const d = new Date(Date.UTC(year, month - 1, day));
            return DATE_FORMAT.format(d);
        } catch (e) {
            return dateStr;
        }
    }
}
