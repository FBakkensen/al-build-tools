## Research: CI Unified Cross-Platform Test Discovery

### Decision Matrix
| Topic | Decision | Rationale | Alternatives | Status |
|-------|----------|-----------|-------------|--------|
| Linux test framework | bats-core latest | Widely adopted, simple TAP-like output, easy install via clone | shUnit2 (less active), bespoke bash harness (reinvent) | Chosen |
| Windows test framework | Pester v5 | De-facto PowerShell standard, built into ecosystem | Custom assertions, older Pester v4 | Chosen |
| Discovery strategy | Recursive glob by extension | Zero config; matches spec FR-001/002 | Config file listing tests (maintenance burden) | Chosen |
| Zero-test guard method | Pre-run file count with explicit exit | Simple, fast, unambiguous logs | Post-run check of framework summary (less explicit) | Chosen |
| bats installation | Shallow git clone + install.sh | Deterministic, minimal steps | apt-get (version drift), vendoring | Chosen |
| Pester availability | Install/ensure latest from PSGallery | Ensures v5 features & consistency | Rely on preinstalled (may downgrade unexpectedly) | Chosen |
| Legacy script migration | Manual port with coverage table | Human validation of semantics | Automated translation (high risk), keep both forever (dup) | Chosen |
| Matrix runners | ubuntu-latest, windows-latest | Coverage of core OS; parity principle | Add macOS (cost/time now) | Deferred |

### Detailed Rationale
1. Bats vs custom harness: Reduces maintenance and leverages community conventions; aligns with contributor expectations.
2. Pester version pinning: Explicit install avoids silent downgrade or API variance.
3. Guard design: Failing early prevents conflating zero tests with a green run; log message is greppable.
4. Migration approach: Guarantees no silent coverage regression by enumerating each legacy file.
5. Non-inclusion of macOS: Current scripts target Linux/Windows parity; macOS adds maintenance without current AL-specific value.

### Risks & Mitigations
| Risk | Impact | Mitigation |
|------|--------|------------|
| bats repo transient failure | CI red flakiness | Retry in future / consider version tarball pin if recurrent |
| Pester gallery outage | Windows leg fails | Could add cached module in future if needed |
| Incomplete migration | Coverage gap | Mandatory coverage mapping checklist in PR |
| Future scale (>500 tests) | Longer CI times | Potential future sharding by directory or parallelization |

### Open Questions (Resolved)
None—spec ambiguities minimal; all assumptions acceptable.

### Conclusion
Research supports minimal, standards-based adoption with clear migration and guard semantics. Proceeding to Phase 1 design outputs.
