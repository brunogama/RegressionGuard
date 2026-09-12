# Rule Loading Guide

This file helps determine which rules to load based on the context and task at hand. Each rule file contains specific guidance for different aspects of Swift development.

## Rule Loading Triggers

Rules are under `ai-rules` folder. If the folder exist in local project directory, use that.

### 📝 general.md - Core Engineering Principles
**Load when:**
- Always
- Starting any new Swift project or feature
- Making architectural decisions
- Discussing code quality, performance, or best practices
- Planning implementation strategy
- Reviewing code for improvements

**Keywords:** architecture, design, performance, quality, best practices, error handling, planning, strategy

### 🔧 mcp-tools-usage.md - MCP Tools Integration
**Load when:**
- Always
- Using Context7 for library documentation
- Implementing sequential thinking for complex problems
- Setting up interactive feedback loops
- Optimizing tool usage and performance
- Working with external MCP tools

**Keywords:** MCP, Context7, sequential thinking, tool, integration, library docs, feedback

### 🧪 testing.md - Swift Testing Framework
**Load when:**
- Writing any tests
- Setting up test suites
- Testing async code
- Working with snapshot tests or ViewInspector
- Discussing test coverage or testing strategy

**Keywords:** test, @Test, @Suite, testing, unit test, integration test, snapshot, ViewInspector, test coverage

### 🎨 view.md - SwiftUI Views
**Load when:**
- Creating new SwiftUI views
- Building UI components
- Implementing view performance optimizations
- Adding accessibility features
- Working with view modifiers or animations

**Keywords:** SwiftUI, View, UI, interface, component, accessibility, animation, LazyVStack, ForEach

### 🎯 view-model.md - ViewModel Architecture
**Load when:**
- Creating ViewModels for SwiftUI views
- Implementing state management
- Coordinating between views and business logic
- Managing async operations in UI
- Handling user interactions

**Keywords:** ViewModel, @Observable, state management, coordinator, business logic, user action

### 📋 commits.md - Git Commit Conventions
**Load when:**
- Making git commits
- Creating commit messages
- Setting up branch naming
- Discussing version control practices
- Implementing conventional commits

**Keywords:** commit, git, version control, feat, fix, branch, conventional commits

### 📚 rules.md - Rule File Creation
**Load when:**
- Creating new rule files
- Documenting coding standards
- Establishing team conventions
- Reviewing or updating existing rules
- Meta-discussions about rule effectiveness

**Keywords:** rule file, documentation, standards, conventions, meta-rules, YAML frontmatter

## Quick Reference

```swift
// When working on a new feature:
// Load: general.md, mcp-tools-usage.md, view.md, view-model.md, dependencies.md

// When writing tests:
// Load: general.md, mcp-tools-usage.md, testing.md, dependencies.md

// When reviewing code:
// Load: general.md, mcp-tools-usage.md, commits.md

// When integrating external libraries:
// Load: general.md, mcp-tools-usage.md, dependencies.md

// When creating documentation:
// Load: general.md
```

## Rule Combinations

### Feature Development
1. Start with `general.md` for architecture decisions
2. Load `mcp-tools-usage.md` for available mcp tools, ignore TaskMaster rules and use internal tasks system
3. Use `view-model.md` for state coordination
4. Apply `view.md` for UI implementation
5. Include `dependencies.md` for service integration
6. Follow with `testing.md` for test coverage

### Code Review & Maintenance
1. Apply `general.md` for quality standards
2. Use `commits.md` for version control
3. Reference specific domain rules as needed

### Complex Problem Solving
1. Load `mcp-tools-usage.md` 
2. Apply `general.md` for chain-of-thought reasoning
3. Follow domain-specific rules for implementation

## Loading Strategy

1. **Always load `general.md` and `mcp-tools-usage.md first`** - It provides the foundation
2. **Load domain-specific rules** based on the task
3. **Load supporting rules** as needed (e.g., testing when implementing)
4. **Keep loaded rules minimal** - Only what's directly relevant
5. **Refresh rules** when switching contexts or tasks
