# OpenCode v2 migration

Reference: https://opencode.ai/docs/migrate-v1/

**V1 audit plugin:** The plugin is parked as `plugins/permission-audit.ts.disabled`
to prevent v1 auto-discovery. To re-enable it in v1 only, rename it back to
`plugins/permission-audit.ts` and restart OpenCode.

`experimental.todo: true` enables todos for all agents, including researcher and reviewer (whose todowrite was off in v1); this is intentional and harmless.

## Switch and rollback

1. Copy `opencode.jsonc` to `opencode.v1.jsonc` before upgrading. Keep the v1 backup.
2. Remove a package-managed v1 installation if applicable, then install the v2 terminal client using the [official installation instructions](https://opencode.ai/#cli). The official migration guide says the v2 curl installer replaces the v1 binary.
3. Rename `opencode.v2.jsonc` to `opencode.jsonc`, replacing the active v1 file, then restart OpenCode and run `opencode debug config`.
4. To roll back, reverse the config swap (save the v2 file back as `opencode.v2.jsonc` and restore `opencode.v1.jsonc` to `opencode.jsonc`), reinstall v1 using the appropriate method for the original installation, restart, and run `opencode debug config`. Do not run v1 against the v2-only config.

## Smoke tests after switching

- Coder can call researcher at subagent depth 2.
- `git push` is denied for coder and built-in build.
- Reading `~/AppData/Local/nvim` prompts; reading `~/AppData/Local/nvim-data` does not prompt for external-directory access.
- Researcher reading a file outside the project (e.g. `~/AppData/Local/nvim/init.lua`) must be denied outright, not prompted.
- Architect shell `Get-ChildItem .` is allowed; `npm --version` is denied.
- Todos work; researcher websearch works with `EXA_API_KEY` set.

## Unverified items and fallbacks

- Check that `{file:}` expands in agent `system` values and the actual prompts are loaded. If not, convert to Markdown agent files in `agents/` with each prompt as the file body.
- Check that `github-copilot/gpt-6.1-terra#medium` is available and the configured medium reasoning variant is used. If not, inspect the v2 provider catalog and use a supported model/variant with equivalent reasoning settings.
- Check how the v2 PowerShell scanner splits piped and chained commands before relying on broad allow patterns. If unsafe, tighten shell permissions to ask or deny until safe rules are established.
- Check prompt references to `task`, `todowrite`, and `question` against v2 tool names. If they differ, update `prompts/*.md` after migration.
- The v1 audit plugin does not run in v2. If audit logging is wanted, rewrite it for v2 using `Plugin.define` and verify it independently.
- `@opencode-ai/plugin` in `package.json` and the `Setup-Symlink.ps1` node_modules note are unused while the audit plugin is parked and by v2 without a ported plugin. If a plugin is later enabled or added, revisit its dependency and setup needs.
- V2 subagents always run in the background (2.3.0). Check orchestration and completion handling; if this disrupts the workflow, adjust prompts and orchestration to wait for results.
