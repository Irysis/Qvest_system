#!/bin/bash
# weekly_research_collect.sh — 주간 논문/블로그 자동 수집
# Cron: 0 21 * * 0 (매주 일요일 21:00 KST)
#
# 파이프라인:
#   1. arxiv 논문 검색 + 다운로드 + 분류 + paper_registry 등록
#   2. RSS 블로그 수집 + idea_registry 등록
#   3. 텔레그램 요약 알림

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
VENV="/home/quant/.venv/bin/python3"
LOG_DIR="${PROJECT_ROOT}/04_Research/logs"

mkdir -p "$LOG_DIR"
LOGFILE="${LOG_DIR}/weekly_research_$(date +%Y%m%d_%H%M).log"

echo "===== Weekly Research Collection: $(date) =====" | tee -a "$LOGFILE"

# Step 1: arxiv papers (MCP 기반으로 전환 — collector.py 제거됨)
echo "[Step 1/2] arxiv paper collection — SKIPPED (MCP arxiv/jina로 대체)" | tee -a "$LOGFILE"
# TODO: Claude Code Scout 에이전트가 MCP로 논문 수집 담당. 크론 수집은 비활성.

sleep 1

# Step 2: Blog/RSS collection (MCP 기반으로 전환)
echo "[Step 2/2] Blog/RSS collection — SKIPPED (MCP rss-reader로 대체)" | tee -a "$LOGFILE"
# TODO: rss-reader MCP 서버가 피드 수집 담당.

echo "===== Weekly Research Complete: $(date) =====" | tee -a "$LOGFILE"
