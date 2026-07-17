## R47 텔레그램 v7 보고 (무결성 근원수리 — 원칙 9 차트 의무 · 비전공자 3장치)
suppressPackageStartupMessages({library(jsonlite)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
Sys.setenv(QM_ROOT=QM)
source("02_Infrastructure/telegram/telegram_notify.R")
OUT <- "stage_artifacts/WT_D20260715_016"
cA <- file.path(QM, OUT, "r47_chart_integrity.png")

sections <- list(
  list(type="summary", emoji="📌",
    body="R46 감지기가 찾은 218개 종가 구멍(비-유니버스)을 KRX 시세로 채워 근원수리. 추가만·기존 무변경·유니버스/현 북 성과 불변."),
  list(type="bullet", emoji="📖", heading="쉬운 설명",
    items=c(
      "구멍이란: 이 218종목은 5·6월 데이터원(QuantiWise) 미수출 종목이라 종가가 통째로 빠짐(4월 이음매 잔재).",
      "한 일 = KRX 공식 일별시세로 빠진 종가만 채움(8,856행·216종목). 기존 데이터는 손 안 댐(추가만).",
      "★4월 사고 방어: 그때는 통째 재빌드가 실데이터 삭제. 이번은 빈 칸만 추가+유니버스 행수 불변 가드.",
      "핵심 확인: 채운 뒤 재계산 수익률=저장 수익률이 216/216 일치 → 구멍만 메우면 이음매 자동 정합.",
      "정지-재개 2종목(3주 정지 후 급등)은 하루 수익률 물리불가(+855%) → 종가 유지·수익률만 정직 빈칸.",
      "못 채운 2종목 = 128~172원 초저가주가 실제 미거래 → KRX에도 시세 없음(없는 걸 지어내지 않음).")),
  list(type="kv", emoji="📊", heading="검증 수치 (가드 5종 + parity 4종 전부 통과)",
    kv=list(
      "채운 규모"="8,856행 · 216종목 · 41거래일 (KRX 캐시 56일 + live 8일)",
      "종가 구멍(source-seam)"="218 → 2 (잔여 = 초저가 미거래 2종목)",
      "행수 가드"="14,009,624 + 8,856 = 14,018,480 (정확·삭제 0)",
      "유니버스 행 보호"="2,370,544 → 2,370,544 불변 (채운 건 전량 비-유니버스)",
      "기존 데이터 무변경"="max|Δ종가|=0 · max|Δ수익률|=0 (14,009,624행)",
      "이음매 정합(07-02)"="216/216 재계산==저장 일치",
      "현 북 14보유"="71,125행 불변 · max|Δ|=0",
      "변경 범위"="rawdata만(추가) · book_state/production/factor_db 무변경")),
  list(type="bullet", emoji="🚩", heading="판정 (평문)",
    items=c(
      "판정: 능력확립 — 218 종가 구멍을 KRX 백필로 근원수리, recompute==stored parity 회복.",
      "안전: append-only(추가만) + 유니버스 행 불변 가드 + 행수 정확 가드 = 4월사고(재빌드 삭제) 기계적 재발차단.",
      "라이브 무영향: 채운 건 전량 비-유니버스 microcap → 유니버스·현 북·factor_db 실측 불변(factor_db 재빌드 불요).",
      "밤샘 무결성 라인 R42(적발)→R43(census)→R44(방화벽)→R45(근원)→R46(감지기)→R47(KRX 백필 근원수리) 완결.")),
  list(type="bullet", emoji="➡️", heading="다음 (next_probe)",
    items=c(
      "P1: 잔여 2 penny 대체소스(Naver 일별/월간) 또는 상장상태(실질 거래정지) 재확인.",
      "P2: 종가 구멍 감지기를 리빌드 pre-hook 게이트로 승격(유니버스內 구멍 시 hard-block).",
      "P3: 다음 QuantiWise 재수출이 이 218종목 5·6월을 수정주가로 자동 승격하는지 검증.")))

tg_agent_brief(
  agent = "Q-Lead",
  title = "WT-D20260715_016 R47 — 4월 이음매 microcap 종가 구멍 KRX 백필 근원수리: 218 seam→2·recompute==stored parity 회복·유니버스/북 무변경 (append-only·위생·자본 아님)",
  sections = sections,
  charts = c(cA),
  as_of = "2026-07-17")
cat("[telegram] R47 sent with 1 chart\n")
