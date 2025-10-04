/**
 * @description Example implementation of IAfterUpsertHandler for the Account object.
 * Performs post-processing logic after Account records have been upserted.
 */
public class AccountAfterUpsertHandler implements IAfterUpsertHandler {
  public void afterUpsert(SObjectResourceModels.UpsertResponse response) {
    System.debug(
      'AccountAfterUpsertHandler executed. Total successful records: ' +
      response.totalSuccess
    );

    // Example Use Case: Gather IDs of newly created accounts to send a platform event
    // or enqueue a Queueable job for further processing.
    List<Id> newAccountIds = new List<Id>();
    for (SObjectResourceModels.RecordResult res : response.results) {
      if (res.success && res.created) {
        newAccountIds.add(res.id);
      }
    }

    if (!newAccountIds.isEmpty()) {
      // In a real scenario, you would publish an event or enqueue a job here.
      // For example:
      // EventBus.publish(new Accounts_Created__e(Account_Ids__c = newAccountIds));
      System.debug(
        'Post-processing hook: Found ' +
        newAccountIds.size() +
        ' new accounts to process: ' +
        newAccountIds
      );
    }
  }
}