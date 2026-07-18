#!/bin/sh
set -eu

REPO="${REPO:-paoloanzn/macwlt}"
REF="${REF:-main}"
SKILL_NAME="${SKILL_NAME:-sending-evm-assets}"
SKILL_PATH="${SKILL_PATH:-plugins/mac-wallet/skills/${SKILL_NAME}}"
AGENT="${MACWLT_SKILL_AGENT:-${AGENT:-auto}}"

case "$AGENT" in
auto|claude|codex)
	;;
*)
	echo "Error: AGENT must be one of: auto, claude, codex" >&2
	exit 1
	;;
esac

download() {
	url="$1"
	out="$2"

	if command -v curl >/dev/null 2>&1; then
		curl -fsSL "$url" -o "$out"
		return
	fi

	if command -v wget >/dev/null 2>&1; then
		wget -q "$url" -O "$out"
		return
	fi

	echo "Error: curl or wget is required" >&2
	exit 1
}

resolve_agent() {
	if [ "$AGENT" != "auto" ]; then
		printf '%s\n' "$AGENT"
		return
	fi
	if [ -n "${CLAUDE_CODE_SKILLS_DIR:-}" ] || [ -d "$HOME/.claude" ]; then
		printf '%s\n' "claude"
		return
	fi
	if [ -n "${CODEX_HOME:-}" ] || [ -d "$HOME/.agents" ] ||
		[ -d "$HOME/.codex" ]; then
		printf '%s\n' "codex"
		return
	fi
	printf '%s\n' "claude"
}

resolve_skills_dir() {
	case "$1" in
	claude)
		printf '%s\n' "${SKILLS_DIR:-${CLAUDE_CODE_SKILLS_DIR:-$HOME/.claude/skills}}"
		;;
	codex)
		if [ -n "${SKILLS_DIR:-}" ]; then
			printf '%s\n' "$SKILLS_DIR"
		elif [ -n "${CODEX_HOME:-}" ]; then
			printf '%s\n' "$CODEX_HOME/skills"
		else
			printf '%s\n' "$HOME/.agents/skills"
		fi
		;;
	esac
}

install_skill() {
	src="$1"
	agent="$(resolve_agent)"
	skills_dir="$(resolve_skills_dir "$agent")"
	dst="${skills_dir%/}/${SKILL_NAME}"

	mkdir -p "$skills_dir"
	rm -rf "$dst"
	cp -R "$src" "$dst"
	printf 'Installed %s for %s at %s\n' "$SKILL_NAME" "$agent" "$dst"
}

install_from_root() {
	root="$1"
	src="${root%/}/${SKILL_PATH}"
	if [ ! -d "$src" ]; then
		echo "Error: skill directory not found at $src" >&2
		exit 1
	fi
	install_skill "$src"
}

if [ -n "${SOURCE_DIR:-}" ]; then
	install_from_root "$SOURCE_DIR"
	exit 0
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT INT TERM

archive="$tmpdir/repo.tar.gz"
url="https://codeload.github.com/${REPO}/tar.gz/refs/heads/${REF}"
download "$url" "$archive"
tar -xzf "$archive" -C "$tmpdir"

root_dir=""
for entry in "$tmpdir"/*; do
	if [ -d "$entry" ]; then
		root_dir="$entry"
		break
	fi
done

if [ -z "$root_dir" ]; then
	echo "Error: could not extract repository archive" >&2
	exit 1
fi

install_from_root "$root_dir"
