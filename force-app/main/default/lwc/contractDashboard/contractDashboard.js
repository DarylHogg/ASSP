import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getDashboardSummary        from '@salesforce/apex/ContractDashboardController.getDashboardSummary';
import getContracts               from '@salesforce/apex/ContractDashboardController.getContracts';
import enqueueContractProcessing  from '@salesforce/apex/ContractDashboardController.enqueueContractProcessing';

const PAGE_SIZE = 12;
const SEARCH_DEBOUNCE_MS = 400;

export default class ContractDashboard extends LightningElement {

    // ─── State ───────────────────────────────────────────────────────────────────
    @track contracts        = [];
    @track summary          = null;
    @track isLoading        = false;
    @track showUploadModal  = false;
    @track isUploading      = false;
    @track uploadError      = '';

    statusFilter = 'All';
    searchTerm   = '';
    pageNumber   = 1;
    totalRecords = 0;
    totalPages   = 1;

    _searchTimer  = null;
    _selectedFile = null;

    // ─── Lifecycle ───────────────────────────────────────────────────────────────
    connectedCallback() {
        this.loadSummary();
        this.loadContracts();
    }

    // ─── Data Loading ────────────────────────────────────────────────────────────
    loadSummary() {
        getDashboardSummary()
            .then(result => { this.summary = result; })
            .catch(error => { console.error('Failed to load summary:', error); });
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
                this.contracts    = result.contracts;
                this.totalRecords = result.totalRecords;
                this.totalPages   = result.totalPages;
                this.isLoading    = false;
            })
            .catch(error => {
                this.isLoading = false;
                this.showToast('Error', 'Failed to load contracts: ' + this.extractError(error), 'error');
            });
    }

    // ─── Filter / Search / Pagination ────────────────────────────────────────────
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
        this.statusFilter = event.currentTarget.dataset.filter;
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

    // ─── Upload Modal ────────────────────────────────────────────────────────────
    handleUploadClick() {
        this.showUploadModal = true;
        this.uploadError     = '';
        this._selectedFile   = null;
    }

    closeUploadModal() {
        this.showUploadModal = false;
        this._selectedFile   = null;
        this.uploadError     = '';
    }

    handleFileChange(event) {
        const files = event.detail.files;
        this._selectedFile = (files && files.length > 0) ? files[0] : null;
        this.uploadError   = '';
    }

    handleUploadAndProcess() {
        if (!this._selectedFile) {
            this.uploadError = 'Please select a file to upload.';
            return;
        }

        this.isUploading = true;
        this.uploadError = '';

        const reader = new FileReader();

        reader.onload = () => {
            // reader.result is "data:<mime>;base64,<data>"
            const base64Content = reader.result.split(',')[1];

            enqueueContractProcessing({
                fileName:     this._selectedFile.name,
                base64Content: base64Content
            })
                .then(() => {
                    this.isUploading   = false;
                    this.showUploadModal = false;
                    this._selectedFile = null;
                    this.showToast(
                        'Upload Successful',
                        'Contract is being processed by AI. It will appear in the dashboard shortly.',
                        'success'
                    );
                    setTimeout(() => {
                        this.loadSummary();
                        this.loadContracts();
                    }, 5000);
                })
                .catch(error => {
                    this.isUploading = false;
                    this.uploadError = this.extractError(error);
                });
        };

        reader.onerror = () => {
            this.isUploading = false;
            this.uploadError = 'Failed to read the file. Please try again.';
        };

        reader.readAsDataURL(this._selectedFile);
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

    get selectedFileName() { return this._selectedFile ? this._selectedFile.name : null; }
    get hasContracts()   { return this.contracts && this.contracts.length > 0; }
    get showPagination() { return this.totalPages > 1; }
    get isFirstPage()    { return this.pageNumber <= 1; }
    get isLastPage()     { return this.pageNumber >= this.totalPages; }

    get emptyStateMessage() {
        if (this.searchTerm) {
            return `No contracts match "${this.searchTerm}". Try a different search term.`;
        }
        if (this.statusFilter !== 'All') {
            return `No contracts with status "${this.statusFilter}".`;
        }
        return 'No contracts yet. Click "Upload Contract" to add one.';
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
