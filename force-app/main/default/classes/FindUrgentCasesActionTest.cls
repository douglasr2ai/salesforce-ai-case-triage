@IsTest
private class FindUrgentCasesActionTest {
  @TestSetup
  static void setup() {
    CaseTriggerHandler.bypass = true;
    insert new List<Case>{
      triaged('Server down', 'High', 'Negative'),
      triaged('Cancel my plan!!', 'High', 'Angry'),
      triaged('Thanks a lot', 'Low', 'Positive'),
      triaged('Wrong invoice', 'Medium', 'Angry'),
      new Case(Subject = 'Not triaged yet')
    };
    CaseTriggerHandler.bypass = false;
  }

  private static Case triaged(
    String subject,
    String priority,
    String sentiment
  ) {
    return new Case(
      Subject = subject,
      AI_Status__c = 'Completed',
      AI_Category__c = 'Billing',
      AI_Suggested_Priority__c = priority,
      AI_Sentiment__c = sentiment,
      AI_Summary__c = 'Summary of ' + subject
    );
  }

  @IsTest
  static void returnsUrgentCasesWithAngryCustomersFirst() {
    FindUrgentCasesAction.Result r = FindUrgentCasesAction.find(
      new List<FindUrgentCasesAction.Request>{
        new FindUrgentCasesAction.Request()
      }
    )[0];

    Assert.areEqual(3, r.caseCount);
    List<String> lines = r.urgentCases.split('\n');
    Assert.isTrue(lines[0].contains('Angry'), lines[0]);
    Assert.isTrue(lines[1].contains('Angry'), lines[1]);
    Assert.isTrue(lines[2].contains('Server down'), lines[2]);
    Assert.isFalse(r.urgentCases.contains('Thanks a lot'));
    Assert.isFalse(r.urgentCases.contains('Not triaged yet'));
  }

  @IsTest
  static void respectsMaxResults() {
    FindUrgentCasesAction.Request req = new FindUrgentCasesAction.Request();
    req.maxResults = 1;

    FindUrgentCasesAction.Result r = FindUrgentCasesAction.find(
      new List<FindUrgentCasesAction.Request>{ req }
    )[0];

    Assert.areEqual(1, r.caseCount);
    Assert.isTrue(r.urgentCases.contains('Angry'));
  }

  @IsTest
  static void saysSoWhenNothingIsUrgent() {
    delete [SELECT Id FROM Case];

    FindUrgentCasesAction.Result r = FindUrgentCasesAction.find(
      new List<FindUrgentCasesAction.Request>{
        new FindUrgentCasesAction.Request()
      }
    )[0];

    Assert.areEqual(0, r.caseCount);
    Assert.areEqual('No urgent open cases.', r.urgentCases);
  }
}
