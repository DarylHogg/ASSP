import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getDashboardSummary from '@salesforce/apex/ContractDashboardController.getDashboardSummary';
import getContracts      from '@salesforce/apex/ContractDashboardController.getContracts';
import triggerSync       from '@salesforce/apex/ContractDashboardController.triggerSync';
import scheduleSyncJob   from '@salesforce/apex/ContractDashboardController.scheduleSyncJob';

const PAGE_SIZE = 12;
const SEARCH_DEBOUNCE_MS = 400;

export default class ContractDashboard extends LightningElement {

    // ─── State ───────────────────────────────────────────────────────────────────
    @track contracts     = [];
    @track summary       = null;
    @track isLoading     = false;
    @track isSyncing     = false;
    @track syncMessage   = '';
    @track syncMessageVariant = 'info';

    statusFilter = 'All';
    searchTerm   = '';
    pageNumber   = 1;
    totalRecords = 0;
    totalPages   = 1;
    syncScheduled = false;

    _searchTimer = null;

    // ─── Lifecycle ───────────────────────────────────────────────────────────────
    connectedCallback() {
        this.loadSummary();
        this.loadContracts();
    }

    // ─── Wire / Data Loading ─────────────────────────────────────────────────────
    loadSummary() {
        getDashboardSummary()
            .then(result => {
                this.summary       = result;
                this.syncScheduled = result.syncScheduled;
            })
            .catch(error => {
                console.error('Failed to load summary:', error);
            });
    }

    loadContracts() {
        this.isLoading = true;
        getContracts({
            statusFilter: this.statusFilter,
            searchTerm:   this.searchTerm,
            pageSize:     PAGE_SIZE,
            pageNumber:   this.pageNumber
        })
            .then(result => {
                this.contracts   = result.contracts;
                this.totalRecords = result.totalRecords;
                this.totalPages  = result.totalPages;
                this.isLoading   = false;
            })
            .catch(error => {
                this.isLoading = false;
                this.showToast('Error', 'Failed to load contracts: ' + this.extractError(error), 'error');
            });
    }

    // ─── Event Handlers ──────────────────────────────────────────────────────────
    handleSearch(event) {
        const value = event.detail.value;
        clearTimeout(this._searchTimer);
        this._searchTimer = setTimeout(() => {
            this.searchTerm = value;
            this.pageNumber = 1;
            this.loadContracts();
        }, SEARCH_DEBOUNCE_MS);
    }

    handleStatusFilter(event) {
        this.statusFilter = event.detail.value;
        this.pageNumber   = 1;
        this.loadContracts();
    }

    handleTileClick(event) {
        const filter = event.currentTarget.dataset.filter;
        this.statusFilter = filter;
        this.pageNumber   = 1;
        this.loadContracts();
    }

    handlePreviousPage() {
        if (this.pageNumber > 1) {
            this.pageNumber--;
            this.loadContracts();
        }
    }

    handleNextPage() {
        if (this.pageNumber < this.totalPages) {
            this.pageNumber++;
            this.loadContracts();
        }
    }

    handleContractUpdate() {
        this.loadSummary();
        this.loadContracts();
    }

    handleSyncNow() {
        this.isSyncing    = true;
        this.syncMessage  = '';
        triggerSync()
            .then(message => {
                this.isSyncing          = false;
                this.syncMessage        = message;
                this.syncMessageVariant = 'success';
                this.showToast('Sync Started', message, 'success');
                // Refresh after a short delay to pick up any fast-processing files
                setTimeout(() => {
                    this.loadSummary();
                    this.loadContracts();
                }, 5000);
            })
            .catch(error => {
                this.isSyncing          = false;
                this.syncMessage        = this.extractError(error);
                this.syncMessageVariant = 'error';
                this.showToast('Sync Failed', this.syncMessage, 'error');
            });
    }

    handleScheduleSync() {
        scheduleSyncJob({ cronExpression: null })
            .then(message => {
                this.syncScheduled = true;
                this.showToast('Scheduled', message, 'success');
                this.loadSummary();
            })
            .catch(error => {
                this.showToast('Error', this.extractError(error), 'error');
            });
    }

    // ─── Getters ─────────────────────────────────────────────────────────────────
    get statusOptions() {
        return [
            { label: 'All',                value: 'All' },
            { label: 'Active',             value: 'Active' },
            { label: 'Expiring Soon',      value: 'Expiring Soon' },
            { label: 'Cancellation Alert', value: 'Cancellation Alert' },
            { label: 'Pending Review',     value: 'Pending Review' },
            { label: 'Expired',            value: 'Expired' },
            { label: 'Cancelled',          value: 'Cancelled' }
        ];
    }

    get hasContracts()   { return this.contracts && this.contracts.length > 0; }
    get showPagination() { return this.totalPages > 1; }
    get isFirstPage()    { return this.pageNumber <= 1; }
    get isLastPage()     { return this.pageNumber >= this.totalPages; }

    get syncMessageClass() {
        const base = 'slds-notify slds-notify_alert slds-m-bottom_small ';
        return base + (this.syncMessageVariant === 'error'
            ? 'slds-theme_error'
            : 'slds-theme_success');
    }

    get emptyStateMessage() {
        if (this.searchTerm) {
            return `No contracts match "${this.searchTerm}". Try a different search term.`;
        }
        if (this.statusFilter !== 'All') {
            return `No contracts with status "${this.statusFilter}".`;
        }
        return 'No contracts have been imported yet. Click "Sync Now" to scan SharePoint for contracts.';
    }

    // ─── Utilities ───────────────────────────────────────────────────────────────
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    extractError(error) {
        if (error && error.body && error.body.message) return error.body.message;
        if (error && error.message) return error.message;
        return JSON.stringify(error);
    }
}
