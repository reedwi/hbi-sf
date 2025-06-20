import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import processCSV from '@salesforce/apex/EnrollmentImporterController.processCSV';
import getPreviewData from '@salesforce/apex/EnrollmentImporterController.getPreviewData';
import downloadResults from '@salesforce/apex/EnrollmentImporterController.downloadResults';

export default class EnrollmentImporter extends LightningElement {
    @track showPreview = false;
    @track showResults = false;
    @track isProcessing = false;
    @track previewData = [];
    @track resultsData = [];
    @track columns = [];
    @track resultsColumns = [
        { label: 'Row', fieldName: 'rowNumber', type: 'number' },
        { label: 'First Name', fieldName: 'firstName', type: 'text' },
        { label: 'Last Name', fieldName: 'lastName', type: 'text' },
        { label: 'Email', fieldName: 'email', type: 'text' },
        { label: 'Program ID', fieldName: 'originalProgramId', type: 'text' },
        { label: 'Program Name', fieldName: 'programName', type: 'text' },
        { label: 'Status', fieldName: 'status', type: 'text' },
        { label: 'Message', fieldName: 'message', type: 'text' },
        { label: 'Contact ID', fieldName: 'contactId', type: 'text' },
        { label: 'Enrollment ID', fieldName: 'enrollmentId', type: 'text' }
    ];
    acceptedFormats = ['.csv'];
    recordId = null;
    contentVersionId = null;

    handleUploadFinished(event) {
        const uploadedFiles = event.detail.files;
        if (uploadedFiles.length > 0) {
            this.contentVersionId = uploadedFiles[0].contentVersionId;
            this.showPreview = true;
            this.loadPreviewData();
        }
    }

    loadPreviewData() {
        getPreviewData({ contentVersionId: this.contentVersionId })
            .then(result => {
                this.previewData = result.data;
                this.columns = result.columns;
            })
            .catch(error => {
                this.showToast('Error', error.body.message, 'error');
            });
    }

    handleProcessImport() {
        this.isProcessing = true;
        processCSV({ contentVersionId: this.contentVersionId })
            .then(result => {
                this.resultsData = result;
                this.showResults = true;
                this.showPreview = false;
                this.showToast('Success', 'CSV processing completed', 'success');
            })
            .catch(error => {
                this.showToast('Error', error.body.message, 'error');
            })
            .finally(() => {
                this.isProcessing = false;
            });
    }

    handleDownloadResults() {
        downloadResults({ contentVersionId: this.contentVersionId })
            .then(result => {
                // Create a download link and trigger it
                const link = document.createElement('a');
                link.href = 'data:text/csv;charset=utf-8,' + encodeURIComponent(result);
                link.download = 'import_results.csv';
                link.click();
            })
            .catch(error => {
                this.showToast('Error', error.body.message, 'error');
            });
    }

    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(event);
    }
} 