# Constitution Update Checklist

When amending the constitution (`/memory/constitution.md`), ensure all dependent documents are updated to maintain consistency.

## Templates to Update

### When adding/modifying ANY principle:
- [ ] `/templates/plan-template.md` - Update Constitution Check section
- [ ] `/templates/spec-template.md` - Update if requirements/scope affected
- [ ] `/templates/tasks-template.md` - Update if new task types needed
- [ ] `/.claude/commands/stage-commit-push.md` - Update if commit workflow references governance changes
- [ ] `/CLAUDE.md` - Update runtime development guidelines

### Principle-specific updates:

#### Principle 1 – Overlay Is The Product
- [ ] Highlight that `overlay/` content is the public contract
- [ ] Remind contributors to document any compatibility risks
- [ ] Ensure no internal-only assets leak into release artifacts

#### Principle 2 – Self-Contained Cross-Platform Scripts
- [ ] Call out Windows/Linux parity expectations in templates
- [ ] Require scripts to avoid repo-internal dependencies
- [ ] Document justified exceptions to parity in planning docs

#### Principle 3 – Guarded Execution & Exit Codes
- [ ] Verify guard (`ALBT_VIA_MAKE`) messaging appears in relevant flows
- [ ] List standard exit codes in runtime guidance
- [ ] Require plans/specs to preserve guard behavior when touched

#### Principle 4 – Deterministic Provisioning & Cache Hygiene
- [ ] Reference cache location environment variables and sentinel files
- [ ] Emphasize reproducible installs with clean environments
- [ ] Capture expectations for log collection during provisioning

#### Principle 5 – Copy-Only Release Discipline
- [ ] Reinforce copy-only installer flow and artifact composition
- [ ] Document release packaging (overlay zip) and semantic versioning
- [ ] Ensure templates require pre-release dry runs and artifact validation

## Validation Steps

1. **Before committing constitution changes:**
   - [ ] All templates reference new requirements
   - [ ] Examples updated to match new rules
   - [ ] No contradictions between documents

2. **After updating templates:**
   - [ ] Run through a sample implementation plan
   - [ ] Verify all constitution requirements addressed
   - [ ] Check that templates are self-contained (readable without constitution)

3. **Version tracking:**
   - [ ] Update constitution version number
   - [ ] Note version in template footers
   - [ ] Add amendment to constitution history

## Common Misses

Watch for these often-forgotten updates:
- Command documentation (`/commands/*.md`)
- Checklist items in templates
- Example code/commands
- Domain-specific variations (web vs mobile vs CLI)
- Cross-references between documents

## Template Sync Status

Last sync check: 2025-10-16
- Constitution version: 1.0.0
- Templates aligned: ✅ (plan/spec/tasks templates refreshed for new principles)

---

*This checklist ensures the constitution's principles are consistently applied across all project documentation.*