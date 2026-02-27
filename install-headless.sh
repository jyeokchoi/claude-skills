#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# claude-skills headless installer
#
# Cloud-based Claude Code 웹 세션(headless, no user input)에서
# claude-skills를 ~/.claude/skills/ (user-level)에 원샷 설치한다.
#
# 동작:
#   1. git clone (없으면 curl fallback)으로 레포 다운로드
#   2. _shared/, _templates/ 복사
#   3. 카테고리 스킬을 플랫하게 복사 (기존 파일 덮어쓰기)
#   4. ~/.claude/settings.json에 훅 등록 (기존 설정 보존, JSON merge)
#   5. Playwright MCP 등록 시도 (실패해도 계속 진행)
#
# Usage:
#   curl -sL https://raw.githubusercontent.com/jyeokchoi/claude-skills/main/install-headless.sh | bash
#   # 또는
#   bash install-headless.sh
###############################################################################

REPO="jyeokchoi/claude-skills"
REPO_URL="https://github.com/$REPO"
SKILLS_DIR="$HOME/.claude/skills"
SETTINGS="$HOME/.claude/settings.json"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

info()  { echo "[info] $*"; }
ok()    { echo "[ok]   $*"; }
warn()  { echo "[warn] $*"; }
fail()  { echo "[FAIL] $*" >&2; }

# ── 1. Download ──────────────────────────────────────────────────────────────

info "Downloading claude-skills..."

if command -v git &>/dev/null; then
  git clone --depth 1 "$REPO_URL" "$TEMP_DIR/claude-skills" 2>/dev/null
elif command -v curl &>/dev/null; then
  curl -sL "$REPO_URL/archive/refs/heads/main.tar.gz" | tar xz -C "$TEMP_DIR"
  mv "$TEMP_DIR/claude-skills-main" "$TEMP_DIR/claude-skills"
elif command -v wget &>/dev/null; then
  wget -qO- "$REPO_URL/archive/refs/heads/main.tar.gz" | tar xz -C "$TEMP_DIR"
  mv "$TEMP_DIR/claude-skills-main" "$TEMP_DIR/claude-skills"
else
  fail "git, curl, wget 모두 없음. 설치 불가."
  exit 1
fi

ok "Downloaded."

# ── 2. Install skills ────────────────────────────────────────────────────────

info "Installing skills to $SKILLS_DIR ..."

mkdir -p "$SKILLS_DIR"

SRC="$TEMP_DIR/claude-skills/skills"

rm -rf "$SKILLS_DIR/_shared" "$SKILLS_DIR/_templates"
cp -r "$SRC/_shared" "$SKILLS_DIR/"
cp -r "$SRC/_templates" "$SKILLS_DIR/"

for category_dir in "$SRC"/*/; do
  category=$(basename "$category_dir")
  [[ "$category" == _* ]] && continue
  for skill_dir in "$category_dir"/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name=$(basename "$skill_dir")
    rm -rf "$SKILLS_DIR/$skill_name"
    cp -r "$skill_dir" "$SKILLS_DIR/$skill_name"
  done
done

if command -v find &>/dev/null; then
  SKILL_COUNT=$(find "$SKILLS_DIR" -name "SKILL.md" | wc -l | tr -d ' ')
else
  SKILL_COUNT="(unknown)"
fi

ok "Installed $SKILL_COUNT skills."

# ── 3. Register hooks in settings.json ───────────────────────────────────────

info "Registering hooks in $SETTINGS ..."

ABS_SKILLS_DIR=$(cd "$SKILLS_DIR" && pwd)

mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

merge_hooks() {
  local settings_file="$1"
  local skills_dir="$2"

  if command -v node &>/dev/null; then
    node -e "
const fs = require('fs');
const path = '$skills_dir';
const settingsFile = '$settings_file';

let settings = {};
try { settings = JSON.parse(fs.readFileSync(settingsFile, 'utf8')); } catch {}

if (!settings.hooks) settings.hooks = {};

// PreCompact hook
const preCompactCmd = 'node \"' + path + '/_shared/hooks/pre-compact-worklog.mjs\"';
const hasPreCompact = Array.isArray(settings.hooks.PreCompact) &&
  settings.hooks.PreCompact.some(h =>
    h.hooks && h.hooks.some(hh => hh.command && hh.command.includes('pre-compact-worklog'))
  );
if (!hasPreCompact) {
  if (!Array.isArray(settings.hooks.PreCompact)) settings.hooks.PreCompact = [];
  settings.hooks.PreCompact.push({
    hooks: [{ type: 'command', command: preCompactCmd, timeout: 10 }]
  });
}

// SessionStart hook (matcher: compact)
const sessionStartCmd = 'node \"' + path + '/_shared/hooks/post-compact-inject.mjs\"';
const hasSessionStart = Array.isArray(settings.hooks.SessionStart) &&
  settings.hooks.SessionStart.some(h =>
    h.hooks && h.hooks.some(hh => hh.command && hh.command.includes('post-compact-inject'))
  );
if (!hasSessionStart) {
  if (!Array.isArray(settings.hooks.SessionStart)) settings.hooks.SessionStart = [];
  settings.hooks.SessionStart.push({
    hooks: [{ type: 'command', command: sessionStartCmd, timeout: 5 }],
    matcher: 'compact'
  });
}

fs.writeFileSync(settingsFile, JSON.stringify(settings, null, 2) + '\\n');
"
  elif command -v python3 &>/dev/null; then
    python3 -c "
import json, os, sys

settings_file = '$settings_file'
skills_dir = '$skills_dir'

try:
    with open(settings_file) as f:
        settings = json.load(f)
except:
    settings = {}

hooks = settings.setdefault('hooks', {})

# PreCompact
pre_cmd = f'node \"{skills_dir}/_shared/hooks/pre-compact-worklog.mjs\"'
pre_list = hooks.get('PreCompact', [])
if not isinstance(pre_list, list):
    pre_list = []
has_pre = any(
    any('pre-compact-worklog' in (hh.get('command','') or '') for hh in h.get('hooks',[]))
    for h in pre_list
)
if not has_pre:
    pre_list.append({'hooks': [{'type': 'command', 'command': pre_cmd, 'timeout': 10}]})
hooks['PreCompact'] = pre_list

# SessionStart
sess_cmd = f'node \"{skills_dir}/_shared/hooks/post-compact-inject.mjs\"'
sess_list = hooks.get('SessionStart', [])
if not isinstance(sess_list, list):
    sess_list = []
has_sess = any(
    any('post-compact-inject' in (hh.get('command','') or '') for hh in h.get('hooks',[]))
    for h in sess_list
)
if not has_sess:
    sess_list.append({
        'hooks': [{'type': 'command', 'command': sess_cmd, 'timeout': 5}],
        'matcher': 'compact'
    })
hooks['SessionStart'] = sess_list

with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\\n')
"
  else
    warn "node/python3 not found. Hook registration skipped."
    warn "수동으로 $SETTINGS 에 훅을 등록하세요."
    return 1
  fi
}

if merge_hooks "$SETTINGS" "$ABS_SKILLS_DIR"; then
  ok "Hooks registered."
else
  warn "Hook registration failed (non-fatal)."
fi

# ── 4. Playwright MCP (best-effort) ─────────────────────────────────────────

info "Attempting Playwright MCP setup (optional)..."

if command -v claude &>/dev/null; then
  claude mcp add playwright -s user -- npx @playwright/mcp@latest 2>/dev/null && \
    ok "Playwright MCP registered." || \
    warn "Playwright MCP registration failed (non-fatal). /vbrowser will be unavailable."
else
  warn "claude CLI not found. Playwright MCP skipped."
fi

if command -v npx &>/dev/null; then
  npx playwright install chromium 2>/dev/null && \
    ok "Chromium installed." || \
    warn "Chromium install failed (non-fatal). Will auto-install on first use."
fi

# ── 5. Summary ───────────────────────────────────────────────────────────────

echo ""
echo "============================================"
echo "  claude-skills installation complete!"
echo "============================================"
echo ""
echo "  Skills:   $SKILL_COUNT"
echo "  Location: $SKILLS_DIR/"
echo "  Hooks:    $SETTINGS"
echo ""
echo "  Recommended starting points:"
echo "    /worklog-start     — Start a new task"
echo "    /vplan             — Structured planning"
echo "    /vimpl             — TDD-based implementation"
echo "    /exhaustive-review — 3-persona debate review"
echo ""
