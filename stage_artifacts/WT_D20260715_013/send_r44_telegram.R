## R44 텔레그램 v7 보고 (무결성 수리 — 원칙 9 차트 의무 · 비전공자 3장치)
suppressPackageStartupMessages({library(jsonlite)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/telegram/telegram_notify.R")
OUT <- "stage_artifacts/WT_D20260715_013"
cA <- file.path(QM, OUT, "chartA_isolation_breakdown.png")
cB <- file.path(QM, OUT, "chartB_regression_parity.png")

sections <- list(
  list(type="summary", emoji="📌",
    body="'물리적으로 불가능한 수익률'이 백테스트 입력단을 무방비로 통과하던 구조 취약을 방화벽으로 수리 — 오염만 제거하고 정당 데이터·현 운용 북은 전부 불변(자본 무영향·위생 배선)."),
  list(type="bullet", emoji="📖", heading="쉬운 설명",
    items=c(
      "배경(R43): 원천데이터에 하루 수익률 +6,699,900%(전일종가 1원 오류) 등 물리불가 값 발견.",
      "이를 걸러낼 장치가 파이프라인 어디에도 없었음(구조 취약).",
      "한국 주식 하루 변동은 ±30% 제한 → |수익률|>31%=제한위반, >100%=물리 불가능.",
      "이번 작업: 오염값이 백테스트 입력으로 흘러들지 못하게 방화벽 함수 배선.",
      "①확실 오염(>100%·전일가 0원류·상폐 날짜갭)은 자동 격리(삭제).",
      "②애매한 분할/증자류(31~100%)는 값 유지+격리리스트만(교정은 별도 재구축).",
      "핵심: 방화벽은 오염만 제거 — 정당 대형주 급등·제한폭(30%) 이동은 불변.")),
  list(type="kv", emoji="📊", heading="검증 수치 (회귀 4-test 전부 PASS · known-case parity)",
    kv=list(
      "격리 총계 (14M행 중)"="HARD 672행(자동삭제) · SUSPECT 2,121행(값유지·리스트)",
      "HARD 원인 분해"="물리불가 257 · 0원제수 373 · 날짜갭 42",
      "투자유니버스內 격리"="17행 = R43 census와 17/17 정확 일치 (1 삭제 + 16 리스트)",
      "① 현 북 14보유 격리"="0 행 (오염 ZERO 재확인 = 라이브 무영향)",
      "② 유니버스 월패널 前/後"="max|Δ 월수익|=0.00 · 상이 0행 (정당 데이터 불변)",
      "③ 입력 가드 clean 실행"="경고 0회 · PORT_t 불변 (정상 데이터엔 무해)",
      "④ monster(+67000) 주입"="가드 1회 발화·격리 → finite·clean과 bit-일치")),
  list(type="bullet", emoji="🚩", heading="판정 · 주의 (평문)",
    items=c(
      "판정: 능력확립 — canonical 입력단 Ret 방화벽 배선·회귀 parity 전부 PASS.",
      "★자본 아님·위생: rawdata/book/05_Production 무변경(함수만)·현 북 무영향.",
      "방화벽=오염 '제거'이지 '수정' 아님 — 분할류(루닛·코미코·LS ELECTRIC)는 표시만.",
      "실제 back-adjust는 별도 KRX 백필 리빌드(R2/R3) 소관.",
      "한계①: 가격제한 시변(2015-06 이전 ±15%) — 현재 0.31 균일(pre-2015 일부 미회수).",
      "한계②: stored-Ret vs 재계산 Δ 최대 4.86(non-universe microcap) — 별개 프로브.")),
  list(type="bullet", emoji="➡️", heading="다음 (next_probe)",
    items=c(
      "P1: 다음 리빌드 시 방화벽 실적용 관측(n_isolated+factor_db 월수익 대조, R2/R3 동시).",
      "P2: 가격제한 시변 정교화(pre-2015 ±15% → SUSPECT 경계 0.16).",
      "P3: stored-Ret vs recompute Δ=4.86 근원 진단.")))

tg_agent_brief(
  agent = "Q-Lead",
  title = "WT-D20260715_013 R44 — Ret sanity 방화벽 배선(canonical 입력단 이중가드)·회귀 parity 전부 PASS (위생·자본 아님)",
  sections = sections,
  charts = c(cA, cB),
  as_of = "2026-07-15")
cat("[telegram] R44 sent with 2 charts\n")
