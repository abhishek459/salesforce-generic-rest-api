/**
 * @description A handler to perform pre-processing on Account records before they are
 * upserted via the API Gateway. It handles data standardization.
 */
public class AccountBeforeUpsertHandler implements IBeforeUpsertHandler {

  /**
   * @description Modifies a list of Account records before they are upserted.
   * @param records The generic list of SObjects to be processed.
   * @return List<SObject> The modified list of records.
   */
  public List<SObject> beforeUpsert(List<SObject> records) {
    // Cast the generic SObject list to a typed list of Accounts
    List<Account> accounts = (List<Account>) records;
    for (Account acc : accounts) {
      // a) Ensure Account Name is properly capitalized for consistency.
      if (String.isNotBlank(acc.Name)) {
        // Trim whitespace first, then apply title case capitalization.
        acc.Name = toTitleCase(acc.Name.trim());
      }

      // b) Standardize website URLs to ensure they include a protocol.
      if (String.isNotBlank(acc.Website) && !acc.Website.startsWith('http')) {
        acc.Website = 'https://' + acc.Website;
      }
    }
    return accounts;
  }

  /**
   * @description A helper method to convert a string to "Title Case" where the
   * first letter of each word is capitalized.
   * @param input The string to convert.
   * @return A new string in title case.
   */
  private static String toTitleCase(String input) {
    if (String.isBlank(input)) {
      return input;
    }

    // Split the string by one or more whitespace characters
    List<String> words = input.split('\\s+');
    List<String> capitalizedWords = new List<String>();

    for (String word : words) {
      if (String.isNotBlank(word)) {
        // Capitalize the first letter and append the rest of the word
        String firstLetter = word.substring(0, 1).toUpperCase();
        String restOfWord = word.substring(1);
        capitalizedWords.add(firstLetter + restOfWord);
      }
    }

    // Join the words back together with a single space
    return String.join(capitalizedWords, ' ');
  }
}