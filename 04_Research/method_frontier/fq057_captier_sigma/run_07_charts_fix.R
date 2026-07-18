# FQ-057 run_07: chart filename collision fix (3 charts had overwritten each
# other into one sweep_compare.png before send) — regenerate with distinct
# filenames + compact corrective follow-up brief.
suppressPackageStartupMessages({library(data.table); library(jsonlite)})
data.table::setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
OUT_DIR <- file.path(ROOT, "stage_artifacts/method_frontier")
ab  <- fromJSON(file.path(OUT_DIR, "fq057_ab_summary.json"))
ctd <- fromJSON(file.path(OUT_DIR, "fq057_cap_tier_decomposition.json"),
                simplifyDataFrame = FALSE)
summ <- as.data.table(ab$summary)
ord <- c("lw_nls", "lw_linear", "sample", "block_lw", "block_nls")
s2 <- summ[match(ord, est)]
source(file.path(ROOT, "02_Infrastructure/telegram/tg_chart_pack.R"))
ch1 <- tg_chart_sweep(labels = ord, values = round(s2$mvp_oos_vol_ann, 3),
  out_dir = OUT_DIR, title = "FQ-057 최소분산 포트 OOS 실현변동성 (연율, 낮을수록 우수)",
  highlight = "lw_nls", filename = "fq057_sweep_mvp_vol.png")
ch2 <- tg_chart_sweep(labels = ord, values = round(s2$cor_rmse_fwd12_mean, 4),
  out_dir = OUT_DIR, title = "FQ-057 상관구조 예측오차 RMSE (fwd-12m, 낮을수록 우수)",
  highlight = "block_nls", filename = "fq057_sweep_cor_rmse.png")
tiers_dt <- rbindlist(lapply(ctd$tiers, function(x)
  data.table(tier = x$tier, capw = x$active_risk_share, ew = x$active_risk_share_ew_basis)))
ch3 <- tg_chart_sweep(
  labels = c(paste0(tiers_dt$tier, " (cap-w)"), paste0(tiers_dt$tier, " (EW-uni)")),
  values = round(c(tiers_dt$capw, tiers_dt$ew), 3),
  out_dir = OUT_DIR, title = "FQ-057 현 북 능동위험 tier 분해 — 기준별 역전 (dual-basis)",
  filename = "fq057_sweep_dualbasis.png")
file.remove(file.path(OUT_DIR, "sweep_compare.png"))
source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R"))
sections <- list(
  list(type = "bullet", emoji = "\U0001F4DA", heading = "연구 컨텍스트 (차트 정정)",
       items = c(
         "직전 FQ-057 보고의 차트 3장이 파일명 충돌로 동일 이미지로 발송됨",
         "정정: 추정기 비교 2종 + dual-basis 위험분해 1종을 각각 재첨부",
         "수치·판정 변경 없음 — 시각 자료만 정정")),
  list(type = "bullet", emoji = "\U0001F4D6", heading = "쉬운 설명",
       items = c(
         "1장: 공분산 추정기 5종의 다음 달 변동성 적중 비교 (낮을수록 우수)",
         "2장: 종목 간 상관구조 예측오차 비교 (블록형이 근소 1위)",
         "3장: 같은 포트의 위험 축이 잣대(시총가중/동일가중)에 따라 정반대")))
r <- tg_agent_brief(agent = "Risk",
  title = "FQ-057 차트 정정 — 추정품질 A/B + dual-basis 분해 3종",
  sections = sections, charts = c(ch1, ch2, ch3))
cat("[telegram] sent:", isTRUE(r$ok) || !is.null(r), "\n")
