# Codebase Index - Complete Architecture Specification

> **Version**: 1.0.0  
> **Last Updated**: 2025-12-23  
> **Status**: Ready for Implementation  
> **Target Application**: osx-ide (macOS native IDE)

---

## How to Use This Document

This specification is designed to be read by an AI agent or developer with **no prior context** about this feature. Read it sequentially - each section builds on the previous. After reading completely, you should understand:

1. What problem we're solving and why it matters
2. What we're building and how each piece connects
3. How it integrates with the existing IDE
4. How to implement it phase by phase
5. How to verify it works correctly

**Jump to**: [Implementation Guide](#part-6-implementation-guide) if you're ready to start coding.

---

# Part 1: The Problem We're Solving

## 1.1 Context: The Current State of AI-Enabled IDEs

Modern AI-enabled IDEs (Cursor, Windsurf, GitHub Copilot) have a fundamental architectural flaw: they use **semantic search** to find relevant code when the AI needs to make changes. Here's how it typically works:

1. User asks: "Add a password reset feature to the authentication system"
2. IDE performs semantic search for "authentication", "password", "user"
3. IDE dumps found files into AI context
4. AI generates code based on what it found

This approach has severe problems that accumulate over time:

### Problem 1: Reactive, Not Proactive

The AI only finds code **after** deciding what to do. It doesn't know the codebase structure before proposing changes. Result: the AI might create a new `resetPassword()` function when one already exists in a different module, because it didn't search for it.

### Problem 2: No Understanding of Architecture

Semantic search finds text matches, not architectural intent. The AI doesn't know:
- That the project uses Clean Architecture
- That business logic must not import UI components
- That there's a specific pattern for database operations
- That authentication is handled by a specific service

Result: AI-generated code violates project patterns, creating inconsistency and technical debt.

### Problem 3: No Memory

Each conversation starts fresh. The AI doesn't remember:
- Why certain decisions were made
- What patterns have been established
- What mistakes were made before
- What the user prefers

Result: Same mistakes repeated. Same questions asked. No accumulated learning.

### Problem 4: Code Duplication Explosion

Because the AI doesn't have comprehensive awareness, it frequently:
- Creates duplicate implementations
- Misses existing utility functions
- Reinvents patterns that already exist

Result: Codebase bloats with duplicated code, making maintenance a nightmare.

### Problem 5: Technical Debt Invisibility

There's no system tracking:
- Which parts of the code are low quality
- Which areas need refactoring
- Which code is no longer used
- How changes affect code health over time

Result: Technical debt accumulates invisibly until the project becomes unmaintainable.

## 1.2 What We're Building: The Solution

We're building a **Codebase Index** - a persistent, structured knowledge system that gives the AI complete awareness of the project. Think of it as the AI's long-term memory and understanding of the codebase.

**Key Insight**: Instead of searching for code when needed, we maintain a structured index that tells the AI what exists, where it is, what it does, and how it connects - before the AI makes any decisions.

### The Codebase Index Does:

1. **Indexes All Code**: Every file, class, function, and method is catalogued with:
   - Its purpose (AI-generated description)
   - Its location (file, line numbers)
   - Its relationships (what it calls, what calls it, what it extends)
   - Its quality score (AI-assessed code health)
   - Its domain (what part of the system it belongs to)

2. **Tracks Project Memory**: Three tiers of persistent knowledge:
   - Short-term: Current conversation context
   - Mid-term: Feature-level decisions and learnings
   - Long-term: Architectural decisions that should never be violated

3. **Detects Problems Proactively**:
   - Code duplication before it happens
   - Dead code that can be removed
   - Quality hotspots that need attention
   - Architecture violations

4. **Captures Knowledge Automatically**:
   - When user pastes documentation in chat, it's indexed
   - When important decisions are made, they're remembered
   - When patterns are established, they're enforced

## 1.3 Why This Matters

**For the Developer**:
- AI understands their project from day one
- No more explaining the same things repeatedly
- No more cleaning up AI-generated duplicate code
- No more AI violating project patterns

**For the Codebase**:
- Consistent patterns enforced automatically
- Dead code identified and removed
- Quality tracked over time
- Technical debt visible and manageable

**For the AI**:
- Complete context before making decisions
- Memory of past conversations and decisions
- Awareness of code quality and problem areas
- Understanding of project architecture

---

# Part 2: How The System Works

## 2.1 The Core Concept: A Living Index

The Codebase Index is not a static database dump. It's a **living system** that:

1. **Updates in real-time**: When a file is saved, the index updates within 1 second
2. **Learns continuously**: Every AI interaction can add to project knowledge
3. **Enforces intelligently**: Protection levels adapt based on context
4. **Aggregates upward**: Quality problems bubble up to surface hotspots

### The Index Answers These Questions Instantly:

| Question | Traditional IDE | With Codebase Index |
|----------|----------------|---------------------|
| "What handles authentication?" | Search, hope for good results | Immediate: `AuthService`, `TokenManager`, location and relationships |
| "Is there already code for password reset?" | Manual search, often missed | Immediate: Yes/No with existing implementation if found |
| "What depends on this function?" | Limited IDE features | Complete dependency graph with impact analysis |
| "What's the architecture pattern?" | Documentation if exists | Indexed and enforced, with violation detection |
| "What did we decide about X?" | Scroll through chat history | Indexed in project memory, instantly retrievable |
| "Where are the problem areas?" | Unknown until bugs appear | Quality scores aggregated by component, hotspots surfaced |

## 2.2 How Information Flows

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           INFORMATION FLOW                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  SOURCE FILES                    AI CONVERSATIONS                           │
│  ────────────                    ────────────────                           │
│  User saves file                 User pastes documentation                  │
│       │                          User makes decision                        │
│       │                          AI learns pattern                          │
│       │                                │                                    │
│       ▼                                ▼                                    │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                        CODEBASE INDEX                                │   │
│  │                                                                      │   │
│  │   ┌───────────────┐  ┌───────────────┐  ┌───────────────┐          │   │
│  │   │ Code Index    │  │ Project       │  │ Quality       │          │   │
│  │   │               │  │ Memory        │  │ Scores        │          │   │
│  │   │ • Symbols     │  │               │  │               │          │   │
│  │   │ • Relations   │  │ • Short-term  │  │ • Per symbol  │          │   │
│  │   │ • Domains     │  │ • Mid-term    │  │ • Aggregated  │          │   │
│  │   │ • Languages   │  │ • Long-term   │  │ • Trends      │          │   │
│  │   └───────────────┘  └───────────────┘  └───────────────┘          │   │
│  │                                                                      │   │
│  │   ┌───────────────┐  ┌───────────────┐                              │   │
│  │   │ Documentation │  │ Dead Code     │                              │   │
│  │   │ Index         │  │ Analysis      │                              │   │
│  │   │               │  │               │                              │   │
│  │   │ • API docs    │  │ • Usage score │                              │   │
│  │   │ • Captured    │  │ • Factors     │                              │   │
│  │   │ • Linked      │  │ • Recommendations│                           │   │
│  │   └───────────────┘  └───────────────┘                              │   │
│  │                                                                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                     │                                        │
│                                     ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                          AI AGENT                                    │   │
│  │                                                                      │   │
│  │  Before making ANY change, the agent can:                           │   │
│  │  • Query what already exists                                        │   │
│  │  • Understand project architecture                                  │   │
│  │  • Check for duplicates                                             │   │
│  │  • Retrieve relevant memory                                         │   │
│  │  • See quality hotspots                                             │   │
│  │  • Access captured documentation                                    │   │
│  │                                                                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 2.3 The Indexing Process

When a file is saved, the following happens automatically:

**Step 1: File Change Detection**
- The IDE's file watcher detects the change
- An event is published to the EventBus
- The IndexCoordinator receives the event

**Step 2: Debouncing**
- Rapid saves are grouped (300ms window)
- This prevents indexing thrash during active editing

**Step 3: Language Detection**
- The file's language is detected (per-file, not per-project)
- This matters because a PHP project might have JS, CSS, HTML, YAML files
- Each file is tagged with its specific language

**Step 4: Parsing**
- The appropriate language parser is selected
- The file is parsed into an AST (Abstract Syntax Tree)
- Symbols are extracted: classes, functions, methods, properties

**Step 5: Symbol Extraction**
- For each symbol, we record:
  - Name and signature
  - Kind (class, function, method, etc.)
  - Line range (start and end)
  - Parent symbol (for nesting)
  - Access level (public, private, etc.)

**Step 6: Relationship Mapping**
- We analyze what each symbol:
  - Extends or implements
  - Imports or uses
  - Calls
  - Is tested by

**Step 7: AI Enhancement**
- Symbols without descriptions are queued for AI description generation
- Quality scores are computed or updated
- Duplicate detection is run against new/changed symbols

**Step 8: Database Update**
- All extracted information is written to SQLite
- Aggregated scores are recalculated (bubbling up)
- Full-text search index is updated

**Step 9: Event Publication**
- IndexingCompletedEvent is published
- UI elements can update (e.g., quality indicator in status bar)

## 2.4 Multi-Language, Multi-Project Support

Real-world projects are messy. A single repository might contain:
- A React frontend (TypeScript, CSS, HTML)
- A PHP backend (PHP, SQL, YAML config)
- Shared utilities (JavaScript)
- Infrastructure (Dockerfile, shell scripts, YAML)
- Documentation (Markdown)

Our index handles this by:

**1. Language Per-File, Not Per-Project**
Each file is tagged with its own language. This allows:
- PHP file next to JavaScript file in same directory
- Proper parsing for each
- Language-aware searching ("show me all TypeScript files in auth")

**2. Hierarchical Structure**
```
Workspace (e.g., monorepo root)
├── Project (e.g., frontend-app)
│   ├── Component (e.g., authentication)
│   │   ├── Resource (e.g., login.tsx)
│   │   │   └── Symbol (e.g., LoginForm class)
```

**3. Semantic Domains**
Files and symbols are tagged with semantic domains:
- `ui.auth.login` - The login UI component
- `business.auth.validation` - Authentication business logic
- `data.users.repository` - User data access

This allows queries like "JS error in registration" to find all relevant files across languages that relate to registration.

---

# Part 3: The Memory System

## 3.1 Why Memory Matters

Without memory, every AI conversation starts from zero. The AI doesn't know:
- That you decided to use JWT tokens for auth (decided 2 weeks ago)
- That you tried approach X and it didn't work (happened yesterday)
- That the `UserService` should never call the database directly (core architecture)
- That you prefer explicit error handling over exceptions (personal preference)

Our memory system captures and protects this knowledge.

## 3.2 Three Tiers of Memory

### Tier 1: Short-Term Memory (Fluid)

**What it holds**:
- Current conversation context
- Recent file edits and decisions
- Active task state
- Temporary working notes

**Behavior**:
- Freely created, updated, overwritten
- No confirmation required for changes
- May be summarized or merged automatically
- Can be promoted to mid-term if valuable

**Example entries**:
- "User is currently working on the registration form"
- "Last 3 files edited: login.tsx, authService.ts, userModel.ts"
- "Current task: Add password validation"

### Tier 2: Mid-Term Memory (Protected)

**What it holds**:
- Feature implementation decisions
- Bug investigation findings
- API patterns and behaviors
- Learned patterns and preferences

**Behavior**:
- Created easily, but changes require confirmation
- When agent tries to update, user sees: "This will modify project knowledge about X. Confirm? [Y/N]"
- More stable than short-term, less sacred than long-term
- Can be promoted to long-term for architectural importance

**Example entries**:
- "Auth API uses 8 fields for registration: email, password, firstName, lastName, phone, country, acceptTerms, marketingConsent"
- "Password validation requires: 8+ chars, 1 uppercase, 1 number, 1 special"
- "User prefers async/await over callbacks throughout the codebase"

### Tier 3: Long-Term Memory (Sacred)

**What it holds**:
- Project architecture decisions
- Fundamental design patterns
- Core principles that should never be violated
- System-wide rules

**Behavior**:
- Changes require explicit multi-step confirmation
- Agent must explain: "This is a SYSTEM-WIDE architecture change"
- Agent must list impact areas
- User must type explicit confirmation phrase
- Features adapt to architecture, NEVER architecture to features

**Example entries**:
- "This project uses Clean Architecture. UI layer cannot import from Data layer."
- "All database operations go through Repository classes, never direct queries."
- "Error handling uses Result types, not exceptions."
- "Authentication is centralized in AuthService, no other service handles tokens."

## 3.3 Memory Protection: Multi-Dimensional

**Key Design Decision**: Protection is NOT just about time. A memory from today might need more protection than a memory from a month ago if it has more impact.

Protection level is computed from multiple factors:

| Factor | Description | Weight |
|--------|-------------|--------|
| **Scope of Change** | How much code would be affected? | High |
| **Architectural Impact** | Does it change core patterns? | High |
| **Breaking Change Potential** | Could it break existing code? | High |
| **Age of Memory** | Older = more established | Medium |
| **Dependency Count** | How much depends on this? | High |
| **Touch Frequency** | How often is it referenced? | Medium |
| **Implementation Effort** | How much work to change? | Low |
| **Regression Risk** | Likelihood of breaking things? | High |
| **Project Maturity** | Early projects are more flexible | Medium |
| **Explicit User Protection** | User marked as protected | Highest |

**Example**: A long-term memory about "using REST for all APIs" that was created yesterday in a new project might only require simple confirmation to change. But the same memory in a 6-month project with 50 API endpoints would require explicit multi-step confirmation because the dependency count is high.

## 3.4 Automatic Knowledge Capture

When the AI recognizes valuable information in a conversation, it captures it automatically:

**What gets captured**:
1. **Documentation**: User pastes API docs, framework guides, etc.
2. **Decisions**: "We decided to use approach X because Y"
3. **Patterns**: "Always structure services this way"
4. **API Knowledge**: "The payment API requires these 7 fields"
5. **Preferences**: "Use descriptive variable names, not abbreviations"

**How it works**:
1. AI recognizes valuable information
2. AI saves to appropriate memory tier
3. AI notifies user in a friendly way: "💡 I'll remember that the Auth API uses 8 fields for registration."
4. No user action required - this is frictionless

**Why frictionless**:
- Requiring approval for every save would be annoying
- Most captured knowledge is helpful
- User can always review/edit memory later
- The notification is informative but not blocking

---

# Part 4: Quality Tracking

## 4.1 Why Track Quality?

Without quality tracking:
- Technical debt accumulates invisibly
- Problems only surface as bugs
- Refactoring is reactive, not proactive
- Agent doesn't know which areas to avoid or improve

With quality tracking:
- Hotspots are visible before they cause bugs
- Agent can proactively suggest refactoring
- Quality trends show if things are improving or declining
- Agent can refuse to add more code to low-quality areas

## 4.2 Quality Scoring

Each symbol (class, function, etc.) receives a quality score from 0-100, computed by AI analysis:

**Dimensions measured**:
- **Readability**: Is the code clear? Are names descriptive?
- **Maintainability**: Is it modular? Low coupling? High cohesion?
- **Testability**: Easy to test? Minimal side effects?
- **Performance**: Any obvious inefficiencies?
- **Security**: Known vulnerability patterns?

**Each score includes**:
- Numeric score (0-100)
- Specific issues with locations
- Reasoning (why this score)
- Suggestions for improvement

## 4.3 Score Aggregation (Bubbling Up)

Individual symbol scores aggregate upward:

```
Symbol: RegistrationForm.handleSubmit() → Score: 35
        RegistrationForm.validateEmail() → Score: 42
        RegistrationForm.render() → Score: 38
                      ↓ Aggregates to
File: registration.tsx → Score: 38
                      ↓ Aggregates to
Component: auth → Score: 45
                      ↓ Aggregates to
Project: frontend-app → Score: 68
                      ↓ Aggregates to
Workspace → Score: 72
```

**Why aggregation matters**:
- A single bad file drags down its component's score
- Hotspots are visible at any level
- Agent can quickly identify "auth component is the problem area"
- Trends at each level show improvement/decline

## 4.4 How Agent Uses Quality Information

The agent doesn't trigger warnings - it uses quality as knowledge for decisions:

**Scenario 1: User asks to add feature to low-quality area**
- Agent checks quality score
- Agent says: "The auth component has a quality score of 45/100 with significant issues. I recommend refactoring before adding new features. Shall I refactor first?"

**Scenario 2: User asks "Where are our biggest problems?"**
- Agent queries hotspots
- Agent returns: "The registration form (35/100) is your worst area. Main issues: complex validation logic mixed with UI, too many props, missing error handling."

**Scenario 3: Agent is implementing a feature**
- Agent checks quality of areas it will modify
- If score is critically low, agent may refuse: "This area has too much technical debt for safe modification. Recommend cleanup first."

---

# Part 5: Integration With Existing IDE

## 5.1 The Existing IDE Architecture

The osx-ide already has:

1. **EventBus** (`Core/EventBus.swift`): A Combine-based pub/sub system for events
2. **ExtensionPoints** (`Core/ExtensionPoint.swift`): Plugin attachment points
3. **CommandRegistry** (`Core/CommandRegistry.swift`): Command registration
4. **UIRegistry** (`Core/UIRegistry.swift`): UI component registration
5. **CorePlugin** (`Core/CorePlugin.swift`): Plugin protocol
6. **DependencyContainer** (`Services/DependencyContainer.swift`): Service registration
7. **Services** directory with all application services

## 5.2 How Codebase Index Integrates

The Codebase Index becomes a new service that:

**1. Registers with DependencyContainer**
```swift
// In DependencyContainer, we add:
container.register(CodebaseIndexProtocol.self) { 
    CodebaseIndex(eventBus: EventBus.shared)
}
```

**2. Subscribes to File Events via EventBus**
The existing file system presumably publishes events (or we add this). The IndexCoordinator subscribes to:
- FileCreatedEvent
- FileModifiedEvent
- FileDeletedEvent
- FileRenamedEvent

**3. Publishes Index Events via EventBus**
Other components can listen to:
- IndexingStartedEvent
- IndexingProgressEvent
- IndexingCompletedEvent
- MemoryCapturedEvent

**4. Integrates with AI Services**
The existing `AIService` and `ConversationManager` use the index:
- Query for relevant context before AI calls
- Capture knowledge from conversations
- Check for duplicates when AI proposes new code

**5. Optionally Extends UI**
Via ExtensionPoints:
- Status bar indicator showing index status
- Panel for browsing project knowledge
- Integration with file explorer for quality indicators

## 5.3 Storage Location

All index data lives in `.ide/` inside the project root:

```
project-root/
├── .ide/                           # Codebase Index data
│   ├── config.json                 # Index configuration
│   ├── index/
│   │   ├── codebase.sqlite         # Main code index
│   │   ├── embeddings.sqlite       # Vector embeddings
│   │   └── index.lock              # Write lock
│   ├── knowledge/
│   │   ├── memory.sqlite           # Three-tier memory
│   │   ├── project.sqlite          # Architecture knowledge
│   │   └── documentation/          # Captured docs
│   └── quality/
│       └── quality.sqlite          # Quality scores
├── osx-ide/                        # Source code
├── osx-ideTests/
└── ...
```

**Why SQLite**:
- Single-file databases, easy to backup/restore
- Well-supported, proven at scale
- FTS5 provides excellent full-text search
- No external dependencies
- Works well with the existing Swift ecosystem

## 5.4 Thread Model

| Component | Thread | Reason |
|-----------|--------|--------|
| IndexCoordinator | Main (@MainActor) | Receives events, coordinates |
| IndexerActor | Background (Swift Actor) | Heavy lifting: parsing, DB writes |
| QueryService | Any (thread-safe reads) | Must be fast, called from anywhere |
| MemoryManager | Background (Swift Actor) | DB operations |

**Key Design Decision**: The main IDE thread is never blocked by index operations. All parsing and database writes happen on background threads. Queries are fast enough to run anywhere.

---

# Part 6: Implementation Guide

## 6.1 File Structure to Create

```
osx-ide/Services/Index/
├── CodebaseIndex.swift              # Main entry point, implements CodebaseIndexProtocol
├── IndexCoordinator.swift           # Receives events, debounces, dispatches
│
├── Indexing/
│   ├── IndexerActor.swift           # Background indexing actor
│   ├── LanguageDetector.swift       # Detect language per-file
│   ├── SymbolExtractor.swift        # Extract symbols from AST
│   └── RelationshipMapper.swift     # Map symbol relationships
│
├── Parsing/
│   ├── LanguageParserRegistry.swift # Registry of all parsers
│   ├── SwiftParser.swift            # Swift-specific parsing
│   └── GenericParser.swift          # Fallback parser
│
├── Database/
│   ├── DatabaseManager.swift        # SQLite management
│   ├── CodebaseDatabase.swift       # Code index operations
│   ├── MemoryDatabase.swift         # Memory tier operations
│   └── QualityDatabase.swift        # Quality score operations
│
├── Memory/
│   ├── MemoryManager.swift          # Memory CRUD with protection
│   ├── ProtectionCalculator.swift   # Multi-factor protection scoring
│   └── ConversationCapture.swift    # Auto-capture from AI chat
│
├── Quality/
│   ├── QualityAnalyzer.swift        # Score calculation
│   └── AggregationService.swift     # Score bubbling
│
├── Query/
│   ├── QueryService.swift           # All read operations
│   ├── ContextBuilder.swift         # Build context for AI
│   └── DuplicateDetector.swift      # Find similar code
│
├── Events/
│   └── IndexEvents.swift            # Event definitions
│
└── Models/
    ├── IndexModels.swift            # Core data models
    ├── MemoryModels.swift           # Memory models
    └── QualityModels.swift          # Quality models
```

## 6.2 Implementation Phases

### Phase 1: Foundation (Week 1-2)

**Goal**: Basic infrastructure working - file events trigger indexing, data stored in SQLite.

**Tasks**:
1. Create database schema and DatabaseManager
2. Implement IndexCoordinator to receive file events
3. Implement basic IndexerActor (just stores file paths initially)
4. Implement LanguageDetector
5. Wire up with EventBus

**Verification**:
- Save a file, verify entry appears in database
- Check that events flow correctly

### Phase 2: Symbol Extraction (Week 2-3)

**Goal**: Extract actual code symbols from Swift files.

**Tasks**:
1. Implement SwiftParser using SwiftSyntax
2. Implement SymbolExtractor
3. Store symbols with line ranges
4. Implement RelationshipMapper

**Verification**:
- Index IDE's own codebase
- Verify all classes, functions found
- Verify line numbers are correct

### Phase 3: Memory System (Week 3-4)

**Goal**: Three-tier memory with protection working.

**Tasks**:
1. Implement MemoryDatabase
2. Implement MemoryManager
3. Implement ProtectionCalculator
4. Implement ConversationCapture

**Verification**:
- Store memory at each tier
- Verify protection levels computed correctly
- Test update confirmation flow

### Phase 4: Quality Scoring (Week 4-5)

**Goal**: AI-generated quality scores with aggregation.

**Tasks**:
1. Implement QualityAnalyzer (integrates with AIService)
2. Implement QualityDatabase
3. Implement AggregationService
4. Add hotspot detection

**Verification**:
- Generate scores for sample code
- Verify aggregation bubbles correctly
- Query hotspots successfully

### Phase 5: Query & Search (Week 5-6)

**Goal**: Fast, relevant queries.

**Tasks**:
1. Implement QueryService
2. Add FTS5 search
3. Implement ContextBuilder
4. Implement DuplicateDetector

**Verification**:
- Search returns relevant results
- Context builder produces useful output
- Duplicate detection works

### Phase 6: Integration & Polish (Week 6-8)

**Goal**: Full integration with IDE and AI.

**Tasks**:
1. Integrate with ConversationManager
2. Add UI elements (optional)
3. Performance optimization
4. Documentation

**Verification**:
- End-to-end workflow works
- Performance meets targets
- No main thread blocking

## 6.3 Verification Approach

**Unit Tests** (`osx-ideTests/Index/`):
- LanguageDetectorTests: Test language detection
- ProtectionCalculatorTests: Test protection factor computation
- SymbolExtractionTests: Test parsing output
- QueryServiceTests: Test search functionality

**Integration Tests**:
- IndexingWorkflowTests: File save → Index → Query
- MemoryWorkflowTests: Create → Protect → Update confirmation

**Manual Verification**:
1. Open IDE with a project
2. Verify `.ide/` folder created
3. Modify file, verify indexed within 1 second
4. Use AI chat, verify context includes indexed data

---

# Part 7: Detailed Data Models

## 7.1 Core Entities

These are the main data structures the system uses:

**Workspace**: The root of a monorepo or single project
- Contains multiple Projects
- Has aggregated quality score

**Project**: A logical project within the workspace
- Has primary languages (but files can be any language)
- Contains Components (feature groups)
- Has its own aggregated quality score

**Component**: A feature or module group
- Groups related files together
- Has semantic domain (e.g., "auth", "payments")
- Has aggregated quality score

**Resource**: A single file
- Has specific language (per-file, not inherited)
- Contains Symbols
- Linked to a Component

**Symbol**: A code element (class, function, method, property)
- Has name, signature, description
- Has line range (for diff operations)
- Has quality score
- Has relationships to other symbols

## 7.2 Memory Entities

**MemoryEntry**: A single piece of remembered knowledge
- Belongs to a tier (short/mid/long)
- Has category (conversation, decision, architecture, etc.)
- Has content and summary
- Has protection level (computed)
- May link to symbols or conversations

## 7.3 Quality Entities

**QualityScore**: Score for a single symbol
- Overall score (0-100)
- Dimension scores (readability, maintainability, etc.)
- List of issues with locations
- Reasoning explanation

**AggregatedScore**: Rolled-up score for file/component/project
- Aggregated from child scores
- Identifies hotspot path
- Tracks trend (improving/declining)

---

# Part 8: The Workflow in Practice

## 8.1 Workflow: User Asks AI to Add Feature

1. **User**: "Add password reset functionality"

2. **AI queries index**: "What exists related to password, reset, authentication?"

3. **Index returns**:
   - AuthService class: handles token refresh, login, logout
   - UserRepository: has `findByEmail()` method
   - EmailService: can send emails
   - Quality: Auth component scores 65/100

4. **AI queries memory**: "Any decisions about password/auth flow?"

5. **Memory returns**:
   - Mid-term: "Password validation requires 8+ chars, 1 uppercase, 1 number"
   - Long-term: "All auth operations go through AuthService"

6. **AI checks for duplicates**: "Is there already password reset?"
   - Index: No existing reset functionality found

7. **AI proposes implementation**:
   - Add `resetPassword()` to AuthService (respecting architecture memory)
   - Use existing EmailService for reset email
   - Follow existing validation patterns
   - Quality suggestion: "Auth component could use refactoring, but acceptable for new feature"

8. **AI generates code** with full awareness of:
   - Where it should go (AuthService)
   - What patterns to follow (from memory)
   - What to reuse (existing services)
   - Current code quality

## 8.2 Workflow: AI Captures Knowledge

1. **User**: "The Stripe API requires these fields for payment: amount, currency, customerId, paymentMethodId, description, metadata"

2. **AI recognizes**: This is valuable API knowledge

3. **AI captures**:
   ```
   Tier: Mid-term
   Category: apiKnowledge
   Content: "Stripe API payment creation requires: amount, currency, customerId, paymentMethodId, description, metadata"
   ```

4. **AI notifies**: "💡 I'll remember that Stripe payments need those 6 fields."

5. **Later, user asks**: "Add payment processing"

6. **AI queries memory**: Returns the Stripe API knowledge

7. **AI generates correct code** using all 6 fields without asking again

## 8.3 Workflow: Protection Prevents Mistake

1. **Long-term memory exists**: "All database operations go through Repository classes"

2. **AI proposes**: Adding direct SQL query in a Service class

3. **AI checks memory**: Finds this violates architecture

4. **AI responds**: "I can't add a direct SQL query in UserService. According to project architecture, all database operations must go through Repository classes. Should I add this to UserRepository instead?"

5. **Architecture protected** without user having to catch the mistake

---

# Part 9: Key Design Decisions

## 9.1 Why SQLite?

- **Single file**: Easy backup, version control, no external server
- **FTS5**: Built-in full-text search, excellent for code search
- **Proven**: Billions of deployments, rock solid
- **Swift support**: Excellent SQLite libraries for Swift
- **Future plugins**: Well-understood format for extensions

## 9.2 Why Per-File Languages?

Real projects mix languages. A "PHP project" has JavaScript, CSS, HTML, YAML. By tracking language per-file:
- Correct parser is always used
- Language-specific search works
- No false assumptions

## 9.3 Why Multi-Factor Protection?

Time-based protection breaks down:
- Brand new projects might need to change architecture
- Old projects might have unchangeable core decisions

Multi-factor considers:
- Impact of change
- How much depends on it
- Project maturity
- User explicit protection

Result: Appropriate protection regardless of time.

## 9.4 Why Automatic Capture?

Requiring approval for every capture:
- Creates friction
- Discourages use
- Bogs down conversation

Automatic capture with notification:
- Frictionless
- Knowledge accumulates naturally
- User stays informed but not blocked

## 9.5 Why Aggregated Scores?

Individual scores are too granular for quick decisions. Aggregation:
- Surfaces hotspots at any level
- Allows quick "where are problems?"
- Shows impact of bad code on broader areas
- Enables trend tracking

---

# Part 10: Success Metrics

How we know this system is working:

| Metric | Target | How to Measure |
|--------|--------|---------------|
| Index freshness | < 1 second from save | Measure time from FileModifiedEvent to IndexingCompletedEvent |
| Query response | < 50ms | Profile QueryService calls |
| Memory footprint | < 100MB | Monitor IndexerActor memory usage |
| Duplicate detection | > 90% caught | Manual review of proposed code vs. existing |
| Context relevance | > 85% | Survey: "Did AI have the context it needed?" |
| Memory protection works | 0 accidental overwrites | Track protection prompts and user responses |

---

# Appendix A: Glossary

| Term | Definition |
|------|-----------|
| **Symbol** | A code element: class, function, method, property |
| **Resource** | A single file in the index |
| **Component** | A group of related files (e.g., "auth" feature) |
| **Domain** | Semantic category (e.g., "ui.auth.login") |
| **Memory Tier** | Short-term, mid-term, or long-term knowledge |
| **Protection Level** | How much confirmation needed to change memory |
| **Aggregation** | Rolling up scores from child to parent |
| **Hotspot** | An area with low quality that needs attention |
| **Capture** | Automatically saving knowledge from conversation |

---

# Appendix B: Configuration Options

`.ide/config.json`:
```json
{
  "version": 1,
  "indexing": {
    "enabled": true,
    "debounceMs": 300,
    "excludePatterns": ["*.generated.*", "Pods/*", "node_modules/*", ".build/*"]
  },
  "memory": {
    "autoCapture": true,
    "shortTermRetentionDays": 7,
    "requireConfirmationForMidTerm": true,
    "requireExplicitApprovalForLongTerm": true
  },
  "quality": {
    "generateScores": true,
    "aggregationEnabled": true,
    "hotspotThreshold": 50
  },
  "ai": {
    "generateDescriptions": true,
    "batchSize": 20,
    "embeddingsEnabled": false
  }
}
```

---

*End of specification. This document provides complete context for implementation. Read fully before starting work.*
