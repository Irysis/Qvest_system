#!/bin/bash
#==============================================================================
# migrate_project_root.sh — Quant_Module_Moltbot 안전 드라이브/경로 이전
#
#   목적: 작업 트리를 새 위치(기본 G:\ = /mnt/g)로 비파괴 이전 + QM_ROOT 정합 검증.
#   설계: 복사+검증만 수행. 원본 삭제는 사용자가 검증 후 수동 (rollback 보장).
#   전제: WSL(Ubuntu)에서 실행. 중앙 resolver 3종(config.R / resolve_project.sh /
#         settings.json)은 이미 QM_ROOT 우선으로 패치됨 (2026-06-03).
#
#   사용:
#     bash 02_Infrastructure/ops/migrate_project_root.sh [DEST]
#       DEST 기본값 = /mnt/g/Quant_Module_Moltbot
#     원본 경로 override: QM_SRC=/mnt/c/... bash ... migrate_project_root.sh
#
#   ※ 대용량(.cache 40GB 포함, 총 ~56GB) 초기 복사는 Windows robocopy가 9p rsync보다
#      훨씬 빠름. 아래 STEP 2 주석의 PowerShell 명령을 먼저 돌린 뒤 본 스크립트를
#      실행하면, rsync는 델타만 동기화(멱등)하여 빠르게 끝난다.
#==============================================================================
set -uo pipefail

SRC_DEFAULT="/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
SRC="${QM_SRC:-$SRC_DEFAULT}"
DEST="${1:-/mnt/g/Quant_Module_Moltbot}"

log(){ echo "[migrate] $*"; }
fail(){ echo "[migrate][ERROR] $*" >&2; exit 1; }

log "이전: [$SRC]"
log "  →  [$DEST]"

# ── STEP 0: pre-flight ───────────────────────────────────────────────────────
[ -d "$SRC" ] || fail "원본 디렉토리 없음: $SRC"
[ "$SRC" != "$DEST" ] || fail "SRC와 DEST가 동일"

DEST_LETTER=$(echo "$DEST" | sed -E 's|^/mnt/([a-z]).*|\1|')
DEST_MNT="/mnt/$DEST_LETTER"
if ! mount | grep -qE " $DEST_MNT (type )?9p| $DEST_MNT type drvfs"; then
  mount | grep -q " $DEST_MNT " || fail "$DEST_MNT 미마운트 — WSL에서 ${DEST_LETTER^^}: 접근 불가. (Windows 탐색기에서 드라이브 인식 후 'wsl --shutdown' 재기동 또는 sudo mount -t drvfs ${DEST_LETTER^^}: $DEST_MNT)"
fi
log "마운트 OK: $DEST_MNT"
mkdir -p "$(dirname "$DEST")" || fail "DEST 상위 디렉토리 생성 실패"

# ── STEP 1: 용량 확인 ────────────────────────────────────────────────────────
NEED=$(du -sb "$SRC" 2>/dev/null | cut -f1)
AVAIL=$(df -B1 --output=avail "$DEST_MNT" 2>/dev/null | tail -1 | tr -d ' ')
log "필요 $((NEED/1024/1024/1024))GB / 가용 $((AVAIL/1024/1024/1024))GB"
[ -n "$AVAIL" ] && [ "$AVAIL" -gt "$NEED" ] || fail "대상 드라이브 공간 부족"

# ── STEP 2: 복사 (rsync — resumable·멱등·원본 보존) ──────────────────────────
#   ↓ 더 빠른 초기 복사를 원하면 PowerShell에서 먼저(원본 보존):
#     robocopy "C:\Users\User\OneDrive\바탕 화면\Quant_Module_Moltbot" `
#              "G:\Quant_Module_Moltbot" /E /COPY:DAT /DCOPY:DAT /MT:16 /R:1 /W:1 /XJ
#   그 뒤 본 스크립트를 돌리면 rsync가 델타만 맞춘다.
log "rsync 복사 시작 (.cache 40GB 포함 — 수 분~수십 분)..."
rsync -a --no-inc-recursive --info=progress2 "$SRC/" "$DEST/" || fail "rsync 실패 (재실행하면 이어서 진행)"
log "복사 완료"

# ── STEP 3: 무결성 검증 ──────────────────────────────────────────────────────
SRC_N=$(find "$SRC"  -type f 2>/dev/null | wc -l)
DEST_N=$(find "$DEST" -type f 2>/dev/null | wc -l)
log "파일 수: 원본 $SRC_N / 사본 $DEST_N"
[ "$DEST_N" -ge "$SRC_N" ] || log "[경고] 사본 파일 수가 적음 — rsync 재실행 권장"
if [ -f "$DEST/.git" ]; then
  log ".git gitfile 이전됨 → $(cat "$DEST/.git")  (저장소 본체는 WSL 홈, 이동 무관)"
else
  log "[경고] $DEST/.git 없음 — git 연결 확인 필요"
fi

# ── STEP 4: QM_ROOT 등록 (모든 resolver의 1순위) ─────────────────────────────
if grep -q "export QM_ROOT=" ~/.bashrc 2>/dev/null; then
  log "[경고] ~/.bashrc 에 QM_ROOT 이미 존재 — 수동 확인: grep QM_ROOT ~/.bashrc"
else
  echo "export QM_ROOT=\"$DEST\"" >> ~/.bashrc
  log "~/.bashrc 에 추가: export QM_ROOT=\"$DEST\""
fi
export QM_ROOT="$DEST"

# ── STEP 5: 새 위치 검증 ─────────────────────────────────────────────────────
log "── 검증 (새 위치)"
if ( cd "$DEST" && git rev-parse --is-inside-work-tree >/dev/null 2>&1 ); then
  log "  git ✓ ( $(cd "$DEST" && git rev-parse --abbrev-ref HEAD 2>/dev/null) )"
else
  log "  git ✗ — 필요 시: git --git-dir=/home/quant/qm_git config core.worktree \"$DEST\""
fi
if command -v Rscript >/dev/null 2>&1; then
  ( cd "$DEST" && Rscript -e 'source("02_Infrastructure/config.R"); cat("  config.R ✓ RESOLVED:", PROJECT_ROOT, "\n"); stopifnot(dir.exists(RAWDATA_PATH))' 2>&1 | grep -E "✓|RESOLVED|Error" | head -3 )
else
  log "  [정보] Rscript 미발견 — config.R 검증은 R 환경에서 수동 확인"
fi
( cd "$DEST" && source 02_Infrastructure/ops/resolve_project.sh && log "  resolve_project.sh ✓ [$PROJECT_ROOT]" )

cat <<EOF

────────────────────────────────────────────────────────────────────
다음 단계 (수동, 순서 준수):
  1) 새 셸에서 환경변수 적용:        source ~/.bashrc   (또는 WSL 재시작)
  2) 부트스트랩 전체 검증:           cd "$DEST" && bash 02_Infrastructure/ops/bootstrap.sh
  3) 정상 확인 후에만 원본 삭제:     rm -rf "$SRC"
  4) Claude Code를 새 위치에서 재실행 (Windows 경로 기준)
  5) 점검 권장(외부 참조): crontab -l / Windows 작업 스케줄러 / MCP 서버 cwd /
     telegram listener 서비스 — 옛 경로 하드코딩 시 갱신
주의:
  • 새 위치는 OneDrive 동기화 밖 → 40GB sync 폭주 해소(이점), 단 클라우드 백업은 별도 마련
  • OneDrive 'cloud-only' 파일이 있으면 복사 전 '이 장치에 항상 유지'로 로컬화
────────────────────────────────────────────────────────────────────
EOF
log "완료 (원본 보존됨 — 검증 후 수동 삭제)"
