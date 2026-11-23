## 08_followup_diag.R — 후속 연구(동적 팩터 배분) 계획의 근거가 되는 진단. 새로 재지 않는다 — 저장된 일별 수익(.cache/aif_research/perf/)만 읽는다.
##   ★IS(~2022-12)만 본다. 2023-01 이후는 후속 연구의 시험 구간으로 남긴다(국면 · 타이밍 규칙을 그 구간을 보고 정하지 않기 위해서다).
##   ① 팩터 수익의 겹침 — 신규 팩터 · 잠재팩터 포트폴리오 · 기존 카테고리 합성의 월별 롱숏 수익 상관과 묶음 수
##   ② 롱 쪽 · 숏 쪽 기여 — 상위 분위 − 유니버스 동일가중 / 유니버스 동일가중 − 하위 분위
##   ③ 국면별 성과 — 월말에 알 수 있던 시장 상태(추세 · 변동성 · 대형주 우위)로 다음 달을 나눠 본 롱숏 수익과 롱온리 초과수익
##   ④ 팩터 모멘텀 — 지난 12개월 롱숏 수익의 부호로 다음 달을 나눠 본 수익
##   산출: results/followup/diag_*.csv · charts/diag_*.png      실행: Rscript run/08_followup_diag.R
here <- function() {   # 이 스크립트가 든 폴더의 위 폴더(연구 폴더). 경로 정규화 함수는 쓰지 않는다 — 구분자만 맞춘다
  a <- commandArgs(FALSE); f <- gsub("\\\\", "/", sub("^--file=", "", a[grepl("^--file=", a)])[1])
  if (!grepl("^([A-Za-z]:)?/", f)) f <- file.path(getwd(), f)
  dirname(dirname(f))
}
D <- here()
for (f in c("aif_common.R", "aif_factor_perf.R", "aif_status.R", "aif_charts.R")) source(file.path(D, "R", f))
root <- aif_root(); cfg <- aif_cfg(root); aif_low_priority(); setwd(root)
RES <- function(...) aif_results("followup", ..., root = root, cfg = cfg); CACHE <- function(...) aif_out(..., root = root, cfg = cfg)
dir.create(RES("charts"), recursive = TRUE, showWarnings = FALSE)
IS_END <- as.Date(cfg$measure$is_end); bl <- cfg$measure$benchmark_label

## ── 일별 수익 모으기 ─────────────────────────────────────────────────────────
sets <- c("new", "stage3_enumerate", "stage3_fboost", "stage3_nn", "stage3_tree", "stage3_gp", "stage4_latent", "stage4_cae")
TOP <- list(); BOT <- list(); LS <- list(); kind <- character(0)
for (s in sets) { d <- CACHE("perf", s); if (!dir.exists(d)) next
  for (id in list.dirs(d, full.names = FALSE, recursive = FALSE)) { if (!file.exists(file.path(d, id, "done.json"))) next
    m <- fromJSON(file.path(d, id, "done.json"), simplifyVector = FALSE); x <- as.data.table(read_parquet(file.path(d, id, "daily.parquet")))
    LS[[id]] <- x[, .(Date, r = ls)]
    if (identical(m$kind, "weights")) kind[[id]] <- "잠재팩터 포트폴리오" else { TOP[[id]] <- x[, .(Date, r = top)]; BOT[[id]] <- x[, .(Date, r = bottom)]; kind[[id]] <- "신규 팩터" } } }
DBL <- as.data.table(read_parquet(CACHE("perf", "db", "daily_ls.parquet"))); DBT <- as.data.table(read_parquet(CACHE("perf", "db", "daily_top.parquet")))
for (id in grep("^CAT_", names(DBL), value = TRUE)) { LS[[id]] <- DBL[, .(Date, r = get(id))]; TOP[[id]] <- DBT[, .(Date, r = get(id))]; kind[[id]] <- "기존 카테고리 합성" }
ref <- as.data.table(read_parquet(CACHE("perf", "_reference", "daily.parquet")))
monthly <- function(x) { x <- x[is.finite(r)]; if (!nrow(x)) return(NULL)                    # 일별 → 달별 누적 수익(측정기와 같은 함수)
  z <- xts::apply.monthly(xts(x$r, order.by = x$Date), PerformanceAnalytics::Return.cumulative, geometric = TRUE); data.table(ym = format(index(z), "%Y-%m"), r = as.numeric(z)) }
wide <- function(L) { W <- Reduce(function(a, b) merge(a, b, by = "ym", all = TRUE), lapply(names(L), function(id) { z <- monthly(L[[id]]); if (is.null(z)) NULL else setnames(z, "r", id) })); setorder(W, ym); W }
MLS <- wide(LS); MTOP <- wide(TOP); MBOT <- wide(BOT)
MREF <- merge(setnames(monthly(ref[, .(Date, r = bm)]), "r", "bm"), setnames(monthly(ref[, .(Date, r = universe_ew)]), "r", "ew"), by = "ym")
is_m <- function(W) W[ym <= format(IS_END, "%Y-%m")]
cum12 <- function(v) as.numeric(PerformanceAnalytics::Return.cumulative(v, geometric = TRUE))   # 창 누적 수익(표준 함수)
aif_log("달별 수익 — 롱숏 %d계열 · 롱온리 %d계열 · %s ~ %s (IS 끝 %s)", ncol(MLS) - 1L, ncol(MTOP) - 1L, MLS$ym[1], MLS$ym[nrow(MLS)], format(IS_END, "%Y-%m"))

## ── ① 겹침(IS) ───────────────────────────────────────────────────────────────
ids <- setdiff(names(MLS), "ym"); X <- as.matrix(is_m(MLS)[ym >= "2008-02", ..ids]); C <- cor(X, use = "pairwise.complete.obs")
hc <- hclust(as.dist(1 - C), method = "average"); cl <- cutree(hc, h = 0.5)                 # 상관 0.5 를 넘게 묶이는 것끼리 한 묶음
CL <- data.table(factor = ids, kind = kind[ids], cluster = cl[ids])
CL[, mean_corr_in_cluster := vapply(seq_len(.N), function(i) { j <- which(cl == cl[ids[i]] & ids != ids[i]); if (length(j)) mean(C[ids[i], ids[j]]) else NA_real_ }, 0)]
CL[, nearest_category := vapply(factor, function(f) { cc <- C[f, grep("^CAT_", ids, value = TRUE)]; cc <- cc[names(cc) != f]; sprintf("%s(%+.2f)", sub("^CAT_", "", names(cc)[which.max(abs(cc))]), cc[which.max(abs(cc))]) }, "")]
setorder(CL, cluster, kind, factor); fwrite(CL, RES("diag_clusters.csv"), bom = TRUE); fwrite(data.table(factor = ids, round(C, 3)), RES("diag_corr_ls.csv"), bom = TRUE)
nn <- CL[kind != "기존 카테고리 합성", factor]; Cn <- C[nn, nn]
aif_log("① 겹침 — 계열 %d개가 묶음 %d개 · 신규(팩터 + 잠재 포트폴리오) %d개는 묶음 %d개 · 신규끼리 평균 상관 %.2f · 신규 종목 점수 팩터끼리 %.2f", length(ids), length(unique(cl)), length(nn), length(unique(cl[nn])),
        mean(Cn[upper.tri(Cn)], na.rm = TRUE), { s <- CL[kind == "신규 팩터", factor]; z <- C[s, s]; mean(z[upper.tri(z)], na.rm = TRUE) })
o <- hc$order; H <- as.data.table(as.table(C[o, o])); setnames(H, c("a", "b", "v")); H[, a := factor(a, levels = ids[o])]; H[, b := factor(b, levels = rev(ids[o]))]
g <- ggplot(H, aes(a, b, fill = v)) + geom_tile() + scale_fill_gradient2(low = "#2166ac", mid = "white", high = "#b2182b", midpoint = 0, limits = c(-1, 1), name = "상관") +
  labs(title = "팩터 롱숏 수익의 상관 — 신규 팩터 · 잠재팩터 포트폴리오 · 기존 카테고리 합성", subtitle = sprintf("달별 수익 · IS(2008-02 ~ %s) · 묶음 순서로 정렬", format(IS_END, "%Y-%m")), x = NULL, y = NULL) +
  aif_theme(9) + theme(axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.5, size = 6.5), axis.text.y = element_text(size = 6.5), legend.position = "right")
aif_png(g, RES("charts", "diag_corr.png"), w = 1300, h = 1250)

## ── ② 롱 쪽 · 숏 쪽 기여(IS · 연율 산술평균) ─────────────────────────────────
sc <- setdiff(names(MBOT), "ym"); LEG <- rbindlist(lapply(sc, function(id) { z <- merge(merge(is_m(MTOP)[, .(ym, t = get(id))], is_m(MBOT)[, .(ym, b = get(id))], by = "ym"), MREF, by = "ym")[is.finite(t) & is.finite(b)]
  data.table(factor = id, months = nrow(z), long_excess = 12 * mean(z$t - z$ew), short_contrib = 12 * mean(z$ew - z$b), top_vs_bm = 12 * mean(z$t - z$bm), ew_vs_bm = 12 * mean(z$ew - z$bm)) }))
LEG[, short_share := short_contrib / (long_excess + short_contrib)]; fwrite(LEG, RES("diag_legs.csv"), bom = TRUE)
aif_log("② 다리 기여 — 신규 팩터 %d개 · 숏 쪽 비중 중앙값 %.0f%% (범위 %.0f%% ~ %.0f%%)", nrow(LEG), 100 * median(LEG$short_share), 100 * min(LEG$short_share), 100 * max(LEG$short_share))

## ── ③ 국면별 성과(IS) — 월말 t 에 알 수 있던 상태로 t+1 달을 나눈다 ─────────────
rb <- ref[is.finite(bm)]; setorder(rb, Date); rb[, ym := format(Date, "%Y-%m")]
vol60 <- frollapply(rb$bm, 60L, sd) * sqrt(cfg$measure$days_per_year); ST <- rb[, .(vol = vol60[.I[.N]]), by = ym]
ST <- merge(ST, MREF, by = "ym"); setorder(ST, ym)
ST[, bm12 := frollapply(bm, 12L, cum12)]; ST[, ew12 := frollapply(ew, 12L, cum12)]   # 상태 변수(지난 12개월 수익) — 성과 지표가 아니다
ST[, volmed := vapply(seq_len(.N), function(i) if (i < 24L) NA_real_ else median(vol[seq_len(i)], na.rm = TRUE), 0)]                  # 그때까지의 중앙값(확장 창)
ST[, `:=`(trend = fifelse(bm12 > 0, "지수 상승 추세", "지수 하락 추세"), volst = fifelse(vol > volmed, "변동성 높음", "변동성 낮음"), size = fifelse(bm12 > ew12, "대형주 우위", "중소형주 우위"))]
ST[, nxt := shift(ym, -1L)]                                                                    # 상태는 t 말 · 수익은 t+1 달
reg_tab <- function(M, ids, what, bench = NULL) rbindlist(lapply(c("trend", "volst", "size"), function(sv) rbindlist(lapply(ids, function(id) {
  z <- merge(ST[!is.na(get(sv)) & !is.na(nxt), .(ym = nxt, state = get(sv))], is_m(M)[, .(ym, r = get(id))], by = "ym")
  if (!is.null(bench)) z <- merge(z, MREF[, .(ym, b = get(bench))], by = "ym")[, r := r - b]
  z[is.finite(r), .(factor = id, what = what, axis = sv, months = .N, mean_ann = 12 * mean(r), t = mean(r) / (sd(r) / sqrt(.N)), hit = mean(r > 0)), by = state] }))))
rep_ls <- intersect(c("NN_1M", "NN_12M", "LAT_RPPCA", "LAT_IPCA", "LAT_CAE", "LAT_PCA", "ENUM_EB20", "FBOOST_C20", "TREE_1M", "ENS_1M", "GP3_EXP", "LAT_RPPCA_F2", "LAT_IPCA_F3", "LAT_CAE_F3", "LAT_CAE_F2",
                      grep("^CAT_", ids, value = TRUE)), ids)
REG <- rbind(reg_tab(MLS, rep_ls, "롱숏"), reg_tab(MTOP, intersect(rep_ls, names(MTOP)), sprintf("롱온리 − %s", bl), "bm")); fwrite(REG, RES("diag_regimes.csv"), bom = TRUE)
sp <- dcast(REG, factor + what + axis ~ state, value.var = "mean_ann");
gap <- function(ax, hi, lo) { z <- sp[axis == ax]; data.table(factor = z$factor, what = z$what, axis = ax, gap = z[[hi]] - z[[lo]]) }
GAP <- rbind(gap("trend", "지수 상승 추세", "지수 하락 추세"), gap("volst", "변동성 높음", "변동성 낮음"), gap("size", "대형주 우위", "중소형주 우위")); fwrite(GAP, RES("diag_regime_gaps.csv"), bom = TRUE)
P <- REG[what == "롱숏" & factor %in% intersect(c("NN_1M", "LAT_RPPCA", "LAT_IPCA", "LAT_CAE", "ENUM_EB20", "FBOOST_C20", "LAT_RPPCA_F2", "LAT_CAE_F3", "CAT_value", "CAT_momentum", "CAT_quality", "CAT_growth", "CAT_risk", "CAT_liquidity"), ids)]
P[, axis := factor(c(trend = "지수 추세(지난 12개월)", volst = "변동성(60일 · 그때까지의 중앙값 대비)", size = "대형주 vs 중소형주(지난 12개월)")[axis], levels = c("지수 추세(지난 12개월)", "변동성(60일 · 그때까지의 중앙값 대비)", "대형주 vs 중소형주(지난 12개월)"))]
g <- ggplot(P, aes(sub("^CAT_", "합성 ", factor), mean_ann, fill = state)) + geom_col(position = position_dodge(width = 0.8), width = 0.75) + facet_wrap(~axis, ncol = 1, scales = "free_y") +
  scale_y_continuous(labels = label_percent(accuracy = 1)) + scale_fill_brewer(palette = "Set2", name = NULL) +
  labs(title = "국면별 롱숏 수익(연율) — 월말의 시장 상태로 다음 달을 나눠 본 것", subtitle = sprintf("IS(~%s)만 · 거래비용 전 · 상태는 그 달 말까지의 자료로 정한다", format(IS_END, "%Y-%m")), x = NULL, y = NULL) +
  aif_theme(10) + theme(axis.text.x = element_text(angle = 35, hjust = 1, size = 8))
aif_png(g, RES("charts", "diag_regimes.png"), w = 1200, h = 1500)
aif_log("③ 국면 — 대표 계열 %d개 · 축 3개(추세 · 변동성 · 대형주 우위)", length(rep_ls))

## ── ④ 팩터 모멘텀(IS) — 지난 12개월 롱숏 수익의 부호로 다음 달을 나눈다 ─────────
FM <- rbindlist(lapply(ids, function(id) { z <- is_m(MLS)[, .(ym, r = get(id))][is.finite(r)]; if (nrow(z) < 36L) return(NULL)
  z[, past := frollapply(r, 12L, cum12)]; z[, nx := shift(r, -1L)]; z <- z[is.finite(past) & is.finite(nx)]
  data.table(factor = id, kind = kind[[id]], months = nrow(z), share_up = mean(z$past > 0), next_after_up = 12 * mean(z[past > 0, nx]), next_after_down = if (any(z$past <= 0)) 12 * mean(z[past <= 0, nx]) else NA_real_,
             ac1 = cor(z$past, z$nx)) }))
FM[, gap := next_after_up - next_after_down]; fwrite(FM, RES("diag_factor_momentum.csv"), bom = TRUE)
aif_log("④ 팩터 모멘텀 — 계열 %d개 · '지난 12개월 수익 > 0' 뒤의 다음 달 수익이 더 높은 계열 %d개(%.0f%%) · 차이의 중앙값 연 %.1f%%p", nrow(FM), sum(FM$gap > 0, na.rm = TRUE), 100 * mean(FM$gap > 0, na.rm = TRUE), 100 * median(FM$gap, na.rm = TRUE))
aif_write_json(list(at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"), is_end = format(IS_END), series = length(ids), clusters = length(unique(cl)), new_series = length(nn), new_clusters = length(unique(cl[nn])),
                    mean_corr_new = mean(Cn[upper.tri(Cn)], na.rm = TRUE), short_share_median = median(LEG$short_share), fm_share_positive = mean(FM$gap > 0, na.rm = TRUE), fm_gap_median = median(FM$gap, na.rm = TRUE)), RES("diag_summary.json"))
