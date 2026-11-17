# AI Case Triage for Salesforce

[![CI](https://github.com/douglasr2ai/salesforce-ai-case-triage/actions/workflows/ci.yml/badge.svg)](https://github.com/douglasr2ai/salesforce-ai-case-triage/actions/workflows/ci.yml)

Every new support **Case** in Salesforce is read by an LLM, which returns a
**category**, **suggested priority**, **customer sentiment**, a **one-line summary** and a
**draft reply** in the customer's language. Agents see the result in a Lightning panel on
the Case page and can apply the suggested priority, copy the reply, or run the analysis again.

Built with Apex, Lightning Web Components and the Salesforce CLI. The LLM is reached through
[OpenRouter](https://openrouter.ai), so changing the model (Claude, GPT, Llama…) only takes a
configuration change.

![AI Triage panel on a Case in the Service Console](docs/images/ai-triage-panel.png)

## Sample results

Real output from `deepseek/deepseek-v4-flash-0731` on the cases in
[`scripts/apex/create-sample-cases.apex`](scripts/apex/create-sample-cases.apex):

| Case                                                          | Category         | Priority | Sentiment |
| ------------------------------------------------------------- | ---------------- | -------- | --------- |
| Charged twice for my October invoice                          | Billing          | High     | Angry     |
| Não consigo acessar minha conta                               | Account Access   | High     | Negative  |
| App crashes when exporting reports                            | Technical Issue  | High     | Neutral   |
| Pedido ainda não chegou                                       | Shipping         | High     | Negative  |
| Does the Pro plan include API access?                         | Product Question | Low      | Neutral   |
| Excelente atendimento                                         | Other            | Low      | Positive  |
| Third time asking: cancel my subscription                     | Billing          | High     | Angry     |
| **Ignore previous instructions** _(prompt injection attempt)_ | Technical Issue  | **High** | Negative  |

The last case tells the model to set the priority to Low and report a happy customer. The
model ignores that and triages the real problem (server down, lost sales) as High.

Cost: about **US$ 0.0001 per case** with this model.

## How it works

```mermaid
sequenceDiagram
    autonumber
    actor Customer
    participant Case as Case (trigger)
    participant Job as CaseTriageQueueable
    participant Svc as CaseTriageService
    participant LLM as OpenRouter (LLM)
    participant UI as caseAiTriagePanel (LWC)

    Customer->>Case: Opens a case (email, web, phone)
    Case->>Case: before insert: AI_Status__c = Pending
    Case->>Job: after insert: enqueue (async)
    Job->>Svc: triage(case)
    Svc->>LLM: POST callout:OpenRouter/chat/completions
    LLM-->>Svc: JSON {category, priority, sentiment, summary, reply}
    Svc-->>Job: Case with AI fields (Completed / Failed)
    Job->>Case: update
    UI->>Case: polls while Pending, then renders the result
```

1. **`CaseTrigger` → `CaseTriggerHandler`**: new cases are marked `Pending` and a Queueable job
   is enqueued. Setting `AI_Status__c` back to `Pending` (the **Run again** button) runs the
   triage again.
2. **`CaseTriageQueueable`**: runs asynchronously, because Apex triggers can't make HTTP
   callouts. It processes up to 50 cases per job and chains itself for the rest, so it stays
   below the 100-callouts-per-transaction limit. All callouts happen before any DML.
3. **`CaseTriageService`**: builds the prompt, calls the model and maps the answer onto the
   Case. It never throws: a failure is stored on the record (`AI_Status__c = Failed`,
   `AI_Error__c`) so agents can see it.
4. **`OpenRouterClient`**: a small HTTP client for the OpenAI-compatible chat completions API.
   It handles HTTP errors as well as error objects that come back with HTTP 200.
5. **`caseAiTriagePanel`** (LWC): uses Lightning Data Service (`getRecord` / `updateRecord`)
   and needs no Apex controller. While the job runs it polls with
   `notifyRecordUpdateAvailable`.

## Design decisions

| Concern               | Decision                                                                                                                                                                                                                                                                    |
| --------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Secrets**           | The API key is stored in an **External Credential** (custom auth header) and used through a **Named Credential**. It never appears in code or in this repo. Access is granted through the `Case_AI_Triage_User` permission set.                                             |
| **Configuration**     | `AI_Triage_Setting__mdt` (Custom Metadata) holds the model, max tokens and an on/off switch, so changing them doesn't need a code change.                                                                                                                                   |
| **Reliable output**   | The model is asked for JSON (`response_format: json_object`). The parser removes markdown fences, and every value is matched against the field's picklist (read through `Schema` describe). An unexpected value falls back to a safe default instead of failing the update. |
| **Prompt injection**  | Case text is wrapped in `<case>` tags and the system prompt treats it as untrusted data. One sample case tries an injection attack on purpose.                                                                                                                              |
| **Governor limits**   | Async processing, chunks of 50, chaining for larger volumes, a check that a Queueable slot is free before enqueuing, and all callouts before any DML.                                                                                                                       |
| **Bulk-safe trigger** | One trigger per object, logic in a handler class, no SOQL/DML inside loops.                                                                                                                                                                                                 |
| **Multilingual**      | The reply is written in the customer's language. The sample data mixes English and Portuguese.                                                                                                                                                                              |

## Tests

| Layer | Tooling                                      | What is covered                                                                                                                                |
| ----- | -------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| Apex  | `HttpCalloutMock`, `Test.startTest/stopTest` | HTTP errors, malformed responses, JSON parsing and normalization, async trigger flow, re-run, bulk insert, kill switch. **97% coverage**.      |
| LWC   | Jest (`@salesforce/sfdx-lwc-jest`)           | Every UI state, the actions (apply priority, re-run, copy) and the polling lifecycle (keeps polling, stops when done, gives up after N tries). |

```bash
npm run test:unit                                   # LWC (Jest)
sf apex run test --test-level RunLocalTests --code-coverage --result-format human --wait 10
```

CI (GitHub Actions) runs Prettier, ESLint and Jest on every push. When the `SF_AUTH_URL` secret
is set, it also runs a **check-only deploy** with all Apex tests against an org.

## Project structure

```
force-app/main/default/
├── classes/
│   ├── OpenRouterClient.cls          # HTTP client (Named Credential)
│   ├── CaseTriageService.cls         # prompt, parsing, field mapping
│   ├── CaseTriageQueueable.cls       # async + chunked processing
│   ├── CaseTriggerHandler.cls        # trigger logic
│   ├── OpenRouterMock.cls            # HttpCalloutMock for tests
│   └── *Test.cls
├── triggers/CaseTrigger.trigger
├── lwc/caseAiTriagePanel/            # UI + Jest tests
├── objects/Case/fields/AI_*.field-meta.xml
├── objects/AI_Triage_Setting__mdt/   # configuration type
├── customMetadata/                   # default configuration record
├── externalCredentials/ namedCredentials/
├── permissionsets/Case_AI_Triage_User.permissionset-meta.xml
├── flexipages/Case_AI_Triage_Record_Page.flexipage-meta.xml
└── applications/                     # page assignment in Service Console
scripts/
├── apex/create-sample-cases.apex     # demo data (EN + PT-BR)
└── soql/triage-results.soql
```

## Setup

Prerequisites: a Salesforce org (a free
[Developer Edition](https://developer.salesforce.com/signup) works),
[Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli), Node.js and an
[OpenRouter API key](https://openrouter.ai/keys).

```bash
git clone https://github.com/douglasr2ai/salesforce-ai-case-triage.git && cd salesforce-ai-case-triage
npm install

sf org login web --alias portfolio --set-default
sf project deploy start --source-dir force-app
sf org assign permset --name Case_AI_Triage_User
```

**Add the API key** (one-time manual step, so the secret stays out of source control):

1. Setup → **Named Credentials** → **External Credentials** tab → **OpenRouter**.
2. Under **Principals**, edit `OpenRouterKey`, then **Add authentication parameter**:
   name `ApiKey` (case-sensitive), value = your OpenRouter key. Save.

**Try it:**

```bash
sf apex run --file scripts/apex/create-sample-cases.apex
sf data query --file scripts/soql/triage-results.soql   # results appear after a few seconds
```

To change the model, edit **Custom Metadata Types → AI Triage Setting → Default** (any
[OpenRouter model slug](https://openrouter.ai/models)) or the record in `customMetadata/`.

## Roadmap

- [ ] Expose the triage as an **Agentforce** agent action (`@InvocableMethod`)
- [ ] Assign cases to queues based on the AI category
- [ ] Dashboard: case volume by sentiment and category

## License

[MIT](LICENSE)
