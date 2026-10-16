## charter_gaps.R — 투자철학 헌장 빈칸 5곳을 도훈께 여쭙기 위한 실제 곡선 사례(보는 창 2005-02~2022-12 · 같은 엔진 DNN 원형)
##   철학 Superfan P1(R-20261016-001) '헌장의 빈칸' 1~5 → 도훈 교정 사례 요청(10-16 '나머지 2,3,4 실행' 의 4번).
##   수치 = R 계약 산출(보는 창 진단 패킷 behavior · exposure · profile · 측정 산출물 02_nav · 04_holdings)만 그린다. 시험 창(2023~) 미사용.
##   칸: P3R02_E2_RX0(기준 · 동일 비중) · P3R01_E2_K1(역변동성) · P3R01_E2_K2(최소분산 LW) · P3R02_E2_M5(정제 공분산 최소분산) · P3R01_E2_K3(낙폭 제약 CDaR LP)
##   ※P3R01 칸은 P3R02 RX0 와 다른 배치에서 쟀다(같은 사양 · 같은 엔진) — 그림은 사례 설명용(판정 아님).
## 실행: Rscript 04_Research/01_reports/charter_gaps_20261016/charter_gaps.R
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(ggplot2); library(scales); library(ragg); library(systemfonts); library(patchwork) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT <- file.path(ROOT, "04_Research/01_reports/charter_gaps_20261016")
TAU <- as.Date("2022-12-31")
fdir <- c(file.path(Sys.getenv("LOCALAPPDATA"), "Microsoft", "Windows", "Fonts"), file.path(Sys.getenv("WINDIR", "C:/Windows"), "Fonts"))
fM <- file.path(fdir, "현대하모니+M.ttf"); fM <- fM[file.exists(fM)][1]; if (is.na(fM)) stop("현대하모니 M 글꼴 없음")
systemfonts::register_font(name = "HDHM", plain = fM); FAM <- "HDHM"
th <- theme_minimal(base_family = FAM, base_size = 12) +
  theme(plot.title = element_text(size = 15, margin = margin(b = 4)), plot.subtitle = element_text(size = 10.5, colour = "#555555"),
        legend.position = "bottom", legend.title = element_blank(), panel.grid.minor = element_blank(), plot.caption = element_text(size = 8.5, colour = "#777777"))
CELLS <- data.table(code = c("P3R02_E2_RX0", "P3R01_E2_K1", "P3R01_E2_K2", "P3R02_E2_M5", "P3R01_E2_K3"),
                    rd = c("P3R02_eigen_markowitz", "P3R01_construction_map", "P3R01_construction_map", "P3R02_eigen_markowitz", "P3R01_construction_map"),
                    lab = c("기준(동일 비중)", "역변동성", "최소분산", "정제 공분산 최소분산", "낙폭 제약(CDaR)"))
CELLS[, lab := factor(lab, levels = lab)]
PAL <- setNames(c("#1f77b4", "#2ca02c", "#ff7f0e", "#d62728", "#9467bd"), levels(CELLS$lab))
pk <- function(code, rd) fromJSON(file.path(ROOT, "04_Research/programs/P3_CONSTRUCTION", rd, "results", code, "visible", "diagnosis_packet.json"), simplifyVector = FALSE)
art <- function(code, rd) fromJSON(file.path(ROOT, "04_Research/programs/P3_CONSTRUCTION", rd, "results", paste0(code, ".json")))$artifacts
P <- setNames(lapply(seq_len(nrow(CELLS)), function(i) pk(CELLS$code[i], CELLS$rd[i])), CELLS$code)
A <- setNames(lapply(seq_len(nrow(CELLS)), function(i) art(CELLS$code[i], CELLS$rd[i])), CELLS$code)
lab_of <- function(cd) CELLS$lab[match(cd, CELLS$code)]
crises <- function(code) rbindlist(lapply(P[[code]]$behavior$crises, function(c) data.table(peak = as.Date(c$peak_date), trough = as.Date(c$trough_date),
  bm_dd = as.numeric(c$bm_dd), dd_capture = as.numeric(c$dd_capture), st_dd = as.numeric(c$st_dd), rec = as.numeric(c$st_recovery_obs %||% NA))))
`%||%` <- function(a, b) if (is.null(a) || !length(a)) b else a
cap <- "보는 창 2005-02~2022-12 · 같은 엔진(DNN 원형) · 수치 = 보는 창 진단 패킷 · 측정 산출물(R 계약) · 위기 = KOSPI200 Lunde-Timmermann 20/20"
summ <- list()

## ── 1 집중의 문턱 — 유효 종목 수(리밸일) · 깊은 위기 한 종목 최악 기여 ─────────────────────────────
effn <- rbindlist(lapply(CELLS$code, function(cd) { H <- fread(file.path(A[[cd]], "04_holdings.csv")); H[, date := as.Date(date)]
  H <- H[date <= TAU & is.finite(target_weight) & target_weight > 0]; H[, .(effn = 1 / sum((target_weight / sum(target_weight))^2)), by = date][, lab := lab_of(cd)] }))
TL <- rbindlist(lapply(CELLS$code, function(cd) { x <- rbindlist(lapply(P[[cd]]$exposure$top_losers, function(z) data.table(peak = substr(z$peak_date, 1, 7), contrib = as.numeric(z$contrib))))
  x[, .(worst = min(contrib)), by = peak][, lab := lab_of(cd)] }))
deep <- c("2008-05", "2020-01")
g1a <- ggplot(effn, aes(date, effn, colour = lab)) + geom_step(linewidth = 0.55, alpha = 0.9) + scale_colour_manual(values = PAL) +
  labs(title = "① 집중 — 리밸일마다 유효 종목 수(1/Σw²)", subtitle = "보유 25종이어도 비중이 쏠리면 '사실상 몇 종목'인지가 줄어든다", x = NULL, y = "유효 종목 수") + th
g1b <- ggplot(TL[peak %in% deep], aes(lab, worst, fill = lab)) + geom_col(width = 0.65) + facet_wrap(~ peak, labeller = as_labeller(c("2008-05" = "위기 2008-05~10", "2020-01" = "위기 2020-01~03"))) +
  geom_text(aes(label = percent(worst, accuracy = 0.1), vjust = 1.3), family = FAM, size = 3.3) + geom_hline(yintercept = -0.10, linetype = "dashed", colour = "#444444") +
  annotate("text", x = 0.6, y = -0.10, label = "잠정 문턱 −10%", hjust = 0, vjust = -0.5, family = FAM, size = 3.2) +
  scale_fill_manual(values = PAL, guide = "none") + scale_y_continuous(labels = percent) +
  labs(title = "깊은 위기에서 한 종목이 포트폴리오에 남긴 최악 손실", x = NULL, y = "한 종목 기여(포트폴리오 대비)") + th + theme(axis.text.x = element_text(angle = 20, hjust = 1))
ggsave(file.path(OUT, "gap1_concentration.png"), g1a / g1b + plot_annotation(caption = cap, theme = th), width = 11, height = 9, dpi = 150, device = ragg::agg_png)
summ$gap1 <- list(effn_mean = setNames(lapply(CELLS$code, function(cd) P[[cd]]$profile$eff_n_mean), as.character(CELLS$lab)),
                  worst_single_name = TL[peak %in% deep, .(peak, lab = as.character(lab), worst)])

## ── 2 위기의 무게 — 위기별 낙폭 포착(시장 낙폭 깊이 순) · 중앙값 vs 깊은 위기 ──────────────────────────
CR <- rbindlist(lapply(c("P3R02_E2_RX0", "P3R02_E2_M5", "P3R01_E2_K2"), function(cd) crises(cd)[, lab := lab_of(cd)]))
CR[, depth := abs(bm_dd)][, crisis := sprintf("%s\n시장 −%s", format(peak, "%Y-%m"), percent(depth, accuracy = 1))]
ordr <- unique(CR[order(-depth)]$crisis)
CR[, crisis := factor(crisis, levels = ordr)]
n_deep <- uniqueN(CR[depth >= stats::median(unique(CR[, .(peak, depth)])$depth), peak])             # 깊은 위기 = 시장 낙폭 크기 ≥ 중앙값(P3R03 규칙과 같은 정의)
med <- data.table(lab = factor(c("기준(동일 비중)", "정제 공분산 최소분산", "최소분산"), levels = levels(CELLS$lab)),
                  m = c(P[["P3R02_E2_RX0"]]$behavior$summary$crisis_dd_capture_median, P[["P3R02_E2_M5"]]$behavior$summary$crisis_dd_capture_median,
                        P[["P3R01_E2_K2"]]$behavior$summary$crisis_dd_capture_median))                  # 중앙값 = 패킷(계약) 산출
g2 <- ggplot(CR, aes(crisis, dd_capture, fill = lab)) + geom_col(position = position_dodge(0.8), width = 0.75) +
  geom_hline(yintercept = 1, colour = "#444444", linewidth = 0.4) + annotate("text", x = 7.45, y = 1.02, label = "시장과 같은 낙폭(1.0)", hjust = 1, vjust = 0, family = FAM, size = 3.1) +
  annotate("rect", xmin = 0.5, xmax = n_deep + 0.5, ymin = -Inf, ymax = Inf, alpha = 0.06, fill = "#d62728") +
  annotate("text", x = (n_deep + 1) / 2, y = max(CR$dd_capture) * 1.08, label = "깊은 위기(시장 낙폭이 중앙값 이상)", family = FAM, size = 3.4, colour = "#a00000") +
  scale_fill_manual(values = PAL[c("기준(동일 비중)", "정제 공분산 최소분산", "최소분산")]) +
  labs(title = "② 위기의 무게 — 위기별 낙폭 포착(전략 낙폭 ÷ 시장 낙폭) · 왼쪽일수록 깊은 위기",
       subtitle = sprintf("낙폭 포착 중앙값은 기준 %.2f → 정제 공분산 최소분산 %.2f · 최소분산 %.2f 로 내려갔지만(방어처럼 보임), 가장 깊은 두 위기(2008-05 · 2020-01)는 그대로이거나 더 나빴다",
                          med[lab == "기준(동일 비중)", m], med[lab == "정제 공분산 최소분산", m], med[lab == "최소분산", m]),
       x = NULL, y = "낙폭 포착(낮을수록 방어)", caption = cap) + th
ggsave(file.path(OUT, "gap2_crisis_weight.png"), g2, width = 12, height = 6.5, dpi = 150, device = ragg::agg_png)
summ$gap2 <- list(median = med, per_crisis = CR[, .(peak = format(peak, "%Y-%m"), bm_dd, lab = as.character(lab), dd_capture)])

## ── 3 β 를 낮춰 산 방어 — 상승장 β vs 하락장 β ─────────────────────────────────────────────
BT <- rbindlist(lapply(CELLS$code, function(cd) { s <- P[[cd]]$behavior$stats
  data.table(lab = lab_of(cd), kind = c("전체 β", "상승장 β", "하락장 β"), v = c(s$beta, s$beta_up, s$beta_down)) }))
BT[, kind := factor(kind, levels = c("상승장 β", "전체 β", "하락장 β"))]
g3 <- ggplot(BT, aes(lab, v, fill = kind)) + geom_col(position = position_dodge(0.8), width = 0.75) +
  geom_text(aes(label = sprintf("%.2f", v)), position = position_dodge(0.8), vjust = -0.35, family = FAM, size = 3) + geom_hline(yintercept = 1, colour = "#444444", linewidth = 0.4) +
  scale_fill_manual(values = c("상승장 β" = "#9ecae1", "전체 β" = "#6baed6", "하락장 β" = "#08519c")) +
  labs(title = "③ β 를 낮춰 산 방어 — 상승장 β 와 하락장 β",
       subtitle = "최소분산 계열은 전체 β 를 0.8 로 낮췄지만 하락장 β(1.0~1.05)가 상승장 β(0.65)보다 높다 — 오를 때 덜 오르고 내릴 때는 같이 내린다(비대칭이 거꾸로)",
       x = NULL, y = "β(KOSPI200 대비)", caption = cap) + th
ggsave(file.path(OUT, "gap3_beta_defense.png"), g3, width = 12, height = 6.5, dpi = 150, device = ragg::agg_png)
summ$gap3 <- BT[, .(lab = as.character(lab), kind = as.character(kind), v)]

## ── 4 엔진 강점 — 강세 국면별 상승 포착 · 0.55 하한 ─────────────────────────────────────────
BU <- rbindlist(lapply(CELLS$code, function(cd) rbindlist(lapply(P[[cd]]$behavior$bull_phases, function(b)
  data.table(lab = lab_of(cd), bull = sprintf("%s~%s", b$start_ym, b$end_ym), uc = as.numeric(b$up_capture))))))
g4 <- ggplot(BU, aes(bull, uc, fill = lab)) + geom_col(position = position_dodge(0.85), width = 0.8) + geom_hline(yintercept = 0.55, linetype = "dashed", colour = "#a00000") +
  geom_hline(yintercept = 1, colour = "#444444", linewidth = 0.4) +
  annotate("text", x = 0.5, y = 0.55, label = "헌장 하한 0.55", hjust = 0, vjust = -0.5, family = FAM, size = 3.2, colour = "#a00000") +
  scale_fill_manual(values = PAL) +
  labs(title = "④ 엔진 강점 — 강세 국면마다 상승 포착(전략 상승 ÷ 시장 상승)",
       subtitle = sprintf("기준 엔진은 강세장에서 시장의 %.2f 배를 벌지만 낙폭 제약 비중은 %.2f 배로 줄었다 — 그래도 하한 0.55 는 통과한다",
                          P[["P3R02_E2_RX0"]]$behavior$summary$bull_up_capture_median, P[["P3R01_E2_K3"]]$behavior$summary$bull_up_capture_median),
       x = "강세 국면(벤치 정의)", y = "상승 포착", caption = cap) + th
ggsave(file.path(OUT, "gap4_engine_strength.png"), g4, width = 12, height = 6.5, dpi = 150, device = ragg::agg_png)
summ$gap4 <- list(median = setNames(lapply(CELLS$code, function(cd) P[[cd]]$behavior$summary$bull_up_capture_median), as.character(CELLS$lab)))

## ── 5 회복 속도 — 수중 곡선(최고점 대비 낙폭) · 위기별 회복 거래일 ────────────────────────────────
UW <- rbindlist(lapply(c("P3R02_E2_RX0", "P3R01_E2_K1", "P3R01_E2_K3"), function(cd) { nv <- fread(file.path(A[[cd]], "02_nav.csv")); nv[, date := as.Date(date)]
  nv[date <= TAU, .(date, dd = drawdown_net, lab = lab_of(cd))] }))
REC <- rbindlist(lapply(c("P3R02_E2_RX0", "P3R01_E2_K1", "P3R02_E2_M5", "P3R01_E2_K3"), function(cd) crises(cd)[, .(crisis = format(peak, "%Y-%m"), rec, lab = lab_of(cd))]))
g5a <- ggplot(UW, aes(date, dd, colour = lab)) + geom_line(linewidth = 0.5) + scale_colour_manual(values = PAL) + scale_y_continuous(labels = percent) +
  labs(title = "⑤ 회복 속도 — 수중 곡선(최고점 대비 낙폭)", subtitle = "0% 로 돌아오기까지가 '회복' — 낙폭이 얕아도 오래 잠겨 있으면 복리가 멈춘다", x = NULL, y = "최고점 대비") + th
g5b <- ggplot(REC, aes(crisis, rec, fill = lab)) + geom_col(position = position_dodge(0.85), width = 0.8) + scale_fill_manual(values = PAL) +
  labs(title = "위기마다 바닥에서 전 고점 회복까지 걸린 거래일", x = "위기(고점 연월)", y = "거래일") + th
ggsave(file.path(OUT, "gap5_recovery.png"), g5a / g5b + plot_annotation(caption = cap, theme = th), width = 12, height = 9, dpi = 150, device = ragg::agg_png)
summ$gap5 <- REC[, .(crisis, lab = as.character(lab), rec)]

writeLines(toJSON(summ, auto_unbox = TRUE, pretty = TRUE, digits = 4), file.path(OUT, "charter_gaps_data.json"), useBytes = TRUE)
cat("[charter_gaps] 차트 5 · 자료 json — ", OUT, "\n")
