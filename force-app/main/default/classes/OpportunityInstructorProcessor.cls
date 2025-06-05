public class OpportunityInstructorProcessor {
    public static void processOpportunities(List<Opportunity> opportunities, Map<Id, Opportunity> oldMap) {
        Set<Id> opportunityIds = new Set<Id>();
        for (Opportunity opp : opportunities) {
            opportunityIds.add(opp.Id);
        }

        Map<String, List<Contact>> contactMap = getContactsByEmails(opportunities);
        Map<Id, Map<Integer, OpportunityContactRole>> rolesMap = getOpportunityContactRoles(opportunityIds);

        List<Contact> contactsToUpdate = new List<Contact>();
        List<Contact> contactsToInsert = new List<Contact>();
        List<OpportunityContactRole> rolesToInsert = new List<OpportunityContactRole>();
        List<OpportunityContactRole> rolesToDelete = new List<OpportunityContactRole>();
        List<TempOCR> tempOCRs = new List<TempOCR>();
        Set<String> uniqueContactIdentifiers = new Set<String>();

        for (Opportunity opp : opportunities) {
            Opportunity oldOpp = oldMap != null ? oldMap.get(opp.Id) : null;

            for (Integer i = 1; i <= 10; i++) {
                String firstNameField = 'Instructor_' + i + '_First_Name__c';
                String lastNameField = 'Instructor_' + i + '_Last_Name__c';
                String emailField = 'Instructor_' + i + '_Email__c';
                String phoneField = 'Instructor_' + i + '_Cell_Phone__c';

                String oldFirstName = oldOpp != null ? (String)oldOpp.get(firstNameField) : null;
                String oldLastName = oldOpp != null ? (String)oldOpp.get(lastNameField) : null;
                String oldEmail = oldOpp != null ? (String)oldOpp.get(emailField) : null;

                String newFirstName = (String)opp.get(firstNameField);
                String newLastName = (String)opp.get(lastNameField);
                String newEmail = (String)opp.get(emailField);
                String newPhone = (String)opp.get(phoneField);

                boolean isFirstNameChanged = (newFirstName != oldFirstName);
                boolean isLastNameChanged = (newLastName != oldLastName);
                boolean isEmailChanged = (newEmail != oldEmail);

                // Only proceed if the instructor-specific fields have changed
                if (!(isFirstNameChanged || isLastNameChanged || isEmailChanged)) {
                    continue;
                }

                // Handling various scenarios
                if (oldFirstName == null && oldLastName == null && oldEmail == null) {
                    // Completely net new
                    Contact contact = findContact(contactMap, newFirstName, newLastName, newEmail);
                    if (contact == null) {
                        contact = new Contact(FirstName = newFirstName, LastName = newLastName, Email = newEmail, AccountId = opp.AccountId, RecordTypeId='0128c000001iLxMAAU', HBI_Contact_Type__c='Instructor');
                        contactsToInsert.add(contact);
                        String uniqueIdentifier = newFirstName + '|' + newLastName + '|' + newEmail;
                        tempOCRs.add(new TempOCR(opp.Id, newFirstName, newLastName, newEmail, i));
                        uniqueContactIdentifiers.add(uniqueIdentifier);
                        System.debug('Inserting new contact: ' + contact);
                    } else {
                        OpportunityContactRole role = findOrCreateRole(rolesMap, opp.Id, contact.Id, i);
                        rolesToInsert.add(role);
                        System.debug('Inserting new OCR: ' + role);
                    }
                } else if (newEmail == null && newFirstName == null && newLastName == null) {
                    // All fields were populated and now they are blank
                    OpportunityContactRole roleToRemove = rolesMap.containsKey(opp.Id) ? rolesMap.get(opp.Id).get(i) : null;
                    rolesToDelete.add(roleToRemove);
                    System.debug('Deleting OCR: ' + roleToRemove);
                } else if (isEmailChanged && oldEmail != null && isFirstNameChanged && oldFirstName != null && isLastNameChanged && oldLastName != null) {
                    // First Name, Last Name, Email all change from one person to another
                    system.debug('In changed from one to another');
                    OpportunityContactRole roleToRemove = rolesMap.containsKey(opp.Id) ? rolesMap.get(opp.Id).get(i) : null;
                    system.debug('Role to delete' + roleToRemove);
                    rolesToDelete.add(roleToRemove);
                    Contact contact = findContact(contactMap, newFirstName, newLastName, newEmail);
                    if (contact == null) {
                        system.debug('In contact is null');
                        contact = new Contact(FirstName = newFirstName, LastName = newLastName, Email = newEmail, AccountId = opp.AccountId, Phone = newPhone, RecordTypeId='0128c000001iLxMAAU', HBI_Contact_Type__c='Instructor');
                        contactsToInsert.add(contact);
                        String uniqueIdentifier = newFirstName + '|' + newLastName + '|' + newEmail;
                        tempOCRs.add(new TempOCR(opp.Id, newFirstName, newLastName, newEmail, i));
                        uniqueContactIdentifiers.add(uniqueIdentifier);
                        System.debug('Inserting new contact: ' + contact);
                    } else {
                        OpportunityContactRole role = findOrCreateRole(rolesMap, opp.Id, contact.Id, i);
                        rolesToInsert.add(role);
                        System.debug('Inserting new OCR: ' + role);
                    }
                } else if (!isEmailChanged && isFirstNameChanged && isLastNameChanged) {
                    // First Name and Last Name Change, email stays the same
                    // Look for contact with name and email, remove existing role, create new role
                    system.debug('In last name and first name changed, email the same');
                    OpportunityContactRole roleToRemove = rolesMap.containsKey(opp.Id) ? rolesMap.get(opp.Id).get(i) : null;
                    system.debug('Role to delete' + roleToRemove);
                    rolesToDelete.add(roleToRemove);
                    Contact contact = findContact(contactMap, newFirstName, newLastName, newEmail);
                    if (contact == null) {
                        system.debug('In contact is null');
                        contact = new Contact(FirstName = newFirstName, LastName = newLastName, Email = newEmail, AccountId = opp.AccountId, Phone = newPhone, RecordTypeId='0128c000001iLxMAAU', HBI_Contact_Type__c='Instructor');
                        contactsToInsert.add(contact);
                        String uniqueIdentifier = newFirstName + '|' + newLastName + '|' + newEmail;
                        tempOCRs.add(new TempOCR(opp.Id, newFirstName, newLastName, newEmail, i));
                        uniqueContactIdentifiers.add(uniqueIdentifier);
                        System.debug('Inserting new contact: ' + contact);
                    } else {
                        OpportunityContactRole role = findOrCreateRole(rolesMap, opp.Id, contact.Id, i);
                        rolesToInsert.add(role);
                        System.debug('Inserting new OCR: ' + role);
                    }
                } else if (isEmailChanged && !isFirstNameChanged && !isLastNameChanged) {
                // Email changes, first name and last name the same
                // Get the current contact and update the contact record with the new email`
                Contact contact = findContact(contactMap, newFirstName, newLastName, oldEmail);
                if (contact == null) {
                    system.debug('In contact is null');
                    OpportunityContactRole roleToRemove = rolesMap.containsKey(opp.Id) ? rolesMap.get(opp.Id).get(i) : null;
                    system.debug('Role to delete' + roleToRemove);
                    rolesToDelete.add(roleToRemove);
                    contact = new Contact(FirstName = newFirstName, LastName = newLastName, Email = newEmail, AccountId = opp.AccountId, Phone=newPhone, RecordTypeId='0128c000001iLxMAAU', HBI_Contact_Type__c='Instructor');
                    contactsToInsert.add(contact);
                    String uniqueIdentifier = newFirstName + '|' + newLastName + '|' + newEmail;
                    tempOCRs.add(new TempOCR(opp.Id, newFirstName, newLastName, newEmail, i));
                    uniqueContactIdentifiers.add(uniqueIdentifier);
                    System.debug('Inserting new contact: ' + contact);
                } else {
                    contact.Email = newEmail;
                    contactsToUpdate.add(contact);
                    System.debug('Updating contact');
                }
            }
            }
        }

        // Insert and update contacts
        Map<String, Id> uniqueIdentifierToContactIdMap = new Map<String, Id>();
        if (!contactsToInsert.isEmpty()) {
            insert contactsToInsert;
            for (Contact insertedContact : contactsToInsert) {
                String uniqueIdentifier = insertedContact.FirstName + '|' + insertedContact.LastName + '|' + insertedContact.Email;
                uniqueIdentifierToContactIdMap.put(uniqueIdentifier, insertedContact.Id);
            }

        }

        if (!contactsToUpdate.isEmpty()) {
            update contactsToUpdate;
        }

        for (TempOCR tempOCR : tempOCRs) {
            String uniqueIdentifier = tempOCR.firstName + '|' + tempOCR.lastName + '|' + tempOCR.email;
            Id contactId = uniqueIdentifierToContactIdMap.get(uniqueIdentifier);
            if (contactId != null) {
                OpportunityContactRole role = findOrCreateRole(rolesMap, tempOCR.opportunityId, contactId, tempOCR.instructorNumber);
                rolesToInsert.add(role);
                System.debug('Inserting new OCR with updated contact ID: ' + role);
            }
        }

        // Insert, update, and delete opportunity contact roles
        if (!rolesToInsert.isEmpty()) {
            insert rolesToInsert;
        }

        if (!rolesToDelete.isEmpty()) {
            delete rolesToDelete;
        }
    }

    private static Map<String, List<Contact>> getContactsByEmails(List<Opportunity> opportunities) {
        Set<String> emails = new Set<String>();
    
        // Collect emails from the opportunities
        for (Opportunity opp : opportunities) {
            for (Integer i = 1; i <= 10; i++) {
                String emailField = 'Instructor_' + i + '_Email__c';
                String email = (String)opp.get(emailField);
                if (email != null) {
                    emails.add(email.toLowerCase());
                }
            }
        }
    
        Map<String, List<Contact>> contactMap = new Map<String, List<Contact>>();
        if (!emails.isEmpty()) {
            List<Contact> contacts = [SELECT Id, FirstName, LastName, Email, Phone FROM Contact WHERE Email IN :emails];
            for (Contact contact : contacts) {
                String emailKey = contact.Email.toLowerCase();
                if (!contactMap.containsKey(emailKey)) {
                    contactMap.put(emailKey, new List<Contact>());
                }
                contactMap.get(emailKey).add(contact);
            }
        }
    
        return contactMap;
    }
    

    private static Contact findContact(Map<String, List<Contact>> contactMap, String firstName, String lastName, String email) {
        if (contactMap == null || email == null) {
            return null;
        }
        if (!contactMap.containsKey(email)) {
            return null;
        }
        for (Contact contact : contactMap.get(email)) {
            if (contact.FirstName.equalsIgnoreCase(firstName) && contact.LastName.equalsIgnoreCase(lastName)) {
                return contact;
            }
        }
        return null;
    }

    private static Map<Id, Map<Integer, OpportunityContactRole>> getOpportunityContactRoles(Set<Id> opportunityIds) {
        Map<Id, Map<Integer, OpportunityContactRole>> rolesMap = new Map<Id, Map<Integer, OpportunityContactRole>>();

        List<OpportunityContactRole> roles = [SELECT Id, ContactId, OpportunityId, Instructor_Number__c, Role, IsPrimary FROM OpportunityContactRole WHERE OpportunityId IN :opportunityIds];
        for (OpportunityContactRole role : roles) {
            if (role.Instructor_Number__c != null) {
                Integer instructorNumber = role.Instructor_Number__c.intValue();
                if (!rolesMap.containsKey(role.OpportunityId)) {
                    rolesMap.put(role.OpportunityId, new Map<Integer, OpportunityContactRole>());
                }
                rolesMap.get(role.OpportunityId).put(instructorNumber, role);
            }
        }

        return rolesMap;
    }
    
    private static OpportunityContactRole findOrCreateRole(Map<Id, Map<Integer, OpportunityContactRole>> rolesMap, Id opportunityId, Id contactId, Integer instructorNumber) {
        if (rolesMap.containsKey(opportunityId)) {
            for (OpportunityContactRole role : rolesMap.get(opportunityId).values()) {
                if (role.ContactId == contactId) {
                    role.Instructor_Number__c = instructorNumber;
                    return role;
                }
            }
        }
        return new OpportunityContactRole(OpportunityId = opportunityId, ContactId = contactId, Role = 'Instructor', Instructor_Number__c = instructorNumber);
    }

    private class TempOCR {
        public Id opportunityId;
        public String firstName;
        public String lastName;
        public String email;
        public Integer instructorNumber;
        public TempOCR(Id opportunityId, String firstName, String lastName, String email, Integer instructorNumber) {
            this.opportunityId = opportunityId;
            this.firstName = firstName;
            this.lastName = lastName;
            this.email = email;
            this.instructorNumber = instructorNumber;
        }
    }      
}