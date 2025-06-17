public class TestDataGenerator {
    
    // Utility method to generate fake email
    private static String generateFakeEmail(Integer num) {
        return 'fake.contact' + num + '@fake.com';
    }
    
    // Account Generator
    public static List<Account> createAccounts(Integer count, Id recordTypeId, Map<String, Object> fields) {
        List<Account> accounts = new List<Account>();
        
        for(Integer i = 0; i < count; i++) {
            Account acc = new Account(
                Name = 'Fake Company ' + i,
                RecordTypeId = recordTypeId
            );
            
            // Apply custom fields if provided
            if(fields != null) {
                for(String field : fields.keySet()) {
                    acc.put(field, fields.get(field));
                }
            }
            
            accounts.add(acc);
        }
        
        insert accounts;
        return accounts;
    }
    
    // Contact Generator
    public static List<Contact> createContacts(Integer count, List<Account> accounts, Id recordTypeId, Map<String, Object> fields) {
        List<Contact> contacts = new List<Contact>();
        
        for(Integer i = 0; i < count; i++) {
            // Rotate through accounts if provided
            Account relatedAccount = accounts != null && !accounts.isEmpty() ? 
                                   accounts[Math.mod(i, accounts.size())] : null;
            
            Contact con = new Contact(
                FirstName = 'Fake',
                LastName = 'Contact ' + i,
                Email = generateFakeEmail(i),
                AccountId = relatedAccount?.Id,
                RecordTypeId = recordTypeId
            );
            
            // Apply custom fields if provided
            if(fields != null) {
                for(String field : fields.keySet()) {
                    con.put(field, fields.get(field));
                }
            }
            
            contacts.add(con);
        }
        
        insert contacts;
        return contacts;
    }
    
    // Opportunity Generator
    public static List<Opportunity> createOpportunities(Integer count, List<Account> accounts, Id recordTypeId, Map<String, Object> fields) {
        List<Opportunity> opportunities = new List<Opportunity>();
        
        for(Integer i = 0; i < count; i++) {
            // Rotate through accounts if provided
            Account relatedAccount = accounts != null && !accounts.isEmpty() ? 
                                   accounts[Math.mod(i, accounts.size())] : null;
            
            Opportunity opp = new Opportunity(
                Name = 'Fake Opportunity ' + i,
                AccountId = relatedAccount?.Id,
                CloseDate = Date.today().addDays(30),
                StageName = 'Prospecting',
                RecordTypeId = recordTypeId
            );
            
            // Apply custom fields if provided
            if(fields != null) {
                for(String field : fields.keySet()) {
                    opp.put(field, fields.get(field));
                }
            }
            
            opportunities.add(opp);
        }
        
        insert opportunities;
        return opportunities;
    }
    
    // Opportunity Contact Role Generator
    public static List<OpportunityContactRole> createOpportunityContactRoles(
        List<Opportunity> opportunities, 
        Integer rolesPerOpp,
        String role
    ) {
        List<OpportunityContactRole> roles = new List<OpportunityContactRole>();
        
        // First, get all related accounts
        Set<Id> accountIds = new Set<Id>();
        for(Opportunity opp : opportunities) {
            if(opp.AccountId != null) {
                accountIds.add(opp.AccountId);
            }
        }
        
        // Query for related contacts
        Map<Id, List<Contact>> accountToContactsMap = new Map<Id, List<Contact>>();
        for(Contact con : [SELECT Id, AccountId FROM Contact WHERE AccountId IN :accountIds]) {
            if(!accountToContactsMap.containsKey(con.AccountId)) {
                accountToContactsMap.put(con.AccountId, new List<Contact>());
            }
            accountToContactsMap.get(con.AccountId).add(con);
        }
        
        // Create roles
        for(Opportunity opp : opportunities) {
            if(opp.AccountId != null && accountToContactsMap.containsKey(opp.AccountId)) {
                List<Contact> availableContacts = accountToContactsMap.get(opp.AccountId);
                
                for(Integer i = 0; i < Math.min(rolesPerOpp, availableContacts.size()); i++) {
                    OpportunityContactRole ocr = new OpportunityContactRole(
                        OpportunityId = opp.Id,
                        ContactId = availableContacts[i].Id,
                        Role = role
                    );
                    roles.add(ocr);
                }
            }
        }
        
        if(!roles.isEmpty()) {
            insert roles;
        }
        return roles;
    }
    
    // Example usage method
    public static void generateSampleData() {
        // Create Accounts with custom fields
        // Account Record Types
        Id fbaPartnerRecordTypeId = '012Ro0000019EftIAE';
        Id organizationRecordTypeId = '0128c000001s9amAAA';

        // Contact Record Types
        Id standardContactRecordTypeId = '0128c000001iLxMAAU';
        Id studentRecordTypeId = '0128c000001iIqGAAU';

        // Opportunity Record Types
        Id licenseAgreementRecordTypeId = '0128c000002FLIaAAO';


        // Map<String, Object> accountFields = new Map<String, Object>{
        //     'BillingStreet' => '123 Fake St',
        //     'BillingCity' => 'Fake City',
        //     'BillingState' => 'CA',
        //     'BillingPostalCode' => '94105',
        //     'Phone' => '(555) 555-5555'
        // };
        Map<String, Object> accountFields = new Map<String, Object>{};
        List<Account> accounts = createAccounts(5, fbaPartnerRecordTypeId, accountFields);
        
        // Create Contacts with custom fields
        // Map<String, Object> contactFields = new Map<String, Object>{
        //     'Phone' => '(555) 555-5555',
        //     'Title' => 'Executive'
        // };
        Map<String, Object> contactFields = new Map<String, Object>{};
        List<Contact> contacts = createContacts(10, accounts, standardContactRecordTypeId, contactFields);
        
        // Create Opportunities with custom fields
        // Map<String, Object> opportunityFields = new Map<String, Object>{
        //     'Amount' => 10000,
        //     'Type' => 'New Business'
        // };
        Map<String, Object> opportunityFields = new Map<String, Object>{};
        List<Opportunity> opportunities = createOpportunities(5, accounts, licenseAgreementRecordTypeId, opportunityFields);
        
        // Create Opportunity Contact Roles
        List<OpportunityContactRole> roles = createOpportunityContactRoles(
            opportunities,
            2,  // roles per opportunity
            'Instructor'
        );
    }
}