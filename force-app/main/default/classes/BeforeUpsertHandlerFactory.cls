/**
 * @description Factory class to retrieve the correct IBeforeUpsertHandler
 * implementation based on a Custom Metadata Type mapping.
 */
global class BeforeUpsertHandlerFactory {
    // Static map to cache mappings for the duration of the transaction.
    private static Map<String, String> handlerMappings;

    // Static block to initialize the map once per transaction.
    static {
        handlerMappings = new Map<String, String>();
        for (SObject_Handler_Mapping__mdt mapping : [
            SELECT SObject_API_Name__c, Handler_Class_Name__c
            FROM SObject_Handler_Mapping__mdt
            WHERE Handler_Type__c = 'Before'
        ]) {
            handlerMappings.put(mapping.SObject_API_Name__c.toLowerCase(), mapping.Handler_Class_Name__c);
        }
    }

    /**
     * @description Returns an instance of the appropriate handler for the given object name.
     * @param objectName The API name of the SObject.
     * @return IBeforeUpsertHandler An instance of the handler, or null if none is found.
     */
    public static IBeforeUpsertHandler getHandler(String objectName) {
        String handlerClassName = handlerMappings.get(objectName.toLowerCase());

        if (String.isNotBlank(handlerClassName)) {
            try {
                Type handlerType = Type.forName(handlerClassName);
                if (handlerType != null) {
                    // Dynamically create an instance of the handler class
                    return (IBeforeUpsertHandler) handlerType.newInstance();
                }
            } catch (Exception e) {
                System.debug(
                    System.LoggingLevel.ERROR,
                    'BeforeUpsertHandlerFactory Error: Failed to create an instance of ' +
                    handlerClassName + '. Details: ' + e.getMessage()
                );
                // Optionally, rethrow as a custom exception to notify the client or developer.
            }
        }
        return null;
    }
}