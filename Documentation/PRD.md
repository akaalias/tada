# Product Requirements Document: Tada

**Version:** 1.0  
**Date:** 2026-04-16  
**Author:** Alexis Rondeau

---

## 1. Executive Summary

Tada is a native macOS task management application that reimagines how people complete tasks. Instead of treating todos as checkboxes to mark off after doing work elsewhere, Tada generates custom micro-UIs that let users complete each task directly within the app. This is powered by two AI agents: a **Planner AI** that structures vague intentions into actionable sub-tasks, and an **Executive AI** that creates purpose-built interfaces for completing each action.

---

## 2. Problem Statement

Traditional task management apps like Todoist excel at organizing and tracking tasks, but they remain passive systems. Users must:

1. Figure out what to do next themselves
2. Leave the app to actually do the work
3. Return to check off the box

This creates friction, context-switching, and tasks that linger because "I don't even know where to start."

---

## 3. Solution Overview

Tada solves this with three innovations:

1. **AI-Assisted Task Planning**: Vague inputs like "revitalize my balcony" are transformed into clear titles, descriptions, and actionable sub-task plans.

2. **Action Required Dashboard**: A dedicated view showing the single most actionable sub-task from each top-level task, preventing overwhelm.

3. **Dynamic Action UIs**: Instead of checkboxes, each action item presents a custom-generated interface (forms, multi-selects, text inputs, drawing canvases, etc.) that lets the user actually complete the task in-app.

---

## 4. User Personas

### Primary Persona: The Overwhelmed Planner

- Has many ideas and intentions but struggles to break them into actionable steps
- Often writes tasks like "figure out the garden situation" and never touches them
- Needs guidance on *what* to do next and *how* to do it
- Values momentum and quick wins

### Secondary Persona: The Busy Professional

- Has clear tasks but limited time
- Wants the app to minimize friction between "deciding to do" and "doing"
- Appreciates structured workflows that feel productive

---

## 5. Core Features

### 5.1 Standard Task Management (Foundation)

**Priority:** P0 (Must Have)

- Create, read, update, delete tasks
- Create, read, update, delete sub-tasks under any task
- Hierarchical task structure (top-level tasks contain sub-tasks)
- Mark tasks as complete/incomplete
- Basic task metadata: title, description, status, created date

### 5.2 Planner AI: Intelligent Task Structuring

**Priority:** P0 (Must Have)

When a user creates a new top-level task:

1. **Title Refinement**: Transform vague input into a clear, actionable title
2. **Description Generation**: Create a helpful description explaining the goal
3. **Sub-Task Planning**: Generate 3-7 logical sub-tasks that form a complete plan
4. **Plan Revision**: After each sub-task is completed, optionally revise remaining sub-tasks based on new information

**Example Transformation:**

- **Input**: "I need to revitalize my balcony because I don't spend much time there and summer is coming but I don't even know where to start"
- **Output Title**: "Turn the balcony into a space I'll actually use this summer"
- **Output Sub-Tasks**: 
  1. Decide how you want to use the balcony (1-2 concrete uses)
  2. Audit the space (measurements, sun patterns, condition)
  3. Clear and deep clean
  4. Set a budget and shop
  5. Set up and live-test for a week

### 5.3 Executive AI: Dynamic Action UIs

**Priority:** P0 (Must Have)

For each sub-task in the Action Required view, the Executive AI generates a custom interface:

**Supported UI Components:**

| Component | Use Case | Example |
|-----------|----------|---------|
| Multi-select | Choosing from predefined options | "Select how you'll use the balcony: morning coffee, reading nook, plant corner" |
| Single-select | Making a single choice | "Which room will this be for?" |
| Text input | Gathering specific information | "What's your budget range?" |
| Number inputs | Measurements, quantities | "Balcony width (m): ___ Depth (m): ___" |
| Yes/No toggle | Binary decisions | "Do you have outdoor power access?" |
| Checklist | Confirming multiple items | "Confirm you've done: swept, scrubbed, fixed loose tiles" |
| Date picker | Scheduling | "When do you want this ready by?" |
| Drawing canvas | Spatial/visual input | "Sketch your balcony shape and mark north" |
| Photo upload | Visual documentation | "Upload a photo of the current state" |

**Key Principle**: The UI should make completing the task as easy as possible. The submit button *is* the completion action.

### 5.4 Action Required Dashboard

**Priority:** P0 (Must Have)

- Appears at the top of the main navigation
- Shows one action item per top-level task (the most actionable sub-task)
- Each action item displays:
  - Parent task title (context)
  - Sub-task title (what you're doing)
  - Generated action UI (how you'll do it)
- Submitting the form completes the sub-task and may trigger plan revision

### 5.5 Plan Revision Loop

**Priority:** P1 (Should Have)

After an action is submitted:

1. Planner AI receives the new input/context
2. Evaluates whether remaining sub-tasks are still relevant
3. Either confirms the existing plan or revises it
4. Executive AI prepares the UI for the next action item

---

## 6. User Experience Flow

### 6.1 Adding a New Task

1. User clicks "Add Task" or uses keyboard shortcut
2. User types natural language input (can be vague)
3. Planner AI processes and returns structured task + sub-tasks
4. User sees the refined task with generated plan
5. User can accept, edit, or regenerate the plan

### 6.2 Working Through Action Required

1. User opens Action Required dashboard
2. Sees one card per active top-level task
3. Each card shows a custom UI for completing that sub-task
4. User fills in the form/makes selections
5. User hits Submit
6. Sub-task marked complete, input saved, plan potentially revised
7. Next action item appears (either next sub-task or revised plan)

### 6.3 Manual Task Management

Users can always:
- View full task list with all sub-tasks
- Manually mark tasks complete (traditional checkbox)
- Edit task titles, descriptions, sub-tasks
- Reorder sub-tasks
- Delete tasks

---

## 7. Information Architecture

```
Tada
├── Action Required (Dashboard)
│   ├── Action Card: [Task A] → Sub-task with generated UI
│   ├── Action Card: [Task B] → Sub-task with generated UI
│   └── Action Card: [Task C] → Sub-task with generated UI
│
├── All Tasks (List View)
│   ├── Task A
│   │   ├── Sub-task 1 (completed)
│   │   ├── Sub-task 2 (current)
│   │   └── Sub-task 3 (pending)
│   ├── Task B
│   │   └── ...
│   └── Task C
│       └── ...
│
└── Completed (Archive)
    └── Past tasks
```

---

## 8. Data Model

### Task
- `id`: UUID
- `title`: String
- `description`: String
- `status`: Enum (active, completed, archived)
- `created_at`: DateTime
- `completed_at`: DateTime (nullable)
- `original_input`: String (what user originally typed)
- `sub_tasks`: [SubTask]

### SubTask
- `id`: UUID
- `task_id`: UUID (parent reference)
- `title`: String
- `description`: String
- `order`: Integer
- `status`: Enum (pending, current, completed, skipped)
- `action_type`: String (the UI type generated)
- `action_schema`: JSON (the UI definition)
- `action_response`: JSON (user's submitted data)
- `completed_at`: DateTime (nullable)

---

## 9. Success Metrics

| Metric | Target | Rationale |
|--------|--------|-----------|
| Tasks completed vs created | >60% | Users actually finish what they start |
| Sub-tasks completed via Action UI | >80% | Users prefer the generated UI over manual checkboxes |
| Time from task creation to first action | <5 minutes | Low friction to start |
| Plan revision rate | 20-40% | AI is adapting but not constantly churning |

---

## 10. Out of Scope (V1)

- Multi-user / collaboration
- Cloud sync
- Mobile apps
- Recurring tasks
- Due dates / calendar integration
- Projects / folders
- Tags / labels
- Natural language task capture via voice
- Third-party integrations

---

## 11. Open Questions

1. **Regeneration UX**: How do users regenerate an action UI if it doesn't fit their needs?
2. **Undo/Edit**: Can users edit their submitted responses after the fact?
3. **Skip Actions**: Should users be able to skip/defer an action item?
4. **AI Transparency**: How much of the AI's "reasoning" should be shown?
5. **Offline Support**: Should the app work without internet (no AI features)?

---

## 12. Appendix: Example Scenarios

### Scenario A: Home Improvement Task

**Input**: "The kitchen faucet is dripping and it's driving me crazy"

**Planner Output**:
- Title: "Fix the dripping kitchen faucet"
- Sub-tasks:
  1. Identify the faucet type and model
  2. Diagnose the likely cause
  3. Get replacement parts
  4. Make the repair

**Action UI for Sub-task 1**:
```
What type of faucet do you have?

○ Single-handle (one lever controls both hot and cold)
○ Double-handle (separate hot and cold knobs)
○ Pull-down sprayer
○ Not sure

[Submit]
```

### Scenario B: Personal Development Task

**Input**: "I want to start meditating but I always forget"

**Planner Output**:
- Title: "Build a sustainable daily meditation habit"
- Sub-tasks:
  1. Choose when you'll meditate
  2. Set up a minimal meditation space
  3. Pick an app or method
  4. Complete your first 5 sessions
  5. Reflect and adjust

**Action UI for Sub-task 1**:
```
When works best for you to meditate?

○ Morning, right after waking
○ Morning, after breakfast
○ Midday break
○ Evening, before dinner
○ Night, before bed

How many minutes to start?
[  5  ] minutes

[Submit]
```
