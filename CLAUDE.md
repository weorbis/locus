# Safety

- Never read `.env`, `secrets/`, credentials, or private keys.
- Never run destructive commands (`rm -rf`, `drop`, `--force`, `reset --hard`).
- All findings must cite concrete evidence (file:line, test output, logs).
