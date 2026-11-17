/**
 * Agent action: triages a case with the LLM right away and saves the result.
 * Exposed to Agentforce (and Flow) through @InvocableMethod.
 */
public with sharing class TriageCaseAction {
  // Each triage is one HTTP callout; stay far below the 100-callout limit.
  @TestVisible
  private static final Integer MAX_REQUESTS = 20;

  public class Request {
    @InvocableVariable(
      label='Case Number or Id'
      description='The case to triage: its Case Number (e.g. 00001029 or 1029) or its record Id.'
      required=true
    )
    public String caseReference;
  }

  public class Result {
    @InvocableVariable(
      label='Success'
      description='True when the case was found and the AI triage completed.'
    )
    public Boolean success;
    @InvocableVariable(label='Case Number')
    public String caseNumber;
    @InvocableVariable(label='Case Id')
    public String caseId;
    @InvocableVariable(
      label='Category'
      description='Category suggested by the AI.'
    )
    public String category;
    @InvocableVariable(
      label='Suggested Priority'
      description='Priority suggested by the AI: High, Medium or Low.'
    )
    public String suggestedPriority;
    @InvocableVariable(
      label='Current Priority'
      description='Priority currently set on the case.'
    )
    public String currentPriority;
    @InvocableVariable(
      label='Sentiment'
      description='Customer sentiment: Positive, Neutral, Negative or Angry.'
    )
    public String sentiment;
    @InvocableVariable(
      label='Summary'
      description='One-sentence summary of the problem.'
    )
    public String summary;
    @InvocableVariable(
      label='Suggested Reply'
      description='Draft reply to the customer, in the customer language.'
    )
    public String suggestedReply;
    @InvocableVariable(
      label='Error Message'
      description='Why the triage failed, when Success is false.'
    )
    public String errorMessage;
  }

  @InvocableMethod(
    label='Triage Support Case with AI'
    description='Analyzes a support case with an LLM and saves the result on the case: category, suggested priority, customer sentiment, a one-line summary and a draft reply to the customer.'
    category='Case AI Triage'
  )
  public static List<Result> triage(List<Request> requests) {
    List<String> refs = new List<String>();
    for (Request r : requests) {
      refs.add(r.caseReference);
    }
    Map<String, Case> cases = CaseReferenceResolver.resolve(refs);

    List<Result> results = new List<Result>();
    Map<Id, Case> updates = new Map<Id, Case>(); // the same case may be asked for twice
    Integer processed = 0;
    // All callouts first, DML once at the end.
    for (Request r : requests) {
      Case source = cases.get(r.caseReference);
      if (source == null) {
        results.add(failure('No case found for "' + r.caseReference + '".'));
        continue;
      }
      if (processed >= MAX_REQUESTS) {
        results.add(
          failure(
            'Too many cases in one request; triage at most ' +
              MAX_REQUESTS +
              ' at a time.'
          )
        );
        continue;
      }
      processed++;
      Case triaged = CaseTriageService.triage(source);
      updates.put(triaged.Id, triaged);
      results.add(toResult(source, triaged));
    }

    // Status becomes Completed/Failed (never Pending), so the trigger won't enqueue again.
    if (!updates.isEmpty()) {
      update updates.values();
    }
    return results;
  }

  private static Result toResult(Case source, Case triaged) {
    Result res = new Result();
    res.caseId = source.Id;
    res.caseNumber = source.CaseNumber;
    res.currentPriority = source.Priority;
    res.success = triaged.AI_Status__c == CaseTriageService.STATUS_COMPLETED;
    if (res.success) {
      res.category = triaged.AI_Category__c;
      res.suggestedPriority = triaged.AI_Suggested_Priority__c;
      res.sentiment = triaged.AI_Sentiment__c;
      res.summary = triaged.AI_Summary__c;
      res.suggestedReply = triaged.AI_Suggested_Reply__c;
    } else {
      res.errorMessage = triaged.AI_Error__c;
    }
    return res;
  }

  private static Result failure(String message) {
    Result res = new Result();
    res.success = false;
    res.errorMessage = message;
    return res;
  }
}
