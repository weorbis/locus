# Investigation Pack

This project uses the Claude Code Investigation Pack for structured code analysis.

## Rules

Detailed investigation standards and checklists live in `.claude/rules/`:

- @.claude/rules/investigation-standards.md — output format, evidence requirements
- @.claude/rules/bug-hunting.md — bug detection methodology
- @.claude/rules/architecture-smells.md — architectural anti-patterns
- @.claude/rules/code-smells.md — code-level anti-patterns
- @.claude/rules/security-basics.md — practical security checks

## Skills (Slash Commands)

- `/investigate` — Full investigation of a module or area
- `/bug-hunt` — Targeted bug detection pass
- `/arch-audit` — Architecture-level audit
- `/smell-scan` — Code smell detection
- `/evidence-report` — Generate a structured findings report

## Safety

- Never read `.env`, `secrets/`, credentials, or private keys.
- Never run destructive commands (`rm -rf`, `drop`, `--force`, `reset --hard`).
- All findings must cite concrete evidence (file:line, test output, logs).


---

# UX Investigation Pack

This project includes the UX Investigation Pack for structured UI/UX analysis and evidence-based improvement reports.

## UX Rules

Detailed UX investigation standards and checklists live in `.claude/rules/`:

- @.claude/rules/ux-investigation-standards.md — output format, evidence requirements, finding categories
- @.claude/rules/visual-design-principles.md — spacing, typography, color, alignment checks
- @.claude/rules/interaction-patterns.md — navigation, feedback, motion, forms, modals
- @.claude/rules/accessibility-basics.md — WCAG 2.2 criteria, code-level a11y checks
- @.claude/rules/design-system-consistency.md — tokens, component architecture, theming

## UX Skills (Slash Commands)

- `/ux-audit` — Full UX + UI evaluation of a feature or screen
- `/visual-audit` — Visual quality audit (spacing, typography, color, consistency)
- `/flow-audit` — User journey and flow analysis
- `/component-audit` — Component architecture and design system scan
- `/redesign-report` — Combined actionable redesign plan with prioritized improvements
