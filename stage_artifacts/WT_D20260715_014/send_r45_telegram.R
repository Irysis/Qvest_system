## R45 텔레그램 v7 보고 (무결성 근원진단 — 원칙 9 차트 의무 · 비전공자 3장치)
suppressPackageStartupMessages({library(jsonlite)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
Sys.setenv(QM_ROOT=QM)
source("02_Infrastructure/telegram/telegram_notify.R")
OUT <- "stage_artifacts/WT_D20260715_014"
cA <- file.path(QM, OUT, "chartA_r45_diagnosis.png")

sections <- list(
  list(type="summary", emoji="📌",
    body="저장Ret vs 재계산 불일치 근원=종가 시계열 구멍(4월사고 잔여). 저장 Ret이 참값·196건 전부 비-유니버스·라이브 무영향."),
  list(type="bullet", emoji="📖", heading="쉬운 설명",
    items=c(
      "배경(R44): '저장된 하루수익률'과 '종가로 재계산한 수익률'이 최대 486% 어긋남.",
      "의문: 저장값이 오염됐나? 그 값 쓰는 팩터DB도 오염?",
      "진단: 저장값이 '참값', '재계산'이 틀림.",
      "이유: 일부 종목 종가에 '구멍'(빠진 거래일) → 전일종가가 실제론 64일 전 값.",
      "재계산이 그 긴 공백을 하루 수익으로 착각(구멍을 뛰어넘음).",
      "예: A004415 4/29(1193원)→7/2(7030원), 사이 2개월 결측. 저장=+2.9%, 재계산=+489%.",
      "이 구멍은 4월 데이터사고의 비-투자대상 종목 잔여물(유니버스는 복구됨).")),
  list(type="kv", emoji="📊", heading="진단 수치 (전수 census 14,004,246행)",
    kv=list(
      "불일치 |Δ|>0.01"="196 종목-일 (전체의 0.0014%) · 최대 4.86",
      "투자 유니버스內 불일치"="0 건 (전부 비-유니버스 우선주·소형주)",
      "중복(종목,날짜) 키"="0 (중복일 원인 반증)",
      "방향판정: 저장 Ret 물리타당"="196/196 = 100% (|Ret|≤31% 제한내)",
      "방향판정: 재계산 물리타당"="157/196 = 80.1% (20%는 ±30% 위반=스퓨리어스)",
      "현 북 14보유 데이터 구멍"="0 (max 갭 4일=주말만) · 유니버스 348종목 구멍 0",
      "팩터DB 오염 여부"="없음 — 팩터DB는 저장 Ret(참값) 소비, 재계산 안 함")),
  list(type="bullet", emoji="🚩", heading="판정 · 근원 (평문)",
    items=c(
      "판정: 능력확립 — 근원 규명(Close 시계열 구멍)+라이브·팩터DB 무영향 확정.",
      "근원: 재계산이 종가 구멍을 뛰어넘은 artifact. 저장 Ret이 참값(KRX 원천).",
      "★R44 프레이밍 반전: '저장 Ret 오염'은 반대 — 저장이 옳고 재계산이 틀림.",
      "★라이브 factor 영향 ZERO: 현 북 7팩터 유니버스필터→196 종목 0 선택.",
      "팩터DB(prod(1+Ret))는 저장 Ret 참값 소비=무오염, canonical은 유니버스로 보호.",
      "2 cluster: 161건@4/29(64일 구멍=4월사고 잔여)+35건@7/2(5일 구멍).")),
  list(type="bullet", emoji="➡️", heading="다음 (next_probe · 수리 경로)",
    items=c(
      "P1: 196 비-유니버스 종가 구멍 KRX 백필로 메움→parity 회복(R2/R3와 동시).",
      "P2: Close 연속성 tripwire 배선(갭>20일 구멍 감지)—Ret firewall과 상보.",
      "P3: firewall 정교화—갭 케이스에서 저장 Ret 참값 보존(재계산만 폐기).")))

tg_agent_brief(
  agent = "Q-Lead",
  title = "WT-D20260715_014 R45 — stored-Ret vs 재계산 불일치 근원 진단: Close 시계열 구멍(April-gap 잔여)·저장 Ret 참값·라이브/factor_db 무영향 (위생·자본 아님)",
  sections = sections,
  charts = c(cA),
  as_of = "2026-07-15")
cat("[telegram] R45 sent with 1 chart\n")
