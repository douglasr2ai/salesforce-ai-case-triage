# AI Case Triage for Salesforce

[![CI](https://github.com/douglasr2ai/salesforce-ai-case-triage/actions/workflows/ci.yml/badge.svg)](https://github.com/douglasr2ai/salesforce-ai-case-triage/actions/workflows/ci.yml)

Every new support **Case** in Salesforce is read by an LLM, which returns a
**category**, **suggested priority**, **customer sentiment**, a **one-line summary** and a
**draft reply** in the customer's language. Agents see the result in a Lightning panel on
the Case page and can apply the suggested priority, copy the reply, or run the analysis again.

An **Agentforce** employee agent, **Support Copilot**, uses the same triage as tools: support
agents can ask _"which cases are urgent?"_ or _"analisa o caso 1035"_ in English or Portuguese.

Built with Apex, Lightning Web Components, Agentforce (Agent Script) and the Salesforce CLI. The LLM is reached through
[OpenRouter](https://openrouter.ai), so changing the model (Claude, GPT, Llama…) only takes a
configuration change.

![Demo: running the AI triage on a Portuguese case, applying the suggested priority and copying the reply](docs/images/ai-triage-demo.gif)

_Run again → the async job calls the LLM → the panel updates by itself → apply the suggested priority → copy the draft reply._

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

## Agentforce: Support Copilot

An internal agent (`AgentforceEmployeeAgent`) defined in
[`Support_Copilot.agent`](force-app/main/default/aiAuthoringBundles/Support_Copilot/Support_Copilot.agent)
with **Agent Script**, so the whole agent is versioned as code. It shows up in the Agentforce panel in
Lightning and runs as the logged-in user.

| Subagent       | Tool (Apex `@InvocableMethod`)                                                      | What it does                                                                                                                                |
| -------------- | ----------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `case_triage`  | [`TriageCaseAction`](force-app/main/default/classes/TriageCaseAction.cls)           | Triages one case right away and saves the result. Accepts `00001029`, `1029`, `#1029` or a record Id. Remembers the last case ("that one"). |
| `urgent_cases` | [`FindUrgentCasesAction`](force-app/main/default/classes/FindUrgentCasesAction.cls) | Lists open cases flagged High priority or Angry/Negative, angry customers first.                                                            |
| `off_topic`    | none                                                                                | Declines anything unrelated to support cases.                                                                                               |

Real conversation (live actions, `sf agent preview`):

> **User:** Me mostra os 3 casos mais urgentes
>
> **Support Copilot:** Aqui estão os 3 casos mais urgentes no momento:
> 00001028 · Charged twice for my October invoice · Angry · High …
>
> **User:** Analisa o caso 1035 pra mim
>
> **Support Copilot:** Resumo: O servidor do cliente está fora do ar, causando perda de vendas…
> Categoria: Problema técnico · Sentimento: Negativo · Prioridade sugerida: Alta (atualmente Média).
> Resposta sugerida: _"Thank you for reaching out…"_ (the customer wrote in English)
>
> **User:** Qual a capital da França?
>
> **Support Copilot:** Posso ajudar apenas com casos de suporte…

**Agent tests** ([`specs/Support_Copilot-testSpec.yaml`](specs/Support_Copilot-testSpec.yaml), Agentforce
Testing Center): 7 cases in English and Portuguese covering routing, tool selection, asking for a
missing case number, off-topic questions and a prompt-injection attempt (stopped by the platform's
built-in guardrail before reaching any subagent). **100% topic, action and outcome pass rate.**

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
| Agent | Agentforce Testing Center (`sf agent test`)  | Routing, tool selection, missing input, off-topic and prompt injection, judged on topic, actions and outcome.                                  |

```bash
npm run test:unit                                   # LWC (Jest)
sf apex run test --test-level RunLocalTests --code-coverage --result-format human --wait 10
sf agent test run --api-name Support_Copilot_Tests --wait 15 --result-format human
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
│   ├── TriageCaseAction.cls          # agent tool: triage one case
│   ├── FindUrgentCasesAction.cls     # agent tool: list urgent cases
│   ├── CaseReferenceResolver.cls     # "1029" / "#1029" / Id -> Case
│   ├── OpenRouterMock.cls            # HttpCalloutMock for tests
│   └── *Test.cls
├── aiAuthoringBundles/Support_Copilot/  # Agentforce agent (Agent Script)
├── triggers/CaseTrigger.trigger
├── lwc/caseAiTriagePanel/            # UI + Jest tests
├── objects/Case/fields/AI_*.field-meta.xml
├── objects/AI_Triage_Setting__mdt/   # configuration type
├── customMetadata/                   # default configuration record
├── externalCredentials/ namedCredentials/
├── permissionsets/Case_AI_Triage_User.permissionset-meta.xml
├── flexipages/Case_AI_Triage_Record_Page.flexipage-meta.xml
└── applications/                     # page assignment in Service Console
agent-access/                         # agent access permission set (deploy after publishing)
specs/Support_Copilot-testSpec.yaml   # agent tests
scripts/
├── apex/create-sample-cases.apex     # demo data (EN + PT-BR)
└── soql/triage-results.soql
```

## Setup

Prerequisites: a Salesforce org with Agentforce enabled (a free
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

**Publish the agent** (the access permission set can only be deployed once the agent exists):

```bash
sf agent publish authoring-bundle --api-name Support_Copilot
sf agent activate --api-name Support_Copilot
sf project deploy start --source-dir agent-access
sf org assign permset --name Support_Copilot_Access
sf agent test create --spec specs/Support_Copilot-testSpec.yaml --api-name Support_Copilot_Tests
```

To change the model, edit **Custom Metadata Types → AI Triage Setting → Default** (any
[OpenRouter model slug](https://openrouter.ai/models)) or the record in `customMetadata/`.

## Roadmap

- [x] Expose the triage as an **Agentforce** agent (`@InvocableMethod` tools + Agent Script)
- [ ] Assign cases to queues based on the AI category
- [ ] Dashboard: case volume by sentiment and category

## License

[MIT](LICENSE)
