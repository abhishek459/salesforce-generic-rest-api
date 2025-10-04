/**
 * @description Interface for classes that need to perform logic before an upsert operation.
 * Any class implementing this must define a beforeUpsert method.
 */
public interface IBeforeUpsertHandler {
    /**
     * @description Modifies a list of SObjects before they are passed to a DML upsert operation.
     * @param records The list of records to be processed.
     * @return List<SObject> The modified list of records.
     */
    List<SObject> beforeUpsert(List<SObject> records);
}