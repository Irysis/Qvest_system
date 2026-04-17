#!/usr/bin/env bash
# ─────────────────────────────────────────────────
# Quant Module Moltbot — 새 머신 초기 동기화 스크립트
# OneDrive에 저장되어 어느 머신에서든 실행 가능
# 사용법: bash 02_Infrastructure/setup_sync.sh
# ─────────────────────────────────────────────────
set -euo pipefail

echo "=== Quant Module Moltbot 동기화 세팅 ==="

# ── 1. OneDrive 경로 자동 탐지 ──
ONEDRIVE=""
for d in /mnt/c/Users/*/OneDrive; do
  if [ -d "$d/.claude_shared" ]; then
    ONEDRIVE="$d"
    break
  fi
done

if [ -z "$ONEDRIVE" ]; then
  echo "[ERROR] OneDrive/.claude_shared 를 찾을 수 없습니다."
  echo "        OneDrive가 동기화된 상태인지 확인해주세요."
  exit 1
fi

CLAUDE_SHARED="$ONEDRIVE/.claude_shared"
PROJECT_DIR="$ONEDRIVE/바탕 화면/Quant_Module_Moltbot"

echo "[OK] OneDrive 경로: $ONEDRIVE"
echo "[OK] Claude 설정:   $CLAUDE_SHARED"
echo "[OK] 프로젝트:      $PROJECT_DIR"

# ── 2. ~/.claude 심링크 ──
if [ -L "$HOME/.claude" ]; then
  CURRENT=$(readlink "$HOME/.claude")
  if [ "$CURRENT" = "$CLAUDE_SHARED" ]; then
    echo "[OK] ~/.claude 심링크 이미 정상 → $CLAUDE_SHARED"
  else
    echo "[FIX] ~/.claude 심링크 대상 변경: $CURRENT → $CLAUDE_SHARED"
    ln -snf "$CLAUDE_SHARED" "$HOME/.claude"
  fi
elif [ -d "$HOME/.claude" ]; then
  echo "[WARN] ~/.claude 가 일반 디렉토리입니다. 백업 후 심링크 생성..."
  BACKUP="$HOME/.claude_backup_$(date +%Y%m%d_%H%M%S)"
  mv "$HOME/.claude" "$BACKUP"
  echo "[OK] 백업: $BACKUP"
  ln -s "$CLAUDE_SHARED" "$HOME/.claude"
  echo "[OK] 심링크 생성: ~/.claude → $CLAUDE_SHARED"
else
  ln -s "$CLAUDE_SHARED" "$HOME/.claude"
  echo "[OK] 심링크 생성: ~/.claude → $CLAUDE_SHARED"
fi

# ── 3. .bashrc alias ──
ALIAS_LINE="alias qm='cd \"$PROJECT_DIR\" && claude'"
if grep -qF "alias qm=" "$HOME/.bashrc" 2>/dev/null; then
  EXISTING=$(grep "alias qm=" "$HOME/.bashrc")
  if [ "$EXISTING" = "$ALIAS_LINE" ]; then
    echo "[OK] .bashrc alias qm 이미 정상"
  else
    # 경로가 다르면 교체
    sed -i "s|^alias qm=.*|$ALIAS_LINE|" "$HOME/.bashrc"
    echo "[FIX] .bashrc alias qm 경로 업데이트"
  fi
else
  echo "" >> "$HOME/.bashrc"
  echo "# Quant_Module_Moltbot 프로젝트 실행 별칭" >> "$HOME/.bashrc"
  echo "$ALIAS_LINE" >> "$HOME/.bashrc"
  echo "[OK] .bashrc alias qm 추가"
fi

# ── 4. 검증 ──
echo ""
echo "=== 검증 ==="
echo "심링크:  $(ls -la "$HOME/.claude" | awk '{print $NF, $(NF-1), $(NF-2)}')"
echo "메모리:  $(ls "$HOME/.claude/projects/-mnt-c-Users-"*"/memory/" 2>/dev/null | wc -l) 파일"
echo "설정:    $(cat "$HOME/.claude/settings.json" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(len(d.get("permissions",{}).get("allow",[])), "permissions")' 2>/dev/null || echo 'OK')"
echo "에이전트: $(ls "$HOME/.claude/agents/" 2>/dev/null | tr '\n' ' ')"
echo "규칙:    $(ls "$HOME/.claude/rules/" 2>/dev/null | wc -l) 파일"
echo ""
echo "=== 완료! 'qm' 으로 시작하세요 ==="
