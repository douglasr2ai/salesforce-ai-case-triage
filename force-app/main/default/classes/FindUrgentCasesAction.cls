/**
 * Agent action: lists open cases the AI flagged as urgent
 * (High suggested priority, or Angry/Negative customer sentiment).
 */
public with sharing class FindUrgentCasesAction {
  private static final Integer DEFAULT_LIMIT = 10;
  private static final Integer MAX_LIMIT = 50;

  public class Request {
    @InvocableVariable(
      label='Max Results'
      description='How many cases to return (default 10, max 50).'
    )
    public Integer maxResults;
  }

  public class Result {
    @InvocableVariable(
      label='Case Count'
      description='Number of urgent cases returned.'
    )
    public Integer caseCount;
    @InvocableVariable(
      label='Urgent Cases'
      description='One line per case: Case Number | Subject | Category | Suggested Priority | Sentiment | Summary. Angry customers come first.'
    )
    public String urgentCases;
  }

  @InvocableMethod(
    label='Find Urgent Support Cases'
    description='Returns open support cases that the AI triage flagged as urgent (suggested priority High, or customer sentiment Angry or Negative), with angry customers first.'
    category='Case AI Triage'
  )
  public static List<Result> find(List<Request> requests) {
    Integer max = DEFAULT_LIMIT;
    if (
      requests != null &&
      !requests.isEmpty() &&
      requests[0].maxResults != null &&
      requests[0].maxResults > 0
    ) {
      max = Math.min(requests[0].maxResults, MAX_LIMIT);
    }

    List<Case> cases = [
      SELECT
        CaseNumber,
        Subject,
        AI_Category__c,
        AI_Suggested_Priority__c,
        AI_Sentiment__c,
        AI_Summary__c
      FROM Case
      WHERE
        IsClosed = FALSE
        AND AI_Status__c = :CaseTriageService.STATUS_COMPLETED
        AND (AI_Suggested_Priority__c = 'High'
        OR AI_Sentiment__c IN ('Angry', 'Negative'))
      ORDER BY CreatedDate DESC
      LIMIT :MAX_LIMIT
    ];

    // Angry customers first, then negative, then the rest (stable within each group).
    List<Case> sorted = new List<Case>();
    for (String sentiment : new List<String>{ 'Angry', 'Negative', null }) {
      for (Case c : cases) {
        Boolean matches = sentiment == null
          ? c.AI_Sentiment__c != 'Angry' && c.AI_Sentiment__c != 'Negative'
          : c.AI_Sentiment__c == sentiment;
        if (matches && sorted.size() < max) {
          sorted.add(c);
        }
      }
    }

    List<String> lines = new List<String>();
    for (Case c : sorted) {
      lines.add(
        String.join(
          new List<String>{
            c.CaseNumber,
            c.Subject,
            c.AI_Category__c,
            c.AI_Suggested_Priority__c,
            c.AI_Sentiment__c,
            c.AI_Summary__c
          },
          ' | '
        )
      );
    }

    Result res = new Result();
    res.caseCount = sorted.size();
    res.urgentCases = lines.isEmpty()
      ? 'No urgent open cases.'
      : String.join(lines, '\n');
    List<Result> results = new List<Result>();
    for (
      Integer i = 0;
      i < (requests == null ? 1 : Math.max(requests.size(), 1));
      i++
    ) {
      results.add(res);
    }
    return results;
  }
}
