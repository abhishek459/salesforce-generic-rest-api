/**
 * @description Helper class for the SObjectResource. Encapsulates logic for
 * request parsing, validation, and data preparation for DML operations.
 */
public with sharing class SObjectResourceHandler {
  /**
   * @description A custom exception class for handling API-specific errors that
   * can be caught and translated into proper HTTP responses.
   */
  public class ApiGatewayException extends Exception {
  }

  /**
   * @description Parses the JSON request body into a typed wrapper object and
   * performs initial validation.
   * @param request The inbound RestRequest.
   * @return A validated SObjectResourceModels.UpsertRequest object.
   * @throws ApiGatewayException if JSON is invalid or the records list is empty.
   */
  public static SObjectResourceModels.UpsertRequest parseAndValidateRequest(
    RestRequest request
  ) {
    try {
      String jsonBody = request.requestBody.toString();
      // Using deserializeUntyped to handle the generic Map<String, Object> structure
      Map<String, Object> payloadMap = (Map<String, Object>) JSON.deserializeUntyped(
        jsonBody
      );

      SObjectResourceModels.UpsertRequest requestBody = new SObjectResourceModels.UpsertRequest();
      requestBody.externalIdField = (String) payloadMap.get('externalIdField');

      List<Map<String, Object>> typedRecords = new List<Map<String, Object>>();
      Object rawRecords = payloadMap.get('data');

      if (rawRecords != null && rawRecords instanceof List<Object>) {
        for (Object recordObj : (List<Object>) rawRecords) {
          // Manually cast each item from Object to the Map type
          typedRecords.add((Map<String, Object>) recordObj);
        }
      }
      requestBody.data = typedRecords;

      if (requestBody.data.isEmpty()) {
        throw new ApiGatewayException(
          'Request body must contain a non-empty list of data.'
        );
      }
      return requestBody;
    } catch (Exception e) {
      throw new ApiGatewayException(
        'Invalid JSON format in request body. Details: ' + e.getMessage()
      );
    }
  }

  /**
   * @description Prepares parent SObjects for DML, validating each field in the
   * payload against the object's schema and user permissions.
   * @param objectName The API name of the parent SObject.
   * @param describe The describe result for the parent SObject.
   * @param requestBody The parsed request wrapper.
   * @param childRelationshipsMap A map of valid child relationships for the object.
   * @return A list of SObjects ready for the upsert operation.
   * @throws ApiGatewayException if the payload contains invalid keys.
   */
  public static List<SObject> prepareAndValidateParentRecords(
    String objectName,
    Schema.DescribeSObjectResult describe,
    SObjectResourceModels.UpsertRequest requestBody,
    Map<String, Schema.ChildRelationship> childRelationshipsMap
  ) {
    List<SObject> recordsToProcess = new List<SObject>();
    Map<String, Schema.SObjectField> fieldMap = describe.fields.getMap();

    for (Map<String, Object> recordMap : requestBody.data) {
      SObject sObj = describe.getSObjectType().newSObject();
      for (String fieldName : recordMap.keySet()) {
        String lowerCaseFieldName = fieldName.toLowerCase();

        if (fieldMap.containsKey(lowerCaseFieldName)) {
          // Check FLS for the parent field before adding
          if (
            fieldMap.get(lowerCaseFieldName).getDescribe().isUpdateable() ||
            fieldMap.get(lowerCaseFieldName).getDescribe().isCreateable()
          ) {
            sObj.put(fieldName, recordMap.get(fieldName));
          }
        } else if (!childRelationshipsMap.containsKey(lowerCaseFieldName)) {
          // If the key is not a valid field and not a child relationship, it's an error.
          throw new ApiGatewayException(
            'Invalid JSON key \'' +
              fieldName +
              '\' is not a valid field or child relationship on object ' +
              objectName
          );
        }
        // If it's a child relationship, we intentionally do nothing here.
      }
      recordsToProcess.add(sObj);
    }
    return recordsToProcess;
  }

  /**
   * @description Prepares and inserts all child records from the payload in a
   * single DML operation to prevent hitting governor limits.
   * @param requestBody The original request wrapper.
   * @param parentResults The results of the parent upsert operation.
   * @param childRelationshipsMap A map of valid child relationships.
   * @param responseWrapper The response wrapper to populate with results.
   */
  public static void prepareAndInsertChildren(
    SObjectResourceModels.UpsertRequest requestBody,
    List<Database.UpsertResult> parentResults,
    Map<String, Schema.ChildRelationship> childRelationshipsMap,
    SObjectResourceModels.UpsertResponse responseWrapper
  ) {
    // Maps used to aggregate children before the single DML call
    List<SObject> allChildrenToInsert = new List<SObject>();
    // Map<Parent Index, Map<Relationship Name, List<Child SObject>>>
    Map<Integer, Map<String, List<SObject>>> parentIndexToChildrenMap = new Map<Integer, Map<String, List<SObject>>>();

    for (Integer i = 0; i < parentResults.size(); i++) {
      Database.UpsertResult parentRes = parentResults[i];
      if (!parentRes.isSuccess()) {
        continue;
      }

      String parentId = parentRes.getId();
      Map<String, Object> originalRecordMap = requestBody.data[i];

      String parentExternalIdValue = null;
      if (String.isNotBlank(requestBody.externalIdField)) {
        parentExternalIdValue = (String) originalRecordMap.get(
          requestBody.externalIdField
        );
      }

      for (String jsonKey : originalRecordMap.keySet()) {
        Schema.ChildRelationship cr = childRelationshipsMap.get(
          jsonKey.toLowerCase()
        );
        if (cr == null) {
          continue; // Not a child relationship key, skip it.
        }

        Schema.DescribeSObjectResult childDescribe = cr.getChildSObject()
          .getDescribe();
        if (!childDescribe.isCreateable()) {
          String parentIdentifier;
          if (
            String.isNotBlank(requestBody.externalIdField) &&
            originalRecordMap.containsKey(requestBody.externalIdField)
          ) {
            parentIdentifier = (String) originalRecordMap.get(
              requestBody.externalIdField
            );
          } else {
            parentIdentifier = parentId;
          }
          responseWrapper.addChildErrorResult(
            parentIdentifier,
            cr.getRelationshipName(),
            'User does not have permission to create ' +
            childDescribe.getLabelPlural()
          );
          continue; // Skip to next relationship
        }

        List<SObject> childrenForThisParent = prepareChildRecordList(
          parentId,
          requestBody.externalIdField,
          parentExternalIdValue,
          cr,
          (List<Object>) originalRecordMap.get(jsonKey)
        );

        if (!childrenForThisParent.isEmpty()) {
          if (!parentIndexToChildrenMap.containsKey(i)) {
            parentIndexToChildrenMap.put(i, new Map<String, List<SObject>>());
          }
          parentIndexToChildrenMap.get(i)
            .put(cr.getRelationshipName(), childrenForThisParent);
          allChildrenToInsert.addAll(childrenForThisParent);
        }
      }
    }

    if (!allChildrenToInsert.isEmpty()) {
      List<Database.SaveResult> allChildSaveResults = Database.insert(
        allChildrenToInsert,
        false
      );
      // Now, map the results back to the correct parent in the response
      Integer resultIndex = 0;
      for (Integer parentIndex : parentIndexToChildrenMap.keySet()) {
        Map<String, Object> originalParentRecord = requestBody.data[
          parentIndex
        ];
        String parentSalesforceId = parentResults[parentIndex].getId();

        // NEW LOGIC: Determine the identifier to use as the key for the child results
        String parentIdentifier;
        if (
          String.isNotBlank(requestBody.externalIdField) &&
          originalParentRecord.containsKey(requestBody.externalIdField)
        ) {
          parentIdentifier = (String) originalParentRecord.get(
            requestBody.externalIdField
          );
        } else {
          parentIdentifier = parentSalesforceId;
        }

        Map<String, List<SObject>> relationshipMap = parentIndexToChildrenMap.get(
          parentIndex
        );

        for (String relationshipName : relationshipMap.keySet()) {
          Integer childCount = relationshipMap.get(relationshipName).size();
          List<Database.SaveResult> resultsForThisGroup = new List<Database.SaveResult>();
          for (Integer j = 0; j < childCount; j++) {
            resultsForThisGroup.add(allChildSaveResults[resultIndex++]);
          }
          responseWrapper.addChildResults(
            parentIdentifier,
            relationshipName,
            resultsForThisGroup
          );
        }
      }
    }
  }

  /**
   * @description Helper method to construct a list of child SObjects, setting the
   * parent relationship and checking FLS for each field.
   * @param parentId The ID of the parent record.
   * @param cr The ChildRelationship schema object.
   * @param rawChildList The list of child records from the JSON payload.
   * @return A list of prepared child SObjects.
   */
  private static List<SObject> prepareChildRecordList(
    String parentId,
    String parentExternalIdField,
    String parentExternalIdValue,
    Schema.ChildRelationship cr,
    List<Object> rawChildList
  ) {
    List<SObject> childSObjectList = new List<SObject>();
    Schema.SObjectType childType = cr.getChildSObject();
    Schema.DescribeSObjectResult childDescribe = childType.getDescribe();
    Map<String, Schema.SObjectField> childFieldMap = childDescribe.fields.getMap();
    Schema.SObjectField relationshipField = cr.getField();

    for (Object childObj : rawChildList) {
      Map<String, Object> childMap = (Map<String, Object>) childObj;
      SObject newChild = childType.newSObject();

      if (
        String.isNotBlank(parentExternalIdField) &&
        String.isNotBlank(parentExternalIdValue)
      ) {
        // Get the parent SObject type (e.g., 'Account') from the relationship
        Schema.SObjectType parentType = relationshipField.getDescribe()
          .getReferenceTo()[0];

        // Create a parent SObject reference using only the external ID field
        SObject parentReference = parentType.newSObject();
        parentReference.put(parentExternalIdField, parentExternalIdValue);

        // Set the relationship on the child using the SObject reference
        newChild.putSObject(
          relationshipField.getDescribe().getRelationshipName(),
          parentReference
        );
      } else {
        // Fallback to using the parent's Salesforce ID
        newChild.put(relationshipField, parentId);
      }

      for (String childFieldName : childMap.keySet()) {
        Schema.SObjectField fieldToken = childFieldMap.get(
          childFieldName.toLowerCase()
        );
        // Check if the field is valid and if user has create permission (FLS)
        if (fieldToken != null && fieldToken.getDescribe().isCreateable()) {
          newChild.put(childFieldName, childMap.get(childFieldName));
        }
      }
      childSObjectList.add(newChild);
    }
    return childSObjectList;
  }
}