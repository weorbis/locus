# Engineering Intelligence Pack

> Ported from Claude Code configuration. Source of truth: `CLAUDE.md` + `.claude/`

**Project**: locus
**Framework**: Flutter

## Core Rules

1. **Evidence-driven**: Every finding must cite concrete evidence (file:line, test output, logs).
2. **Confidence labels**: Classify findings as CONFIRMED, LIKELY, or POSSIBLE.
3. **No guessing**: If you cannot determine something from code, say what verification is needed.
4. **Safety first**: Never read `.env`, `secrets/`, credentials, or private keys. Never run destructive commands (`rm -rf`, `drop`, `--force`, `reset --hard`).
5. **Reference docs**: Detailed investigation standards and checklists are in `.claude/docs/`.

## Available Skills

### Investigation
- `investigate` — Full investigation of a module or area
- `bug-hunt` — Targeted bug detection pass
- `arch-audit` — Architecture-level audit
- `smell-scan` — Code smell detection
- `evidence-report` — Generate a structured findings report

### UX Analysis
- `ux-audit` — Full UX + UI evaluation
- `visual-audit` — Visual quality audit (spacing, typography, color)
- `flow-audit` — User journey and flow analysis
- `component-audit` — Component architecture and design system scan
- `redesign-report` — Combined actionable redesign plan

### Simplification
- `simplify` — Smart one-run pipeline: scan, analyze, plan, refactor, prove

### Verification
- `verify-changes` — Run lightest safe checks for this project type

## Verification Commands

- **Build**: `flutter pub get`
- **Test**: `flutter test`
- **Lint**: `flutter analyze`

## Skill Invocation

All skills require **explicit invocation**. They will not trigger automatically.
Invoke a skill by name (e.g., `investigate`, `ux-audit`, `simplify`).
