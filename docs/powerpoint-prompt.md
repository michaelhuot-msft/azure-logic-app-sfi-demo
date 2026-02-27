# PowerPoint Generation Prompt

Use the following prompt with an LLM that has PowerPoint slide generation capabilities. Copy everything between the `---` delimiters.

---

## Prompt

Create a professional PowerPoint presentation (16:9 aspect ratio) for a **20-minute educational session with a live demo** on the topic:

**"Azure Logic Apps: Building No-Code Integration Pipelines on Azure"**

**Audience**: Cloud engineers, solution architects, IT decision makers, and developers evaluating Azure integration services.

**Tone**: Educational and hands-on. Teach Logic Apps concepts by example — use a real deployed pipeline (healthcare referral routing) as the running demo, but keep the focus on Logic Apps capabilities, patterns, and best practices that apply to any domain.

**Design**: Use the Microsoft_brand_template_May2023.potx. Minimize text per slide — favor diagrams, tables, and visual callouts. Use official Azure service icons where possible (Logic Apps, Service Bus, API Management, Key Vault, Log Analytics, Managed Grafana). All diagrams that reference any industry should be healthcare provider aligned.

---

### Slide-by-Slide Outline

**Slide 1 — Title Slide**
- Title: "Azure Logic Apps"
- Subtitle: "Building No-Code Integration Pipelines — From Concept to Production"
- Footer: Educational Session with Live Demo
- Visual: Azure Logic Apps icon prominently placed, with faint connected-service icons (Service Bus, APIM, Key Vault) forming a constellation pattern behind it

**Slide 2 — What Are Logic Apps?**
- Headline: "Azure Logic Apps at a Glance"
- Definition card: "A cloud-based integration platform that lets you automate workflows and connect services — with little or no code."
- Four key attributes as icon + label cards:
  1. **Visual Designer** — Build workflows graphically in the Azure Portal or VS Code
  2. **450+ Connectors** — Prebuilt connectors to Azure services, Microsoft 365, Salesforce, SAP, and hundreds more
  3. **Enterprise Integration** — Schema validation, message transformation, B2B protocols (EDI, AS2)
  4. **Consumption Pricing** — Pay only when workflows execute — no idle cost
- Bottom note: "Two hosting models: Consumption (multi-tenant, serverless) and Standard (single-tenant, VNet-integrated)"

**Slide 3 — When to Use Logic Apps**
- Headline: "Logic Apps vs. the Alternatives"
- Comparison table:

| Scenario | Logic Apps | Azure Functions | Power Automate | Durable Functions |
|----------|-----------|----------------|---------------|------------------|
| No-code integration | **Best fit** | Requires code | Good for simple flows | Requires code |
| Complex branching + conditions | **Built-in** | Manual coding | Limited | Manual coding |
| Enterprise connectors (SAP, EDI) | **450+ connectors** | Custom HTTP calls | Fewer connectors | Custom HTTP calls |
| Long-running orchestrations | **Stateful by default** | Stateless (use Durable) | Limited | **Best fit** |
| Citizen developer friendly | Moderate | No | **Best fit** | No |
| Fine-grained code control | Limited | **Best fit** | Limited | **Best fit** |

- Bottom callout: "Rule of thumb: Logic Apps for integration & orchestration, Functions for compute, Power Automate for end-user automation"

**Slide 4 — Core Concepts**
- Headline: "Anatomy of a Logic App Workflow"
- Annotated diagram of a generic workflow showing:
  1. **Trigger** — The event that starts the workflow (HTTP request, queue message, schedule, webhook)
  2. **Actions** — Steps that execute in sequence or parallel (call API, transform data, send message, condition)
  3. **Conditions & Loops** — If/else branches, for-each loops, switch cases, until loops
  4. **Connectors** — Managed (Azure-hosted) vs. built-in (in-process). API connections authenticate to external services.
  5. **Run History** — Every execution is logged with inputs/outputs at each step
- Side note: "Workflows are defined as JSON (Workflow Definition Language) — versionable, deployable via IaC"

**Slide 5 — Trigger Types**
- Headline: "How Workflows Start"
- Four trigger categories with examples:
  1. **Request (HTTP)** — Expose a REST endpoint. Callers POST data; workflow processes it and returns a response. _Used in demo: Intake Logic App._
  2. **Queue / Message** — Trigger when a message arrives in Service Bus, Event Hub, or Storage Queue. Polling-based with configurable interval. _Used in demo: Router Logic App polls incoming-referrals every 30s._
  3. **Schedule (Recurrence)** — Run on a cron-like schedule. Common for batch processing, nightly reports.
  4. **Event-driven (Webhook)** — Subscribe to events from Event Grid, GitHub, Dataverse, etc. Push-based — no polling overhead.
- Bottom note: "A workflow has exactly one trigger. Need multiple entry points? Create multiple workflows."

**Slide 6 — Connectors Deep Dive**
- Headline: "Connectors: The Integration Layer"
- Two-column layout:
  - **Left: Managed Connectors** — Hosted by Azure. Create an "API Connection" resource that stores auth credentials. Examples: Service Bus, SQL, Outlook, SharePoint, Salesforce, SAP.
  - **Right: Built-in Connectors** — Run in-process (lower latency). Examples: HTTP, Request/Response, Compose, Parse JSON, Variables, Control (conditions/loops).
- Callout box: "API Connections + Managed Identity"
  - Instead of storing credentials, use Managed Identity to authenticate to Azure services (Service Bus, Key Vault, SQL)
  - _Demo uses this pattern: Logic Apps authenticate to Service Bus via Managed Identity — zero passwords_
- Bottom note: "Custom connectors available for internal APIs via OpenAPI/Swagger definition"

**Slide 7 — Demo Architecture**
- Headline: "Today's Demo: A Two-Stage Integration Pipeline"
- Full architecture diagram showing the demo project:
  ```
  HTTP POST → API Management (rate-limited, API key) → Intake Logic App (validate + enrich) → Service Bus: incoming-referrals queue → Router Logic App (priority check) → urgent-referrals OR standard-referrals queue
  ```
- Cross-cutting services below:
  - Key Vault (secrets), Log Analytics (diagnostics), Managed Identity + RBAC (auth)
- Use colored grouping boxes: orange = API gateway, blue = Logic Apps, green = Service Bus, purple = observability, red/pink = security
- Annotations highlighting Logic Apps concepts:
  - "HTTP Request trigger with JSON schema validation"
  - "Compose action for data enrichment"
  - "Service Bus connector via Managed Identity"
  - "Conditional routing (If/Else on message property)"
- Bottom note: "Healthcare referral routing — but the patterns apply to any intake-validate-route workflow"

**Slide 8 — Logic App #1: Intake Workflow (Deep Dive)**
- Headline: "Intake Logic App — Request Trigger + Schema Validation"
- Visual workflow diagram showing 3 steps:
  1. **HTTP Request Trigger** — Defines a JSON schema with required fields (patientId, patientName, referralType, priority, diagnosis, referringProvider). Invalid payloads automatically return 400.
  2. **Compose: Enrich** — Uses `@guid()` and `@utcNow()` expressions to add correlationId, receivedAt, and status fields. Demonstrates Logic Apps expression language.
  3. **Send Message (Service Bus)** — Sends to `incoming-referrals` queue. Custom message properties set from workflow expressions. Uses API Connection with Managed Identity auth.
- Side callouts for each step explaining the Logic Apps concept demonstrated:
  - Step 1: "Schema validation is declarative — defined in the trigger, not in code"
  - Step 2: "Workflow expressions: `@guid()`, `@utcNow()`, `@triggerBody()` — a built-in expression language"
  - Step 3: "Connection authentication: `ManagedServiceIdentity` — no secrets in the workflow definition"
- Bottom: "The workflow returns HTTP 202 with the correlationId for tracking"

**Slide 9 — Logic App #2: Router Workflow (Deep Dive)**
- Headline: "Router Logic App — Queue Trigger + Conditional Routing"
- Visual workflow diagram showing 3 steps:
  1. **Service Bus Trigger** — Polls `incoming-referrals` queue every 30 seconds. Auto-completes messages on success.
  2. **Parse JSON** — Decodes Base64 message content, parses against expected schema. Demonstrates content transformation.
  3. **Condition (If/Else)** — Evaluates `@or(@equals(body('Parse_Message')?['priority'], 'urgent'), @equals(body('Parse_Message')?['priority'], 'high'))`. True branch sends to `urgent-referrals`; False branch sends to `standard-referrals`.
- Side callouts:
  - "Queue triggers: polling interval is configurable — balance cost vs. latency"
  - "Parse JSON: always validate message structure after deserialization"
  - "Conditions: combine with `@and()`, `@or()`, `@not()`, `@equals()`, `@contains()`, `@greater()` expressions"
- Bottom: "Two Logic Apps form a decoupled pipeline — change routing logic without touching intake"

**Slide 10 — Workflow Expressions & Data Operations**
- Headline: "The Logic Apps Expression Language"
- Three sections:
  - **String & Data**: `@guid()`, `@utcNow()`, `@concat()`, `@substring()`, `@replace()`, `@json()`, `@base64()`, `@base64ToString()`
  - **References**: `@triggerBody()`, `@triggerOutputs()`, `@body('ActionName')`, `@outputs('ActionName')`, `@actions('ActionName')?['status']`
  - **Logic**: `@equals()`, `@and()`, `@or()`, `@not()`, `@if()`, `@contains()`, `@greater()`, `@less()`
- Practical example from the demo:
  ```
  Compose Enriched Referral:
  {
    "correlationId": "@{guid()}",
    "receivedAt": "@{utcNow()}",
    "status": "received",
    "patientId": "@{triggerBody()?['patientId']}",
    ...
  }
  ```
- Bottom note: "Full reference: learn.microsoft.com/azure/logic-apps/workflow-definition-language-functions-reference"

**Slide 11 — Identity & Security for Logic Apps**
- Headline: "Securing Logic Apps in Production"
- Four patterns as numbered cards:
  1. **SystemAssigned Managed Identity** — Enable on the Logic App → Azure creates and manages the service principal. Use it to authenticate to Azure services (Service Bus, Key Vault, SQL, Storage) without embedding keys.
  2. **API Connection + Managed Identity** — API Connections can use the Logic App's managed identity instead of stored credentials. Set `authentication.type: ManagedServiceIdentity` in the connection config.
  3. **RBAC Scoping** — Grant only the roles each Logic App needs. Intake: Service Bus Data Sender. Router: Service Bus Data Sender + Receiver. Scope to the specific resource, not the resource group.
  4. **Securing the HTTP Trigger** — Options: place behind API Management (subscription key + rate limiting), use Azure AD OAuth, or restrict by IP range. _Demo uses APIM as the front door._
- Bottom: "Best practice: never put secrets in workflow definitions — use Managed Identity or Key Vault references"

**Slide 12 — Deploying Logic Apps with Bicep IaC**
- Headline: "Logic Apps as Infrastructure-as-Code"
- Two-column layout:
  - **Left: Why IaC for Logic Apps?**
    - Workflow definitions are JSON — embed directly in Bicep templates
    - Version-controlled, PR-reviewable, repeatable across environments
    - Deploy workflow + identity + role assignments + connections in one template
    - No Portal click-ops drift
  - **Right: Module structure from the demo**
    ```
    main.bicep orchestrates:
    ├── log-analytics.bicep
    ├── service-bus.bicep → key-vault.bicep
    ├── api-connections.bicep → logic-app-intake.bicep → apim.bicep
    │                        → logic-app-router.bicep
    ├── role-assignments.bicep
    ├── grafana.bicep
    └── diagnostics.bicep
    ```
- Key Bicep patterns highlighted:
  - `Microsoft.Logic/workflows` resource type with inline workflow definition
  - `identity: { type: 'SystemAssigned' }` enables managed identity
  - `listCallbackUrl()` extracts the HTTP trigger URL post-deployment
  - API Connection wiring via `$connections` parameter in workflow definition
- Bottom: "One command deploys everything: `./deploy.ps1` — ~5 minutes"

**Slide 13 — DEMO INTRO (Transition Slide)**
- Large centered text: "Live Demo"
- Subtitle: "See These Concepts in Action"
- Four numbered steps as a horizontal timeline:
  1. Explore the deployed Logic Apps in Azure Portal
  2. Send test messages (valid + invalid) and watch schema validation
  3. Trace message flow through run history
  4. Inspect conditional routing and queue delivery

**Slide 14 — Demo: Logic App Designer & Run History**
- Headline: "Inside the Azure Portal"
- Two screenshot placeholders side by side:
  - **Left: Workflow Designer** — Shows the Intake Logic App visual flow (trigger → compose → send message → response) in the Portal designer view
  - **Right: Run History** — Shows 3 runs (2 succeeded, 1 failed) with timestamps and status indicators
- Callout: "Every run captures full inputs and outputs at every step — click any action to inspect its data"
- Bottom note: "The designer and run history work identically whether the workflow was built in Portal or deployed via Bicep"

**Slide 15 — Demo: Schema Validation in Action**
- Headline: "Trigger Schema = Automatic Input Validation"
- Two-column layout:
  - **Left: Valid Payload** — JSON body with all required fields → HTTP 202 Accepted → message on queue
  - **Right: Invalid Payload** — JSON body missing required fields → HTTP 400 Bad Request → no message on queue, run marked as failed
- Show the JSON schema snippet from the trigger:
  ```json
  {
    "type": "object",
    "required": ["patientId", "patientName", "referralType",
                 "priority", "diagnosis", "referringProvider"],
    "properties": { ... }
  }
  ```
- Callout: "No code needed — the schema in the trigger definition handles validation. Bad data is rejected before any action executes."

**Slide 16 — Demo: Tracing a Message Through the Pipeline**
- Headline: "End-to-End Message Flow"
- Step-by-step visual trace (numbered):
  1. HTTP POST → APIM validates subscription key → proxies to Intake Logic App
  2. Intake trigger fires → validates schema → enriches payload → sends to `incoming-referrals` queue
  3. Router trigger fires (30s poll) → parses message → evaluates condition → routes to `urgent-referrals` or `standard-referrals`
- Screenshot placeholder: Logic App run detail view showing green checkmarks on each action
- Screenshot placeholder: Service Bus Queues blade showing message counts (1 urgent, 1 standard)
- Callout: "The `correlationId` (a GUID generated by the Intake workflow) lets you trace a single message across both Logic Apps and all three queues"

**Slide 17 — Demo: Observability**
- Headline: "Monitoring Logic Apps in Production"
- Two approaches shown:
  - **Azure Portal Run History** — Built-in, per-workflow, shows every run with pass/fail and per-action detail
  - **Log Analytics + Grafana** — Centralized across workflows. Diagnostic settings send `WorkflowRuntime` logs. Query with KQL or visualize in dashboards.
- Callout cards to include on the slide:
  - **APIM Requests (Total / Success / Failed)** — Use Azure Monitor metrics to show API traffic health over time.
  - **Recent Referral Activity** — Show latest workflow executions with status and tracking ID.
- KQL snippet:
  ```kql
  AzureDiagnostics
  | where ResourceProvider == "MICROSOFT.LOGIC"
  | where Category == "WorkflowRuntime"
  | project TimeGenerated, resource_workflowName_s, status_s
  | order by TimeGenerated desc | take 20
  ```
- Screenshot placeholder: Grafana dashboard highlighting **APIM Requests (Total / Success / Failed)**, Logic App run charts, and queue message flow
- Bottom note: "Enable Diagnostic Settings on every Logic App — it takes one Bicep resource"

**Slide 18 — Logic Apps Best Practices**
- Headline: "Patterns & Practices"
- Six best-practice cards in a 2×3 grid:
  1. **Use Managed Identity** — Eliminate stored credentials; authenticate via RBAC
  2. **Define schemas on triggers** — Reject bad data before it enters the workflow
  3. **Decouple with queues** — Use Service Bus between stages so each Logic App can scale and fail independently
  4. **Deploy as IaC** — Define workflows in Bicep/ARM templates; never rely on Portal as source of truth
  5. **Enable diagnostics** — Send `WorkflowRuntime` logs to Log Analytics for centralized monitoring
  6. **Idempotent design** — Service Bus has at-least-once delivery; design actions to handle duplicate messages
- Bottom note: "All six patterns are implemented in the demo project"

**Slide 19 — Common Logic Apps Patterns**
- Headline: "Patterns You'll Use Everywhere"
- Four integration patterns as visual cards:
  1. **Request-Response** — Expose a REST API backed by a Logic App. Validate, transform, return. _(Demo: Intake Logic App)_
  2. **Queue-Based Load Leveling** — Decouple producers and consumers with a message queue. Scale independently. _(Demo: Service Bus between Intake and Router)_
  3. **Content-Based Routing** — Inspect message content and route to different destinations based on field values. _(Demo: Router Logic App priority check)_
  4. **Scatter-Gather** — Fan out to multiple services in parallel, wait for all responses, aggregate results. _(Not in demo — mention as next-level pattern)_
- Bottom note: "These are cloud architecture patterns — Logic Apps makes them no-code"

**Slide 20 — Beyond the Demo**
- Headline: "What Else Can Logic Apps Do?"
- Five extension scenarios as bullet cards:
  1. **B2B Integration** — EDI/AS2 processing with Integration Accounts, partner management, X12/EDIFACT schemas
  2. **Event-Driven Architectures** — Event Grid triggers for Azure resource events (blob created, database change, IoT telemetry)
  3. **SaaS Integration** — Sync data between Salesforce, Dynamics 365, ServiceNow, SAP using managed connectors
  4. **AI Enrichment** — Call Azure OpenAI, Cognitive Services, or ML endpoints as workflow actions
  5. **Hybrid Connectivity** — On-premises Data Gateway for connecting to SQL Server, file shares, and legacy systems behind the firewall
- Bottom note: "Logic Apps Standard also supports running in containers and custom VNet configurations"

**Slide 21 — Key Takeaways**
- Headline: "What You Learned Today"
- Six takeaway bullets with checkmark icons:
  - ✅ Logic Apps = no-code/low-code workflow engine for cloud integration
  - ✅ Triggers start workflows; actions do work; connectors bridge services
  - ✅ Schema validation on triggers rejects bad data automatically
  - ✅ Managed Identity eliminates credential management
  - ✅ Decouple pipeline stages with queues for resilience and scalability
  - ✅ Deploy workflows as IaC with Bicep — version-controlled and repeatable
- Centered statement: "Logic Apps turns integration patterns into configuration, not code."

**Slide 22 — Resources & Links**
- Headline: "Learn More"
- Resource list:
  - Azure Logic Apps Documentation: `learn.microsoft.com/azure/logic-apps`
  - Workflow Expression Reference: `learn.microsoft.com/azure/logic-apps/workflow-definition-language-functions-reference`
  - Logic Apps Connectors Catalog: `learn.microsoft.com/azure/connectors/connectors-overview`
  - Bicep for Logic Apps: `learn.microsoft.com/azure/logic-apps/create-single-tenant-workflows-bicep`
  - Demo Source Code: `github.com/<org>/azure-logic-app-demo`
  - Azure Well-Architected Framework: `learn.microsoft.com/azure/well-architected`
- Footer: "Demo code is Apache 2.0 licensed — fork, extend, deploy"

**Slide 23 — Q&A**
- Large centered text: "Questions?"
- Four conversation starter prompts in smaller text:
  - "What integration workflows are you building or maintaining today?"
  - "Are you currently using any no-code/low-code platforms?"
  - "What services would you need to connect in your environment?"
  - "Have you evaluated Logic Apps Standard vs. Consumption for your workloads?"

---

### Additional Instructions for the PowerPoint Generator

1. **Speaker Notes**: Include detailed speaker notes on every slide. The speaker notes should be conversational, written as if the presenter is teaching Logic Apps concepts to the audience. Reference the demo project where appropriate to ground abstract concepts in concrete examples.

2. **Slide Transitions**: Use subtle, consistent transitions (e.g., fade or morph). No flashy animations.

3. **Diagrams**: For the architecture diagram (Slide 7), workflow diagrams (Slides 8-9), and pattern diagrams (Slide 20), create them as native PowerPoint shapes/SmartArt so they are editable, not images.

4. **Code Blocks**: Format JSON, KQL, and expression snippets in a monospace font (Consolas or Cascadia Code) with a light gray background. Keep font size readable (14-16pt minimum).

5. **Screenshot Placeholders**: On demo slides (14, 15, 16, 17), insert placeholder rectangles labeled "SCREENSHOT: [description]" with a dashed border so the presenter can replace them with actual screenshots after running the demo.

6. **Color Coding**: Use guidance from template

7. **Educational Flow**: The first 12 slides teach Logic Apps concepts. Slides 13-17 are the live demo applying those concepts. Slides 18-24 cover practices, patterns, and wrap-up. Ensure speaker notes reference back to concepts from earlier slides during the demo section.

8. **Total Slide Count**: 24 slides. Designed for a 20-minute session with 8 minutes of concept teaching, 7 minutes of live demo, and 5 minutes of practices/patterns/Q&A.

---
