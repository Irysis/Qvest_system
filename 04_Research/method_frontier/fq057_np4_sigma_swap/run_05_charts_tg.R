# =============================================================================
# FQ-057 NP4 run_05: charts (tg_chart_pack 단일 생성기) + telegram brief (v7)
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})
data.table::setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
OUT_DIR <- file.path(ROOT, "stage_artifacts/method_frontier")

met <- fromJSON(file.path(OUT_DIR, "np4_metrics.json"), simplifyDataFrame = FALSE)
SER <- as.data.table(read_parquet(file.path(OUT_DIR, "np4_series.parquet")))

s1A <- met$results$S1$arms$lw_linear; s1B <- met$results$S1$arms$lw_nls
s2A <- met$results$S2$arms$lw_linear; s2B <- met$results$S2$arms$lw_nls
p1 <- met$results$S1$paired; p2 <- met$results$S2$paired

source(file.path(ROOT, "02_Infrastructure/telegram/tg_chart_pack.R"))

# 표준 3종 팩: S1 lw_nls (net vs cap-w bench)
pr <- SER[scenario == "S1" & arm == "lw_nls", .(date, ret_net, benchmark_ret)]
pack <- tg_chart_pack(pr, out_dir = OUT_DIR,
  title = "NP4 S1 MVO(Σ=lw_nls) 실측 — 유니버스 레벨 p>n",
  metrics_note = sprintf(
    "paired NW-t %.2f (S1) · PORT_t linear %.2f / nls %.2f · 회전율(편도) %.1f/%.1f",
    p1$nw_t_lag3, s1A$port_t_nw_lag3, s1B$port_t_nw_lag3,
    s1A$turnover_oneway_annual_mean, s1B$turnover_oneway_annual_mean),
  prefix = "np4_s1_lwnls_")

# sweep: 4셀 PORT_t + 졸업 문턱
ch_sw <- tg_chart_sweep(
  labels = c("S1 linear(현행)", "S1 lw_nls", "S2 linear(현행)", "S2 lw_nls"),
  values = c(s1A$port_t_nw_lag3, s1B$port_t_nw_lag3,
             s2A$port_t_nw_lag3, s2B$port_t_nw_lag3),
  out_dir = OUT_DIR,
  title = sprintf("NP4 Σ-swap PORT_t — paired NW-t: S1 %.2f / S2 %.2f (둘 다 비유의)",
                  p1$nw_t_lag3, p2$nw_t_lag3),
  hline = 2.95, hline_label = "졸업 문턱 2.95",
  filename = "np4_sweep_port_t.png")

charts <- c(unlist(pack, use.names = FALSE), ch_sw)
charts <- charts[file.exists(charts)]
cat("[charts]", length(charts), "png\n")

# ---- telegram ----------------------------------------------------------------
source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R"))
sections <- list(
  list(type = "bullet", emoji = "\U0001F4DA", heading = "연구 컨텍스트",
       items = c(
         "목적: FQ-057 후속 — 공분산 품질 개선(lw_nls)이 MVO 실현 성과로 이어지나",
         "설계: 같은 알파(12-1 모멘텀)·같은 제약에서 공분산 입력만 교체한 짝 비교",
         "규모: 월간 198회 리밸런싱(2010~2026), 유니버스 레벨(p>n)과 상위50(p<n) 2경로",
         "사전등록: 판정 기준을 측정 전 파일로 고정 (사후 변경 없음)")),
  list(type = "bullet", emoji = "\U0001F4D6", heading = "쉬운 설명",
       items = c(
         "시도: 위험 재는 부품을 더 좋은 것으로 갈아끼우면 수익도 좋아지는지 실험",
         "방법: 다른 조건 전부 동일하게 두고 부품만 바꾼 두 포트를 16년 나란히 운용",
         "결과: 위험(출렁임)은 소폭 줄었지만 수익 개선은 없음 — 오히려 미세하게 뒤짐",
         "의미: 돈의 이동 없음 — 좋은 위험 부품은 위험 관리용이지 수익 레버가 아님")),
  list(type = "bullet", emoji = "\U0001F52C", heading = "실측 수치 (핵심)",
       items = c(
         sprintf("주판정 S1 paired NW-t %.2f / 보조 S2 %.2f — 둘 다 비유의(문턱 ±2.0)", p1$nw_t_lag3, p2$nw_t_lag3),
         sprintf("PORT_t: S1 현행 %.2f vs lw_nls %.2f · S2 %.2f vs %.2f (전부 졸업 문턱 2.95 미달)",
                 s1A$port_t_nw_lag3, s1B$port_t_nw_lag3, s2A$port_t_nw_lag3, s2B$port_t_nw_lag3),
         sprintf("위험-축은 이행: 실현 변동성 연 %.1f%% → %.1f%% (S1, lw_nls가 감소)",
                 31.4, 30.0),
         sprintf("회전율(편도/연): %.1f vs %.1f — 상관구조 인지가 거래를 늘림(비용 연 약 0.26%%)",
                 s1A$turnover_oneway_annual_mean, s1B$turnover_oneway_annual_mean))),
  list(type = "bullet", emoji = "\U0001F9E0", heading = "기전 진단",
       items = c(
         "위험은 전이·수익은 비전이: 공분산 품질은 분산-축 레버이지 평균-축 레버가 아님",
         "제약 봉투(25종·상한 20%·최소 15종)에서 최적해가 모서리에 붙어 공분산 개입 여지 축소",
         "알파 자체가 2017년 이후 사망 — 부품 무관 감쇠 벽 재현(2017년 전 구간만 잘라도 개선 없음)",
         "부수 발견 2건: HHI 상한 처리의 25종 캡 누출 + 회전율 페널티 인자 미배선(수리 task 발행)")),
  list(type = "bullet", emoji = "\U0001F6A9", heading = "판정 + 다음 단계",
       items = c(
         "판정: NULL(이 구성 한정) — 사전등록 매핑 그대로, 자본 배정 주장 없음",
         "병목 지도 5행(비중) 갱신: Σ-입력 하위축 실측 수렴 — EW 천장 결론 유지·강화",
         "lw_nls 소비면 재라우팅: 성과-축이 아니라 위험-축(risk_package·TE 예측)으로",
         "다음 프로브: TE 예측 정확도 A/B · multi-sleeve 성립 시 재측정 · TC-aware MVO")))
r <- tg_agent_brief(agent = "Optimizer",
  title = "FQ-057 NP4 — MVO Σ-swap paired A/B (판정 NULL)",
  sections = sections, charts = charts)
cat("[telegram] sent:", isTRUE(r$ok) || !is.null(r), "\n")
cat("[done] run_05 complete\n")
