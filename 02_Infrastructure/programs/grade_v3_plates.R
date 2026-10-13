#!/usr/bin/env Rscript
#==============================================================================
# grade_v3_plates.R — 등급 v3 눈검사 도판 (S0 · v10.01 2026-10-13)
#
# 무엇: grade_v3_retro.R 산출(retro_scores.csv)에서 두 묶음을 골라 P/L 곡선 도판을 만든다.
#   ① S 상위 10 — 같은 계보(승격 사슬 뿌리)는 1개만(같은 곡선 10장을 피한다)
#   ② CR 강함 상위 10 — CR(위기 복원력) 판정 strong 중 S 순, 계보당 1개
#   + 분포 지도 — PORT_t × Calmar 평면에 전 칸 · S 등고선(1 · B 후보 · 0.5) · CR 판정 색
# 도판 1칸 = 로그 누적수익(전략 vs 공표 KOSPI200) + 낙폭 곡선 · 벤치 위기 구간 음영 · τ_D 선.
# 경계: 읽기만 한다(원장·등록부 무변경). 선정 규칙은 위 두 줄이 전부다(사람이 고르지 않는다).
#
# 사용: Rscript 02_Infrastructure/programs/grade_v3_plates.R [--root <ROOT>] [--out <DIR>] [--k 10]
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(ggplot2); library(patchwork) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
args <- commandArgs(trailingOnly = TRUE)
argv <- function(k, d = NULL) { i <- match(k, args); if (is.na(i) || i == length(args)) d else args[i + 1L] }
ROOT0 <- argv("--root", NULL)
for (p in c(ROOT0, Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd())) {
  if (is.null(p) || !nzchar(p)) next
  if (file.exists(file.path(p, "02_Infrastructure/contracts/grade_v3.R"))) { ROOT0 <- gsub("\\\\", "/", p); break }
}
source(file.path(ROOT0, "02_Infrastructure/contracts/grade_v3.R"))
ROOT <- .gv3_root(ROOT0)
OUT <- argv("--out", file.path(ROOT, "04_Research/01_reports/l1_prescription_redesign_20261013/s0_grade_v3"))
K <- as.integer(argv("--k", "10"))
PL <- file.path(OUT, "plates"); dir.create(PL, recursive = TRUE, showWarnings = FALSE)
FAM <- if ("Malgun Gothic" %in% systemfonts::system_fonts()$family) "Malgun Gothic" else ""

e <- .gv3_deps(ROOT); bcc <- e$bc_cfg(ROOT); th <- gv3_thresholds(ROOT); cfg <- gv3_cfg(ROOT)
TAB <- fread(file.path(OUT, "retro_scores.csv"))
T1 <- TAB[close_t1 == TRUE & is.finite(S)]
setorder(T1, -S, -calmar)

pick <- function(D, k) { D <- D[!duplicated(root_lineage)]; head(D, k) }
SEL_S <- pick(T1, K)
SEL_CR <- pick(T1[cr == "strong"], K)

label_of <- function(r) {
  pk <- as.character(r$paper_key)
  pk <- if (startsWith(pk, "combo:")) sprintf("결합 %d편", length(strsplit(sub("^combo:", "", pk), "+", fixed = TRUE)[[1]])) else pk
  where <- if (identical(r$kind, "base")) "기저" else sprintf("n=%s %s", r$n, ifelse(is.na(r$cell_code), "", r$cell_code))
  sprintf("%s · %s", pk, where)
}
pct <- function(x) sprintf("%.1f%%", 100 * x)

# 벤치 위기 구간(누적 고점 → 저점, 깊이 ≥ crisis_depth) — 행동 카드와 같은 정의 · 같은 설정
H <- gv3_bench_history(ROOT)
CRI <- e$bc_crises(H[, .(date, r = benchmark_ret)], bcc$crisis_depth)
CRI[is.na(recover_date), recover_date := max(H$date)]
TAU <- as.Date(bcc$tau_d)

plate <- function(r, rank, tag) {
  pr <- fread(file.path(r$dir, "03_period_returns.csv"))[, .(date = as.Date(date), s = ret_net)]
  br <- fread(file.path(r$dir, "05_benchmark_returns.csv"))[, .(date = as.Date(date), k = benchmark_ret)]
  J <- merge(pr, br, by = "date")[order(date)]
  J[, `:=`(nav_s = cumprod(1 + s), nav_k = cumprod(1 + k))]
  J[, `:=`(dd_s = nav_s / cummax(nav_s) - 1, dd_k = nav_k / cummax(nav_k) - 1)]
  L1 <- melt(J[, .(date, 전략 = nav_s, KOSPI200 = nav_k)], id.vars = "date", variable.name = "who", value.name = "nav")
  L2 <- melt(J[, .(date, 전략 = dd_s, KOSPI200 = dd_k)], id.vars = "date", variable.name = "who", value.name = "dd")
  # 전략 표본 안에서 고점→저점이 진행된 위기만 — 표본 시작 전에 바닥을 친 위기는 행동 카드와 같이 제외한다
  cw <- CRI[trough_date > min(J$date) & peak_date <= max(J$date)]
  cw[, `:=`(x0 = pmax(peak_date, min(J$date)), x1 = pmin(trough_date, max(J$date)))]
  cw <- cw[x1 > x0]
  # 로그 축에서는 −Inf 가 NaN 이 된다 — 하한 0(= log10 −Inf → 패널 바닥)으로 칠한다
  shade_log <- if (nrow(cw)) geom_rect(data = cw, aes(xmin = x0, xmax = x1, ymin = 0, ymax = Inf), inherit.aes = FALSE,
                                       fill = "#d62728", alpha = 0.10) else NULL
  shade <- if (nrow(cw)) geom_rect(data = cw, aes(xmin = x0, xmax = x1, ymin = -Inf, ymax = Inf), inherit.aes = FALSE,
                                   fill = "#d62728", alpha = 0.10) else NULL
  cols <- c(전략 = "#1f4e9c", KOSPI200 = "#8c8c8c")
  ttl <- sprintf("%s%d. %s", tag, rank, label_of(r))
  sub1 <- sprintf("S %.3f · Calmar %.3f · PORT_t %.2f · CAGR %s · MDD %s · Sharpe %.2f",
                  r$S, r$calmar, r$port_t, pct(r$cagr), pct(r$mdd), r$sharpe)
  sub2 <- sprintf("CR %s(시험창 %s) · 상승포착 %.2f · 위기낙폭포착 중앙 %.2f · 최악 %.2f · v3 %s · 현행 %s%s",
                  r$cr, r$cr_test, r$uc_median, r$dd_capture_median, r$dd_capture_worst, r$grade_v3, r$essence_grade,
                  if (isTRUE(r$c1_flag)) " · ⚠C1 표식 계보" else "")
  g1 <- ggplot(L1, aes(date, nav, colour = who)) + shade_log +
    geom_vline(xintercept = TAU, linetype = "dashed", linewidth = 0.3) +
    geom_line(linewidth = 0.45) + scale_y_log10() + scale_colour_manual(values = cols, name = NULL) +
    labs(title = ttl, subtitle = paste(sub1, sub2, sep = "\n"), x = NULL, y = "누적(로그)") +
    theme_minimal(base_size = 9, base_family = FAM) +
    theme(legend.position = c(0.08, 0.85), plot.title = element_text(face = "bold", size = 10),
          plot.subtitle = element_text(size = 7.5), axis.text.x = element_blank())
  g2 <- ggplot(L2, aes(date, dd, colour = who)) + shade +
    geom_vline(xintercept = TAU, linetype = "dashed", linewidth = 0.3) +
    geom_line(linewidth = 0.35) + scale_colour_manual(values = cols, guide = "none") +
    scale_y_continuous(labels = function(x) sprintf("%d%%", round(100 * x))) +
    labs(x = NULL, y = "낙폭") + theme_minimal(base_size = 8, base_family = FAM)
  g1 / g2 + plot_layout(heights = c(3, 1.2))
}

grid_png <- function(SEL, tag, file, title) {
  if (!nrow(SEL)) { cat(sprintf("[plates] %s — 대상 0건\n", tag)); return(invisible(NULL)) }
  ps <- lapply(seq_len(nrow(SEL)), function(i) plate(SEL[i], i, tag))
  nr <- ceiling(length(ps) / 2)
  g <- wrap_plots(ps, ncol = 2) + plot_annotation(title = title,
        subtitle = sprintf("빨간 음영 = KOSPI200 위기(고점→저점 −%d%% 이상) · 점선 = τ_D %s(오른쪽 = 처방이 못 본 시험 구간)",
                           round(100 * bcc$crisis_depth), format(TAU)),
        theme = theme(text = element_text(family = FAM), plot.title = element_text(face = "bold", size = 14)))
  ragg::agg_png(file.path(PL, file), width = 2000, height = 620 * nr + 120, res = 120)
  suppressWarnings(print(g)); invisible(dev.off())   # 로그 축 음영 하한 0 → '무한값' 안내 경고만 억제
  cat(sprintf("[plates] %s → %s (%d칸)\n", tag, file, length(ps)))
}

grid_png(SEL_S, "S", "eye_check_S_top10.png", sprintf("등급 v3 S 상위 %d (계보당 1개) — 진단 · 권위 등급 아님", nrow(SEL_S)))
grid_png(SEL_CR, "CR", "eye_check_CR_strong_top10.png", sprintf("위기 복원력(CR) 강함 상위 %d (S 순 · 계보당 1개) — 진단", nrow(SEL_CR)))

# 분포 지도 — PORT_t × Calmar · S 등고선 · CR 판정
s_b_star <- (th$port_t_b / th$port_t_a)^cfg$weights$port_t
iso <- rbindlist(lapply(c(1, s_b_star, 0.5), function(s) {
  x <- seq(0.05, max(4.5, max(T1$port_t, na.rm = TRUE)), length.out = 200)
  data.table(port_t = x, calmar = th$calmar_a * (s / (x / th$port_t_a)^cfg$weights$port_t)^(1 / cfg$weights$calmar),
             iso = sprintf("S = %s", format(round(s, 3))))
}))
iso <- iso[calmar <= max(1.2, max(T1$calmar, na.rm = TRUE))]
gm <- ggplot(T1[port_t > -2 & calmar > -0.2], aes(port_t, calmar)) +
  geom_line(data = iso, aes(group = iso, linetype = iso), colour = "#444444", linewidth = 0.4) +
  geom_point(aes(colour = cr), size = 1.1, alpha = 0.6) +
  geom_hline(yintercept = th$calmar_a, colour = "#999999", linewidth = 0.3) +
  geom_vline(xintercept = c(th$port_t_b, th$port_t_a), colour = "#999999", linewidth = 0.3) +
  scale_colour_manual(values = c(strong = "#2ca02c", normal = "#1f77b4", weak = "#d62728", insufficient = "#bbbbbb",
                                 error = "#000000"), name = "CR") +
  labs(title = sprintf("등급 v3 분포 지도 — close_t1 측정 %d칸(기저 포함)", nrow(T1)),
       subtitle = sprintf("실선 = S 등고선(1 = A 경계 · %.3f = 'A Calmar + B PORT_t' 후보 · 0.5) · 회색선 = Calmar %.2f · PORT_t %.1f / %.2f",
                          s_b_star, th$calmar_a, th$port_t_b, th$port_t_a),
       x = "PORT_t (NW lag-3)", y = "Calmar (전기간)", linetype = NULL) +
  theme_minimal(base_size = 10, base_family = FAM)
ragg::agg_png(file.path(PL, "s_map.png"), width = 1500, height = 1050, res = 130); print(gm); invisible(dev.off())
cat("[plates] 분포 지도 → s_map.png\n")

keep <- c("root_lineage", "kind", "base_id", "n", "cell_code", "paper_key", "S", "calmar", "port_t", "cagr", "mdd", "sharpe",
          "cr", "cr_test", "uc_median", "dd_capture_median", "dd_capture_worst", "pass_oos", "oos_gate", "grade_v3",
          "essence_grade", "c1_flag", "blocked_by", "dir")
fwrite(SEL_S[, ..keep], file.path(OUT, "eye_check_S_top10.csv"))
fwrite(SEL_CR[, ..keep], file.path(OUT, "eye_check_CR_strong_top10.csv"))
cat(sprintf("[plates] 선정 표 → eye_check_S_top10.csv(%d) · eye_check_CR_strong_top10.csv(%d)\n", nrow(SEL_S), nrow(SEL_CR)))
