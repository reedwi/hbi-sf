public with sharing class EnrollmentImporterController {
    
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
                throw new EnrollmentException('The uploaded file is empty');
            }
            
            List<String> headers = lines[0].split(',');
            if (headers.isEmpty()) {
                throw new EnrollmentException('The uploaded file has no headers');
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
            Map<Id, Contact> contactsToUpdate = new Map<Id, Contact>();
            List<Contact> contactsToInsert = new List<Contact>();
            List<Enrollment__c> enrollmentsToInsert = new List<Enrollment__c>();
            List<Integer> successfulResultIndices = new List<Integer>();  // Track indices of successful results
            
            // Get all program IDs and emails from the CSV
            Set<String> programIds = new Set<String>();
            Set<String> emails = new Set<String>();
            for (Integer i = 1; i < lines.size(); i++) {
                List<String> values = lines[i].split(',');
                Map<String, String> rowData = new Map<String, String>();
                for (Integer j = 0; j < values.size(); j++) {
                    if (j < headers.size()) {
                        rowData.put(headers[j].trim(), values[j].trim());
                    }
                }
                programIds.add(rowData.get('program id'));
                String email = rowData.get('email');
                if (String.isNotBlank(email)) {
                    emails.add(email.toLowerCase());
                }
            }
            
            System.debug(LoggingLevel.INFO, '=== Collected Emails ===');
            System.debug(LoggingLevel.INFO, 'Emails: ' + emails);
            
            // Query programs to get their associated sites and names
            Map<String, Id> programToSiteMap = new Map<String, Id>();
            Map<String, String> programToNameMap = new Map<String, String>();
            Map<String, Id> externalIdToProgramIdMap = new Map<String, Id>();  // New map for external ID to Salesforce ID
            
            // First try to find programs by their Salesforce ID
            Set<String> programIdsToQuery = new Set<String>();
            for (String programId : programIds) {
                if (programId.startsWith('a3E')) {  // Salesforce ID format check
                    programIdsToQuery.add(programId);
                }
            }
            
            // Query programs by Salesforce ID
            for (Program__c program : [SELECT Id, External_Program_ID__c, Site__c, Name 
                                     FROM Program__c 
                                     WHERE Id IN :programIdsToQuery]) {
                programToSiteMap.put(program.Id, program.Site__c);
                programToNameMap.put(program.Id, program.Name);
                // Also map the external ID to the same program
                if (program.External_Program_ID__c != null) {
                    programToSiteMap.put(program.External_Program_ID__c, program.Site__c);
                    programToNameMap.put(program.External_Program_ID__c, program.Name);
                    externalIdToProgramIdMap.put(program.External_Program_ID__c, program.Id);
                }
            }
            
            // Now query programs by External ID for any remaining IDs
            Set<String> remainingProgramIds = new Set<String>();
            for (String programId : programIds) {
                if (!programToSiteMap.containsKey(programId)) {
                    remainingProgramIds.add(programId);
                }
            }
            
            if (!remainingProgramIds.isEmpty()) {
                for (Program__c program : [SELECT Id, External_Program_ID__c, Site__c, Name 
                                         FROM Program__c 
                                         WHERE External_Program_ID__c IN :remainingProgramIds]) {
                    programToSiteMap.put(program.External_Program_ID__c, program.Site__c);
                    programToNameMap.put(program.External_Program_ID__c, program.Name);
                    externalIdToProgramIdMap.put(program.External_Program_ID__c, program.Id);
                    // Also map the Salesforce ID to the same program
                    programToSiteMap.put(program.Id, program.Site__c);
                    programToNameMap.put(program.Id, program.Name);
                }
            }
            
            // Query all potential site schools for the program sites
            Map<Id, List<Licensee_Sites__c>> siteToSiteSchoolsMap = new Map<Id, List<Licensee_Sites__c>>();
            for (Licensee_Sites__c siteSchool : [
                SELECT Id, Account__c, Start_Date__c, End_Date__c, 
                       License_Agreement__r.License_Start_Date__c, 
                       License_Agreement__r.License_End_Date__c
                FROM Licensee_Sites__c 
                WHERE Account__c IN :programToSiteMap.values()
            ]) {
                if (!siteToSiteSchoolsMap.containsKey(siteSchool.Account__c)) {
                    siteToSiteSchoolsMap.put(siteSchool.Account__c, new List<Licensee_Sites__c>());
                }
                siteToSiteSchoolsMap.get(siteSchool.Account__c).add(siteSchool);
            }
            
            System.debug(LoggingLevel.INFO, '=== Program to Site Mapping ===');
            System.debug(LoggingLevel.INFO, 'Mapping: ' + programToSiteMap);
            System.debug(LoggingLevel.INFO, 'Program Names: ' + programToNameMap);
            System.debug(LoggingLevel.INFO, 'Site Schools Map: ' + siteToSiteSchoolsMap);
            
            // Query existing contacts by email
            Map<String, Contact> emailToContactMap = new Map<String, Contact>();
            if (!emails.isEmpty()) {
                for (Contact existingContact : [SELECT Id, Email, FirstName, LastName, Phone, Date_of_Birth__c, 
                                             Ethnicity__c, Gender__c, AccountId, RecordTypeId 
                                             FROM Contact WHERE Email IN :emails]) {
                    if (existingContact.Email != null) {
                        emailToContactMap.put(existingContact.Email.toLowerCase(), existingContact);
                    }
                }
            }
            
            System.debug(LoggingLevel.INFO, '=== Existing Contacts ===');
            System.debug(LoggingLevel.INFO, 'Contact Map: ' + emailToContactMap);
            
            // Query existing enrollments for all relevant students
            Map<String, List<Enrollment__c>> emailToExistingEnrollments = new Map<String, List<Enrollment__c>>();
            if (!emails.isEmpty()) {
                // Get all contacts for these emails
                Map<String, Id> emailToContactId = new Map<String, Id>();
                for (Contact c : emailToContactMap.values()) {
                    emailToContactId.put(c.Email.toLowerCase(), c.Id);
                }
                Set<Id> contactIds = new Set<Id>(emailToContactId.values());
                if (!contactIds.isEmpty()) {
                    for (Enrollment__c enr : [SELECT Id, Student__c, Program__c, Start_Date__c, End_Date__c FROM Enrollment__c WHERE Student__c IN :contactIds]) {
                        // Find the email for this contact
                        String foundEmail = null;
                        for (String em : emailToContactId.keySet()) {
                            if (emailToContactId.get(em) == enr.Student__c) {
                                foundEmail = em;
                                break;
                            }
                        }
                        if (foundEmail != null) {
                            if (!emailToExistingEnrollments.containsKey(foundEmail)) {
                                emailToExistingEnrollments.put(foundEmail, new List<Enrollment__c>());
                            }
                            emailToExistingEnrollments.get(foundEmail).add(enr);
                        }
                    }
                }
            }

            // Track new enrollments in this batch by email
            Map<String, List<Map<String, Object>>> emailToBatchEnrollments = new Map<String, List<Map<String, Object>>>();
            
            // Process each row
            for (Integer i = 1; i < lines.size(); i++) {
                Map<String, String> rowData = new Map<String, String>();
                try {
                    List<String> values = lines[i].split(',');
                    
                    // Debug the current row
                    System.debug(LoggingLevel.DEBUG, '=== Processing Row ' + i + ' ===');
                    System.debug(LoggingLevel.DEBUG, 'Values: ' + values);
                    System.debug(LoggingLevel.DEBUG, 'Headers: ' + headers);
                    
                    for (Integer j = 0; j < values.size(); j++) {
                        if (j < headers.size()) {
                            rowData.put(headers[j].trim(), values[j].trim());
                        }
                    }
                    
                    // Debug the parsed data
                    System.debug(LoggingLevel.DEBUG, 'Parsed Row Data: ' + rowData);
                    
                    // Validate required fields
                    if (String.isBlank(rowData.get('first name')) || 
                        String.isBlank(rowData.get('last name')) || 
                        String.isBlank(rowData.get('email')) || 
                        String.isBlank(rowData.get('program id'))) {
                        throw new EnrollmentException('Missing required fields: first name, last name, email, and program id are required');
                    }
                    
                    // Validate email format
                    String email = rowData.get('email');
                    if (!Pattern.matches('^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$', email)) {
                        throw new EnrollmentException('Invalid email format');
                    }
                    
                    // Apply title case to first and last name
                    String firstName = titleCase(rowData.get('first name'));
                    String lastName = titleCase(rowData.get('last name'));
                    
                    // Get phone (no format validation)
                    String phone = rowData.get('phone');
                    
                    // Get date of birth if provided
                    Date dob = null;
                    if (String.isNotBlank(rowData.get('date of birth'))) {
                        dob = Date.valueOf(rowData.get('date of birth'));
                    }
                    
                    // Get enrollment dates
                    Date startDate = String.isNotBlank(rowData.get('enrollment start date')) ? 
                                             Date.valueOf(rowData.get('enrollment start date')) : 
                                             Date.today();
                    Date endDate = String.isNotBlank(rowData.get('enrollment end date')) ? 
                                 Date.valueOf(rowData.get('enrollment end date')) : null;
                    
                    // Debug the date parsing
                    System.debug(LoggingLevel.INFO, '=== Date Parsing Debug ===');
                    System.debug(LoggingLevel.INFO, 'Raw start date from CSV: ' + rowData.get('enrollment start date'));
                    System.debug(LoggingLevel.INFO, 'Raw end date from CSV: ' + rowData.get('enrollment end date'));
                    System.debug(LoggingLevel.INFO, 'Parsed startDate: ' + startDate);
                    System.debug(LoggingLevel.INFO, 'Parsed endDate: ' + endDate);
                    
                    if (endDate != null && endDate < startDate) {
                        throw new EnrollmentException('End date cannot be before start date');
                    }
                    
                    // Validate gender if provided
                    String gender = rowData.get('gender');
                    if (String.isNotBlank(gender)) {
                        Set<String> validGenders = new Set<String>{
                            'Male', 'Female', 'Non-Binary', 'Prefer Not To Say'
                        };
                        if (!validGenders.contains(gender)) {
                            throw new EnrollmentException('Gender must be one of: Male, Female, Non-Binary, Prefer Not To Say');
                        }
                    }
                    
                    // Validate ethnicity if provided
                    String ethnicity = rowData.get('ethnicity');
                    if (String.isNotBlank(ethnicity)) {
                        Set<String> validEthnicities = new Set<String>{
                            'American Indian or Alaska Native',
                            'Asian',
                            'Black or African American',
                            'Hispanic or Latino',
                            'Multiracial',
                            'Native Hawaiian or Other Pacific Islander',
                            'White',
                            'Prefer not to answer'
                        };
                        if (!validEthnicities.contains(ethnicity)) {
                            throw new EnrollmentException('Ethnicity must be one of: ' + String.join(new List<String>(validEthnicities), ', '));
                        }
                    }
                    
                    // Get the site ID from the program
                    String programId = rowData.get('program id');
                    Id siteId = programToSiteMap.get(programId);
                    if (siteId == null) {
                        throw new EnrollmentException('Invalid program ID or program has no associated site');
                    }
                    
                    // Get the Salesforce Program ID for enrollment creation
                    Id salesforceProgramId;
                    if (programId.startsWith('a3E')) {
                        salesforceProgramId = programId;
                    } else {
                        salesforceProgramId = externalIdToProgramIdMap.get(programId);
                        if (salesforceProgramId == null) {
                            throw new EnrollmentException('Could not find Salesforce Program ID for external ID: ' + programId);
                        }
                    }
                    
                    String emailToLower = email.toLowerCase();
                    Contact existingContact = emailToContactMap.get(emailToLower);
                    
                    System.debug(LoggingLevel.INFO, '=== Contact Lookup ===');
                    System.debug(LoggingLevel.INFO, 'Email: ' + emailToLower);
                    System.debug(LoggingLevel.INFO, 'Found Contact: ' + existingContact);
                    
                    // Get Job Corp ID if the column exists and has a value
                    String jobCorpId = rowData.containsKey('job corp id') ? rowData.get('job corp id') : null;
                    
                    if (existingContact != null) {
                        // Update existing contact
                        existingContact.FirstName = firstName;
                        existingContact.LastName = lastName;
                        if (String.isNotBlank(phone)) existingContact.Phone = phone;
                        if (dob != null) existingContact.Date_of_Birth__c = dob;
                        if (String.isNotBlank(ethnicity)) existingContact.Ethnicity__c = ethnicity;
                        if (String.isNotBlank(gender)) existingContact.Gender__c = gender;
                        if (String.isNotBlank(jobCorpId)) existingContact.Job_Corp_ID__c = jobCorpId;
                        existingContact.RecordTypeId = '0128c000001iIqGAAU';
                        existingContact.AccountId = siteId;
                        contactsToUpdate.put(existingContact.Id, existingContact);
                    } else {
                        // Create new contact
                        Contact newContact = new Contact(
                            FirstName = firstName,
                            LastName = lastName,
                            Email = emailToLower,
                            Phone = phone,
                            Date_of_Birth__c = dob,
                            Ethnicity__c = ethnicity,
                            Gender__c = gender,
                            Job_Corp_ID__c = jobCorpId,
                            RecordTypeId = '0128c000001iIqGAAU',
                            AccountId = siteId
                        );
                        contactsToInsert.add(newContact);
                    }
                    
                    // Create Enrollment
                    String programName = programToNameMap.get(programId);
                    if (programName == null) {
                        throw new EnrollmentException('Program name not found for ID: ' + programId);
                    }
                    
                    String enrollmentName = String.format('{0} {1} - {2} - {3}', 
                        new List<String>{
                            firstName,
                            lastName,
                            programName,
                            String.isNotBlank(rowData.get('enrollment start date')) ? 
                                String.valueOf(rowData.get('enrollment start date')) : 
                                String.valueOf(Date.today())
                        }
                    );
                    
                    // Find matching site school
                    Id siteSchoolId = null;
                    if (siteId != null && siteToSiteSchoolsMap.containsKey(siteId)) {
                        Date enrollmentStartDate = startDate;
                        
                        for (Licensee_Sites__c siteSchool : siteToSiteSchoolsMap.get(siteId)) {
                            // Path 1: Check direct dates on site school
                            if (siteSchool.Start_Date__c != null && siteSchool.End_Date__c != null) {
                                if (enrollmentStartDate >= siteSchool.Start_Date__c && 
                                    enrollmentStartDate <= siteSchool.End_Date__c) {
                                    siteSchoolId = siteSchool.Id;
                                    break;
                                }
                            }
                            // Path 2: Check license agreement dates
                            else if (siteSchool.License_Agreement__r != null && 
                                     siteSchool.License_Agreement__r.License_Start_Date__c != null && 
                                     siteSchool.License_Agreement__r.License_End_Date__c != null) {
                                if (enrollmentStartDate >= siteSchool.License_Agreement__r.License_Start_Date__c && 
                                    enrollmentStartDate <= siteSchool.License_Agreement__r.License_End_Date__c) {
                                    siteSchoolId = siteSchool.Id;
                                    break;
                                }
                            }
                        }
                    }
                    
                    System.debug(LoggingLevel.INFO, '=== Site School Lookup ===');
                    System.debug(LoggingLevel.INFO, 'Enrollment Start Date: ' + rowData.get('enrollment start date'));
                    System.debug(LoggingLevel.INFO, 'Site ID: ' + siteId);
                    System.debug(LoggingLevel.INFO, 'Found Site School ID: ' + siteSchoolId);
                    
                    // --- DEDUPLICATION & OVERLAP CHECKS ---
                    // Gather all enrollments to check: existing (SF) and batch (CSV)
                    List<Enrollment__c> existingEnrollments = emailToExistingEnrollments.containsKey(emailToLower) ? emailToExistingEnrollments.get(emailToLower) : new List<Enrollment__c>();
                    List<Map<String, Object>> batchEnrollments = emailToBatchEnrollments.containsKey(emailToLower) ? emailToBatchEnrollments.get(emailToLower) : new List<Map<String, Object>>();

                    Boolean isDuplicate = false;
                    String duplicateReason = '';

                    // Check against existing enrollments in Salesforce
                    for (Enrollment__c enr : existingEnrollments) {
                        // 1. Exact duplicate: same program, start, end
                        if (enr.Program__c == salesforceProgramId && enr.Start_Date__c == startDate && enr.End_Date__c == endDate) {
                            isDuplicate = true;
                            duplicateReason = 'Exact duplicate enrollment (same program, start date, and end date as an existing enrollment).';
                            break;
                        }
                        // 2. Overlap: date ranges overlap
                        if ((enr.End_Date__c == null || endDate == null || enr.End_Date__c >= startDate) && (endDate == null || enr.Start_Date__c <= endDate)) {
                            isDuplicate = true;
                            duplicateReason = 'Overlapping enrollment (date range overlaps with an existing enrollment).';
                            break;
                        }
                        // 3. Multiple active: only block if both are active (no end date)
                        if (enr.End_Date__c == null && endDate == null) {
                            isDuplicate = true;
                            duplicateReason = 'Multiple active enrollments (an existing enrollment and this one both have no end date).';
                            break;
                        }
                    }
                    // Check against batch enrollments in this CSV
                    for (Map<String, Object> enr : batchEnrollments) {
                        Id batchProgramId = (Id)enr.get('programId');
                        Date batchStart = (Date)enr.get('startDate');
                        Date batchEnd = (Date)enr.get('endDate');
                        // 1. Exact duplicate
                        if (batchProgramId == salesforceProgramId && batchStart == startDate && batchEnd == endDate) {
                            isDuplicate = true;
                            duplicateReason = 'Exact duplicate enrollment in this import batch (same program, start date, and end date).';
                            break;
                        }
                        // 2. Overlap
                        if ((batchEnd == null || endDate == null || batchEnd >= startDate) && (endDate == null || batchStart <= endDate)) {
                            isDuplicate = true;
                            duplicateReason = 'Overlapping enrollment in this import batch (date range overlaps with another enrollment in this file).';
                            break;
                        }
                        // 3. Multiple active: only block if both are active (no end date)
                        if (batchEnd == null && endDate == null) {
                            isDuplicate = true;
                            duplicateReason = 'Multiple active enrollments in this import batch (another enrollment in this file and this one both have no end date).';
                            break;
                        }
                    }
                    if (isDuplicate) {
                        results.add(new Map<String, Object>{
                            'rowNumber' => i,
                            'status' => 'Error',
                            'message' => duplicateReason,
                            'firstName' => firstName,
                            'lastName' => lastName,
                            'email' => email,
                            'contactId' => null,
                            'enrollmentId' => null,
                            'originalProgramId' => rowData.get('program id'),
                            'programName' => programToNameMap.get(rowData.get('program id'))
                        });
                        continue;
                    }
                    // Add this enrollment to the batch tracker for future rows
                    Map<String, Object> batchEnr = new Map<String, Object>{
                        'programId' => salesforceProgramId,
                        'startDate' => startDate,
                        'endDate' => endDate
                    };
                    if (!emailToBatchEnrollments.containsKey(emailToLower)) {
                        emailToBatchEnrollments.put(emailToLower, new List<Map<String, Object>>());
                    }
                    emailToBatchEnrollments.get(emailToLower).add(batchEnr);
                    
                    Enrollment__c enrollment = new Enrollment__c(
                        Name = enrollmentName,
                        Student__c = null, // Will be set after contact operations
                        Program__c = salesforceProgramId, // Use the Salesforce Program ID here
                        Start_Date__c = startDate,
                        End_Date__c = endDate,
                        Dismissal_Reason__c = rowData.get('dismissal reason'),
                        Site_Site_School__c = siteSchoolId // Set the site school if found
                    );
                    enrollmentsToInsert.add(enrollment);
                    
                    results.add(new Map<String, Object>{
                        'rowNumber' => i,
                        'status' => 'Success',
                        'message' => 'Record validated successfully',
                        'firstName' => firstName,
                        'lastName' => lastName,
                        'email' => email,
                        'contactId' => null, // Will be set after DML
                        'enrollmentId' => null, // Will be set after DML
                        'compositeKey' => email + '|' + salesforceProgramId, // Store the composite key
                        'programId' => salesforceProgramId, // Store the Salesforce Program ID
                        'originalProgramId' => rowData.get('program id'),
                        'programName' => programToNameMap.get(rowData.get('program id')),
                        'startDate' => startDate,
                        'endDate' => endDate,
                        'dismissalReason' => rowData.get('dismissal reason')
                    });
                    
                } catch (Exception e) {
                    // Debug the error
                    System.debug(LoggingLevel.ERROR, '=== Error in Row ' + i + ' ===');
                    System.debug(LoggingLevel.ERROR, 'Error Message: ' + e.getMessage());
                    System.debug(LoggingLevel.ERROR, 'Row Data: ' + rowData);
                    
                    results.add(new Map<String, Object>{
                        'rowNumber' => i,
                        'status' => 'Error',
                        'message' => e.getMessage(),
                        'firstName' => rowData.get('first name'),
                        'lastName' => rowData.get('last name'),
                        'email' => rowData.get('email'),
                        'contactId' => null,
                        'enrollmentId' => null,
                        'originalProgramId' => rowData.get('program id'),
                        'programName' => programToNameMap.get(rowData.get('program id'))
                    });
                }
            }
            
            // Perform DML operations
            List<Database.SaveResult> contactUpdateResults = new List<Database.SaveResult>();
            List<Database.SaveResult> contactInsertResults = new List<Database.SaveResult>();
            List<Database.SaveResult> enrollmentInsertResults = new List<Database.SaveResult>();
            
            if (!contactsToUpdate.isEmpty()) {
                contactUpdateResults = Database.update(contactsToUpdate.values(), false);
            }
            if (!contactsToInsert.isEmpty()) {
                contactInsertResults = Database.insert(contactsToInsert, false);
            }
            
            // Create a map of composite keys to contact IDs
            Map<String, Id> compositeKeyToContactIdMap = new Map<String, Id>();
            
            // Add existing contact IDs
            for (Contact existingContact : emailToContactMap.values()) {
                for (String programId : programIds) {
                    // Use the Salesforce Program ID for the composite key
                    Id salesforceProgramId;
                    if (programId.startsWith('a3E')) {
                        salesforceProgramId = programId;
                    } else {
                        salesforceProgramId = externalIdToProgramIdMap.get(programId);
                    }
                    if (salesforceProgramId != null) {
                        String compositeKey = existingContact.Email.toLowerCase() + '|' + salesforceProgramId;
                        compositeKeyToContactIdMap.put(compositeKey, existingContact.Id);
                    }
                }
            }
            
            // Add new contact IDs
            for (Integer i = 0; i < contactsToInsert.size(); i++) {
                if (contactInsertResults[i].isSuccess()) {
                    Contact newContact = contactsToInsert[i];
                    for (String programId : programIds) {
                        // Use the Salesforce Program ID for the composite key
                        Id salesforceProgramId;
                        if (programId.startsWith('a3E')) {
                            salesforceProgramId = programId;
                        } else {
                            salesforceProgramId = externalIdToProgramIdMap.get(programId);
                        }
                        if (salesforceProgramId != null) {
                            String compositeKey = newContact.Email.toLowerCase() + '|' + salesforceProgramId;
                            compositeKeyToContactIdMap.put(compositeKey, contactInsertResults[i].getId());
                        }
                    }
                }
            }
            
            // Update enrollments with contact IDs and create proper names
            System.debug(LoggingLevel.INFO, '=== Starting Enrollment Processing ===');
            System.debug(LoggingLevel.INFO, 'Total Enrollments to Insert: ' + enrollmentsToInsert.size());
            System.debug(LoggingLevel.INFO, 'Composite Key Map: ' + compositeKeyToContactIdMap);
            
            // Create a map of composite keys to enrollments
            Map<String, Enrollment__c> compositeKeyToEnrollment = new Map<String, Enrollment__c>();
            
            // First, create all enrollments and map them by composite key
            for (Integer i = 0; i < results.size(); i++) {
                Map<String, Object> result = results[i];
                if (result.get('status') == 'Success') {
                    String email = result.get('email').toString().toLowerCase();
                    Id programId = (Id)result.get('programId');
                    String compositeKey = email + '|' + programId;
                    
                    // Get contact ID
                    Id contactId = compositeKeyToContactIdMap.get(compositeKey);
                    if (contactId != null) {
                        // Get the stored dates from the results map
                        Date startDate = (Date)result.get('startDate');
                        Date endDate = (Date)result.get('endDate');
                        String dismissalReason = (String)result.get('dismissalReason');
                        
                        // Debug the date retrieval
                        System.debug(LoggingLevel.INFO, '=== Enrollment Creation Debug ===');
                        System.debug(LoggingLevel.INFO, 'Email: ' + email);
                        System.debug(LoggingLevel.INFO, 'Retrieved startDate from results: ' + startDate);
                        System.debug(LoggingLevel.INFO, 'Retrieved endDate from results: ' + endDate);
                        
                        Enrollment__c enrollment = new Enrollment__c(
                            Name = String.format('{0} {1} - {2} - {3}', 
                                new List<String>{
                                    String.valueOf(result.get('firstName')),
                                    String.valueOf(result.get('lastName')),
                                    programToNameMap.get(programId),
                                    String.format('{0}/{1}', 
                                        new List<String>{
                                            String.valueOf(startDate.month()).leftPad(2, '0'),
                                            String.valueOf(startDate.year())
                                        }
                                    )
                                }
                            ),
                            Student__c = contactId,
                            Program__c = programId,
                            Start_Date__c = startDate,
                            End_Date__c = endDate,
                            Dismissal_Reason__c = dismissalReason
                        );
                        
                        // Find matching site school
                        Id siteId = programToSiteMap.get(programId);
                        if (siteId != null && siteToSiteSchoolsMap.containsKey(siteId)) {
                            Date enrollmentStartDate = enrollment.Start_Date__c;
                            
                            for (Licensee_Sites__c siteSchool : siteToSiteSchoolsMap.get(siteId)) {
                                // Path 1: Check direct dates on site school
                                if (siteSchool.Start_Date__c != null && siteSchool.End_Date__c != null) {
                                    if (enrollmentStartDate >= siteSchool.Start_Date__c && 
                                        enrollmentStartDate <= siteSchool.End_Date__c) {
                                        enrollment.Site_Site_School__c = siteSchool.Id;
                                        break;
                                    }
                                }
                                // Path 2: Check license agreement dates
                                else if (siteSchool.License_Agreement__r != null && 
                                         siteSchool.License_Agreement__r.License_Start_Date__c != null && 
                                         siteSchool.License_Agreement__r.License_End_Date__c != null) {
                                    if (enrollmentStartDate >= siteSchool.License_Agreement__r.License_Start_Date__c && 
                                        enrollmentStartDate <= siteSchool.License_Agreement__r.License_End_Date__c) {
                                        enrollment.Site_Site_School__c = siteSchool.Id;
                                        break;
                                    }
                                }
                            }
                        }
                        
                        compositeKeyToEnrollment.put(compositeKey, enrollment);
                    }
                }
            }
            
            // Insert all enrollments
            if (!compositeKeyToEnrollment.isEmpty()) {
                System.debug(LoggingLevel.INFO, '=== Inserting Enrollments ===');
                List<Enrollment__c> enrollmentRecordsToInsert = compositeKeyToEnrollment.values();
                enrollmentInsertResults = Database.insert(enrollmentRecordsToInsert, false);
                
                // Map enrollment results to their composite keys
                Map<String, Database.SaveResult> compositeKeyToEnrollmentResult = new Map<String, Database.SaveResult>();
                Integer resultIndex = 0;
                for (String compositeKey : compositeKeyToEnrollment.keySet()) {
                    if (resultIndex < enrollmentInsertResults.size()) {
                        compositeKeyToEnrollmentResult.put(compositeKey, enrollmentInsertResults[resultIndex]);
                        resultIndex++;
                    }
                }
                
                // Update results with enrollment IDs
                for (Integer i = 0; i < results.size(); i++) {
                    Map<String, Object> result = results[i];
                    if (result.get('status') == 'Success') {
                        String email = result.get('email').toString().toLowerCase();
                        Id programId = (Id)result.get('programId');
                        String compositeKey = email + '|' + programId;
                        
                        Database.SaveResult enrollmentResult = compositeKeyToEnrollmentResult.get(compositeKey);
                        if (enrollmentResult != null) {
                            if (enrollmentResult.isSuccess()) {
                                result.put('enrollmentId', enrollmentResult.getId());
                            } else {
                                result.put('status', 'Error');
                                String errorMessage = 'Enrollment operation failed: ';
                                for (Database.Error err : enrollmentResult.getErrors()) {
                                    errorMessage += err.getMessage() + '; ';
                                }
                                result.put('message', errorMessage);
                            }
                        }
                    }
                }
            }
            
            return results;
        } catch (Exception e) {
            // Get the stack trace
            String stackTrace = e.getStackTraceString();
            
            // Get the line number where the error occurred
            Integer lineNumber = e.getLineNumber();
            
            // Get the type of exception
            String exceptionType = e.getTypeName();
            
            // Create a detailed error message
            String detailedMessage = String.format(
                'Error Type: {0}\nLine Number: {1}\nMessage: {2}\nStack Trace: {3}',
                new List<String>{
                    exceptionType,
                    String.valueOf(lineNumber),
                    e.getMessage(),
                    stackTrace
                }
            );
            
            // Log the error details
            System.debug(LoggingLevel.ERROR, '=== Error Details ===');
            System.debug(LoggingLevel.ERROR, detailedMessage);
            
            // Throw a more detailed error
            throw new AuraHandledException(detailedMessage);
        }
    }
    
    @AuraEnabled
    public static String downloadResults(String contentVersionId) {
        try {
            // Get the processed results
            List<Map<String, Object>> results = processCSV(contentVersionId);
            
            // Create CSV content with detailed headers
            String csvContent = 'Row Number,First Name,Last Name,Email,Program ID,Program Name,Status,Message,Contact ID,Enrollment ID\n';
            for (Map<String, Object> result : results) {
                csvContent += result.get('rowNumber') + ',' + 
                            escapeCsvField(String.valueOf(result.get('firstName'))) + ',' +
                            escapeCsvField(String.valueOf(result.get('lastName'))) + ',' +
                            escapeCsvField(String.valueOf(result.get('email'))) + ',' +
                            escapeCsvField(String.valueOf(result.get('originalProgramId'))) + ',' +
                            escapeCsvField(String.valueOf(result.get('programName'))) + ',' +
                            escapeCsvField(String.valueOf(result.get('status'))) + ',' +
                            escapeCsvField(String.valueOf(result.get('message'))) + ',' +
                            escapeCsvField(String.valueOf(result.get('contactId'))) + ',' +
                            escapeCsvField(String.valueOf(result.get('enrollmentId'))) + '\n';
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
    
    // Helper method for title case
    private static String titleCase(String input) {
        if (String.isBlank(input)) return input;
        
        String[] words = input.toLowerCase().split(' ');
        for (Integer i = 0; i < words.size(); i++) {
            if (String.isNotBlank(words[i])) {
                words[i] = words[i].substring(0, 1).toUpperCase() + 
                          (words[i].length() > 1 ? words[i].substring(1) : '');
            }
        }
        return String.join(words, ' ');
    }
    
    public class EnrollmentException extends Exception {}
} 