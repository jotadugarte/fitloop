# Data Flow & Side-Effect Map

**Purpose:** Maps how entities mutate and propagate throughout the system. AI agents must consult this document to ensure they do not orphan data or bypass necessary side-effects.

## 1. Primary Data Flow
*(Example Template: Describe the standard lifecycle of your core entity here)*
1. **Client** submits payload.
2. **API/Controller** validates payload schema.
3. **Service Object** executes business logic (Pre/Post conditions checked).
4. **ORM/Database** persists state.

## 2. Cascading Side Effects
*When an entity is modified, these asynchronous or secondary actions MUST occur:*

| Trigger Action | Required Side Effect | Mechanism |
|---|---|---|
| [e.g., User created] | [e.g., Send welcome email] | [e.g., Background Job / Webhook] |
| [e.g., Order completed] | [e.g., Deduct inventory] | [e.g., Database Transaction] |

## 3. Caching Invalidation Strategy
* **Strategy:** [e.g., Cache invalidation via updated_at timestamps]
* **Critical Nodes:** [List any UI components or API endpoints that require manual cache purging when underlying data changes].
