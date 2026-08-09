#!/usr/bin/env Rscript
# p4b_close.R — NP-2 결과 FQ 반영 + 텔레그램
suppressPackageStartupMessages({ library(jsonlite) })
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ); OUT <- file.path(PROJ, "stage_artifacts/scrap_ensemble_20260809")

source(file.path(PROJ, "02_Infrastructure/ops/frontier_queue_io.R"))
Q <- read_frontier_queue()
ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))
i <- which(ids == "FQ-174"); stopifnot(length(i) == 1)
Q$entries[[i]]$np2_result_20260809 <- paste0(
  "NP-2 실측 완료(p4_np2_beta_weighting, 사전등록 = 스크립트 헤더): ★라운드 첫 MDD 유의 양성. ",
  "층 구분 정정 — 이산 멤버십에는 MDD 레버가 없으나 **연속 비중 층에는 있다**. ",
  "통합 풀 99, trailing-36m beta(t-1) 연속 가중 4 arm: inverse-beta² 가 MDD 38.3%→**29.4%**(−8.9%p, ",
  "사전등록 유의 바 4.49%p 의 2배)·SR 0.714→0.840·Calmar 0.288→0.347·포트 beta 0.604→0.439. ",
  "연속>이산 기전 확인: 전 arm 이 저beta-20 **선택**(Calmar 0.192)을 압도 — breadth 보존이 결정적. ",
  "⚠정직 한정 3: (a) 절대 PORT_t +0.040 — 위험 형태만 개선, 벤치 대비 알파는 0. 자본 주장 아님 ",
  "(b) Calmar 0.347 << HARD 0.64 (c) 4 arm 중 최선 선택 = sweep 성격, 단 유의 바는 사전등록이고 2배 초과. ",
  "FQ-058(주식-레벨 분산-최적화 weighting negative·EW 지배)과 config 상이 — 모듈-레벨 beta 산포(0.34~0.96)",
  "+지속성(rho 0.564)이 재료라는 점이 차별점(Distilled 정련이지 모순 아님). ",
  "소비처: FR Track2 dispatcher 비중 계열(inverse-vol RP 앵커의 형제) — 알파 있는 풀(FR_001 계열)에 ",
  "이식해 위험 형태 개선분이 실질 기여로 전이되는지가 다음 관문."
)
Q$entries[[i]]$next_action <- paste0(
  "[NP-2b 최우선] inverse-beta² 비중을 **알파 있는 풀**(FR_001 우량 12 또는 RCMA admitted)에 이식 A/B — ",
  "폐지 풀에서는 위험 형태만 개선됐으나(PORT_t 0.04) 알파 풀에서는 Calmar/DSR 실질 기여 가능성. ",
  "사전등록: arm 고정(EW/inv-vol/inv-beta/inv-beta²), MDD 유의 바 재산출, FR_001 대비 paired. ",
  "[NP-3] 재료 교체 — 비-수익 원천 모듈 유입 시 천장 재산정. ",
  "[라벨 축] 사전 관측 가능 국면 라벨 교체(상태-조건부 lane 유일 관문). ",
  "[처분 완료] NP-1 수익 위생(광역 풀 한정 capability) · 멤버십 선택 계열(천장 기각) · 축소추정/ML(철회)."
)
res <- write_frontier_queue(Q)
cat("[fq174-np2] n=", res$n, "\n", sep="")

source(file.path(PROJ, "02_Infrastructure/telegram/tg_chart_pack.R"))
CH <- file.path(OUT, "charts")
p1 <- tg_chart_sweep(
  labels = c("동일가중 (기준)", "변동성 반비례", "민감도 반비례", "민감도 상한 혼합", "민감도 반비례 제곱"),
  values = c(38.3, 36.2, 34.8, 37.5, 29.4),
  out_dir = CH, title = "최대낙폭 비교 — 연속 비중 틸트가 처음으로 유의하게 깎았다",
  value_label = "최대낙폭 (%, 낮을수록 좋음)", hline = 33.8, hline_label = "유의 개선선 33.8%",
  highlight = "민감도 반비례 제곱", filename = "np2_mdd.png")
p2 <- tg_chart_sweep(
  labels = c("저민감도 20개 선택(이산)", "동일가중 기준", "민감도 반비례 제곱(연속)"),
  values = c(0.192, 0.288, 0.347),
  out_dir = CH, title = "같은 재료, 이산 대 연속 — 폭을 지키며 기울이면 다르다",
  value_label = "칼마 (연수익/최대낙폭)", hline = 0.64, hline_label = "자본 합격선 0.64",
  highlight = "민감도 반비례 제곱(연속)", filename = "np2_calmar.png")
source(file.path(PROJ, "02_Infrastructure/telegram/telegram_notify.R"))
tg_agent_brief(
  agent = "Q-Lead",
  title = "낙폭 축 첫 유의 개선 — 고르지 말고 기울여라 (연속 비중 틸트)",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "시장 민감도에 반비례해 비중을 주니 최대낙폭이 38.3%에서 29.4%로 처음 유의하게 줄었습니다."),
    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "발상: 위험한 전략을 빼는 대신 전부 들고 비중만 민감도 반비례로 기울였습니다",
           "결과: 최대낙폭 -8.9%p — 유의 기준 4.49%p 의 두 배를 넘었습니다",
           "비교: 위험한 것을 아예 빼는 방식은 수익까지 죽었는데 이 방식은 다릅니다",
           "이유: 종목 폭을 유지한 채 기울이면 분산 효과를 잃지 않기 때문입니다",
           "한계: 시장 대비 초과수익은 없습니다 — 위험 모양만 좋아진 것입니다")),
    list(type = "kv", emoji = "📊", heading = "핵심 수치",
         kv = list(
           "최대낙폭" = "38.3% → 29.4% (-8.9%p, 유의 바 4.49%p)",
           "샤프지수" = "0.714 → 0.840",
           "칼마"     = "0.288 → 0.347 (합격선 0.64 미달)",
           "이산대비" = "선택 방식 칼마 0.192 를 전 배분안이 압도",
           "민감도"   = "포트 전체 0.604 → 0.439")),
    list(type = "bullet", emoji = "🚩", heading = "주의",
         items = c(
           "시장 대비 초과수익 t값 0.04 — 자본 자격과 무관한 위험 형태 개선입니다",
           "4개 안 중 최선을 고른 것이라 선택 편의 소지 — 단 유의 바는 사전등록입니다",
           "칼마 합격선 0.64 에는 여전히 크게 못 미칩니다")),
    list(type = "bullet", emoji = "➡️", heading = "다음",
         items = c(
           "이 비중 방식을 초과수익 있는 우량 풀에 이식해 실질 기여를 검증합니다",
           "낙폭 레버 지도 갱신: 이산 선택엔 없고 연속 비중엔 있습니다",
           "판정: 자본 반영 없음 — 배분 계층 능력 확립으로만 기록합니다"))
  ),
  charts = c(p1, p2),
  footer = "📚 FQ-174 NP-2 · p4_np2_weighting.json · metric_type=diagnostic_precheck",
  force = TRUE)  # 한글 제목 scope 정규화 30분 잠금 — 별개 내용 후속 보고 명시 우회
cat("[tg] 발송 완료\n")
