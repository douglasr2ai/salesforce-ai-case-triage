@IsTest
private class CaseTriggerHandlerTest {
  private static List<Case> newCases(Integer count) {
    List<Case> cases = new List<Case>();
    for (Integer i = 0; i < count; i++) {
      cases.add(
        new Case(
          Subject = 'Case ' + i,
          Description = 'I was charged twice',
          Origin = 'Web'
        )
      );
    }
    return cases;
  }

  @IsTest
  static void newCasesAreTriagedAsynchronously() {
    CaseTriageService.settingsOverride = new AI_Triage_Setting__mdt(
      Enabled__c = true,
      Model__c = 'test/model'
    );
    OpenRouterMock mock = OpenRouterMock.success(OpenRouterMock.sampleTriage());
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    insert newCases(5);
    Assert.areEqual(
      5,
      [SELECT COUNT() FROM Case WHERE AI_Status__c = 'Pending'],
      'pending before async job'
    );
    Test.stopTest();

    Assert.areEqual(5, mock.calls);
    for (Case c : [
      SELECT AI_Status__c, AI_Category__c, AI_Sentiment__c
      FROM Case
    ]) {
      Assert.areEqual('Completed', c.AI_Status__c);
      Assert.areEqual('Billing', c.AI_Category__c);
      Assert.areEqual('Angry', c.AI_Sentiment__c);
    }
  }

  @IsTest
  static void settingStatusBackToPendingRerunsTriage() {
    CaseTriageService.settingsOverride = new AI_Triage_Setting__mdt(
      Enabled__c = true,
      Model__c = 'test/model'
    );
    CaseTriggerHandler.bypass = true;
    Case c = new Case(Subject = 'Old case', AI_Status__c = 'Failed');
    insert c;
    CaseTriggerHandler.bypass = false;

    OpenRouterMock mock = OpenRouterMock.success(OpenRouterMock.sampleTriage());
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    update new Case(Id = c.Id, AI_Status__c = 'Pending');
    Test.stopTest();

    Assert.areEqual(1, mock.calls);
    Assert.areEqual(
      'Completed',
      [SELECT AI_Status__c FROM Case WHERE Id = :c.Id].AI_Status__c
    );
  }

  @IsTest
  static void unrelatedUpdatesDoNotCallTheAi() {
    CaseTriageService.settingsOverride = new AI_Triage_Setting__mdt(
      Enabled__c = true,
      Model__c = 'test/model'
    );
    CaseTriggerHandler.bypass = true;
    Case c = new Case(Subject = 'Done', AI_Status__c = 'Completed');
    insert c;
    CaseTriggerHandler.bypass = false;

    OpenRouterMock mock = OpenRouterMock.success(OpenRouterMock.sampleTriage());
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    update new Case(Id = c.Id, Subject = 'Done (edited)');
    Test.stopTest();

    Assert.areEqual(0, mock.calls);
  }

  @IsTest
  static void disabledSettingSkipsTriage() {
    CaseTriageService.settingsOverride = new AI_Triage_Setting__mdt(
      Enabled__c = false
    );
    OpenRouterMock mock = OpenRouterMock.success(OpenRouterMock.sampleTriage());
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    insert newCases(1);
    Test.stopTest();

    Assert.areEqual(0, mock.calls);
    Assert.isNull([SELECT AI_Status__c FROM Case LIMIT 1].AI_Status__c);
  }

  @IsTest
  static void bulkInsertProcessesOneBatchPerJob() {
    CaseTriageService.settingsOverride = new AI_Triage_Setting__mdt(
      Enabled__c = true,
      Model__c = 'test/model'
    );
    OpenRouterMock mock = OpenRouterMock.success(OpenRouterMock.sampleTriage());
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    insert newCases(CaseTriageQueueable.BATCH_SIZE + 10);
    Test.stopTest();

    // Chaining is skipped in tests, so only the first batch is processed here.
    Assert.areEqual(CaseTriageQueueable.BATCH_SIZE, mock.calls);
    Assert.areEqual(
      10,
      [SELECT COUNT() FROM Case WHERE AI_Status__c = 'Pending']
    );
  }
}
