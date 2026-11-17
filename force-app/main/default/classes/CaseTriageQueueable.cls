/**
 * Runs the AI triage asynchronously (callouts are not allowed inside triggers).
 * Processes up to BATCH_SIZE cases per execution and chains itself for the rest,
 * keeping well below the 100-callouts-per-transaction governor limit.
 */
public with sharing class CaseTriageQueueable implements Queueable, Database.AllowsCallouts {
  @TestVisible
  private static final Integer BATCH_SIZE = 50;

  private final List<Id> caseIds;

  public CaseTriageQueueable(List<Id> caseIds) {
    this.caseIds = caseIds;
  }

  /**
   * Enqueues triage for the given cases if the transaction still has room
   * for an async job. Cases that could not be enqueued stay "Pending".
   */
  public static void enqueue(List<Id> caseIds) {
    if (caseIds == null || caseIds.isEmpty()) {
      return;
    }
    if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
      return;
    }
    System.enqueueJob(new CaseTriageQueueable(caseIds));
  }

  public void execute(QueueableContext context) {
    List<Id> current = new List<Id>();
    List<Id> remaining = new List<Id>();
    for (Integer i = 0; i < caseIds.size(); i++) {
      if (i < BATCH_SIZE) {
        current.add(caseIds[i]);
      } else {
        remaining.add(caseIds[i]);
      }
    }

    // All callouts must happen before any DML in the same transaction.
    List<Case> updates = new List<Case>();
    for (Case c : [
      SELECT Id, Subject, Description, Origin
      FROM Case
      WHERE Id IN :current AND AI_Status__c = :CaseTriageService.STATUS_PENDING
    ]) {
      updates.add(CaseTriageService.triage(c));
    }

    if (!updates.isEmpty()) {
      Database.update(updates, false);
    }

    if (!remaining.isEmpty() && !Test.isRunningTest()) {
      System.enqueueJob(new CaseTriageQueueable(remaining));
    }
  }
}
