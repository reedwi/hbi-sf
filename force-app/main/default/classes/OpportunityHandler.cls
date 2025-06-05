public class OpportunityHandler {
    private static final String TARGET_RECORD_TYPE_ID = '0128c000002FLIaAAO'; // Replace with the actual record type ID

    public static void afterInsertUpdate(List<Opportunity> newOpportunities, Map<Id, Opportunity> oldMap) {
        // Filter opportunities by record type
        List<Opportunity> instructorOpps = instructorCheck(newOpportunities, oldMap);
        List<Opportunity> siteOpps = siteCheck(newOpportunities, oldMap);
        
        if (!instructorOpps.isEmpty()) {
            OpportunityInstructorProcessor.processOpportunities(instructorOpps, oldMap);
        }
        if (!siteOpps.isEmpty()) {
            OpportunitySiteProcessor.processOpportunities(siteOpps, oldMap);
        }
    }

    private static List<Opportunity> instructorCheck(List<Opportunity> newOpportunities, Map<Id, Opportunity> oldMap) {
        List<Opportunity> filteredOpportunities = new List<Opportunity>();
        List<Opportunity> opportunitiesToProcess = new List<Opportunity>();
        for (Opportunity opp : newOpportunities) {
            Opportunity oldOpp = oldMap != null ? oldMap.get(opp.Id) : null;
            Datetime oldTimestamp = oldOpp != null ? (Datetime)oldOpp.get('Instructor_Writing_Process__c') : null;
            Datetime newTimestamp = (Datetime)opp.get('Instructor_Writing_Process__c');
            boolean isTimestampChanged = (newTimestamp != oldTimestamp);

            if (isTimestampChanged) {
                continue;
            }

            if (opp.RecordTypeId == TARGET_RECORD_TYPE_ID ) {
                filteredOpportunities.add(opp);
            }
        }

        if (filteredOpportunities.isEmpty()) {
            return opportunitiesToProcess; // No opportunities to process
        }

        // Filter opportunities to process only changed instructor fields
        for (Opportunity opp : filteredOpportunities) {
            Opportunity oldOpp = oldMap != null ? oldMap.get(opp.Id) : null;
            for (Integer i = 1; i <= 10; i++) {
                String firstNameField = 'Instructor_' + i + '_First_Name__c';
                String lastNameField = 'Instructor_' + i + '_Last_Name__c';
                String emailField = 'Instructor_' + i + '_Email__c';

                String oldFirstName = oldOpp != null ? (String)oldOpp.get(firstNameField) : null;
                String oldLastName = oldOpp != null ? (String)oldOpp.get(lastNameField) : null;
                String oldEmail = oldOpp != null ? (String)oldOpp.get(emailField) : null;

                String newFirstName = (String)opp.get(firstNameField);
                String newLastName = (String)opp.get(lastNameField);
                String newEmail = (String)opp.get(emailField);

                // Only add if the instructor fields have changed
                if ((newFirstName != oldFirstName) || (newLastName != oldLastName) || (newEmail != oldEmail)) {
                    opportunitiesToProcess.add(opp);
                    break;
                }
            }
        }
        return opportunitiesToProcess;    
    }
    private static List<Opportunity> siteCheck(List<Opportunity> newOpportunities, Map<Id, Opportunity> oldMap) {
        List<Opportunity> filteredOpportunities = new List<Opportunity>();
        List<Opportunity> opportunitiesToProcess = new List<Opportunity>();
        for (Opportunity opp : newOpportunities) {
            Opportunity oldOpp = oldMap != null ? oldMap.get(opp.Id) : null;
            Datetime oldTimestamp = oldOpp != null ? (Datetime)oldOpp.get('Site_Writing_Process__c') : null;
            Datetime newTimestamp = (Datetime)opp.get('Site_Writing_Process__c');
            boolean isTimestampChanged = (newTimestamp != oldTimestamp);

            if (isTimestampChanged) {
                continue;
            }

            if (opp.RecordTypeId == TARGET_RECORD_TYPE_ID ) {
                filteredOpportunities.add(opp);
            }
        }

        if (filteredOpportunities.isEmpty()) {
            return opportunitiesToProcess; // No opportunities to process
        }

        // Filter opportunities to process only changed instructor fields
        for (Opportunity opp : filteredOpportunities) {
            Opportunity oldOpp = oldMap != null ? oldMap.get(opp.Id) : null;
            for (Integer i = 1; i <= 10; i++) {
                String addressField = 'Site_' + i + '_Address__c';
                String nameField = 'Site_' + i + '_Name__c';
                String streetField = 'Site_' + i + '_Address__Street__s';
                String cityField = 'Site_' + i + '_Address__City__s';
                String stateField = 'Site_' + i + '_Address__StateCode__s';
                String zipField = 'Site_' + i + '_Address__PostalCode__s';

                Address oldAddress = oldOpp != null ? (Address)oldOpp.get(addressField) : null;
                String oldStreet = oldOpp != null ? (String)oldOpp.get(streetField) : null;
                String oldCity = oldOpp != null ? (String)oldOpp.get(cityField) : null;
                String oldState = oldOpp != null ? (String)oldOpp.get(stateField) : null;
                String oldZip = oldOpp != null ? (String)oldOpp.get(zipField) : null;

                String oldName = oldOpp != null ? (String)oldOpp.get(nameField) : null;

                // Address newAddress = (Address)opp.get(addressField);
                String newName = (String)opp.get(nameField);
                String newStreet = (String)opp.get(streetField);
                String newCity = (String)opp.get(cityField);
                String newState = (String)opp.get(stateField);
                String newZip = (String)opp.get(zipField);

                boolean isAddressChanged = 
                    (newStreet != oldStreet) || 
                    (newCity != oldCity) || 
                    (newState != oldState) || 
                    (newZip != oldZip);


                boolean isNameChanged = (newName != oldName);

                // Only add if the instructor fields have changed
                if (isAddressChanged || isNameChanged) {
                    opportunitiesToProcess.add(opp);
                    break;
                }
            }
        }
        return opportunitiesToProcess;
    }
}