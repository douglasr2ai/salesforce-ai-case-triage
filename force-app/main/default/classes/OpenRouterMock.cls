/**
 * Fake OpenRouter endpoint for unit tests. Records how many calls it received.
 */
@IsTest
public class OpenRouterMock implements HttpCalloutMock {
  public Integer statusCode;
  public String body;
  public Integer calls = 0;
  public HttpRequest lastRequest;

  public OpenRouterMock(Integer statusCode, String body) {
    this.statusCode = statusCode;
    this.body = body;
  }

  /** A successful chat completion whose message content is the given JSON. */
  public static OpenRouterMock success(Map<String, Object> triage) {
    Map<String, Object> payload = new Map<String, Object>{
      'model' => 'anthropic/claude-haiku-5.5',
      'choices' => new List<Object>{
        new Map<String, Object>{
          'message' => new Map<String, Object>{
            'role' => 'assistant',
            'content' => JSON.serialize(triage)
          }
        }
      }
    };
    return new OpenRouterMock(200, JSON.serialize(payload));
  }

  public static Map<String, Object> sampleTriage() {
    return new Map<String, Object>{
      'category' => 'Billing',
      'priority' => 'High',
      'sentiment' => 'Angry',
      'summary' => 'Customer was charged twice for the same invoice.',
      'suggested_reply' => 'Hi! Sorry about the double charge, we are looking into it.'
    };
  }

  public HttpResponse respond(HttpRequest req) {
    calls++;
    lastRequest = req;
    HttpResponse res = new HttpResponse();
    res.setStatusCode(statusCode);
    res.setHeader('Content-Type', 'application/json');
    res.setBody(body);
    return res;
  }
}
