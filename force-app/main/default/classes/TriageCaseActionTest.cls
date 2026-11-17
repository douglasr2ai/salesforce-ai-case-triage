@IsTest
private class TriageCaseActionTest {
  @TestSetup
  static void setup() {
    CaseTriggerHandler.bypass = true;
    insert new Case(
      Subject = 'Double charge',
      Description = 'Charged twice',
      Origin = 'Email',
      Priority = 'Medium'
    );
    CaseTriggerHandler.bypass = false;
  }

  private static TriageCaseAction.Request request(String ref) {
    TriageCaseAction.Request r = new TriageCaseAction.Request();
    r.caseReference = ref;
    return r;
  }

  @IsTest
  static void triagesCaseByShortCaseNumberAndSavesResult() {
    Case c = [SELECT Id, CaseNumber FROM Case LIMIT 1];
    String shortNumber = String.valueOf(Integer.valueOf(c.CaseNumber)); // "00001029" -> "1029"
    Test.setMock(
      HttpCalloutMock.class,
      OpenRouterMock.success(OpenRouterMock.sampleTriage())
    );

    Test.startTest();
    List<TriageCaseAction.Result> results = TriageCaseAction.triage(
      new List<TriageCaseAction.Request>{ request('#' + shortNumber) }
    );
    Test.stopTest();

    TriageCaseAction.Result r = results[0];
    Assert.isTrue(r.success, 'Triage failed: ' + r.errorMessage);
    Assert.areEqual(c.CaseNumber, r.caseNumber);
    Assert.areEqual('Billing', r.category);
    Assert.areEqual('High', r.suggestedPriority);
    Assert.areEqual('Medium', r.currentPriority);
    Assert.areEqual('Angry', r.sentiment);
    Assert.isNotNull(r.suggestedReply);

    Case saved = [
      SELECT AI_Status__c, AI_Category__c
      FROM Case
      WHERE Id = :c.Id
    ];
    Assert.areEqual('Completed', saved.AI_Status__c);
    Assert.areEqual('Billing', saved.AI_Category__c);
  }

  @IsTest
  static void acceptsRecordIdAndReportsUnknownCases() {
    Case c = [SELECT Id FROM Case LIMIT 1];
    Test.setMock(
      HttpCalloutMock.class,
      OpenRouterMock.success(OpenRouterMock.sampleTriage())
    );

    Test.startTest();
    List<TriageCaseAction.Result> results = TriageCaseAction.triage(
      new List<TriageCaseAction.Request>{
        request(c.Id),
        request('99999999'),
        request('  ')
      }
    );
    Test.stopTest();

    Assert.areEqual(3, results.size());
    Assert.isTrue(results[0].success);
    Assert.isFalse(results[1].success);
    Assert.isTrue(results[1].errorMessage.contains('99999999'));
    Assert.isFalse(results[2].success);
  }

  @IsTest
  static void returnsLlmErrorWhenTriageFails() {
    Test.setMock(
      HttpCalloutMock.class,
      new OpenRouterMock(401, '{"error":{"message":"No auth"}}')
    );
    Case c = [SELECT CaseNumber FROM Case LIMIT 1];

    Test.startTest();
    TriageCaseAction.Result r = TriageCaseAction.triage(
      new List<TriageCaseAction.Request>{ request(c.CaseNumber) }
    )[0];
    Test.stopTest();

    Assert.isFalse(r.success);
    Assert.isTrue(r.errorMessage.contains('No auth'), r.errorMessage);
    Assert.areEqual(
      'Failed',
      [SELECT AI_Status__c FROM Case LIMIT 1].AI_Status__c
    );
  }

  @IsTest
  static void capsTheNumberOfCalloutsPerRequest() {
    Case c = [SELECT CaseNumber FROM Case LIMIT 1];
    OpenRouterMock mock = OpenRouterMock.success(OpenRouterMock.sampleTriage());
    Test.setMock(HttpCalloutMock.class, mock);
    List<TriageCaseAction.Request> requests = new List<TriageCaseAction.Request>();
    for (Integer i = 0; i < TriageCaseAction.MAX_REQUESTS + 2; i++) {
      requests.add(request(c.CaseNumber));
    }

    Test.startTest();
    List<TriageCaseAction.Result> results = TriageCaseAction.triage(requests);
    Test.stopTest();

    Assert.areEqual(TriageCaseAction.MAX_REQUESTS, mock.calls);

    Assert.isTrue(
      results[0].success,
      'Repeated references to one case are fine'
    );
    Assert.isFalse(results[results.size() - 1].success);
  }
}
