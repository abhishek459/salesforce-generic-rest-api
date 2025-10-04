/**
 * @description Provides a generic REST API endpoint for upserting SObject records,
 * including their related child records, in a single transaction. It dynamically
 * handles any SObject specified in the URL. This class acts as the main controller,
 * orchestrating the validation, processing, and DML operations.
 *
 * @author      Abhishek Thulasi <abhishekthulasi.work@gmail.com>
 * @date        October 4, 2025
 * @version     1.0.0
 *
 * @example
 * To upsert Account records with related Contacts:
 *
 * Endpoint: POST /services/apexrest/v1/data-gateway/Account
 *
 * Headers:
 * Authorization: Bearer [Your_Access_Token]
 * Content-Type: application/json

 * Body:
{
  "externalIdField": "External_Id__c",
  "data": [
    {
      "Name": "Global Tech Innovations Ltd.",
      "Industry": "Technology",
      "BillingCity": "San Francisco",
      "External_Id__c": "GTI-001",
      "Contacts": [
        {
          "FirstName": "Abhishek",
          "LastName": "Thulasi",
          "Email": "abhishek.thulasi@globaltech-example.com",
          "Title": "Software Architect"
        }
      ],
      "Opportunities": [
        {
          "Name": "GTI - Q4 Enterprise Cloud Platform",
          "StageName": "Prospecting",
          "CloseDate": "2025-12-20",
          "Amount": 150000
        },
        {
          "Name": "GTI - 2026 Global Support Contract",
          "StageName": "Needs Analysis",
          "CloseDate": "2026-01-31",
          "Amount": 45000
        }
      ]
    }
  ]
}
*/
@RestResource(urlMapping='/v1/data-gateway/*')
global with sharing class SObjectResource {
    // =================================================================================
    // == HTTP POST Method Handler
    // =================================================================================
    @HttpPost
    global static SObjectResourceModels.UpsertResponse handleUpsert() {
        RestRequest request = RestContext.request;
        RestResponse response = RestContext.response;
        String objectName = request.requestURI.substringAfterLast('/');
        
        try {
            if (String.isBlank(objectName)) {
                response.statusCode = 400; // Bad Request
                return new SObjectResourceModels.UpsertResponse(
                    'Object name is missing in the request URI.'
                );
            }
            
            // --- 1. Validate SObject Type and Permissions ---
            Schema.SObjectType sobjectType = Schema.getGlobalDescribe()
                .get(objectName);
            if (sobjectType == null) {
                response.statusCode = 404; // Not Found
                return new SObjectResourceModels.UpsertResponse(
                    'Object not found: ' + objectName
                );
            }
            Schema.DescribeSObjectResult describeResult = sobjectType.getDescribe();
            if (!describeResult.isUpdateable() || !describeResult.isCreateable()) {
                response.statusCode = 403; // Forbidden
                return new SObjectResourceModels.UpsertResponse(
                    'User lacks create or update permission for object: ' + objectName
                );
            }
            
            // --- 2. Parse and Validate Request Body ---
            // Delegate to a helper class to keep this method focused on orchestration.
            SObjectResourceModels.UpsertRequest upsertRequest = SObjectResourceHandler.parseAndValidateRequest(
                request
            );
            
            System.debug(' upsertRequest: ' + upsertRequest);
            
            // --- 3. Prepare for DML Operation ---
            // Build a map of valid child relationships for efficient lookup later.
            Map<String, Schema.ChildRelationship> childRelationshipsMap = new Map<String, Schema.ChildRelationship>();
            for (
                Schema.ChildRelationship cr : describeResult.getChildRelationships()
            ) {
                if (cr.getRelationshipName() != null) {
                    childRelationshipsMap.put(cr.getRelationshipName().toLowerCase(), cr);
                }
            }
            
            // Delegate parent record preparation and field validation to the helper.
            List<SObject> recordsToProcess = SObjectResourceHandler.prepareAndValidateParentRecords(
                objectName,
                describeResult,
                upsertRequest,
                childRelationshipsMap
            );
            
            System.debug(
                ' recordsToProcess: ' + JSON.serialize(recordsToProcess, true)
            );
            
            // --- 4. Invoke Before-Upsert Handler (Dynamic Logic Injection) ---
            // This allows for custom, object-specific business logic to be injected before the DML operation.
            IBeforeUpsertHandler beforeUpsertHandler = BeforeUpsertHandlerFactory.getHandler(
                objectName
            );
            if (beforeUpsertHandler != null) {
                recordsToProcess = beforeUpsertHandler.beforeUpsert(recordsToProcess);
            }
            
            // --- 5. Perform Parent DML Operation ---
            List<Database.UpsertResult> parentResults;
            if (String.isNotBlank(upsertRequest.externalIdField)) {
                Schema.SObjectField externalIdFieldDescribe = describeResult.fields.getMap()
                    .get(upsertRequest.externalIdField);
                if (
                    externalIdFieldDescribe == null ||
                    !externalIdFieldDescribe.getDescribe().isExternalId()
                ) {
                    response.statusCode = 400; // Bad Request
                    return new SObjectResourceModels.UpsertResponse(
                        'Invalid externalIdField specified: ' +
                        upsertRequest.externalIdField
                    );
                }
                parentResults = Database.upsert(
                    recordsToProcess,
                    externalIdFieldDescribe,
                    false
                );
            } else {
                // Use standard upsert if no external ID field is provided.
                parentResults = Database.upsert(recordsToProcess, false);
            }
            
            // --- 6. Process Child Records and Finalize Response ---
            SObjectResourceModels.UpsertResponse upsertResponse = new SObjectResourceModels.UpsertResponse(
                parentResults,
                upsertRequest.data,
                upsertRequest.externalIdField
            );
            SObjectResourceHandler.prepareAndInsertChildren(
                upsertRequest,
                parentResults,
                childRelationshipsMap,
                upsertResponse
            );
            
            IAfterUpsertHandler afterUpsertHandler = AfterUpsertHandlerFactory.getHandler(
                objectName
            );
            if (afterUpsertHandler != null) {
                try {
                    afterUpsertHandler.afterUpsert(upsertResponse);
                } catch (Exception e) {
                    System.debug(
                        System.LoggingLevel.ERROR,
                        'After-Upsert handler failed for object ' +
                        objectName +
                        '. Error: ' +
                        e.getMessage() +
                        ' Stacktrace: ' +
                        e.getStackTraceString()
                    );
                }
            }
            
            response.statusCode = 200; // OK
            return upsertResponse;
        } catch (SObjectResourceHandler.ApiGatewayException e) {
            // Catch specific, predictable errors from the helper (e.g., bad JSON, invalid fields).
            response.statusCode = 400; // Bad Request
            return new SObjectResourceModels.UpsertResponse(e.getMessage());
        } catch (Exception e) {
            // Catch all other unexpected errors (e.g., DML exceptions from triggers, validation rules).
            System.debug(
                System.LoggingLevel.ERROR,
                'SObject API Gateway failed. Error: ' +
                e.getMessage() +
                ' Stack Trace: ' +
                e.getStackTraceString()
            );
            response.statusCode = 500; // Internal Server Error
            return new SObjectResourceModels.UpsertResponse(
                'An unexpected error occurred during the data operation. Details: ' +
                e.getMessage()
            );
        }
    }
}