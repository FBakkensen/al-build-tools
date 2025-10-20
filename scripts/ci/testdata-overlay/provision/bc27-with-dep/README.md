# Test Fixture: BC 27 with Dependency

This test fixture validates the `Invoke-Build provision` workflow with:

- **BC Version**: 27.0.0.0 (platform and application)
- **Runtime**: 14.0
- **Dependency**: 9A Advanced Manufacturing - License (9altitudes, v24.7.0.0)

## Purpose

Tests that the provision task correctly:
1. Downloads and installs the AL compiler for BC 27
2. Resolves and downloads symbol packages from Microsoft NuGet feed
3. Downloads third-party dependency symbols (9altitudes)
4. Creates proper cache structure at `~/.bc-tool-cache/` and `~/.bc-symbol-cache/`

## Structure

```
bc27-with-dep/
├── app.json           # BC 27 app with 9altitudes dependency
├── app/
│   └── HelloWorld.al  # Minimal AL code
└── README.md          # This file
```

## Usage

This fixture is mounted into test containers and used by `container-test-overlay-provision.ps1` to validate the provision workflow.
