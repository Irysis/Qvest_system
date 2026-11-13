## 원천 이음매(2026-03-30) 수리 보고 차트 — 4장
##   실행: 저장소 루트에서 Rscript 04_Research/01_reports/rawdata_seam_20260330_repair_20261113/tools/seam_repair_charts.R
##   출력: ../charts/*.png · 마지막 표준 출력 줄 = JSON 배열 [{"file","caption"}] (prep_send charts 인자용)
##
##   수치 출처(AX-008 — 등급 · 판정에 닿는 값은 다시 계산하지 않는다):
##     · 등급 · Calmar · OOS(시험 창) Calmar · 벤치 시험 창 Calmar = 각 산출물 authoritative_remeasure.json(essence · grade_v3)
##     · 03-30 하루 수익 · NAV = 산출물 03_period_returns.csv · 02_nav.csv · 05_benchmark_returns.csv(기술 통계 — 판정 아님)
##     · RAWDATA 단면 극단 수익 종목 수 = 정정 전 백업(.cache/rawdata_pre_seamguard_20261113.parquet) · 정정 뒤 정본(.cache/RAWDATA.parquet)의
##       저장 Ret 그대로(|Ret| > SEAM_MAX_RET · 문턱 = seam_guard_config.json · 경보 문턱 = rawdata_seam_audit_config.json)
##     · 수리 전 산출물 = P1R03 results/<칸>.json::artifacts · 수리 뒤 = remeasure_seam_20261113/results/<칸>.json::artifacts
##   쓰는 곳은 ../charts/ 뿐이다(발송 · 커밋 없음).
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(ggplot2); library(arrow) })
for (p in c("ragg", "systemfonts", "scales")) if (!requireNamespace(p, quietly = TRUE)) stop("[seam_charts] 패키지 없음: ", p)

ROOT <- sub("/+$", "", gsub("\\\\", "/", Sys.getenv("QM_ROOT", getwd())))
if (!file.exists(file.path(ROOT, "CLAUDE.md"))) ROOT <- gsub("\\\\", "/", getwd())
REP <- file.path(ROOT, "04_Research/01_reports/rawdata_seam_20260330_repair_20261113")
OUT <- file.path(REP, "charts"); dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
RD  <- file.path(ROOT, "04_Research/programs/P1_RETURN/P1R03_factor_family_composites")
OLD <- file.path(RD, "results"); NEW <- file.path(RD, "remeasure_seam_20261113/results")
SEAM <- as.Date("2026-03-30"); TAU <- as.Date("2022-12-31")

CAT <- c(FACCR = "발생액", FCONS = "컨센서스", FCROW = "쏠림", FDEFE = "방어", FGROW = "성장",
         FINVE = "수급", FLEVE = "레버리지", FLIQU = "유동성", FMOME = "모멘텀", FQUAL = "퀄리티",
         FREGI = "국면", FRISK = "위험", FTECH = "기술적", FVALU = "밸류", TOTAL = "토탈")
KEY5 <- c("FGROW", "FREGI", "FTECH", "FLIQU", "FRISK")

C_PRE <- "#e34948"; C_POST <- "#2a78d6"; C_BENCH <- "#898781"; INK <- "#0b0b0b"; INK2 <- "#52514e"; MUTED <- "#898781"
GRID <- "#e1e0d9"; TEST_FILL <- "#eceae3"
FAM <- ""
fdir <- c(file.path(Sys.getenv("LOCALAPPDATA"), "Microsoft", "Windows", "Fonts"), file.path(Sys.getenv("WINDIR", "C:/Windows"), "Fonts"))
fM <- file.path(fdir, "현대하모니+M.ttf"); fM <- fM[file.exists(fM)][1]
if (!is.na(fM)) { try(systemfonts::register_font(name = "HDHM", plain = fM), silent = TRUE); FAM <- "HDHM" }
th <- function(base = 12) {
  theme_minimal(base_family = FAM, base_size = base) +
    theme(plot.title = element_text(size = base + 4, colour = INK), plot.title.position = "plot",
          plot.subtitle = element_text(size = base - 1.5, colour = INK2, lineheight = 1.15),
          plot.caption = element_text(size = base - 4, colour = MUTED, hjust = 0, lineheight = 1.1), plot.caption.position = "plot",
          panel.grid.minor = element_blank(), panel.grid.major = element_line(colour = GRID, linewidth = 0.3),
          axis.text = element_text(colour = INK2), legend.position = "top", legend.justification = "left",
          legend.title = element_blank(), plot.background = element_rect(fill = "white", colour = NA),
          strip.text = element_text(colour = INK, size = base - 1), plot.margin = margin(10, 14, 8, 10))
}
save_png <- function(g, name, h, w = 7.2) { p <- file.path(OUT, name); ggsave(p, g, width = w, height = h, dpi = 150, device = ragg::agg_png, bg = "white"); p }
pct <- function(x, d = 1) ifelse(is.finite(x), sprintf(paste0("%+.", d, "f%%"), 100 * x), "–")
num <- function(x) { v <- suppressWarnings(as.numeric(x)); if (length(v) == 1L) v else NA_real_ }
gcfg <- fromJSON(file.path(ROOT, "02_Infrastructure/data/seam_guard_config.json"))
acfg <- fromJSON(file.path(ROOT, "02_Infrastructure/data/rawdata_seam_audit_config.json"))
MX <- as.numeric(gcfg$SEAM_MAX_RET); DAYF <- as.numeric(acfg$DAY_FRAC_OFF_ALARM)

## ---- 산출물 읽기 ----------------------------------------------------------------------------------
art_of <- function(dir, code) { p <- file.path(dir, paste0(code, ".json")); if (!file.exists(p)) return(NA_character_)
  j <- fromJSON(p); if (!isTRUE(j$ok)) return(NA_character_); sub("/+$", "", gsub("\\\\", "/", j$artifacts)) }
rd_auth <- function(a) {
  if (is.na(a) || !file.exists(file.path(a, "authoritative_remeasure.json"))) return(NULL)
  j <- fromJSON(file.path(a, "authoritative_remeasure.json"), simplifyVector = FALSE)
  e <- j$essence; g <- j$grade_v3
  list(grade = j$essence_grade %||% NA, calmar = num(e$calmar), cagr = num(e$cagr), sharpe = num(e$net_sharpe), mdd = num(e$mdd),
       port_t = num(e$portfolio_alpha_t_nw_lag3), calmar_tw = num(g$oos$calmar_tw), bench_calmar_tw = num(g$oos$bench_calmar_tw),
       S = num(g$S), fa_t = num(g$fa$t_min), blocked = paste(unlist(g$blocked_by), collapse = " · "))
}
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
rd_ret <- function(a) {
  if (is.na(a)) return(NULL)
  r <- fread(file.path(a, "03_period_returns.csv"), select = c("date", "ret_net"))
  b <- fread(file.path(a, "05_benchmark_returns.csv"), select = c("date", "benchmark_ret"))
  r[, date := as.Date(date)]; b[, date := as.Date(date)]
  merge(r, b, by = "date", all.x = TRUE)
}
codes <- names(CAT)
M <- rbindlist(lapply(codes, function(c) {
  code <- paste0("P1R03_", c, "_C0"); ao <- art_of(OLD, code); an <- art_of(NEW, code)
  o <- rd_auth(ao); n <- rd_auth(an); ro <- rd_ret(ao); rn <- rd_ret(an)
  s0 <- function(x, d) if (is.null(x)) NA_real_ else { v <- x[date == d, ret_net]; if (length(v)) v[1] else NA_real_ }
  data.table(code = c, name = CAT[[c]], art_old = ao, art_new = an,
             g_old = o$grade %||% NA, g_new = n$grade %||% NA,
             calmar_old = o$calmar %||% NA, calmar_new = n$calmar %||% NA, cagr_old = o$cagr %||% NA, cagr_new = n$cagr %||% NA,
             sharpe_old = o$sharpe %||% NA, sharpe_new = n$sharpe %||% NA, tw_old = o$calmar_tw %||% NA, tw_new = n$calmar_tw %||% NA,
             btw = (n$bench_calmar_tw %||% o$bench_calmar_tw) %||% NA, fa_old = o$fa_t %||% NA, fa_new = n$fa_t %||% NA,
             S_old = o$S %||% NA, S_new = n$S %||% NA, blk_new = n$blocked %||% NA,
             d_old = s0(ro, SEAM), d_new = s0(rn, SEAM), bench_d = if (is.null(ro)) NA_real_ else ro[date == SEAM, benchmark_ret][1])
}))
fwrite(M, file.path(REP, "p1r03_before_after.csv"))

charts <- list()

## ---- 1. RAWDATA 단면 — 하루 |Ret| > 문턱 종목 수(정정 전 · 뒤) ---------------------------------------
cnt <- function(p) {
  x <- as.data.table(read_parquet(p, col_select = tidyselect::all_of(c("Date", "Ret")), mmap = FALSE))
  x[, Date := as.Date(Date)]
  y <- x[Date >= as.Date("2000-01-01") & is.finite(Ret), .(n = .N, n_off = sum(abs(Ret) > MX)), by = Date]
  y[, frac := n_off / n][]
}
pre_p <- file.path(ROOT, ".cache/rawdata_pre_seamguard_20261113.parquet"); post_p <- file.path(ROOT, ".cache/RAWDATA.parquet")
if (file.exists(pre_p) && file.exists(post_p)) {
  A <- cnt(pre_p)[, kind := "정정 전(11-11 11:28 ~ 11-13 09:07 저장본)"]
  B <- cnt(post_p)[, kind := "정정 뒤(현행)"]
  AB <- rbind(A, B)
  out_max <- A[Date != SEAM, .(mx = max(n_off), fx = max(frac))]
  W <- AB[Date >= as.Date("2025-07-01")]
  thr <- DAYF * median(B[Date >= as.Date("2025-07-01"), n])
  g1 <- ggplot(W, aes(Date, n_off)) +
    geom_col(aes(fill = kind), width = 1.6, position = "identity", alpha = 0.9) +
    geom_hline(yintercept = thr, colour = INK2, linetype = "22", linewidth = 0.4) +
    annotate("text", x = as.Date("2025-07-05"), y = thr, vjust = -0.5, hjust = 0, family = FAM, size = 3.1, colour = INK2,
             label = sprintf("경보 문턱 ≈ %.0f종목(하루 유한 Ret 의 %.0f%%)", thr, 100 * DAYF)) +
    annotate("text", x = SEAM, y = A[Date == SEAM, n_off], vjust = -0.4, family = FAM, size = 3.3, colour = C_PRE,
             label = sprintf("2026-03-30 · %d종목(%.1f%%) → 정정 뒤 %d", A[Date == SEAM, n_off], 100 * A[Date == SEAM, frac], B[Date == SEAM, n_off])) +
    scale_fill_manual(values = c("정정 전(11-11 11:28 ~ 11-13 09:07 저장본)" = C_PRE, "정정 뒤(현행)" = C_POST),
                      breaks = c("정정 전(11-11 11:28 ~ 11-13 09:07 저장본)", "정정 뒤(현행)")) +
    scale_y_continuous(expand = expansion(mult = c(0, 0.12))) + scale_x_date(date_labels = "%y-%m") +
    labs(title = "RAWDATA 단면 — 하루 |수익| > 35% 종목 수",
         subtitle = sprintf("가격제한폭 ±30%% 밖 하루 수익. 2000년 이후 이음매 밖 최댓값 %d종목(%.1f%%).\n03-30 = 수정주가 기준 단절(분할 · 병합 비율 ×5 · ×2 · ×10 · ×0.2 …)이 하루 수익으로 들어간 날.\n정정 = 배율 정정 280종목 · 미측정 처리 82종목(정수배로 특정 안 되는 단절).",
                         out_max$mx, 100 * out_max$fx),
         x = NULL, y = "종목 수", caption = "출처: RAWDATA 정정 전 백업(.cache/rawdata_pre_seamguard_20261113.parquet) · 정정 뒤 정본(.cache/RAWDATA.parquet)\n문턱: seam_guard_config.json(35%) · rawdata_seam_audit_config.json(경보 2%)") +
    th()
  charts[[length(charts) + 1L]] <- list(file = save_png(g1, "c1_rawdata_cross_section.png", 4.6),
    caption = sprintf("RAWDATA 하루 |수익|>35%% 종목 수 — 03-30 %d → %d(이음매 밖 최댓값 %d)", A[Date == SEAM, n_off], B[Date == SEAM, n_off], out_max$mx))
}

## ---- 2. P1R03 15칸 — 03-30 하루 수익 전 · 뒤 -------------------------------------------------------
D2 <- M[is.finite(d_old)][order(-d_old)]
D2[, lab := factor(name, levels = rev(name))]
bench <- D2$bench_d[1]
g2 <- ggplot(D2) +
  geom_vline(xintercept = bench, colour = C_BENCH, linetype = "22") +
  geom_segment(aes(x = d_old, xend = d_new, y = lab, yend = lab), colour = GRID, linewidth = 1.6, na.rm = TRUE) +
  geom_point(aes(x = d_old, y = lab, colour = "수리 전(11-13 06:43 측정)"), size = 2.6) +
  geom_point(aes(x = d_new, y = lab, colour = "수리 뒤(재측정)"), size = 2.6, na.rm = TRUE) +
  geom_text(aes(x = pmax(d_old, d_new, na.rm = TRUE), y = lab, label = sprintf("%s → %s", pct(d_old), pct(d_new))),
            hjust = -0.12, family = FAM, size = 3, colour = INK2) +
  annotate("text", x = bench, y = nrow(D2) + 0.55, label = sprintf("KOSPI200 %s", pct(bench)), hjust = -0.08, family = FAM, size = 3, colour = C_BENCH) +
  scale_colour_manual(values = c("수리 전(11-13 06:43 측정)" = C_PRE, "수리 뒤(재측정)" = C_POST),
                      breaks = c("수리 전(11-13 06:43 측정)", "수리 뒤(재측정)")) +
  scale_y_discrete(expand = expansion(add = c(0.6, 1.1))) +
  scale_x_continuous(labels = function(x) sprintf("%+.0f%%", 100 * x), expand = expansion(mult = c(0.05, 0.35))) +
  labs(title = "P1R03 엔진 15 — 2026-03-30 하루 순수익",
       subtitle = "25종 동일가중 롱온리에서 하루 +75% 는 나올 수 없다 — 보유 종목의 분할 · 병합 비율이 수익으로 잡힌 값.\n수리 뒤 = 같은 사양 · 같은 정본 측정기로 재측정\n(정정된 RAWDATA · FF 요인 · 당월 팩터 DB · IC 원장 · 결합용 뷰).",
       x = "하루 순수익", y = NULL,
       caption = "출처: 각 측정 산출물 03_period_returns.csv · 05_benchmark_returns.csv\n수리 전 = P1R03 results · 수리 뒤 = P1R03 remeasure_seam_20261113/results") + th()
charts[[length(charts) + 1L]] <- list(file = save_png(g2, "c2_p1r03_seam_day.png", 5.8),
  caption = sprintf("P1R03 03-30 하루 수익 — 성장 %s → %s · 국면 %s → %s", pct(M[code == "FGROW", d_old]), pct(M[code == "FGROW", d_new]),
                    pct(M[code == "FREGI", d_old]), pct(M[code == "FREGI", d_new])))

## ---- 3. 핵심 5엔진 NAV 전 · 뒤 (2022-07 ~) ----------------------------------------------------------
nav_of <- function(a, kind, c) {
  if (is.na(a)) return(NULL)
  x <- fread(file.path(a, "02_nav.csv"), select = c("date", "nav_net")); x[, date := as.Date(date)]
  x <- x[date >= as.Date("2022-07-01")]; x[, nav := nav_net / nav_net[1]]
  x[, `:=`(kind = kind, name = CAT[[c]])][]
}
N3 <- rbindlist(lapply(KEY5, function(c) rbind(nav_of(M[code == c, art_old], "수리 전", c), nav_of(M[code == c, art_new], "수리 뒤", c))))
if (nrow(N3)) {
  bn <- fread(file.path(M[code == "FGROW", art_old], "05_benchmark_returns.csv"), select = c("date", "benchmark_nav"))
  bn[, date := as.Date(date)]; bn <- bn[date >= as.Date("2022-07-01")]; bn[, nav := benchmark_nav / benchmark_nav[1]]
  BN <- rbindlist(lapply(KEY5, function(c) copy(bn)[, `:=`(kind = "KOSPI200", name = CAT[[c]])]))
  N3[, name := factor(name, levels = CAT[KEY5])]; BN[, name := factor(name, levels = CAT[KEY5])]
  g3 <- ggplot() +
    annotate("rect", xmin = as.Date("2023-01-01"), xmax = max(N3$date), ymin = 0, ymax = Inf, fill = TEST_FILL, alpha = 0.5) +   # 0 → 로그 축 −∞(바닥까지 음영 · -Inf 는 변환에서 NaN 이 돼 그려지지 않는다)
    geom_vline(xintercept = SEAM, colour = C_PRE, linewidth = 0.3, linetype = "22") +
    geom_line(data = BN, aes(date, nav, colour = kind), linewidth = 0.4) +
    geom_line(data = N3, aes(date, nav, colour = kind), linewidth = 0.55) +
    facet_wrap(~name, ncol = 1, scales = "free_y") +
    scale_y_log10(labels = function(x) sprintf("%.1f", x)) + scale_x_date(date_labels = "%y") +
    scale_colour_manual(values = c("수리 전" = C_PRE, "수리 뒤" = C_POST, "KOSPI200" = C_BENCH), breaks = c("수리 전", "수리 뒤", "KOSPI200")) +
    labs(title = "핵심 5엔진 — 순자산(2022-07 = 1 · 로그)",
         subtitle = "회색 = OOS(2023-01~). 점선 = 2026-03-30. 수리 전 곡선은 그날 하루에 계단처럼 뛴다(보유 이음매 종목의 비율 ×5 등).",
         x = NULL, y = NULL, caption = "출처: 각 산출물 02_nav.csv(nav_net) · 05_benchmark_returns.csv(benchmark_nav)") + th(11)
  charts[[length(charts) + 1L]] <- list(file = save_png(g3, "c3_p1r03_nav_key5.png", 8.6),
    caption = "핵심 5엔진(성장 · 국면 · 기술적 · 유동성 · 위험) 순자산 — 수리 전 03-30 계단 제거")
}

## ---- 4. 전기간 · OOS Calmar 전 · 뒤 + 등급 ---------------------------------------------------------
L4 <- rbind(M[, .(name, code, k = "전기간 Calmar", old = calmar_old, new = calmar_new)],
            M[, .(name, code, k = "OOS(2023-01~) Calmar", old = tw_old, new = tw_new)])
L4 <- L4[is.finite(old) | is.finite(new)]
M[, ylab := sprintf("%s  %s→%s", name, ifelse(is.na(g_old), "–", g_old), ifelse(is.na(g_new), "–", g_new))]
ordn <- M[order(-pmax(calmar_new, calmar_old, na.rm = TRUE))]$ylab
L4 <- merge(L4, M[, .(code, ylab)], by = "code")
L4[, lab := factor(ylab, levels = rev(ordn))]; L4[, k := factor(k, levels = c("전기간 Calmar", "OOS(2023-01~) Calmar"))]
btw <- M$btw[is.finite(M$btw)][1]
g4 <- ggplot(L4) +
  geom_segment(aes(x = old, xend = new, y = lab, yend = lab), colour = GRID, linewidth = 1.5, na.rm = TRUE) +
  geom_point(aes(x = old, y = lab, colour = "수리 전"), size = 2.3, na.rm = TRUE) +
  geom_point(aes(x = new, y = lab, colour = "수리 뒤"), size = 2.3, na.rm = TRUE) +
  geom_vline(data = data.frame(k = factor("OOS(2023-01~) Calmar", levels = levels(L4$k)), v = btw), aes(xintercept = v),
             colour = C_BENCH, linetype = "22", na.rm = TRUE) +
  facet_wrap(~k, nrow = 1, scales = "free_x") +
  scale_colour_manual(values = c("수리 전" = C_PRE, "수리 뒤" = C_POST), breaks = c("수리 전", "수리 뒤")) +
  labs(title = "P1R03 엔진 15 — Calmar 수리 전 vs 후",
       subtitle = sprintf("행 이름 옆 = 권위 등급(수리 전→후). OOS 점선 = 같은 OOS 구간 KOSPI200 Calmar %.2f(등급 v3.4 OOS 관문).\nIS(~2022-12) 수익은 수리 전후 같다 — 03-30 은 OOS 안이다.", btw),
       x = NULL, y = NULL, caption = "출처: 각 측정 산출물 authoritative_remeasure.json(essence.calmar · grade_v3.oos.calmar_tw · bench_calmar_tw · essence_grade)") +
  th(11)
charts[[length(charts) + 1L]] <- list(file = save_png(g4, "c4_p1r03_calmar_grade.png", 6.2, 8.4),
  caption = "P1R03 15엔진 전기간 · OOS Calmar 와 등급 — 수리 전 → 뒤")

cat(toJSON(lapply(charts, function(z) list(file = gsub("\\\\", "/", z$file), caption = z$caption)), auto_unbox = TRUE), "\n")
