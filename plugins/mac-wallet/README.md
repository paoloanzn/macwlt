# Mac Wallet Agent Skills

`mac-wallet` packages reusable agent workflows for the macwlt CLI.

The plugin is compatible with both plugin layouts:

- Codex: `.codex-plugin/plugin.json`
- Claude Code: `.claude-plugin/plugin.json`

## Skills

### `sending-evm-assets`

Resolves friendly asset and network names from macwlt's config, checks the
sender's token and gas balances, presents an exact transfer summary, requires a
fresh confirmation, and submits the transfer once through `macwlt send`.

Example:

```text
Send 10 USDC on Base to <recipient-address>.
```

The skill never accesses or exports private key material.

## Install A Standalone Skill

From the repository:

```shell
./install-skill.sh
```

Select an agent explicitly when auto-detection is ambiguous:

```shell
AGENT=claude ./install-skill.sh
AGENT=codex ./install-skill.sh
```

The installer mirrors the skill to `~/.claude/skills` for Claude Code or
`~/.agents/skills` for Codex. `SOURCE_DIR` can point at a local checkout.

## Test The Plugin Directly

Claude Code can load the plugin without installation:

```shell
claude --plugin-dir ./plugins/mac-wallet
```

To install through the repository marketplaces:

```shell
claude plugin marketplace add .
claude plugin install mac-wallet@macwlt

codex plugin marketplace add .
codex plugin add mac-wallet@macwlt
```

Start a new agent session after plugin installation.
