/**
 * Thin HTTP client for the OpenRouter chat completions API (OpenAI-compatible).
 * Authentication is handled by the OpenRouter Named Credential, so no secret
 * ever appears in code.
 */
public with sharing class OpenRouterClient {
    @TestVisible
    private static final String ENDPOINT = 'callout:OpenRouter/chat/completions';
    private static final Integer TIMEOUT_MS = 60000;

    public class OpenRouterException extends Exception {
    }

    public class ChatResponse {
        public String content;
        public String model;
    }

    /**
     * Sends a single-turn chat request and returns the assistant message.
     * The model is asked to answer with a JSON object.
     */
    public static ChatResponse chat(String model, String systemPrompt, String userPrompt, Integer maxTokens) {
        Map<String, Object> body = new Map<String, Object>{
            'model' => model,
            'max_tokens' => maxTokens,
            'temperature' => 0.2,
            'response_format' => new Map<String, Object>{ 'type' => 'json_object' },
            'messages' => new List<Object>{
                new Map<String, Object>{ 'role' => 'system', 'content' => systemPrompt },
                new Map<String, Object>{ 'role' => 'user', 'content' => userPrompt }
            }
        };

        HttpRequest req = new HttpRequest();
        req.setEndpoint(ENDPOINT);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(TIMEOUT_MS);
        req.setBody(JSON.serialize(body));

        HttpResponse res;
        try {
            res = new Http().send(req);
        } catch (CalloutException e) {
            throw new OpenRouterException('Callout to OpenRouter failed: ' + e.getMessage());
        }

        Integer status = res.getStatusCode();
        if (status < 200 || status >= 300) {
            throw new OpenRouterException('OpenRouter returned HTTP ' + status + ': ' + extractError(res.getBody()));
        }
        return parseResponse(res.getBody());
    }

    @TestVisible
    private static ChatResponse parseResponse(String rawBody) {
        Map<String, Object> parsed;
        try {
            parsed = (Map<String, Object>) JSON.deserializeUntyped(rawBody);
        } catch (Exception e) {
            throw new OpenRouterException('OpenRouter returned a non-JSON response.');
        }
        // OpenRouter can report provider errors with HTTP 200.
        if (parsed.containsKey('error')) {
            throw new OpenRouterException('OpenRouter error: ' + extractError(rawBody));
        }

        List<Object> choices = (List<Object>) parsed.get('choices');
        if (choices == null || choices.isEmpty()) {
            throw new OpenRouterException('OpenRouter response contained no choices.');
        }
        Map<String, Object> message = (Map<String, Object>) ((Map<String, Object>) choices[0]).get('message');

        ChatResponse out = new ChatResponse();
        out.content = message == null ? null : (String) message.get('content');
        out.model = (String) parsed.get('model');
        if (String.isBlank(out.content)) {
            throw new OpenRouterException('OpenRouter response had an empty message.');
        }
        return out;
    }

    private static String extractError(String rawBody) {
        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(rawBody);
            Object err = parsed.get('error');
            if (err instanceof Map<String, Object>) {
                Object msg = ((Map<String, Object>) err).get('message');
                if (msg != null) {
                    return String.valueOf(msg);
                }
            }
        } catch (Exception ignored) {
            // Fall through to the raw body.
        }
        return String.isBlank(rawBody) ? '(empty body)' : rawBody.abbreviate(500);
    }
}
