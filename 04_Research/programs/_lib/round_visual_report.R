## 1계층 라운드 시각 보고 — ① 전략이 돈을 버나 ② 개선이 알파를 만들었나 (도훈 2026-10-15 요청 · 텍스트 1쪽 + 시각화)
## 수치 = R 계약만(AX-008): 창 지표 = grade_v3::gv3_window(build_metrics · build_benchmark_compare) · 벤치 지표 = 같은 함수에 벤치를 전략처럼
##   (.gv3_bench_as_strategy) · 알파 = beta_controlled_alpha(월 복리 = 행동 카드 계약 bc_monthly · NW lag 3) · 누적 수익 = 측정 산출물
##   02_nav(nav_net) · 벤치 = 05_benchmark_returns(benchmark_nav). 개선의 알파 = (개선 셀 − 기준 엔진) 월 차이 수익의 β-통제 알파(증분 α).
## 차트 글꼴 = 현대하모니 M(도훈 10-15). 실행: Rscript round_visual_report.R [출력 폴더]
suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(ggplot2); library(patchwork); library(scales); library(ragg); library(systemfonts)
})
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
invisible(capture.output(suppressMessages({
  source("02_Infrastructure/contracts/diagnosis_packet.R")
  source("02_Infrastructure/contracts/beta_controlled_alpha.R")
  source("02_Infrastructure/contracts/grade_v3.R")
})))
E <- .dp_deps(ROOT)
A <- commandArgs(trailingOnly = TRUE)
OUT <- if (length(A) && nzchar(A[1])) A[1] else file.path(ROOT, "04_Research/01_reports/l1_round1_results_20261015")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
TAU <- as.Date("2022-12-31")

## ── 글꼴(현대하모니 M) ──
fdir <- c(file.path(Sys.getenv("LOCALAPPDATA"), "Microsoft", "Windows", "Fonts"), file.path(Sys.getenv("WINDIR", "C:/Windows"), "Fonts"))
fM <- file.path(fdir, "현대하모니+M.ttf"); fM <- fM[file.exists(fM)][1]
if (is.na(fM)) stop("[visual] 현대하모니 M 글꼴 파일 없음")
systemfonts::register_font(name = "HDHM", plain = fM)
FAM <- "HDHM"
th <- theme_minimal(base_family = FAM, base_size = 11) +
  theme(plot.title = element_text(size = 14, margin = margin(b = 4)), plot.subtitle = element_text(size = 10, colour = "#555555"),
        legend.position = "bottom", legend.title = element_blank(), panel.grid.minor = element_blank(),
        strip.text = element_text(size = 11), plot.caption = element_text(size = 8, colour = "#777777"))
PAL <- c("KOSPI200" = "#7f7f7f", "모멘텀 12-1" = "#d62728", "DNN 원형" = "#1f77b4", "B6_36(DNN 계보)" = "#2ca02c")

## ── 셀 · 이름 ──
RES <- list(P0 = "04_Research/programs/P0_FRONTIER/P0R01_feasibility_map", P3 = "04_Research/programs/P3_CONSTRUCTION/P3R01_construction_map",
            P32 = "04_Research/programs/P3_CONSTRUCTION/P3R02_eigen_markowitz")
art <- function(rd, code) { j <- fromJSON(file.path(ROOT, RES[[rd]], "results", paste0(code, ".json"))); if (!isTRUE(j$ok)) NA_character_ else j$artifacts }
ENG <- c(E1 = "모멘텀 12-1", E2 = "DNN 원형", E3 = "B6_36(DNN 계보)")
VAR <- c(C1 = "추세 현금", C2 = "변동성 타기팅", C3 = "낙폭 제어", C4 = "저변동 틸트", C5 = "퀄리티 틸트", C6 = "추세 현금+저변동",
         K1 = "역변동성", K2 = "최소분산(LW)", K3 = "낙폭 제약(CDaR)", K4 = "켈리", K5 = "순위 버퍼 2배", M5 = "정제 공분산 최소분산")
FAMY <- c(C1 = "방어 장치(P2)", C2 = "방어 장치(P2)", C3 = "방어 장치(P2)", C4 = "방어 장치(P2)", C5 = "방어 장치(P2)", C6 = "방어 장치(P2)",
          K1 = "구성(P3R01)", K2 = "구성(P3R01)", K3 = "구성(P3R01)", K4 = "구성(P3R01)", K5 = "구성(P3R01)", M5 = "정제 공분산(P3R02)")
cells <- rbindlist(c(
  lapply(names(ENG), function(e) data.table(code = sprintf("P0R01_%s_C0", e), rd = "P0", engine = e, var = "C0")),
  lapply(c("E2", "E3"), function(e) data.table(code = sprintf("P0R01_%s_C%d", e, 1:6), rd = "P0", engine = e, var = sprintf("C%d", 1:6))),
  list(data.table(code = sprintf("P3R01_E2_K%d", 1:5), rd = "P3", engine = "E2", var = sprintf("K%d", 1:5)),
       data.table(code = "P3R02_E2_M5", rd = "P32", engine = "E2", var = "M5"))))
cells[, artifacts := mapply(art, rd, code)]
if (anyNA(cells$artifacts)) stop("[visual] 측정 산출물 없음: ", paste(cells[is.na(artifacts)]$code, collapse = ","))
RD <- setNames(lapply(cells$artifacts, function(a) .dp_read(E, a)), cells$code)
mon <- function(d, col) E$bc_monthly(d[, .(date, r = get(col))], "r")

## ── ① 돈을 버나: 공통 창(세 엔진 실효 시작의 가장 늦은 날 ~ 끝) ──
base3 <- sprintf("P0R01_%s_C0", names(ENG))
t0 <- max(vapply(base3, function(k) as.numeric(min(RD[[k]]$nv$date)), numeric(1))); t0 <- as.Date(t0, origin = "1970-01-01")
t1 <- min(vapply(base3, function(k) as.numeric(max(RD[[k]]$nv$date)), numeric(1))); t1 <- as.Date(t1, origin = "1970-01-01")
wins <- list("전기간" = c(t0, t1), "보는 창(~2022)" = c(t0, TAU), "시험 창(2023~)" = c(TAU + 1, t1))
metr <- function(rd, w, bench = FALSE) {
  if (bench) { b <- .gv3_bench_as_strategy(rd$br); E$gv3_window(b$pr, rd$br, b$nv, from = w[1], to = w[2], root = ROOT) }
  else E$gv3_window(rd$pr, rd$br, rd$nv, from = w[1], to = w[2], root = ROOT)
}
M1 <- rbindlist(lapply(names(wins), function(wn) {
  w <- wins[[wn]]
  rbind(rbindlist(lapply(names(ENG), function(e) { m <- metr(RD[[sprintf("P0R01_%s_C0", e)]], w)
          data.table(window = wn, who = ENG[[e]], CAGR = m$cagr, Sharpe = m$sharpe, MDD = m$mdd, Calmar = m$calmar, PORT_t = m$port_t) })),
        { m <- metr(RD[["P0R01_E2_C0"]], w, bench = TRUE)
          data.table(window = wn, who = "KOSPI200", CAGR = m$cagr, Sharpe = m$sharpe, MDD = m$mdd, Calmar = m$calmar, PORT_t = NA_real_) })
}))
## 누적 수익(공통 시작일 1 로 맞춤 — 표시 변환) · 낙폭
navs <- rbindlist(c(lapply(names(ENG), function(e) { nv <- RD[[sprintf("P0R01_%s_C0", e)]]$nv[date >= t0 & date <= t1]
                       data.table(date = nv$date, who = ENG[[e]], nav = nv$nav_net / nv$nav_net[1], dd = nv$drawdown_net) }),
                    list({ br <- RD[["P0R01_E2_C0"]]$br[date >= t0 & date <= t1]; nb <- br$benchmark_nav / br$benchmark_nav[1]
                           data.table(date = br$date, who = "KOSPI200", nav = nb, dd = nb / cummax(nb) - 1) })))
navs[, who := factor(who, levels = c("KOSPI200", unname(ENG)))]
g1a <- ggplot(navs, aes(date, nav, colour = who)) + geom_line(linewidth = 0.6) + scale_y_log10(labels = label_number(accuracy = 0.1, suffix = "배")) +
  geom_vline(xintercept = TAU, linetype = "dashed", colour = "#444444") +
  annotate("text", x = TAU, y = max(navs$nav), label = "  시험 창 →", hjust = 0, vjust = 1, family = FAM, size = 3.2, colour = "#444444") +
  scale_colour_manual(values = PAL) + labs(title = "① 돈을 버나 — 누적 수익(P/L) · 로그 축", subtitle = sprintf("%s 에 1 을 넣었을 때 · 15bps 순비용 · KOSPI200 대비", format(t0)), x = NULL, y = NULL) + th
g1b <- ggplot(navs, aes(date, dd, colour = who)) + geom_line(linewidth = 0.45) + scale_y_continuous(labels = label_percent()) +
  geom_vline(xintercept = TAU, linetype = "dashed", colour = "#444444") + scale_colour_manual(values = PAL) +
  labs(title = "낙폭(고점 대비)", x = NULL, y = NULL) + th + theme(legend.position = "none")
mlong <- melt(M1, id.vars = c("window", "who"), measure.vars = c("CAGR", "Sharpe", "MDD", "Calmar"), variable.name = "metric")
mlong[, who := factor(who, levels = c("KOSPI200", unname(ENG)))][, window := factor(window, levels = names(wins))]
mlong[, lab := fifelse(metric %in% c("CAGR", "MDD"), percent(value, accuracy = 0.1), number(value, accuracy = 0.01))]
mlong[, metric := factor(metric, levels = c("CAGR", "Sharpe", "MDD", "Calmar"), labels = c("CAGR", "Sharpe", "MDD(낮을수록 좋음)", "Calmar"))]
SEP1 <- data.frame(window = factor("시험 창(2023~)", levels = names(wins)))
g1c <- ggplot(mlong[window != "보는 창(~2022)"], aes(who, value, fill = who)) + geom_col(width = 0.7) +
  geom_vline(data = SEP1, aes(xintercept = -Inf), linetype = "dashed", colour = "#555555", linewidth = 0.7) +
  geom_text(aes(label = lab, vjust = ifelse(value >= 0, -0.3, 1.2)), family = FAM, size = 2.9) +
  facet_grid(metric ~ window, scales = "free_y") + scale_fill_manual(values = PAL) + scale_y_continuous(expand = expansion(mult = 0.18)) +
  labs(title = "수익률 · 리스크 지표 — 엔진 vs KOSPI200", subtitle = "같은 창 · 같은 계약 함수(gv3_window)로 잰 값", x = NULL, y = NULL) +
  th + theme(axis.text.x = element_text(size = 8.5, angle = 20, hjust = 1), legend.position = "none", panel.spacing.x = unit(14, "pt"))
f1 <- file.path(OUT, "fig1_money.png")
agg_png(f1, width = 3400, height = 2000, res = 220); print((g1a / g1b + plot_layout(heights = c(2.2, 1))) | g1c); invisible(dev.off())

## ── ② 개선이 알파를 만들었나: 증분 α(개선 − 기준 엔진 월 차이 수익의 β-통제 알파) ──
alpha_of <- function(s, k) tryCatch(beta_controlled_alpha(s, k, periods_per_year = 12, nw_lag = 3L), error = function(e) NULL)
inc <- rbindlist(lapply(seq_len(nrow(cells[var != "C0"])), function(i) {
  x <- cells[var != "C0"][i]; b <- RD[[sprintf("P0R01_%s_C0", x$engine)]]; v <- RD[[x$code]]
  S <- merge(mon(v$pr[, .(date, ret_net)], "ret_net")[, .(ym, s = r)], mon(b$pr[, .(date, ret_net)], "ret_net")[, .(ym, b = r)], by = "ym")
  K <- mon(b$br[, .(date, benchmark_ret)], "benchmark_ret")[, .(ym, k = r)]
  D <- merge(S, K, by = "ym")[order(ym)]; tym <- format(TAU, "%Y-%m")
  rbindlist(lapply(list(c("보는 창(~2022)", "vis"), c("시험 창(2023~)", "test")), function(w) {
    d <- if (w[2] == "vis") D[ym <= tym] else D[ym > tym]
    a <- alpha_of(d$s - d$b, d$k)
    data.table(engine = x$engine, var = x$var, window = w[1], d_alpha = a$alpha_ann %||% NA_real_, t = a$t_alpha %||% NA_real_, n = a$n %||% NA_integer_)
  }))
}))
inc[, label := paste0(VAR[var], " (", var, ")")][, family := FAMY[var]]
inc[, se := abs(d_alpha / t)][, lo := d_alpha - 1.96 * se][, hi := d_alpha + 1.96 * se]
inc[, sig := fifelse(is.finite(t) & t >= 2, "알파 증가(t ≥ 2)", fifelse(is.finite(t) & t <= -2, "알파 감소(t ≤ −2)", "차이 유의하지 않음"))]
inc[, eng_lab := factor(ENG[engine], levels = unname(ENG[c("E2", "E3")]))][, window := factor(window, levels = c("보는 창(~2022)", "시험 창(2023~)"))]
ord <- inc[window == "보는 창(~2022)" & engine == "E2", label][order(inc[window == "보는 창(~2022)" & engine == "E2", d_alpha])]
inc[, label := factor(label, levels = unique(c(ord, inc$label)))]
SIGPAL <- c("알파 증가(t ≥ 2)" = "#2ca02c", "알파 감소(t ≤ −2)" = "#d62728", "차이 유의하지 않음" = "#9e9e9e")
g2 <- ggplot(inc, aes(d_alpha, label, colour = sig)) + geom_vline(xintercept = 0, colour = "#333333") +
  geom_errorbar(aes(xmin = lo, xmax = hi), width = 0.25, linewidth = 0.5, orientation = "y") + geom_point(size = 2.2) +
  facet_grid(eng_lab ~ window, scales = "free_y", space = "free_y") + scale_x_continuous(labels = label_percent(accuracy = 1)) +
  scale_colour_manual(values = SIGPAL) +
  labs(title = "② 개선이 알파를 만들었나 — 기준 엔진 대비 증분 알파(β-통제 · 연율)",
       subtitle = "점 = (개선 − 기준) 월 차이 수익의 KOSPI200 β-통제 알파 · 막대 = 95% 구간(NW lag 3) · 0 오른쪽 = 알파 증가",
       x = "증분 알파(연율)", y = NULL, caption = "계약: beta_controlled_alpha · 월 복리 bc_monthly") + th
f2 <- file.path(OUT, "fig2_alpha.png")
agg_png(f2, width = 3400, height = 2300, res = 220); print(g2); invisible(dev.off())

## ── ② 보조: 개선의 손익(DNN 원형 · 대표 개선) — 누적 수익 · 낙폭 · 지표 ──
keyv <- c("P0R01_E2_C0", "P0R01_E2_C4", "P0R01_E2_C6", "P3R01_E2_K1", "P3R02_E2_M5")
klab <- c(P0R01_E2_C0 = "기준(DNN 원형 · EW)", P0R01_E2_C4 = "저변동 틸트", P0R01_E2_C6 = "추세 현금+저변동", P3R01_E2_K1 = "역변동성", P3R02_E2_M5 = "정제 공분산 최소분산")
t0b <- as.Date(max(vapply(keyv, function(k) as.numeric(min(RD[[k]]$nv$date)), numeric(1))), origin = "1970-01-01")
nv2 <- rbindlist(c(lapply(keyv, function(k) { nv <- RD[[k]]$nv[date >= t0b]; data.table(date = nv$date, who = klab[[k]], nav = nv$nav_net / nv$nav_net[1], dd = nv$drawdown_net) }),
                   list({ br <- RD[["P0R01_E2_C0"]]$br[date >= t0b]; nb <- br$benchmark_nav / br$benchmark_nav[1]; data.table(date = br$date, who = "KOSPI200", nav = nb, dd = nb / cummax(nb) - 1) })))
PAL2 <- c("KOSPI200" = "#7f7f7f", "기준(DNN 원형 · EW)" = "#1f77b4", "저변동 틸트" = "#ff7f0e", "추세 현금+저변동" = "#9467bd", "역변동성" = "#2ca02c", "정제 공분산 최소분산" = "#d62728")
nv2[, who := factor(who, levels = names(PAL2))]
g3a <- ggplot(nv2, aes(date, nav, colour = who)) + geom_line(linewidth = 0.55) + scale_y_log10(labels = label_number(accuracy = 0.1, suffix = "배")) +
  geom_vline(xintercept = TAU, linetype = "dashed", colour = "#444444") + scale_colour_manual(values = PAL2) +
  labs(title = "개선의 손익 — DNN 원형 기준 vs 대표 개선 · KOSPI200", subtitle = sprintf("%s 에 1 · 로그 축 · 점선 = 시험 창 시작(2023)", format(t0b)), x = NULL, y = NULL) + th
g3b <- ggplot(nv2, aes(date, dd, colour = who)) + geom_line(linewidth = 0.4) + scale_y_continuous(labels = label_percent()) +
  geom_vline(xintercept = TAU, linetype = "dashed", colour = "#444444") + scale_colour_manual(values = PAL2) + labs(title = "낙폭", x = NULL, y = NULL) +
  th + theme(legend.position = "none")
M3 <- rbindlist(lapply(names(wins)[c(1, 3)], function(wn) {
  w <- c(t0b, if (wn == "전기간") t1 else t1); if (wn != "전기간") w[1] <- TAU + 1
  rbind(rbindlist(lapply(keyv, function(k) { m <- metr(RD[[k]], w); data.table(window = wn, who = klab[[k]], CAGR = m$cagr, MDD = m$mdd, Sharpe = m$sharpe, Calmar = m$calmar) })),
        { m <- metr(RD[["P0R01_E2_C0"]], w, bench = TRUE); data.table(window = wn, who = "KOSPI200", CAGR = m$cagr, MDD = m$mdd, Sharpe = m$sharpe, Calmar = m$calmar) })
}))
m3 <- melt(M3, id.vars = c("window", "who"), variable.name = "metric")
m3[, who := factor(who, levels = names(PAL2))][, window := factor(window, levels = names(wins)[c(1, 3)])]
m3[, lab := fifelse(metric %in% c("CAGR", "MDD"), percent(value, accuracy = 0.1), number(value, accuracy = 0.01))]
m3[, metric := factor(metric, levels = c("CAGR", "MDD", "Sharpe", "Calmar"), labels = c("CAGR", "MDD(낮을수록 좋음)", "Sharpe", "Calmar"))]
SEP3 <- data.frame(window = factor("시험 창(2023~)", levels = names(wins)[c(1, 3)]))
g3c <- ggplot(m3, aes(who, value, fill = who)) + geom_col(width = 0.72) +
  geom_vline(data = SEP3, aes(xintercept = -Inf), linetype = "dashed", colour = "#555555", linewidth = 0.7) + geom_text(aes(label = lab, vjust = ifelse(value >= 0, -0.3, 1.2)), family = FAM, size = 2.6) +
  facet_grid(metric ~ window, scales = "free_y") + scale_fill_manual(values = PAL2) + scale_y_continuous(expand = expansion(mult = 0.2)) +
  labs(title = "지표 — 개선 vs 기준 · KOSPI200", x = NULL, y = NULL) + th + theme(axis.text.x = element_blank(), legend.position = "bottom", panel.spacing.x = unit(14, "pt"))
f3 <- file.path(OUT, "fig3_improvement_pl.png")
agg_png(f3, width = 3400, height = 2000, res = 220); print((g3a / g3b + plot_layout(heights = c(2.2, 1))) | g3c); invisible(dev.off())

## ── 요약 데이터(본문 작성용 · 계약 수치 그대로) ──
fwrite(M1, file.path(OUT, "q1_metrics.csv")); fwrite(inc[, .(engine, var, window, d_alpha, t, n, sig)], file.path(OUT, "q2_incremental_alpha.csv")); fwrite(M3, file.path(OUT, "q2_key_metrics.csv"))
base_alpha <- rbindlist(lapply(names(ENG), function(e) { b <- RD[[sprintf("P0R01_%s_C0", e)]]
  D <- merge(mon(b$pr[, .(date, ret_net)], "ret_net")[, .(ym, s = r)], mon(b$br[, .(date, benchmark_ret)], "benchmark_ret")[, .(ym, k = r)], by = "ym")
  tym <- format(TAU, "%Y-%m")
  rbindlist(lapply(list(c("전기간", "all"), c("보는 창(~2022)", "vis"), c("시험 창(2023~)", "test")), function(w) {
    d <- if (w[2] == "all") D else if (w[2] == "vis") D[ym <= tym] else D[ym > tym]
    a <- alpha_of(d$s, d$k); data.table(engine = e, window = w[1], alpha = a$alpha_ann %||% NA_real_, t = a$t_alpha %||% NA_real_, beta = a$beta %||% NA_real_) })) }))
fwrite(base_alpha, file.path(OUT, "q1_engine_alpha.csv"))
cat(sprintf("[visual] %s · 공통 창 %s ~ %s · 그림 3 · 표 4\n", OUT, t0, t1))
