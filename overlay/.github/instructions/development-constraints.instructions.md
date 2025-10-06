---
applyTo: '**'
---
# Development Constraints

## YAGNI (You Aren't Gonna Need It)

Build only what's **required RIGHT NOW** for current, concrete requirements.

- ❌ No hypothetical features, "just in case" flexibility, or abstractions before 3+ uses
- ✅ Solve current problems only, remove unused code

**Red flags**: "might need later", "more flexible", "just in case", "future extensibility"

## KISS (Keep It Simple, Stupid)

Choose simple, obvious implementations over clever solutions.

- ❌ No clever tricks, edge-case engineering, or generic solutions for specific problems
- ✅ Boring patterns, readability over cleverness, minimal parameters

## Progressive Enhancement

Start minimal, enhance based on **real usage**.

- ✅ Simplest implementation first, refactor when needs emerge
- ✅ Target ~60-80 lines for service codeunits
- ❌ No elaborate upfront systems

## Separation of Concerns

Extract when complexity **demands** it:

**Extract when**:
- Logic >100 lines
- Used in 3+ places
- Multiple responsibilities
- Testing difficult

**Don't extract when**: "might be reused", "more modular", simple/localized logic

## Backward Compatibility

**PUBLIC API ONLY** - Internal code refactors freely.

**Public** (no `Access` or `Access = Public`):
- ✅ Maintain stability, add don't modify, deprecate before removing

**Internal** (`Access = Internal` or `local`):
- ✅ Freely refactor/rename/remove, change signatures at will
