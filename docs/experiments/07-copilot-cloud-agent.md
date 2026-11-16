# 07 — The Copilot cloud agent on the runners

**Date:** 2026-11-16 · **Answers:** Q9 · **Versions:** image `gh-runner:e1410b7`, `egress-proxy:1375b5d` then with `learn.microsoft.com`, Copilot cloud agent (November 2026)

## Goal

The target repository's Copilot cloud agent sessions run on the ephemeral `aca-agent` runners, behind the egress proxy, and finish their task.

## Setup

- The target repository's `copilot-setup-steps.yml` with `runs-on: aca-agent` and `actions/setup-go` (the image has no Go); run once by hand on the runners from a branch: 1 min 47 s, no request denied.
- The proxy's allowlist with `.githubcopilot.com` (the Copilot API hosts of every plan); `uploads.github.com` and `user-images.githubusercontent.com` were already covered.
- The agent's integrated firewall turned off in the repository's settings (required on self-hosted runners).
- Up to 4 executions at once (`RUNNER_MAX_EXECUTIONS`): an agent session holds one for its whole length.

## Steps and result

1. **A session started with the default environment (Cloud)** ran in a GitHub-hosted cloud sandbox: no workflow run, no execution, no runner. The environment is chosen when the session starts (Environment → Cloud or Actions) and can't be changed afterwards.
2. **Two sessions started with Environment → Actions** each ran as a `Copilot cloud agent` workflow run on an `aca-agent` runner and succeeded (6 min 46 s, and 5 min 40 s for a one-line README fix that opened a pull request). Each runner left when its session ended.
3. **Through the proxy** (second session): 194 connections allowed, among them `api.enterprise.githubcopilot.com`, `copilot-proxy.githubusercontent.com`, `codeload.github.com`, npm and about 1 GB from `release-assets.githubusercontent.com`. Denied: `learn.microsoft.com`, four times at start-up in both sessions: the Microsoft Learn MCP server the repository declares in `.mcp.json`. Added to the allowlist; the smoke test passed after the update.

## Conclusion

- **Q9, answered:** the cloud agent runs on these runners, behind the allowlist proxy, when sessions are started with **Actions**.
- **To keep in mind:** with the integrated firewall off, sessions started with **Cloud** in this repository run in GitHub's sandbox without that firewall (the sandbox follows the agent's firewall setting). Start this repository's sessions with Actions.
- The agent connects at start-up to the MCP servers the repository declares: their hosts belong on the allowlist.
