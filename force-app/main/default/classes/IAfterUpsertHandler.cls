/**
 * @description Interface for classes that need to perform logic after an upsert
 * operation has completed. This is useful for post-processing tasks like logging,
 * sending platform events, or enqueuing asynchronous jobs.
 */
public interface IAfterUpsertHandler {
  /**
   * @description Executes custom logic after the DML operations are complete.
   * This method does not return a value and cannot modify the response sent to the client.
   * @param result The response object containing the full results of the parent
   * and child DML operations.
   */
  void afterUpsert(SObjectResourceModels.UpsertResponse result);
}