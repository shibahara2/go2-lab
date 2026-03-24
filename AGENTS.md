# Agent Operation Policy

This file defines repository-boundary rules for agents working in this project.

## Allowed

- Write operations are allowed only for this repository (`go2-lab`).
- Allowed write operations for `go2-lab` include creating issues, creating pull requests, and pushing changes.

## Forbidden

- Do not create issues, pull requests, pushes, or perform any other write operation against any repository other than `go2-lab`.
- This prohibition includes repositories listed in `go2.repos`.
- This prohibition also includes nested or vendored external repositories such as `zenoh`.

## Confirmation Rule

- If the target repository is ambiguous, ask before taking any write action.
- Before any write action, state the target repository and the intended action explicitly.
