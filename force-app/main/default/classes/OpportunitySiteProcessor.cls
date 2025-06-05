public with sharing class OpportunitySiteProcessor {
    public static void processOpportunities(List<Opportunity> opportunities, Map<Id, Opportunity> oldMap) {
        Set<Id> opportunityIds = new Set<Id>();
        for (Opportunity opp : opportunities) {
            opportunityIds.add(opp.Id);
        }

        RecordType fbaType = [
            SELECT Id FROM RecordType 
            WHERE SObjectType = 'Account' 
            AND DeveloperName = 'FBA_Partners'
            LIMIT 1
        ];

        Map<String, List<Account>> accountMap = getAccountsByName(opportunities, fbaType.id);
        Map<Id, Map<Integer, Licensee_Sites__c>> sitesMap = getSitesSchools(opportunityIds);

        List<Account> accountsToUpdate = new List<Account>();
        List<Account> accountsToInsert = new List<Account>();
        List<Licensee_Sites__c> sitesToInsert = new List<Licensee_Sites__c>();
        List<Licensee_Sites__c> sitesToDelete = new List<Licensee_Sites__c>();
        List<TempSite> tempSites = new List<TempSite>();
        Set<String> uniqueAccountIdentifiers = new Set<String>();


        for (Opportunity opp : opportunities) {
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

                boolean isOldAddressNull = (oldStreet == null && oldCity == null && oldState == null && oldZip == null);
                boolean isAddressChanged = 
                    (newStreet != oldStreet) || 
                    (newCity != oldCity) || 
                    (newState != oldState) || 
                    (newZip != oldZip);


                boolean isNameChanged = (newName != oldName);
                boolean isNewAddressNull = (newStreet == null && newCity == null && newState == null && newZip == null);


                // Only proceed if the instructor-specific fields have changed
                if (!(isNameChanged || isAddressChanged)) {
                    continue;
                }
                system.debug('In the loop');
                // system.debug('Is old address null?' + isOldAddressNull);
                // Completely Net New Population of Fields
                if (oldName == null && isOldAddressNull) {
                    // Completely net new
                    Account account = findAccount(accountMap, newName);
                    if (account == null) {
                        account = new Account(
                            Name = newName, 
                            BillingStreet = newStreet, 
                            BillingCity = newCity, 
                            BillingStateCode = newState,
                            BillingPostalCode = newZip,
                            ParentId = opp.AccountId, 
                            RecordTypeId=fbaType.id, 
                            Account_Type__c='Site'
                        );
                        accountsToInsert.add(account);
                        String uniqueIdentifier = newName + '|' + newStreet;
                        tempSites.add(new TempSite(opp.Id, newName, newStreet, i));
                        uniqueAccountIdentifiers.add(uniqueIdentifier);
                        System.debug('Inserting new account: ' + account);
                    } else {
                        Licensee_Sites__c site = findOrCreateSite(sitesMap, opp.Id, account.Id, account.Name, i);
                        sitesToInsert.add(site);
                        account.BillingStreet = newStreet;
                        account.BillingStateCode = newState;
                        account.BillingCity = newCity;
                        account.BillingPostalCode = newZip;
                        accountsToUpdate.add(account);
                        System.debug('Inserting new OCR: ' + site);
                    }
                } else if (newName == null && isNewAddressNull) {
                    // All fields were populated and now they are blank
                    Licensee_Sites__c siteToRemove = sitesMap.containsKey(opp.Id) ? sitesMap.get(opp.Id).get(i) : null;
                    sitesToDelete.add(siteToRemove);
                    System.debug('Deleting Site: ' + siteToRemove);
                } else if (isAddressChanged && isNameChanged) {
                    // Address changed
                    system.debug('In changed from one to another');
                    Licensee_Sites__c siteToRemove = sitesMap.containsKey(opp.Id) ? sitesMap.get(opp.Id).get(i) : null;
                    system.debug('Site to delete' + siteToRemove);
                    sitesToDelete.add(siteToRemove);
                    Account account = findAccount(accountMap, newName);
                    if (account == null) {
                        account = new Account(
                            Name = newName, 
                            BillingStreet = newStreet, 
                            BillingCity = newCity, 
                            BillingStateCode = newState,
                            BillingPostalCode = newZip,
                            ParentId = opp.AccountId, 
                            RecordTypeId=fbaType.id, 
                            Account_Type__c='Site'
                        );
                        accountsToInsert.add(account);
                        String uniqueIdentifier = newName + '|' + newStreet;
                        tempSites.add(new TempSite(opp.Id, newName, newStreet, i));
                        uniqueAccountIdentifiers.add(uniqueIdentifier);
                        System.debug('Inserting new account: ' + account);
                    } else {
                        Licensee_Sites__c site = findOrCreateSite(sitesMap, opp.Id, account.Id, account.Name, i);
                        sitesToInsert.add(site);
                        account.BillingStreet = newStreet;
                        account.BillingStateCode = newState;
                        account.BillingCity = newCity;
                        account.BillingPostalCode = newZip;
                        accountsToUpdate.add(account);
                        System.debug('Inserting new site: ' + site);
                    }
                } else if (isAddressChanged) {
                    Account account = findAccount(accountMap, newName);
                    if (account == null) {
                        // system.debug('In contact is null');
                        // Licensee_Sites__c siteToRemove = sitesMap.containsKey(opp.Id) ? sitesMap.get(opp.Id).get(i) : null;
                        // system.debug('Site to delete' + siteToRemove);
                        // sitesToDelete.add(siteToRemove);
                        // account = new Account(
                        //     Name = newName, 
                        //     BillingStreet = newStreet, 
                        //     BillingCity = newCity, 
                        //     BillingStateCode = newState,
                        //     BillingPostalCode = newZip,
                        //     ParentId = opp.AccountId, 
                        //     RecordTypeId=fbaType.id, 
                        //     Account_Type__c='Site'
                        // );
                        // accountsToInsert.add(account);
                        // String uniqueIdentifier = newName + '|' + newAddress;
                        // tempSites.add(new TempSite(opp.Id, newName, newStreet, i));
                        // uniqueAccountIdentifiers.add(uniqueIdentifier);
                        System.debug('An account should be found');
                    } else {
                        account.BillingStreet = newStreet;
                        account.BillingStateCode = newState;
                        account.BillingCity = newCity;
                        account.BillingPostalCode = newZip;
                        accountsToUpdate.add(account);
                        System.debug('Updating account');
                    }
                } else if (isNameChanged) {
                    // Email changes, first name and last name the same
                    // Get the current contact and update the contact record with the new email`
                    Account oldAccount = findAccount(accountMap, oldName);
                    if (oldAccount == null) {
                        Licensee_Sites__c siteToRemove = sitesMap.containsKey(opp.Id) ? sitesMap.get(opp.Id).get(i) : null;
                        system.debug('Site to delete' + siteToRemove);
                        sitesToDelete.add(siteToRemove);
                    }
                    Account account  = findAccount(accountMap, newName);
                    if (account == null) {
                        account = new Account(
                            Name = newName, 
                            BillingStreet = newStreet, 
                            BillingCity = newCity, 
                            BillingStateCode = newState,
                            BillingPostalCode = newZip,
                            ParentId = opp.AccountId, 
                            RecordTypeId=fbaType.id, 
                            Account_Type__c='Site'
                        );
                        accountsToInsert.add(account);
                        String uniqueIdentifier = newName + '|' + newStreet;
                        tempSites.add(new TempSite(opp.Id, newName, newStreet, i));
                        uniqueAccountIdentifiers.add(uniqueIdentifier);
                        System.debug('Inserting new account: ' + account);
                    } else {
                        Licensee_Sites__c site = findOrCreateSite(sitesMap, opp.Id, account.Id, account.Name, i);
                        sitesToInsert.add(site);
                        account.BillingStreet = newStreet;
                        account.BillingStateCode = newState;
                        account.BillingCity = newCity;
                        account.BillingPostalCode = newZip;
                        accountsToUpdate.add(account);
                        System.debug('Inserting new site: ' + site);
                    }
                }
            }
        }
        // Insert and update contacts
        Map<String, Id> uniqueIdentifierToAccountIdMap = new Map<String, Id>();
        if (!accountsToInsert.isEmpty()) {
            insert accountsToInsert;
            for (Account insertedAccount : accountsToInsert) {
                String uniqueIdentifier = insertedAccount.Name + '|' + insertedAccount.BillingStreet;
                uniqueIdentifierToAccountIdMap.put(uniqueIdentifier, insertedAccount.Id);
            }

        }

        if (!accountsToUpdate.isEmpty()) {
            update accountsToUpdate;
        }

        for (TempSite tempSite : tempSites) {
            String uniqueIdentifier = tempSite.name + '|' + tempSite.street;
            Id accountId = uniqueIdentifierToAccountIdMap.get(uniqueIdentifier);
            if (accountId != null) {
                Licensee_Sites__c site = findOrCreateSite(sitesMap, tempSite.opportunityId, accountId, tempSite.name, tempSite.siteNumber);
                sitesToInsert.add(site);
                System.debug('Inserting new site with updated account ID: ' + site);
            }
        }

        // Insert, update, and delete opportunity contact roles
        if (!sitesToInsert.isEmpty()) {
            insert sitesToInsert;
        }

        if (!sitesToDelete.isEmpty()) {
            delete sitesToDelete;
        }

    }

    private static Map<String, List<Account>> getAccountsByName(List<Opportunity> opportunities, Id rtId) {
        Set<String> names = new Set<String>();
    
        // Collect emails from the opportunities
        for (Opportunity opp : opportunities) {
            for (Integer i = 1; i <= 10; i++) {
                String nameField = 'Site_' + i + '_Name__c';
                String name = (String)opp.get(nameField);
                if (name != null && name != '') {
                    names.add(name.toLowerCase());
                }
            }
        }
    
        Map<String, List<Account>> accountMap = new Map<String, List<Account>>();
        if (!names.isEmpty()) {
            List<Account> accounts = [SELECT Id, Name, BillingStreet, BillingCity, BillingState, BillingPostalCode FROM Account WHERE Name IN :names and RecordTypeId = :rtId];
            for (Account account : accounts) {
                String nameKey = account.Name.toLowerCase();
                if (!accountMap.containsKey(nameKey)) {
                    accountMap.put(nameKey, new List<Account>());
                }
                accountMap.get(nameKey).add(account);
            }
        }
    
        return accountMap;
    }

    private static Map<Id, Map<Integer, Licensee_Sites__c>> getSitesSchools(Set<Id> opportunityIds) {
        Map<Id, Map<Integer, Licensee_Sites__c>> sitesMap = new Map<Id, Map<Integer, Licensee_Sites__c>>();

        List<Licensee_Sites__c> sites = [SELECT Id, Name, Account__c, License_Agreement__c, Site_School_Number__c FROM Licensee_Sites__c WHERE License_Agreement__c IN :opportunityIds];
        for (Licensee_Sites__c site : sites) {
            if (site.Site_School_Number__c != null) {
                Integer siteNumber = site.Site_School_Number__c.intValue();
                if (!sitesMap.containsKey(site.License_Agreement__c)) {
                    sitesMap.put(site.License_Agreement__c, new Map<Integer, Licensee_Sites__c>());
                }
                sitesMap.get(site.License_Agreement__c).put(siteNumber, site);
            }
        }

        return sitesMap;
    }

    private static Account findAccount(Map<String, List<Account>> accountMap, String name) {
        // Add null checks
        if (accountMap == null || name == null) {
            return null;
        }
        
        String nameLower = name.toLowerCase();
        if (!accountMap.containsKey(nameLower)) {
            return null;
        }
        
        List<Account> accounts = accountMap.get(nameLower);
        return !accounts.isEmpty() ? accounts[0] : null;
    }

    private static Licensee_Sites__c findOrCreateSite(Map<Id, Map<Integer, Licensee_Sites__c>> sitesMap, Id opportunityId, Id accountId, String name, Integer siteNumber) {
        if (sitesMap.containsKey(opportunityId)) {
            for (Licensee_Sites__c site : sitesMap.get(opportunityId).values()) {
                if (site.Account__c == accountId) {
                    site.Site_School_Number__c = siteNumber;
                    return site;
                }
            }
        }
        return new Licensee_Sites__c(
            License_Agreement__c = opportunityId, 
            Account__c = accountId, 
            Name = name, 
            Site_School_Number__c = siteNumber
        );
    }

    private class TempSite {
        public Id opportunityId;
        public String name;
        public String street;
        public Integer siteNumber;
        public TempSite(Id opportunityId, String name, String street, Integer siteNumber) {
            this.opportunityId = opportunityId;
            this.name = name;
            this.street = street;
            this.siteNumber = siteNumber;
        }
    }  
}