#!/usr/bin/env bash
set -euo pipefail

# Non-interactive installer. 대화형 설정은 docs/install.md를 따르는 에이전트가 처리한다.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

REPO="jyeokchoi/claude-skills"
REPO_URL="https://github.com/$REPO"
SKILLS_DIR="${SKILLS_DIR:-$HOME/.claude/skills}"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

info()  { echo -e "${BLUE}[info]${NC} $*"; }
ok()    { echo -e "${GREEN}[ok]${NC} $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC} $*"; }

# ── Check oh-my-claudecode ───────────────────────────────────────────
echo ""
echo -e "${BOLD}Checking oh-my-claudecode${NC}"

OMC_INSTALLED=false
if [ -d "$HOME/.claude/plugins/cache/omc" ] || \
   [ -d "$HOME/.claude/plugins/cache/oh-my-claudecode" ]; then
  OMC_VERSION=$(ls "$HOME/.claude/plugins/cache/omc/oh-my-claudecode/" 2>/dev/null | sort -V | tail -1 || echo "unknown")
  ok "oh-my-claudecode found (version: $OMC_VERSION)"
  OMC_INSTALLED=true
else
  warn "oh-my-claudecode not found."
  echo "  OMC 없이도 기본 동작은 가능하지만 멀티에이전트 기능이 제한됩니다."
  echo "  https://github.com/Yeachan-Heo/oh-my-claudecode"
fi

# ── Download ─────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Downloading skills${NC}"

if command -v git &>/dev/null; then
  info "Cloning $REPO..."
  git clone --depth 1 "$REPO_URL" "$TEMP_DIR/claude-skills" 2>/dev/null
else
  info "git not found, using curl..."
  curl -sL "$REPO_URL/archive/refs/heads/main.tar.gz" | tar xz -C "$TEMP_DIR"
  mv "$TEMP_DIR"/claude-skills-main "$TEMP_DIR/claude-skills"
fi

ok "Downloaded."

# ── Install skills ───────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Installing skills${NC}"

mkdir -p "$SKILLS_DIR"

SRC="$TEMP_DIR/claude-skills/skills"

# Backup only conflicting directories
CONFLICTS=()
for category_dir in "$SRC"/*/; do
  category=$(basename "$category_dir")
  [[ "$category" == _* ]] && continue
  for skill_dir in "$category_dir"/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name=$(basename "$skill_dir")
    [ -d "$SKILLS_DIR/$skill_name" ] && CONFLICTS+=("$skill_name")
  done
done
[ -d "$SKILLS_DIR/_shared" ] && CONFLICTS+=("_shared")
[ -d "$SKILLS_DIR/_templates" ] && CONFLICTS+=("_templates")

if [ ${#CONFLICTS[@]} -gt 0 ]; then
  BACKUP_DIR="$SKILLS_DIR.backup.$(date +%Y%m%d%H%M%S)"
  mkdir -p "$BACKUP_DIR"
  warn "${#CONFLICTS[@]}개 기존 스킬이 덮어씌워집니다. 백업: $BACKUP_DIR"
  for name in "${CONFLICTS[@]}"; do
    cp -r "$SKILLS_DIR/$name" "$BACKUP_DIR/"
  done
fi

# Copy _shared and _templates
cp -r "$SRC/_shared" "$SKILLS_DIR/"
cp -r "$SRC/_templates" "$SKILLS_DIR/"

# Flatten category subdirectories
for category_dir in "$SRC"/*/; do
  category=$(basename "$category_dir")
  [[ "$category" == _* ]] && continue
  for skill_dir in "$category_dir"/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name=$(basename "$skill_dir")
    cp -r "$skill_dir" "$SKILLS_DIR/$skill_name"
  done
done

SKILL_COUNT=$(find "$SKILLS_DIR" -name "SKILL.md" | wc -l | tr -d ' ')
ok "Installed $SKILL_COUNT skills to $SKILLS_DIR/"

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}Installation complete!${NC}"
echo ""
echo "  Skills:   $SKILL_COUNT"
echo "  Location: $SKILLS_DIR/"
echo "  OMC:      $([ "$OMC_INSTALLED" = true ] && echo "installed" || echo "not installed")"
echo ""
