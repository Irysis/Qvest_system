## R46 텔레그램 v7 보고 (무결성 라인 완결 — 원칙 9 차트 의무 · 비전공자 3장치)
suppressPackageStartupMessages({library(jsonlite)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
Sys.setenv(QM_ROOT=QM)
source("02_Infrastructure/telegram/telegram_notify.R")
OUT <- "stage_artifacts/WT_D20260715_015"
cA <- file.path(QM, OUT, "chart_r46_integrity.png")

sections <- list(
  list(type="summary", emoji="📌",
    body="R45 근원 지식을 방화벽(참값 보존 39건)·구멍 감지기로 배선. 북·유니버스 성과 불변(6-test parity)·무결성 라인 완결."),
  list(type="bullet", emoji="📖", heading="쉬운 설명",
    items=c(
      "배경(R45): 종가 '구멍'(빠진 거래일)이면 재계산 수익률이 헛값(예 +489%). 저장 수익률이 참값.",
      "R46에 한 일 = 이 지식을 코드에 심음(2가지).",
      "① 방화벽: 구멍 케이스에서 참값(저장 수익률)이 정상이면 살려둠(예전엔 통째 버림). 39건 복원.",
      "② 감지기: 재빌드 前에 종가 구멍(20일 초과)을 미리 찾아 경보(4월사고류 재발 사전차단).",
      "가장 중요: 바꿔도 현 보유 14종목·유니버스 성과 소수점까지 그대로(안전).",
      "예: A004415 7/2 = 재계산 +489%(구멍 착시) → 저장 +2.93%(참값)로 보존.")),
  list(type="kv", emoji="📊", heading="검증 수치 (6-test parity 전부 통과)",
    kv=list(
      "방화벽 분류 변화"="HARD(폐기) 672→633 · RESTORE(참값 보존·신규) +39",
      "유니버스內 분류 불변"="17건 그대로(1 물리불가+16 분할의심)·참값복원 0",
      "현 북 14보유 격리"="0 건 (구멍 없음 재확인)",
      "유니버스 월수익 패널 前/後"="max|Δ|=0 (복원 39건 전부 비-유니버스)",
      "R45 196 구멍 케이스"="RESTORE 39(복원)·미발화 157(소폭·기존동일)",
      "구멍 감지기(현 데이터)"="245 구멍·유니버스內 활성 0→게이트 CLEAN",
      "변경 범위"="rawdata·북·production·factor_db 무변경(함수 배선만)")),
  list(type="bullet", emoji="🚩", heading="판정 (평문)",
    items=c(
      "판정: 능력확립 — R45 근원 지식을 방화벽(참값 보존)·감지기로 제도화.",
      "설계 핵심: 구멍이면 재계산이 물리불가 크기여도 구멍 지문 → 저장 참값 우선 보존(초기설계 정정).",
      "방화벽=사후 헛값 격리, 감지기=사전 구멍 포착 → 상보.",
      "라이브 무영향: 복원 39건 전부 비-유니버스 → 북·유니버스 성과 불변.",
      "무결성 라인 R42→R43→R44→R45→R46 배선 완결.")),
  list(type="bullet", emoji="➡️", heading="다음 (next_probe · 근본수리는 별도)",
    items=c(
      "P1(별도 리빌드·armed): 245 활성 종가 구멍(비-유니버스 4/7월 이음매) KRX 백필→parity 회복.",
      "P2(선택): 구멍 감지기를 재빌드 pre-hook 게이트로 승격(유니버스內 구멍 시 hard-block).",
      "P3(선택): pre-2015 가격제한(±15%) 시변 임계 검토.")))

tg_agent_brief(
  agent = "Q-Lead",
  title = "WT-D20260715_015 R46 — 방화벽 date-gap 정교화(참값 보존)+종가 연속성 감지기 배선: R45 근원 지식 제도화·6-test parity 불변·무결성 라인 완결 (위생·자본 아님)",
  sections = sections,
  charts = c(cA),
  as_of = "2026-07-15")
cat("[telegram] R46 sent with 1 chart\n")
