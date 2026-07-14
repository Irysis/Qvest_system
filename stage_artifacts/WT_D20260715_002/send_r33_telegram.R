## R33 텔레그램 v7 판정 보고 (원칙 9 — 차트 첨부 의무)
suppressPackageStartupMessages({library(jsonlite)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/telegram/tg_chart_pack.R")
source("02_Infrastructure/telegram/telegram_notify.R")
OUT <- "stage_artifacts/WT_D20260715_002"
res <- fromJSON(file.path(OUT,"r33_results.json"))
sn  <- fromJSON(file.path(OUT,"r33_sizeneutral.json"))

## 차트 1 — 배제 필터 (Branch A) paired + 절대 PORT_t
c1 <- tg_chart_sweep(
  labels = c("base cap-w PORT_t", "filtered cap-w PORT_t", "paired NW-t (filtered-base)"),
  values = c(res$parity$base_capw_port_t, res$branchA$filt_capw_port_t, res$branchA$paired_nw_t),
  out_dir = OUT, title = "갈래A 임원 순매도 배제 필터 — 무기여 (paired ~ 0)",
  value_label = "t / PORT_t", hline = 2.0, hline_label = "paired KILL",
  filename = "chart_A_exclusion.png")

## 차트 2 — 클러스터 경보 신호력 (Branch B) forward gap-t
nb <- res$branchB$net_buy_cluster; ns <- res$branchB$net_sell_extreme
large_t <- as.numeric(sn$tercile$gap_t[sn$tercile$sz_tercile=="large"])
c2 <- tg_chart_sweep(
  labels = c("net-buy gap-t (raw)", "net-buy gap-t (size통제)", "net-buy large-cap tier t", "net-sell tripwire gap-t"),
  values = c(nb$gap_ret_t, sn$size_resid_gap_t, large_t, ns$gap_ret_t),
  out_dir = OUT, title = "갈래B monitoring 신호력 — net-buy 生 / net-sell 死",
  value_label = "forward NW-t", hline = 2.0, hline_label = "유의",
  filename = "chart_B_monitoring.png")

## 차트 3 — dual-basis (size tercile) net-buy 클러스터 gap-t
terc <- sn$tercile
c3 <- tg_chart_sweep(
  labels = paste0(terc$sz_tercile, " tier"),
  values = terc$gap_t,
  out_dir = OUT, title = "갈래B dual-basis(size tercile) — 배포 large tier도 生",
  value_label = "forward gap NW-t", hline = 2.0, hline_label = "유의",
  highlight = "large tier",
  filename = "chart_C_dualbasis.png")

sections <- list(
  list(type="summary", emoji="📌",
    body="insider 소비면 전환: 선별/필터 3면 무기여이나 임원 순매수 클러스터는 monitoring 신호 확립 — tripwire 배선 후보."),
  list(type="bullet", emoji="📖", heading="쉬운 설명",
    items=c(
      "R9: 임원거래로 '종목 고르기'는 도움 안 됨(기존 팩터와 중복).",
      "R33: 자리를 바꿈 — ①대량 순매도 종목 제외(필터) ②순매수 몰린 종목 위험감시.",
      "①필터는 성과·낙폭 개선 못 함.",
      "②임원이 꾸준히 사 모은 종목은 다음달 수익 높고 낙폭·변동성·급락 적음.",
      "이 효과는 소형주 착시 아님 — 크기 통제 후 강해지고 대형주도 유의.",
      "즉 종목선별엔 벽, '상대적 안전' 감시신호론 살아있음.")),
  list(type="kv", emoji="📊", heading="핵심 수치 (net-of-cost 15bps, NW lag-3)",
    kv=list(
      "갈래A 배제 paired(필터-기존)"=sprintf("t=%.2f (연 %+.2f%%p) — 무기여", res$branchA$paired_nw_t, res$branchA$paired_delta_ann*100),
      "갈래A 최대낙폭(기존/필터)"=sprintf("%.1f%% / %.1f%% (불개선)", res$branchA$risk$base_mdd*100, res$branchA$risk$filt_mdd*100),
      "갈래B 순매수 익월 수익차"=sprintf("연 %+.1f%% · 다중검정 t=%.2f", nb$gap_ret_ann*100, nb$gap_ret_t),
      "갈래B 순매수 크기통제후"=sprintf("연 %+.1f%% · t=%.2f (강화)", sn$size_resid_gap_ann*100, sn$size_resid_gap_t),
      "갈래B 순매수 대형주 분위"=sprintf("t=%.2f (배포-관련 유의)", large_t),
      "갈래B 순매수 위험감소"=sprintf("하방 %.1f→%.1f%% · 급락빈도 %.1f→%.1f%%", nb$downside_nonflag*100, nb$downside_flag*100, nb$tail_hit_nonflag*100, nb$tail_hit_flag*100),
      "갈래B 순매도 경보"=sprintf("t=%.2f — 무효", ns$gap_ret_t))),
  list(type="bullet", emoji="🚩", heading="판정 · 주의 (평문)",
    items=c(
      "판정: capability_established(monitoring net-buy) — 자본 아님.",
      "선별/필터 3면(R9 pool·A 배제·B 순매도)은 config-scoped negative.",
      "base=production clean T-1(§7b, parity 검증) — 동월 vintage 패널 미사용.",
      "절대 PORT_t는 재구성 벤치 기준 — paired/gap는 벤치 canceling이라 불변.",
      "잔여 confound: 섹터/지배구조 편중 미격리(크기 통제는 통과).")),
  list(type="bullet", emoji="➡️", heading="다음 (next_probe)",
    items=c(
      "net-buy 클러스터를 PG2 book overlay/de-risk 예외 신호로 배선 측정(tripwire 실효, 자본 아님)",
      "coverage 확장(126m→) + 대형주 tier 안정성 재검정",
      "sector-neutral 검정으로 잔여 confound 격리"))
)

tg_agent_brief(
  agent = "Alpha",
  title = "WT-D20260715_002 R33 insider 소비면 전환 — monitoring(net-buy) capability / 선별·필터 3면 negative",
  sections = sections,
  charts = c(c1, c2, c3),
  as_of = "2026-07-15")
cat("[telegram] sent with 3 charts\n")
