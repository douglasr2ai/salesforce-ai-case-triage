@IsTest
private class CaseTriageServiceTest {
    @IsTest
    static void mapsModelAnswerOntoCaseFields() {
        Test.setMock(HttpCalloutMock.class, OpenRouterMock.success(OpenRouterMock.sampleTriage()));
        Case source = new Case(Subject = 'Double charge', Description = 'You charged me twice!', Origin = 'Email');

        Test.startTest();
        Case result = CaseTriageService.triage(source);
        Test.stopTest();

        Assert.areEqual(CaseTriageService.STATUS_COMPLETED, result.AI_Status__c);
        Assert.areEqual('Billing', result.AI_Category__c);
        Assert.areEqual('High', result.AI_Suggested_Priority__c);
        Assert.areEqual('Angry', result.AI_Sentiment__c);
        Assert.areEqual('Customer was charged twice for the same invoice.', result.AI_Summary__c);
        Assert.isTrue(result.AI_Suggested_Reply__c.startsWith('Hi!'));
        Assert.areEqual('anthropic/claude-haiku-5.5', result.AI_Model__c);
        Assert.isNotNull(result.AI_Processed_At__c);
        Assert.isNull(result.AI_Error__c);
    }

    @IsTest
    static void recordsFailureInsteadOfThrowing() {
        Test.setMock(HttpCalloutMock.class, new OpenRouterMock(500, '{"error":{"message":"boom"}}'));

        Case result = CaseTriageService.triage(new Case(Subject = 'x'));

        Assert.areEqual(CaseTriageService.STATUS_FAILED, result.AI_Status__c);
        Assert.isTrue(result.AI_Error__c.contains('boom'), result.AI_Error__c);
    }

    @IsTest
    static void parseNormalizesValuesAndStripsCodeFences() {
        String content = '```json\n{"category":"billing","priority":"URGENT","sentiment":null,"summary":"s","suggested_reply":"r"}\n```';

        CaseTriageService.TriageResult r = CaseTriageService.parse(content);

        Assert.areEqual('Billing', r.category, 'case-insensitive match');
        Assert.areEqual('Medium', r.priority, 'unknown value falls back');
        Assert.areEqual('Neutral', r.sentiment, 'missing value falls back');
        Assert.areEqual('s', r.summary);
        Assert.areEqual('r', r.suggestedReply);
    }

    @IsTest
    static void invalidJsonFromModelMarksCaseFailed() {
        Map<String, Object> payload = new Map<String, Object>{
            'choices' => new List<Object>{
                new Map<String, Object>{ 'message' => new Map<String, Object>{ 'content' => 'Sorry, I cannot help.' } }
            }
        };
        Test.setMock(HttpCalloutMock.class, new OpenRouterMock(200, JSON.serialize(payload)));

        Case result = CaseTriageService.triage(new Case(Subject = 'x'));

        Assert.areEqual(CaseTriageService.STATUS_FAILED, result.AI_Status__c);
    }

    @IsTest
    static void promptsListPicklistValuesAndWrapCaseData() {
        String systemPrompt = CaseTriageService.buildSystemPrompt();
        Assert.isTrue(systemPrompt.contains('"Billing"'));
        Assert.isTrue(systemPrompt.contains('"Angry"'));
        Assert.isFalse(systemPrompt.contains('{categories}'));

        String userPrompt = CaseTriageService.buildUserPrompt(new Case(Subject = 'Hello', Description = null));
        Assert.isTrue(userPrompt.startsWith('<case>'));
        Assert.isTrue(userPrompt.contains('Subject: Hello'));
        Assert.isTrue(userPrompt.contains('Channel: Unknown'));
    }

    @IsTest
    static void usesDefaultsWhenSettingsAreIncomplete() {
        CaseTriageService.settingsOverride = new AI_Triage_Setting__mdt(Enabled__c = false);
        Test.setMock(HttpCalloutMock.class, OpenRouterMock.success(OpenRouterMock.sampleTriage()));

        Assert.isFalse(CaseTriageService.isEnabled());
        OpenRouterMock mock = OpenRouterMock.success(OpenRouterMock.sampleTriage());
        Test.setMock(HttpCalloutMock.class, mock);
        CaseTriageService.triage(new Case(Subject = 'x'));

        Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(mock.lastRequest.getBody());
        Assert.areEqual(CaseTriageService.DEFAULT_MODEL, sent.get('model'));
        Assert.areEqual(800, sent.get('max_tokens'));
    }
}
