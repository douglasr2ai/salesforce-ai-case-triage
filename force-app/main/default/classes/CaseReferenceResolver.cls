/**
 * Resolves what a person (or an agent) calls a case - "00001029", "1029",
 * "#1029" or a record Id - into Case records.
 */
public with sharing class CaseReferenceResolver {
  private static final Integer CASE_NUMBER_LENGTH = 8;

  public static Map<String, Case> resolve(List<String> references) {
    Set<Id> ids = new Set<Id>();
    Set<String> numbers = new Set<String>();
    for (String ref : references) {
      String clean = normalize(ref);
      if (clean == null) {
        continue;
      }
      if (isCaseId(clean)) {
        ids.add(Id.valueOf(clean));
      } else {
        numbers.add(clean);
      }
    }

    Map<String, Case> byReference = new Map<String, Case>();
    if (ids.isEmpty() && numbers.isEmpty()) {
      return byReference;
    }
    Map<Id, Case> byId = new Map<Id, Case>();
    Map<String, Case> byNumber = new Map<String, Case>();
    for (Case c : [
      SELECT Id, CaseNumber, Subject, Description, Origin, Priority, Status
      FROM Case
      WHERE Id IN :ids OR CaseNumber IN :numbers
    ]) {
      byId.put(c.Id, c);
      byNumber.put(c.CaseNumber, c);
    }
    for (String ref : references) {
      String clean = normalize(ref);
      if (clean == null) {
        continue;
      }
      Case found = isCaseId(clean)
        ? byId.get(Id.valueOf(clean))
        : byNumber.get(clean);
      if (found != null) {
        byReference.put(ref, found);
      }
    }
    return byReference;
  }

  @TestVisible
  private static String normalize(String ref) {
    if (String.isBlank(ref)) {
      return null;
    }
    String clean = ref.trim().removeStart('#').trim();
    if (isCaseId(clean)) {
      return clean;
    }
    return clean.isNumeric() ? clean.leftPad(CASE_NUMBER_LENGTH, '0') : clean;
  }

  private static Boolean isCaseId(String value) {
    if (
      !(value.length() == 15 || value.length() == 18) ||
      !value.startsWith('500')
    ) {
      return false;
    }
    try {
      return Id.valueOf(value).getSobjectType() == Case.SObjectType;
    } catch (Exception e) {
      return false;
    }
  }
}
