# Success Metrics & Observation Plan

| Metric | Target | Collection Method | Frequency |
|--------|--------|-------------------|-----------|
| Artifact Purity | 100% | Manual spot check of archive file list vs overlay path | Each release |
| Hash Verification | 100% match | Recompute root hash locally using manifest lines | Each release |
| Workflow Duration P95 | ≤ 2 min | GitHub Actions run time export | Monthly review |
| Support Ticket Context Inclusion | ≥ 80% include version + root hash | Triage checklist | Quarterly |
| Tag Collisions | 0 | Count aborted runs due to existing tag | Continuous |
| Internal Leakage Incidents | 0 | Incident report log | Continuous |

## Data Handling
- Store observed durations and hash verification status in a lightweight internal log (future enhancement).
- For now, maintainers record anomalies in release PR or issue tracker label.
