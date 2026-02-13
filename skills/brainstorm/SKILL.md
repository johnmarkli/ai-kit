---
name: brainstorm
description: Use when designing non-trivial features, components, or behavior changes. Explore user intent, requirements, constraints, and design before implementation.
---

# Brainstorm

## Overview

Help turn ideas into fully formed designs and plans through natural collaborative dialogue.

Start by understanding the current project context (prefer the `spelunk` skill if available; otherwise do manual exploration of key files/docs), then ask questions one at a time to refine the idea. Once you understand what you're building, present the design in small sections (200-300 words), checking after each section whether it looks right so far.

**Announce at start:** "Let's brainstorm this together."

## The Process

**Understanding the idea:**

- If there is spelunk documentation (`docs/spelunk/`), use the `spelunk` skill (or read those docs directly) to understand the project
- If there is no spelunk documentation, run `spelunk` if available; otherwise manually inspect project structure, docs, and core entry points first
- Ask questions one at a time to refine the idea
- Prefer multiple choice questions when possible, but open-ended is fine too
- Only one question per message - if a topic needs more exploration, break it into multiple questions
- Focus on understanding: purpose, constraints, success criteria

**Exploring approaches:**

- Propose 2-3 different approaches with trade-offs
- Present options conversationally with your recommendation and reasoning
- Lead with your recommended option and explain why
- Recommend testing approaches (use the `tdd` skill if available; otherwise follow test-first principles)

**Presenting the design:**

- Once you believe you understand what you're building, present the design
- Break it into sections of 200-300 words
- Ask after each section whether it looks right so far
- Cover: architecture, components, data flow, error handling, testing
- Be ready to go back and clarify if something doesn't make sense

## After the Design

**Documentation:**

- Write the validated design to `docs/plans/YYYY-MM-DD-<topic>-design.md`

**Implementation (if continuing):**

- Ask: "Ready to implement?"
- If user is ready to implement, use `implement-plan` if available; otherwise execute the plan in small reviewed batches

## Key Principles

- **ALWAYS UNDERSTAND CURRENT PROJECT CONTEXT FIRST (prefer `spelunk` when available)**
- **NEVER ASK TO IMPLEMENT BEFORE WRITING THE PLAN**
- **One question at a time** - Don't overwhelm with multiple questions
- **Multiple choice preferred** - Easier to answer than open-ended when possible
- **YAGNI ruthlessly** - Remove unnecessary features from all designs
- **Explore alternatives** - Always propose 2-3 approaches before settling
- **Incremental validation** - Present design in sections, validate each
- **Be flexible** - Go back and clarify when something doesn't make sense
- **Ignore Git history** - Don't bother inspecting Git commit history to build context
