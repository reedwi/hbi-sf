public with sharing class CertificateImporterController {
    
    @AuraEnabled
    public static Map<String, Object> getPreviewData(String contentVersionId) {
        try {
            // Get the ContentVersion and its ContentDocument
            ContentVersion cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :contentVersionId];
            ContentDocument cd = [SELECT Id, LatestPublishedVersionId FROM ContentDocument WHERE Id = :cv.ContentDocumentId];
            
            // Get the actual file content using the LatestPublishedVersionId
            ContentVersion fileContent = [SELECT VersionData FROM ContentVersion WHERE Id = :cd.LatestPublishedVersionId];
            String csvContent = fileContent.VersionData.toString();
            
            // Parse CSV content
            List<String> lines = csvContent.split('\n');
            if (lines.isEmpty()) {
                throw new CertificateException('The uploaded file is empty');
            }
            
            List<String> headers = lines[0].split(',');
            if (headers.isEmpty()) {
                throw new CertificateException('The uploaded file has no headers');
            }
            
            // Create column definitions for the datatable
            List<Map<String, String>> columns = new List<Map<String, String>>();
            for (Integer i = 0; i < headers.size(); i++) {
                columns.add(new Map<String, String>{
                    'label' => headers[i].trim(),
                    'fieldName' => 'col' + i,
                    'type' => 'text'
                });
            }
            
            // Create preview data
            List<Map<String, Object>> data = new List<Map<String, Object>>();
            for (Integer i = 1; i < Math.min(lines.size(), 11); i++) { // Show first 10 rows
                List<String> values = lines[i].split(',');
                Map<String, Object> row = new Map<String, Object>();
                for (Integer j = 0; j < values.size(); j++) {
                    row.put('col' + j, values[j].trim());
                }
                data.add(row);
            }
            
            return new Map<String, Object>{
                'columns' => columns,
                'data' => data
            };
        } catch (Exception e) {
            throw new AuraHandledException('Error processing file: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static List<Map<String, Object>> processCSV(String contentVersionId) {
        try {
            // Get the ContentVersion and its ContentDocument
            ContentVersion cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :contentVersionId];
            ContentDocument cd = [SELECT Id, LatestPublishedVersionId FROM ContentDocument WHERE Id = :cv.ContentDocumentId];
            
            // Get the actual file content using the LatestPublishedVersionId
            ContentVersion fileContent = [SELECT VersionData FROM ContentVersion WHERE Id = :cd.LatestPublishedVersionId];
            String csvContent = fileContent.VersionData.toString();
            
            List<String> lines = csvContent.split('\n');
            List<String> headers = lines[0].split(',');
            
            List<Map<String, Object>> results = new List<Map<String, Object>>();
            List<Certificate__c> certificatesToInsert = new List<Certificate__c>();
            
            // Get all ETO contact IDs from the CSV
            Set<String> etoContactIds = new Set<String>();
            for (Integer i = 1; i < lines.size(); i++) {
                List<String> values = lines[i].split(',');
                Map<String, String> rowData = new Map<String, String>();
                for (Integer j = 0; j < values.size(); j++) {
                    if (j < headers.size()) {
                        rowData.put(headers[j].trim(), values[j].trim());
                    }
                }
                String etoContactId = rowData.get('eto contact id');
                if (String.isNotBlank(etoContactId)) {
                    etoContactIds.add(etoContactId);
                }
            }
            
            // Query contacts by ETO Contact ID only if needed
            Map<String, Contact> etoContactIdToContactMap = new Map<String, Contact>();
            if (!etoContactIds.isEmpty()) {
                for (Contact contact : [SELECT Id, Name, Participant_ID__c FROM Contact WHERE Participant_ID__c IN :etoContactIds]) {
                    etoContactIdToContactMap.put(contact.Participant_ID__c, contact);
                }
            }
            
            // Process each row
            for (Integer i = 1; i < lines.size(); i++) {
                Map<String, String> rowData = new Map<String, String>();
                try {
                    List<String> values = lines[i].split(',');
                    
                    for (Integer j = 0; j < values.size(); j++) {
                        if (j < headers.size()) {
                            rowData.put(headers[j].trim(), values[j].trim());
                        }
                    }
                    
                    // Validate required fields
                    String sfContactId = rowData.get('sf contact id');
                    String etoContactId = rowData.get('eto contact id');
                    String dateEarned = rowData.get('date earned');
                    String certificateType = rowData.get('certificate type');
                    String certificateId = rowData.get('certificate id');
                    
                    if (String.isBlank(sfContactId) && String.isBlank(etoContactId)) {
                        throw new CertificateException('Either SF Contact ID or ETO Contact ID is required');
                    }
                    
                    if (String.isBlank(dateEarned)) {
                        throw new CertificateException('Date Earned is required');
                    }
                    
                    if (String.isBlank(certificateType)) {
                        throw new CertificateException('Certificate Type is required');
                    }
                    
                    if (String.isBlank(certificateId)) {
                        throw new CertificateException('Certificate ID is required');
                    }
                    
                    // Validate date format
                    Date earnedDate;
                    try {
                        earnedDate = Date.valueOf(dateEarned);
                    } catch (Exception e) {
                        throw new CertificateException('Invalid date format for Date Earned. Use YYYY-MM-DD format');
                    }
                    
                    // Validate expiration date if provided
                    Date expirationDate = null;
                    String expirationDateStr = rowData.get('expiration date');
                    if (String.isNotBlank(expirationDateStr)) {
                        try {
                            expirationDate = Date.valueOf(expirationDateStr);
                        } catch (Exception e) {
                            throw new CertificateException('Invalid date format for Expiration Date. Use YYYY-MM-DD format');
                        }
                    }
                    
                    // Find the contact
                    Id contactId = null;
                    String contactName = '';
                    
                    if (String.isNotBlank(sfContactId)) {
                        // Use SF Contact ID directly - no need to query for name since flow will handle naming
                        contactId = sfContactId;
                    } else {
                        // Use ETO Contact ID
                        Contact contact = etoContactIdToContactMap.get(etoContactId);
                        if (contact == null) {
                            throw new CertificateException('ETO Contact ID not found: ' + etoContactId);
                        }
                        contactId = contact.Id;
                        contactName = contact.Name;
                    }
                    
                    // Create Certificate record (name will be set by flow)
                    Certificate__c certificate = new Certificate__c(
                        Certificate_ID__c = certificateId,
                        Certificate_Type__c = certificateType,
                        Date_Earned__c = earnedDate,
                        Student__c = contactId,
                        Expiration_Date__c = expirationDate
                    );
                    
                    certificatesToInsert.add(certificate);
                    
                    results.add(new Map<String, Object>{
                        'rowNumber' => i,
                        'status' => 'Success',
                        'message' => 'Record validated successfully',
                        'contactId' => contactId,
                        'certificateId' => certificateId,
                        'certificateType' => certificateType,
                        'dateEarned' => earnedDate,
                        'expirationDate' => expirationDate
                    });
                    
                } catch (Exception e) {
                    results.add(new Map<String, Object>{
                        'rowNumber' => i,
                        'status' => 'Error',
                        'message' => e.getMessage(),
                        'contactId' => null,
                        'certificateId' => rowData.get('certificate id'),
                        'certificateType' => rowData.get('certificate type'),
                        'dateEarned' => rowData.get('date earned'),
                        'expirationDate' => rowData.get('expiration date')
                    });
                }
            }
            
            // Insert certificates
            List<Database.SaveResult> certificateInsertResults = new List<Database.SaveResult>();
            if (!certificatesToInsert.isEmpty()) {
                certificateInsertResults = Database.insert(certificatesToInsert, false);
                
                // Update results with certificate IDs
                Integer resultIndex = 0;
                for (Integer i = 0; i < results.size(); i++) {
                    Map<String, Object> result = results[i];
                    if (result.get('status') == 'Success') {
                        if (resultIndex < certificateInsertResults.size()) {
                            Database.SaveResult insertResult = certificateInsertResults[resultIndex];
                            if (insertResult.isSuccess()) {
                                result.put('certificateRecordId', insertResult.getId());
                            } else {
                                result.put('status', 'Error');
                                String errorMessage = 'Certificate creation failed: ';
                                for (Database.Error err : insertResult.getErrors()) {
                                    errorMessage += err.getMessage() + '; ';
                                }
                                result.put('message', errorMessage);
                            }
                            resultIndex++;
                        }
                    }
                }
            }
            
            return results;
        } catch (Exception e) {
            throw new AuraHandledException('Error processing file: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static String downloadResults(String contentVersionId) {
        try {
            // Get the processed results
            List<Map<String, Object>> results = processCSV(contentVersionId);
            
            // Create CSV content with detailed headers
            String csvContent = 'Row Number,Contact ID,Certificate ID,Certificate Type,Date Earned,Expiration Date,Status,Message,Certificate Record ID\n';
            for (Map<String, Object> result : results) {
                csvContent += result.get('rowNumber') + ',' + 
                            escapeCsvField(String.valueOf(result.get('contactId'))) + ',' +
                            escapeCsvField(String.valueOf(result.get('certificateId'))) + ',' +
                            escapeCsvField(String.valueOf(result.get('certificateType'))) + ',' +
                            escapeCsvField(String.valueOf(result.get('dateEarned'))) + ',' +
                            escapeCsvField(String.valueOf(result.get('expirationDate'))) + ',' +
                            escapeCsvField(String.valueOf(result.get('status'))) + ',' +
                            escapeCsvField(String.valueOf(result.get('message'))) + ',' +
                            escapeCsvField(String.valueOf(result.get('certificateRecordId'))) + '\n';
            }
            
            return csvContent;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    private static String escapeCsvField(String field) {
        if (field == null) return '';
        // If the field contains a comma, quote, or newline, wrap it in quotes and escape any existing quotes
        if (field.contains(',') || field.contains('"') || field.contains('\n')) {
            return '"' + field.replace('"', '""') + '"';
        }
        return field;
    }
    
    public class CertificateException extends Exception {}
} 