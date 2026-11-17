/**
 * Trigger handler for Case. Marks new cases as pending AI triage and enqueues
 * the async job. Setting AI_Status__c back to "Pending" re-runs the triage.
 */
public with sharing class CaseTriggerHandler {
  @TestVisible
  private static Boolean bypass = false;

  public void run() {
    if (bypass || !CaseTriageService.isEnabled()) {
      return;
    }
    switch on Trigger.operationType {
      when BEFORE_INSERT {
        markPending((List<Case>) Trigger.new);
      }
      when AFTER_INSERT {
        CaseTriageQueueable.enqueue(
          collectPending((List<Case>) Trigger.new, null)
        );
      }
      when AFTER_UPDATE {
        CaseTriageQueueable.enqueue(
          collectPending(
            (List<Case>) Trigger.new,
            (Map<Id, Case>) Trigger.oldMap
          )
        );
      }
    }
  }

  private void markPending(List<Case> cases) {
    for (Case c : cases) {
      if (String.isBlank(c.AI_Status__c)) {
        c.AI_Status__c = CaseTriageService.STATUS_PENDING;
      }
    }
  }

  private List<Id> collectPending(List<Case> cases, Map<Id, Case> oldMap) {
    List<Id> ids = new List<Id>();
    for (Case c : cases) {
      Boolean isPending = c.AI_Status__c == CaseTriageService.STATUS_PENDING;
      Boolean becamePending =
        oldMap == null ||
        oldMap.get(c.Id).AI_Status__c != CaseTriageService.STATUS_PENDING;
      if (isPending && becamePending) {
        ids.add(c.Id);
      }
    }
    return ids;
  }
}
