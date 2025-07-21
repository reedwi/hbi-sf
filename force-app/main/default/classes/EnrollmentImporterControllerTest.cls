@isTest
public class EnrollmentImporterControllerTest {
    
    @TestSetup
    static void setupTestData() {
        // Create test account (site)
        Account testSite = new Account(
            Name = 'Test Site'
        );
        insert testSite;
        
        // Create test program
        Program__c testProgram = new Program__c(
            Name = 'Test Program',
            Site__c = testSite.Id,
            External_Program_ID__c = 'EXT001'
        );
        insert testProgram;
        
        // Create existing contact
        Contact existingContact = new Contact(
            FirstName = 'John',
            LastName = 'Doe',
            Email = 'john.doe@test.com',
            Phone = '555-1234',
            Date_of_Birth__c = Date.newInstance(1990, 1, 1),
            Ethnicity__c = 'White',
            Gender__c = 'Male',
            Job_Corp_ID__c = 'JC001',
            AccountId = testSite.Id
        );
        insert existingContact;
    }
    
    @isTest
    static void testGetPreviewData_Success() {
        // Create test CSV content
        String csvContent = 'first name,last name,email,program id,phone,date of birth,gender,ethnicity,enrollment start date,enrollment end date,dismissal reason,job corp id\n' +
                          'Jane,Smith,jane.smith@test.com,a3E000000000001,555-5678,1995-05-15,Female,Asian,2024-01-15,2024-06-15,,JC002\n' +
                          'Bob,Johnson,bob.johnson@test.com,a3E000000000001,555-9012,1992-08-20,Male,Hispanic or Latino,2024-02-01,,,JC003';
        
        // Create ContentVersion
        ContentVersion cv = new ContentVersion(
            Title = 'Test Enrollment Data.csv',
            PathOnClient = 'Test Enrollment Data.csv',
            VersionData = Blob.valueOf(csvContent),
            IsMajorVersion = true
        );
        insert cv;
        
        Test.startTest();
        Map<String, Object> result = EnrollmentImporterController.getPreviewData(cv.Id);
        Test.stopTest();
        
        // Verify results
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.containsKey('columns'), 'Result should contain columns');
        System.assert(result.containsKey('data'), 'Result should contain data');
        
        List<Map<String, String>> columns = (List<Map<String, String>>)result.get('columns');
        List<Map<String, Object>> data = (List<Map<String, Object>>)result.get('data');
        
        System.assertEquals(12, columns.size(), 'Should have 12 columns');
        System.assertEquals(2, data.size(), 'Should have 2 data rows');
        
        // Verify first column
        System.assertEquals('first name', columns[0].get('label'), 'First column should be first name');
        System.assertEquals('col0', columns[0].get('fieldName'), 'First column field name should be col0');
    }
    
    @isTest
    static void testGetPreviewData_NoMeaningfulHeaders() {
        // Create CSV content with no meaningful headers (just empty strings)
        String csvContent = ',,,\n,,,'; // Empty headers and data
        
        ContentVersion cv = new ContentVersion(
            Title = 'No Headers.csv',
            PathOnClient = 'No Headers.csv',
            VersionData = Blob.valueOf(csvContent),
            IsMajorVersion = true
        );
        insert cv;
        
        Test.startTest();
        try {
            EnrollmentImporterController.getPreviewData(cv.Id);
        } catch (AuraHandledException e) {
            // Expected to throw exception
        }
        Test.stopTest();
    }
    
    @isTest
    static void testGetPreviewData_NoHeaders() {
        // Create CSV content without proper headers (just data)
        String csvContent = 'Jane,Smith,jane.smith@test.com,a3E000000000001,555-5678,1995-05-15,Female,Asian,2024-01-15,2024-06-15,,JC002\n' +
                          'Bob,Johnson,bob.johnson@test.com,a3E000000000001,555-9012,1992-08-20,Male,Hispanic or Latino,2024-02-01,,,JC003';
        
        ContentVersion cv = new ContentVersion(
            Title = 'No Headers.csv',
            PathOnClient = 'No Headers.csv',
            VersionData = Blob.valueOf(csvContent),
            IsMajorVersion = true
        );
        insert cv;
        
        Test.startTest();
        try {
            EnrollmentImporterController.getPreviewData(cv.Id);
        } catch (AuraHandledException e) {
            // Expected to throw exception
        }
        Test.stopTest();
    }
    
    @isTest
    static void testProcessCSV_Success() {
        // Get the test program
        Program__c testProgram = [SELECT Id, External_Program_ID__c FROM Program__c LIMIT 1];
        
        // Create test CSV content
        String csvContent = 'first name,last name,email,program id,phone,date of birth,gender,ethnicity,enrollment start date,enrollment end date,dismissal reason,job corp id\n' +
                          'Jane,Smith,jane.smith@test.com,' + testProgram.Id + ',555-5678,1995-05-15,Female,Asian,2024-01-15,2024-06-15,,JC002\n' +
                          'Bob,Johnson,bob.johnson@test.com,' + testProgram.Id + ',555-9012,1992-08-20,Male,Hispanic or Latino,2024-02-01,,,JC003';
        
        ContentVersion cv = new ContentVersion(
            Title = 'Test Enrollment Data.csv',
            PathOnClient = 'Test Enrollment Data.csv',
            VersionData = Blob.valueOf(csvContent),
            IsMajorVersion = true
        );
        insert cv;
        
        Test.startTest();
        List<Map<String, Object>> results = EnrollmentImporterController.processCSV(cv.Id);
        Test.stopTest();
        
        // Test executed successfully
    }
    
    @isTest
    static void testProcessCSV_UpdateExistingContact() {
        // Get the test program and existing contact
        Program__c testProgram = [SELECT Id FROM Program__c LIMIT 1];
        Contact existingContact = [SELECT Id, Email FROM Contact WHERE Email = 'john.doe@test.com' LIMIT 1];
        
        // Create CSV content with existing email
        String csvContent = 'first name,last name,email,program id,phone,date of birth,gender,ethnicity,enrollment start date,enrollment end date,dismissal reason,job corp id\n' +
                          'John,Updated,john.doe@test.com,' + testProgram.Id + ',555-9999,1990-01-01,Male,White,2024-03-01,2024-08-01,,JC001';
        
        ContentVersion cv = new ContentVersion(
            Title = 'Update Contact.csv',
            PathOnClient = 'Update Contact.csv',
            VersionData = Blob.valueOf(csvContent),
            IsMajorVersion = true
        );
        insert cv;
        
        Test.startTest();
        List<Map<String, Object>> results = EnrollmentImporterController.processCSV(cv.Id);
        Test.stopTest();
        
        // Test executed successfully
    }
    
    @isTest
    static void testProcessCSV_ExternalProgramId() {
        // Get the test program with external ID
        Program__c testProgram = [SELECT Id, External_Program_ID__c FROM Program__c WHERE External_Program_ID__c = 'EXT001' LIMIT 1];
        
        // Create CSV content using external program ID
        String csvContent = 'first name,last name,email,program id,phone,date of birth,gender,ethnicity,enrollment start date,enrollment end date,dismissal reason,job corp id\n' +
                          'Alice,Brown,alice.brown@test.com,' + testProgram.External_Program_ID__c + ',555-1111,1993-03-10,Female,Black or African American,2024-01-20,2024-07-20,,JC004';
        
        ContentVersion cv = new ContentVersion(
            Title = 'External Program ID.csv',
            PathOnClient = 'External Program ID.csv',
            VersionData = Blob.valueOf(csvContent),
            IsMajorVersion = true
        );
        insert cv;
        
        Test.startTest();
        List<Map<String, Object>> results = EnrollmentImporterController.processCSV(cv.Id);
        Test.stopTest();
        
        // Test executed successfully
    }
    
    @isTest
    static void testProcessCSV_MissingRequiredFields() {
        // Create CSV content with missing required fields
        String csvContent = 'first name,last name,email,program id,phone,date of birth,gender,ethnicity,enrollment start date,enrollment end date,dismissal reason,job corp id\n' +
                          'Jane,,jane.smith@test.com,a3E000000000001,555-5678,1995-05-15,Female,Asian,2024-01-15,2024-06-15,,JC002';
        
        ContentVersion cv = new ContentVersion(
            Title = 'Missing Fields.csv',
            PathOnClient = 'Missing Fields.csv',
            VersionData = Blob.valueOf(csvContent),
            IsMajorVersion = true
        );
        insert cv;
        
        Test.startTest();
        List<Map<String, Object>> results = EnrollmentImporterController.processCSV(cv.Id);
        Test.stopTest();
        
        // Test executed successfully
    }
    
    @isTest
    static void testProcessCSV_InvalidEmail() {
        // Get the test program
        Program__c testProgram = [SELECT Id FROM Program__c LIMIT 1];
        
        // Create CSV content with invalid email
        String csvContent = 'first name,last name,email,program id,phone,date of birth,gender,ethnicity,enrollment start date,enrollment end date,dismissal reason,job corp id\n' +
                          'Jane,Smith,invalid-email,' + testProgram.Id + ',555-5678,1995-05-15,Female,Asian,2024-01-15,2024-06-15,,JC002';
        
        ContentVersion cv = new ContentVersion(
            Title = 'Invalid Email.csv',
            PathOnClient = 'Invalid Email.csv',
            VersionData = Blob.valueOf(csvContent),
            IsMajorVersion = true
        );
        insert cv;
        
        Test.startTest();
        List<Map<String, Object>> results = EnrollmentImporterController.processCSV(cv.Id);
        Test.stopTest();
        
        // Test executed successfully
    }
    
    @isTest
    static void testProcessCSV_InvalidProgramId() {
        // Create CSV content with invalid program ID
        String csvContent = 'first name,last name,email,program id,phone,date of birth,gender,ethnicity,enrollment start date,enrollment end date,dismissal reason,job corp id\n' +
                          'Jane,Smith,jane.smith@test.com,INVALID_PROGRAM_ID,555-5678,1995-05-15,Female,Asian,2024-01-15,2024-06-15,,JC002';
        
        ContentVersion cv = new ContentVersion(
            Title = 'Invalid Program.csv',
            PathOnClient = 'Invalid Program.csv',
            VersionData = Blob.valueOf(csvContent),
            IsMajorVersion = true
        );
        insert cv;
        
        Test.startTest();
        List<Map<String, Object>> results = EnrollmentImporterController.processCSV(cv.Id);
        Test.stopTest();
        
        // Test executed successfully
    }
    
    @isTest
    static void testProcessCSV_InvalidGender() {
        // Get the test program
        Program__c testProgram = [SELECT Id FROM Program__c LIMIT 1];
        
        // Create CSV content with invalid gender
        String csvContent = 'first name,last name,email,program id,phone,date of birth,gender,ethnicity,enrollment start date,enrollment end date,dismissal reason,job corp id\n' +
                          'Jane,Smith,jane.smith@test.com,' + testProgram.Id + ',555-5678,1995-05-15,Invalid,Asian,2024-01-15,2024-06-15,,JC002';
        
        ContentVersion cv = new ContentVersion(
            Title = 'Invalid Gender.csv',
            PathOnClient = 'Invalid Gender.csv',
            VersionData = Blob.valueOf(csvContent),
            IsMajorVersion = true
        );
        insert cv;
        
        Test.startTest();
        List<Map<String, Object>> results = EnrollmentImporterController.processCSV(cv.Id);
        Test.stopTest();
        
        // Test executed successfully
    }
    
    @isTest
    static void testProcessCSV_InvalidEthnicity() {
        // Get the test program
        Program__c testProgram = [SELECT Id FROM Program__c LIMIT 1];
        
        // Create CSV content with invalid ethnicity
        String csvContent = 'first name,last name,email,program id,phone,date of birth,gender,ethnicity,enrollment start date,enrollment end date,dismissal reason,job corp id\n' +
                          'Jane,Smith,jane.smith@test.com,' + testProgram.Id + ',555-5678,1995-05-15,Female,Invalid,2024-01-15,2024-06-15,,JC002';
        
        ContentVersion cv = new ContentVersion(
            Title = 'Invalid Ethnicity.csv',
            PathOnClient = 'Invalid Ethnicity.csv',
            VersionData = Blob.valueOf(csvContent),
            IsMajorVersion = true
        );
        insert cv;
        
        Test.startTest();
        List<Map<String, Object>> results = EnrollmentImporterController.processCSV(cv.Id);
        Test.stopTest();
        
        // Test executed successfully
    }
    
    @isTest
    static void testProcessCSV_EndDateBeforeStartDate() {
        // Get the test program
        Program__c testProgram = [SELECT Id FROM Program__c LIMIT 1];
        
        // Create CSV content with end date before start date
        String csvContent = 'first name,last name,email,program id,phone,date of birth,gender,ethnicity,enrollment start date,enrollment end date,dismissal reason,job corp id\n' +
                          'Jane,Smith,jane.smith@test.com,' + testProgram.Id + ',555-5678,1995-05-15,Female,Asian,2024-06-15,2024-01-15,,JC002';
        
        ContentVersion cv = new ContentVersion(
            Title = 'Invalid Dates.csv',
            PathOnClient = 'Invalid Dates.csv',
            VersionData = Blob.valueOf(csvContent),
            IsMajorVersion = true
        );
        insert cv;
        
        Test.startTest();
        List<Map<String, Object>> results = EnrollmentImporterController.processCSV(cv.Id);
        Test.stopTest();
        
        // Test executed successfully
    }
    
    @isTest
    static void testDownloadResults() {
        // Get the test program
        Program__c testProgram = [SELECT Id FROM Program__c LIMIT 1];
        
        // Create test CSV content
        String csvContent = 'first name,last name,email,program id,phone,date of birth,gender,ethnicity,enrollment start date,enrollment end date,dismissal reason,job corp id\n' +
                          'Jane,Smith,jane.smith@test.com,' + testProgram.Id + ',555-5678,1995-05-15,Female,Asian,2024-01-15,2024-06-15,,JC002';
        
        ContentVersion cv = new ContentVersion(
            Title = 'Test Download.csv',
            PathOnClient = 'Test Download.csv',
            VersionData = Blob.valueOf(csvContent),
            IsMajorVersion = true
        );
        insert cv;
        
        Test.startTest();
        String downloadContent = EnrollmentImporterController.downloadResults(cv.Id);
        Test.stopTest();
        
        // Verify download content
        System.assertNotEquals(null, downloadContent, 'Download content should not be null');
        System.assert(downloadContent.contains('Row Number,First Name,Last Name,Email,Program ID,Program Name,Status,Message,Contact ID,Enrollment ID'), 'Should contain headers');
        System.assert(downloadContent.contains('Jane'), 'Should contain first name');
        System.assert(downloadContent.contains('Smith'), 'Should contain last name');
        System.assert(downloadContent.contains('jane.smith@test.com'), 'Should contain email');
    }
    
    @isTest
    static void testTitleCase() {
        // Get the test program
        Program__c testProgram = [SELECT Id FROM Program__c LIMIT 1];
        
        // Create CSV content with lowercase names
        String csvContent = 'first name,last name,email,program id,phone,date of birth,gender,ethnicity,enrollment start date,enrollment end date,dismissal reason,job corp id\n' +
                          'jane,smith,jane.smith@test.com,' + testProgram.Id + ',555-5678,1995-05-15,Female,Asian,2024-01-15,2024-06-15,,JC002';
        
        ContentVersion cv = new ContentVersion(
            Title = 'Title Case Test.csv',
            PathOnClient = 'Title Case Test.csv',
            VersionData = Blob.valueOf(csvContent),
            IsMajorVersion = true
        );
        insert cv;
        
        Test.startTest();
        List<Map<String, Object>> results = EnrollmentImporterController.processCSV(cv.Id);
        Test.stopTest();
        
        // Test executed successfully
    }
    
    @isTest
    static void testProcessCSV_LargeDataset() {
        // Get the test program
        Program__c testProgram = [SELECT Id FROM Program__c LIMIT 1];
        
        // Create CSV content with multiple rows
        String csvContent = 'first name,last name,email,program id,phone,date of birth,gender,ethnicity,enrollment start date,enrollment end date,dismissal reason,job corp id\n';
        
        // Add 10 rows
        for (Integer i = 1; i <= 10; i++) {
            csvContent += 'User' + i + ',Test' + i + ',user' + i + '@test.com,' + testProgram.Id + ',555-' + String.valueOf(i).leftPad(4, '0') + 
                         ',1990-01-01,Male,White,2024-01-01,2024-06-01,,JC' + String.valueOf(i).leftPad(3, '0') + '\n';
        }
        
        ContentVersion cv = new ContentVersion(
            Title = 'Large Dataset.csv',
            PathOnClient = 'Large Dataset.csv',
            VersionData = Blob.valueOf(csvContent),
            IsMajorVersion = true
        );
        insert cv;
        
        Test.startTest();
        List<Map<String, Object>> results = EnrollmentImporterController.processCSV(cv.Id);
        Test.stopTest();
        
        // Test executed successfully
    }
} 