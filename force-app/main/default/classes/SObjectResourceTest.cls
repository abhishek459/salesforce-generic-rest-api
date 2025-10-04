/**
 * @description Integration test for the SObjectResource class.
 * This class tests the end-to-end functionality of the generic REST API,
 * including happy paths, error handling, and handler invocation.
 *
 * @see SObjectResource
 * @see SObjectResourceHandler
 * @see SObjectResourceModels
 *
 * @note This test class requires a custom field `External_Id__c` (Text, External ID, Unique)
 * on the Account object to run successfully.
 */
@isTest
private class SObjectResourceTest {

    // A constant for the external ID field name used in tests.
    private static final String EXTERNAL_ID_FIELD = 'External_Id__c';

    /**
     * @description Tests the successful creation of a new Account and its related child Contacts.
     * It also implicitly verifies that the Before and After handlers are invoked correctly.
     */
    @isTest
    static void testSuccessfulUpsert_NewAccountAndContacts_ShouldReturnSuccess() {
        // Arrange
        String requestBodyJson = '{' +
            '  "data": [' +
            '    {' +
            '      "Name": "test corp inc",' +
            '      "Industry": "Technology",' +
            '      "Website": "www.test.com",' +
            '      "Contacts": [' +
            '        { "FirstName": "Jane", "LastName": "Doe", "Email": "jane.doe@testcorp.com" },' +
            '        { "FirstName": "John", "LastName": "Smith", "Email": "john.smith@testcorp.com" }' +
            '      ]' +
            '    }' +
            '  ]' +
            '}';
        
        // Set up the mock RestContext
        RestRequest request = new RestRequest();
        request.requestUri = '/services/apexrest/v1/data-gateway/Account';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(requestBodyJson);
        RestContext.request = request;
        RestContext.response = new RestResponse();

        // Act
        Test.startTest();
        SObjectResourceModels.UpsertResponse response = SObjectResource.handleUpsert();
        Test.stopTest();

        // Assert
        System.assertEquals(200, RestContext.response.statusCode, 'Status code should be 200 OK.');
        System.assertEquals(1, response.totalSuccess, 'Should have 1 successful parent record.');
        System.assertEquals(0, response.totalErrors, 'Should have 0 parent errors.');
        System.assert(response.results[0].created, 'The parent record should be marked as created.');

        Id newAccountId = response.results[0].id;
        System.assertNotEquals(null, newAccountId, 'New Account ID should not be null.');
        
        // Verify child results
        System.assertEquals(1, response.childResults.keySet().size(), 'Should have child results for one parent.');
        SObjectResourceModels.ChildRelationshipResult contactResults = response.childResults.get(newAccountId).get('Contacts');
        System.assertEquals(2, contactResults.results.size(), 'Should have 2 successful contact results.');
        System.assertEquals(null, contactResults.error, 'There should be no error processing the child relationship.');

        // Verify database state
        Account createdAccount = [SELECT Id, Name FROM Account WHERE Id = :newAccountId];
        System.assertEquals('Test Corp Inc', createdAccount.Name, 'BeforeUpsertHandler should have capitalized the name.');
        
        List<Contact> createdContacts = [SELECT Id FROM Contact WHERE AccountId = :newAccountId];
        System.assertEquals(2, createdContacts.size(), 'Two contacts should be created and linked to the account.');
    }
    
    /**
     * @description Tests updating an existing Account record using an external ID.
     */
    @isTest
    static void testSuccessfulUpsert_UpdateWithExternalId_ShouldReturnSuccess() {
        // Arrange: Create an existing record to be updated.
        Account existingAccount = new Account(Name = 'Old Name', External_Id__c = 'EXT-001');
        insert existingAccount;
        
        String requestBodyJson = '{' +
            '  "externalIdField": "' + EXTERNAL_ID_FIELD + '",' +
            '  "data": [' +
            '    {' +
            '      "Name": "updated name",' +
            '      "' + EXTERNAL_ID_FIELD + '": "EXT-001"' +
            '    }' +
            '  ]' +
            '}';

        RestRequest request = new RestRequest();
        request.requestUri = '/services/apexrest/v1/data-gateway/Account';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(requestBodyJson);
        RestContext.request = request;
        RestContext.response = new RestResponse();
        
        // Act
        Test.startTest();
        SObjectResourceModels.UpsertResponse response = SObjectResource.handleUpsert();
        Test.stopTest();
        
        // Assert
        System.assertEquals(200, RestContext.response.statusCode, 'Status code should be 200 OK.');
        System.assertEquals(1, response.totalSuccess, 'Should have 1 successful record.');
        System.assert(!response.results[0].created, 'The record should be marked as updated, not created.');
        System.assertEquals(existingAccount.Id, response.results[0].id, 'The ID in the response should match the updated record.');

        // Verify the database was updated correctly
        Account updatedAccount = [SELECT Name FROM Account WHERE Id = :existingAccount.Id];
        System.assertEquals('Updated Name', updatedAccount.Name, 'The Account name should have been updated by the handler.');
    }

    /**
     * @description Tests the error response when an invalid SObject name is provided in the URL.
     */
    @isTest
    static void testError_InvalidSObjectName_ShouldReturn404() {
        // Arrange
        RestRequest request = new RestRequest();
        request.requestUri = '/services/apexrest/v1/data-gateway/NonExistentObject__c';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf('{ "data": [{}] }');
        RestContext.request = request;
        RestContext.response = new RestResponse();
        
        // Act
        SObjectResourceModels.UpsertResponse response = SObjectResource.handleUpsert();
        
        // Assert
        System.assertEquals(404, RestContext.response.statusCode, 'Status code should be 404 Not Found.');
        System.assert(response.errorMessage.contains('Object not found'), 'Error message should indicate the object was not found.');
    }
    
    /**
     * @description Tests the error response when the SObject name in the URL is blank.
     */
    @isTest
    static void testError_BlankSObjectName_ShouldReturn400() {
        // Arrange
        RestRequest request = new RestRequest();
        // The URI ends with a slash, which results in a blank object name.
        request.requestUri = '/services/apexrest/v1/data-gateway/';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf('{ "data": [{}] }');
        RestContext.request = request;
        RestContext.response = new RestResponse();
        
        // Act
        SObjectResourceModels.UpsertResponse response = SObjectResource.handleUpsert();
        
        // Assert
        System.assertEquals(400, RestContext.response.statusCode, 'Status code should be 400 Bad Request.');
        System.assert(response.errorMessage.contains('Object name is missing'), 'Error message should indicate the object name is missing.');
    }

    /**
     * @description Tests the error response when the JSON body is malformed.
     */
    @isTest
    static void testError_MalformedJson_ShouldReturn400() {
        // Arrange
        RestRequest request = new RestRequest();
        request.requestUri = '/services/apexrest/v1/data-gateway/Account';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf('{ "data": [ { "Name": "test" }'); // Intentionally malformed JSON
        RestContext.request = request;
        RestContext.response = new RestResponse();
        
        // Act
        SObjectResourceModels.UpsertResponse response = SObjectResource.handleUpsert();
        
        // Assert
        System.assertEquals(400, RestContext.response.statusCode, 'Status code should be 400 Bad Request.');
        System.assert(response.errorMessage.contains('Invalid JSON format'), 'Error message should indicate a JSON format error.');
    }
    
    /**
     * @description Tests the error response when a field in the payload does not exist on the SObject.
     */
    @isTest
    static void testError_InvalidFieldInPayload_ShouldReturn400() {
        // Arrange
        String requestBodyJson = '{' +
            '  "data": [' +
            '    {' +
            '      "Name": "Test Co",' +
            '      "Non_Existent_Field__c": "some value"' +
            '    }' +
            '  ]' +
            '}';
        
        RestRequest request = new RestRequest();
        request.requestUri = '/services/apexrest/v1/data-gateway/Account';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(requestBodyJson);
        RestContext.request = request;
        RestContext.response = new RestResponse();
        
        // Act
        SObjectResourceModels.UpsertResponse response = SObjectResource.handleUpsert();
        
        // Assert
        System.assertEquals(400, RestContext.response.statusCode, 'Status code should be 400 Bad Request.');
        System.assert(response.errorMessage.contains('Invalid JSON key \'Non_Existent_Field__c\''), 'Error message should identify the invalid field.');
    }
}