/**
 * @description Defines the data transfer objects (DTOs) or models used by the
 * SObjectResource. This centralizes the API's data contract.
 */
global with sharing class SObjectResourceModels {
  // =================================================================================
  // == API Data Structures (Request and Response Payloads)
  // =================================================================================

  /**
   * @description Represents the structure of the inbound POST request body.
   */
  global class UpsertRequest {
    public String externalIdField { get; set; }
    public List<Map<String, Object>> data { get; set; }
  }

  /**
   * @description Contains the result for a single processed record.
   */
  global class RecordResult {
    public Id id { get; private set; }
    public String externalId { get; private set; }
    public Boolean success { get; private set; }
    public Boolean created { get; private set; }
    public List<String> errors { get; private set; }

    public RecordResult(Database.UpsertResult res, String externalId) {
      this.id = res.getId();
      this.externalId = externalId;
      this.success = res.isSuccess();
      this.created = res.isCreated();
      this.errors = new List<String>();
      if (!res.isSuccess()) {
        for (Database.Error err : res.getErrors()) {
          this.errors.add(err.getStatusCode() + ': ' + err.getMessage());
        }
      }
    }

    public RecordResult(Database.SaveResult res) {
      this.id = res.getId();
      this.success = res.isSuccess();
      this.created = res.isSuccess(); // For child inserts, success implies creation.
      this.errors = new List<String>();
      if (!res.isSuccess()) {
        for (Database.Error err : res.getErrors()) {
          this.errors.add(err.getStatusCode() + ': ' + err.getMessage());
        }
      }
    }
  }

  /**
   * @description A container for the results of processing a collection of child records
   * under a specific relationship. Can hold either the results or an error message.
   */
  global class ChildRelationshipResult {
    public List<RecordResult> results { get; private set; }
    public String error { get; private set; }

    public ChildRelationshipResult(List<RecordResult> results) {
      this.results = results;
    }
    public ChildRelationshipResult(String errorMessage) {
      this.error = errorMessage;
    }
  }

  /**
   * @description Represents the structure of the outbound API response.
   */
  global class UpsertResponse {
    public String errorMessage { get; private set; }
    public Integer totalProcessed { get; private set; }
    public Integer totalSuccess { get; private set; }
    public Integer totalErrors { get; private set; }
    public List<RecordResult> results { get; private set; }
    // Structure: Map<Parent Record ID / External Id, Map<Relationship Name, Child Relationship Result>>
    public Map<String, Map<String, ChildRelationshipResult>> childResults {
      get;
      private set;
    }

    public UpsertResponse(
      List<Database.UpsertResult> upsertResults,
      List<Map<String, Object>> originalRecords,
      String externalIdField
    ) {
      this.results = new List<RecordResult>();
      this.totalSuccess = 0;
      this.totalErrors = 0;
      for (Integer i = 0; i < upsertResults.size(); i++) {
        Database.UpsertResult res = upsertResults[i];
        Map<String, Object> originalRecord = originalRecords[i];
        String externalId = null;
        if (
          String.isNotBlank(externalIdField) &&
          originalRecord.containsKey(externalIdField)
        ) {
          externalId = (String) originalRecord.get(externalIdField);
        }
        results.add(new RecordResult(res, externalId));
        if (res.isSuccess()) {
          this.totalSuccess++;
        } else {
          this.totalErrors++;
        }
      }
      this.totalProcessed = this.totalSuccess + this.totalErrors;
      this.childResults = new Map<String, Map<String, ChildRelationshipResult>>();
    }

    public UpsertResponse(String errorMsg) {
      this.errorMessage = errorMsg;
      this.totalProcessed = 0;
      this.totalSuccess = 0;
      this.totalErrors = 0;
      this.results = new List<RecordResult>();
      this.childResults = new Map<String, Map<String, ChildRelationshipResult>>();
    }

    public void addChildResults(
      String parentId,
      String relationshipName,
      List<Database.SaveResult> saveResults
    ) {
      List<RecordResult> childRecordResults = new List<RecordResult>();
      for (Database.SaveResult res : saveResults) {
        childRecordResults.add(new RecordResult(res));
      }

      if (!this.childResults.containsKey(parentId)) {
        this.childResults.put(
          parentId,
          new Map<String, ChildRelationshipResult>()
        );
      }
      this.childResults.get(parentId)
        .put(relationshipName, new ChildRelationshipResult(childRecordResults));
    }

    public void addChildErrorResult(
      String parentId,
      String relationshipName,
      String errorMsg
    ) {
      if (!this.childResults.containsKey(parentId)) {
        this.childResults.put(
          parentId,
          new Map<String, ChildRelationshipResult>()
        );
      }
      this.childResults.get(parentId)
        .put(relationshipName, new ChildRelationshipResult(errorMsg));
    }
  }
}