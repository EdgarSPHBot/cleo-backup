#!/usr/bin/env bash
# Cleo Daily Backup Script
set -euo pipefail

BACKUP_DIR="/home2/cleo/src/cleo-backup"
OPENCLAW_DIR="/home2/cleo/.openclaw"
WORKSPACE_DIR="$OPENCLAW_DIR/workspace"
TIMESTAMP=$(date -u '+%Y-%m-%d %H:%M UTC')
DATE_TAG=$(date -u '+%Y-%m-%d')

declare -a SECRET_PATTERNS=(
  's/sk-[A-Za-z0-9_-]{20,}/[OPENAI_API_KEY]/g'
  's/sk-ant-[A-Za-z0-9_-]{20,}/[ANTHROPIC_API_KEY]/g'
  's/xai-[A-Za-z0-9_-]{20,}/[XAI_API_KEY]/g'
  's/AKIA[A-Z0-9]{16}/[AWS_ACCESS_KEY_ID]/g'
  's/"apiKey"\s*:\s*"[^"]+/"apiKey": "[REDACTED_API_KEY]/g'
  's/"token"\s*:\s*"[^"]+/"token": "[REDACTED_TOKEN]/g'
  's/"secret"\s*:\s*"[^"]+/"secret": "[REDACTED_SECRET]/g'
  's/"password"\s*:\s*"[^"]+/"password": "[REDACTED_PASSWORD]/g'
  's/"appPassword"\s*:\s*"[^"]+/"appPassword": "[REDACTED_APP_PASSWORD]/g'
  's/"appSecret"\s*:\s*"[^"]+/"appSecret": "[REDACTED_APP_SECRET]/g'
  's/"clientSecret"\s*:\s*"[^"]+/"clientSecret": "[REDACTED_CLIENT_SECRET]/g'
  's/"appPassword"\s*:\s*"[^"]+/"appPassword": "[REDACTED_APP_PASSWORD]/g'
  's/"appSecret"\s*:\s*"[^"]+/"appSecret": "[REDACTED_APP_SECRET]/g'
  's/mongodb(\+srv)?:\/\/[^@]+@/mongodb\1:\/\/[MONGO_USER:MONGO_PASS]@/g'
  's/ghp_[A-Za-z0-9]{36}/[GITHUB_PAT]/g'
  's/ghs_[A-Za-z0-9]{36}/[GITHUB_APP_TOKEN]/g'
)

scrub_secrets() {
  local content="$1"
  for pattern in "${SECRET_PATTERNS[@]}"; do
    content=$(echo "$content" | perl -pe "$pattern" 2>/dev/null || echo "$content")
  done
  echo "$content"
}

copy_and_scrub() {
  local src="$1"
  local dest="$2"
  if [ ! -f "$src" ]; then return 1; fi
  mkdir -p "$(dirname "$dest")"
  if file "$src" | grep -qE 'image|PNG|JPEG|bitmap'; then
    cp "$src" "$dest"
  else
    local content
    content=$(cat "$src")
    scrub_secrets "$content" > "$dest"
  fi
}

echo "═══ Cleo Backup — $TIMESTAMP ═══"
COPIED=0

# Workspace core files
for f in AGENTS.md SOUL.md TOOLS.md IDENTITY.md USER.md HEARTBEAT.md MEMORY.md DREAMS.md TENETS.md; do
  src="$WORKSPACE_DIR/$f"
  if [ -f "$src" ]; then
    copy_and_scrub "$src" "$BACKUP_DIR/workspace/$f" && COPIED=$((COPIED+1))
  fi
done

# Memory files
mkdir -p "$BACKUP_DIR/workspace/memory"
for f in "$WORKSPACE_DIR"/memory/*.md; do
  [ -f "$f" ] || continue
  copy_and_scrub "$f" "$BACKUP_DIR/workspace/memory/$(basename "$f")" && COPIED=$((COPIED+1))
done

# Skills
for skill_dir in "$WORKSPACE_DIR"/skills/*/; do
  [ -d "$skill_dir" ] || continue
  skill_name=$(basename "$skill_dir")
  if [ -f "$skill_dir/SKILL.md" ]; then
    copy_and_scrub "$skill_dir/SKILL.md" "$BACKUP_DIR/workspace/skills/$skill_name/SKILL.md" && COPIED=$((COPIED+1))
  fi
done

# Gateway config (scrubbed)
copy_and_scrub "$OPENCLAW_DIR/openclaw.json" "$BACKUP_DIR/config/openclaw.json" && COPIED=$((COPIED+1))

# Git config
if [ -f "/home2/cleo/.gitconfig" ]; then
  cp "/home2/cleo/.gitconfig" "$BACKUP_DIR/config/gitconfig" && COPIED=$((COPIED+1))
fi

# Commit and push
cd "$BACKUP_DIR"
git add -A

if git diff --cached --quiet; then
  echo "✅ No changes since last backup."
  SUMMARY="no changes"
else
  CHANGED=$(git diff --cached --stat | tail -1)
  SUMMARY="$CHANGED"
  git commit -m "backup: $DATE_TAG — $CHANGED" --quiet
  git push origin main --quiet 2>&1
  echo "✅ Backup pushed: $CHANGED"
fi

echo "═══ Done: $COPIED files backed up ═══"
echo "$SUMMARY"
