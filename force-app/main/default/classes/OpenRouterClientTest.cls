@IsTest
private class OpenRouterClientTest {
  @IsTest
  static void returnsMessageContentAndSendsExpectedRequest() {
    OpenRouterMock mock = OpenRouterMock.success(
      new Map<String, Object>{ 'ok' => true }
    );
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    OpenRouterClient.ChatResponse res = OpenRouterClient.chat(
      'some/model',
      'system',
      'user',
      100
    );
    Test.stopTest();

    Assert.areEqual('{"ok":true}', res.content);
    Assert.areEqual('anthropic/claude-haiku-5.5', res.model);
    Assert.areEqual(OpenRouterClient.ENDPOINT, mock.lastRequest.getEndpoint());
    Assert.areEqual('POST', mock.lastRequest.getMethod());
    Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(
      mock.lastRequest.getBody()
    );
    Assert.areEqual('some/model', sent.get('model'));
    Assert.areEqual(2, ((List<Object>) sent.get('messages')).size());
  }

  @IsTest
  static void throwsOnHttpErrorWithProviderMessage() {
    Test.setMock(
      HttpCalloutMock.class,
      new OpenRouterMock(
        401,
        '{"error":{"message":"No auth credentials found","code":401}}'
      )
    );
    try {
      OpenRouterClient.chat('m', 's', 'u', 10);
      Assert.fail('Expected an exception');
    } catch (OpenRouterClient.OpenRouterException e) {
      Assert.isTrue(e.getMessage().contains('401'), e.getMessage());
      Assert.isTrue(
        e.getMessage().contains('No auth credentials found'),
        e.getMessage()
      );
    }
  }

  @IsTest
  static void throwsOnErrorObjectWithHttp200() {
    Test.setMock(
      HttpCalloutMock.class,
      new OpenRouterMock(200, '{"error":{"message":"Provider overloaded"}}')
    );
    try {
      OpenRouterClient.chat('m', 's', 'u', 10);
      Assert.fail('Expected an exception');
    } catch (OpenRouterClient.OpenRouterException e) {
      Assert.isTrue(
        e.getMessage().contains('Provider overloaded'),
        e.getMessage()
      );
    }
  }

  @IsTest
  static void throwsOnMalformedResponses() {
    for (
      String body : new List<String>{
        'not json',
        '{"choices":[]}',
        '{"choices":[{"message":{"content":""}}]}'
      }
    ) {
      try {
        OpenRouterClient.parseResponse(body);
        Assert.fail('Expected an exception for: ' + body);
      } catch (OpenRouterClient.OpenRouterException e) {
        Assert.isNotNull(e.getMessage());
      }
    }
  }

  @IsTest
  static void throwsOnHttpErrorWithPlainBody() {
    Test.setMock(HttpCalloutMock.class, new OpenRouterMock(502, 'Bad Gateway'));
    try {
      OpenRouterClient.chat('m', 's', 'u', 10);
      Assert.fail('Expected an exception');
    } catch (OpenRouterClient.OpenRouterException e) {
      Assert.isTrue(e.getMessage().contains('Bad Gateway'), e.getMessage());
    }
  }
}
