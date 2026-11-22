## 06_measure_latent.R — 단계 4 잠재팩터 묶음을 측정한다.
##   묶음 목록(--manifest)의 항목은 두 종류다.
##     kind = "score"   종목 기대수익 점수 → 다른 팩터와 같은 방식(전 종목 5분위 · 05_measure_set.R 과 같은 함수)으로 잰다
##     kind = "weights" 잠재팩터의 종목 비중(롱숏) → 그 비중대로 든 포트폴리오의 일별 수익을 Return.portfolio 로 만들어 잰다
##   모형 설명력(표본 밖 전체 R² · 예측 R²)과 팩터 수는 생성기가 남긴 기록(--logs 의 json 들)에서 읽어 요약에 싣는다.
##   실행: Rscript run/06_measure_latent.R --manifest=<json> --set=<이름> --stage=<단계 키> [--from=0.9 --to=1 --label=<머리말> --logs=<json,json>]
here <- function() {   # 이 스크립트가 든 폴더의 위 폴더(연구 폴더). 경로 정규화 함수는 쓰지 않는다 — 구분자만 맞춘다
  a <- commandArgs(FALSE); f <- gsub("\\\\", "/", sub("^--file=", "", a[grepl("^--file=", a)])[1])
  if (!grepl("^([A-Za-z]:)?/", f)) f <- file.path(getwd(), f)
  dirname(dirname(f))
}
D <- here()
for (f in c("aif_common.R", "aif_factor_perf.R", "aif_status.R", "aif_charts.R", "aif_report.R")) source(file.path(D, "R", f))
A <- commandArgs(TRUE); arg <- function(k, d = NULL) { v <- sub(paste0("^--", k, "="), "", A[grepl(paste0("^--", k, "="), A)])[1]; if (is.na(v)) d else v }
root <- aif_root(); cfg <- aif_cfg(root); aif_low_priority(); setwd(root)
man <- fromJSON(arg("manifest"), simplifyVector = FALSE); SET <- arg("set"); STAGE <- arg("stage"); LABEL <- arg("label", "잠재팩터")
PART <- c(as.numeric(arg("from", "0")), as.numeric(arg("to", "1")))
is_w <- vapply(man$factors, function(f) identical(f$kind, "weights"), TRUE); facs <- man$factors[!is_w]; wfacs <- man$factors[is_w]
OUTD <- aif_results(SET, "charts", root = root, cfg = cfg); dir.create(OUTD, recursive = TRUE, showWarnings = FALSE)
aif_stage_begin(STAGE, unit_total = length(facs) + length(wfacs) + 3L, unit_name = "팩터", part_from = PART[1], part_to = PART[2], threads = cfg$resources$jobs$perf$threads, root = root, cfg = cfg)
M <- aif_market(root, cfg); Rx <- aif_rx(M)
ref <- list(stats = fread(aif_out("perf", "_reference", "stats.csv", root = root, cfg = cfg), encoding = "UTF-8"),
            daily = as.data.table(read_parquet(aif_out("perf", "_reference", "daily.parquet", root = root, cfg = cfg))))
fp_of <- function(src) sprintf("%s_%s", format(file.mtime(src), "%Y%m%d%H%M%S"), file.size(src))
fresh <- function(dn, fp) file.exists(dn) && identical(fromJSON(dn)$input_fp, fp) && identical(as.integer(fromJSON(dn)$measurer_version), AIF_MEASURER_VERSION)
panel <- function(f) aif_score_matrix(as.data.table(read_parquet(f$path, col_select = c("Date", "Ticker", "Raw_Value"))), M, direction = 1)

## ① 종목 점수 팩터 — 다른 팩터와 같은 측정
res <- list(); labels <- list(); S_all <- list(); u <- 0L
for (f in facs) {
  fp <- fp_of(f$path); labels[[f$id]] <- f$id; S <- panel(f); S_all[[f$id]] <- S
  dn <- file.path(aif_perf_dir(SET, f$id, root = root, cfg = cfg), "done.json")
  if (fresh(dn, fp)) res[[f$id]] <- aif_perf_load(SET, f$id, root = root, cfg = cfg) else {
    aif_status_set(detail = sprintf("%s 측정 중", f$id), root = root, cfg = cfg)
    res[[f$id]] <- aif_measure_factor(f$id, S, M, Rx, cfg, all_quantiles = TRUE)
    aif_perf_save(SET, res[[f$id]], meta = list(input = f$path, input_fp = fp, measurer_version = AIF_MEASURER_VERSION, method = f$method, desc = f$desc), root = root, cfg = cfg)
  }
  aif_chart_factor(res[[f$id]], ref, cfg, f$id, file.path(OUTD, sprintf("factor_%s.png", f$id)), note = sprintf("%s · %s · 점선 = IS/OOS 경계", f$method, f$desc))
  u <- u + 1L; aif_stage_unit(u, sprintf("%s 측정 끝", f$id), root = root, cfg = cfg)
}
tab <- aif_perf_rows(res, ref, cfg)
aif_write_atomic(aif_results(SET, "factors_perf.csv", root = root, cfg = cfg), function(p) fwrite(tab, p))
aif_write_atomic(aif_results(SET, "factors_ic.csv", root = root, cfg = cfg), function(p) fwrite(rbindlist(lapply(res, function(r) r$ic)), p))
imgs <- aif_perf_tables(tab, ref, cfg, OUTD, paste(LABEL, "종목 점수"))
grids <- c(aif_chart_grid(res, labels, ref, cfg, file.path(OUTD, "grid"), what = "top"), aif_chart_grid(res, labels, ref, cfg, file.path(OUTD, "grid"), what = "ls"))
OV <- aif_overlap(S_all, M, root, cfg); rm(S_all)
aif_write_atomic(aif_results(SET, "overlap_with_existing.csv", root = root, cfg = cfg), function(p) fwrite(OV, p))
CT <- aif_compare_tables(res, M, cfg, root, OUTD, label = LABEL, overlap = OV)
aif_write_atomic(aif_results(SET, "common_period_perf.csv", root = root, cfg = cfg), function(p) fwrite(CT$CMN[kind != "개별 팩터"], p))
u <- u + 1L; aif_stage_unit(u, "종목 점수 팩터 비교표", root = root, cfg = cfg)

## ② 잠재팩터 포트폴리오(비중 표) — 비중대로 든 롱숏 포트폴리오
wres <- list()
for (f in wfacs) {
  fp <- fp_of(f$path); d <- aif_perf_dir(SET, f$id, root = root, cfg = cfg); dn <- file.path(d, "done.json")
  if (fresh(dn, fp)) {
    wres[[f$id]] <- list(id = f$id, stats = fread(file.path(d, "stats.csv")), daily = as.data.table(read_parquet(file.path(d, "daily.parquet"))), misc = fread(file.path(d, "misc.csv")))
  } else {
    aif_status_set(detail = sprintf("%s 측정 중", f$id), root = root, cfg = cfg)
    W <- panel(f); if (!any(is.finite(W))) { u <- u + 1L; next }
    wres[[f$id]] <- aif_measure_weights(f$id, W, M, Rx, cfg); rm(W)
    dir.create(d, recursive = TRUE, showWarnings = FALSE)
    aif_write_atomic(file.path(d, "daily.parquet"), function(p) write_parquet(wres[[f$id]]$daily, p))
    aif_write_atomic(file.path(d, "stats.csv"), function(p) fwrite(wres[[f$id]]$stats, p))
    aif_write_atomic(file.path(d, "misc.csv"), function(p) fwrite(wres[[f$id]]$misc, p))
    aif_write_json(list(id = f$id, set = SET, input = f$path, input_fp = fp, measurer_version = AIF_MEASURER_VERSION, kind = "weights", method = f$method, desc = f$desc), dn)
  }
  u <- u + 1L; aif_stage_unit(u, sprintf("%s 측정 끝", f$id), root = root, cfg = cfg)
}
wimgs <- character(0); WT <- NULL
if (length(wres)) {
  WT <- rbindlist(lapply(wres, function(r) r$stats), fill = TRUE)
  aif_write_atomic(aif_results(SET, "latent_portfolios_perf.csv", root = root, cfg = cfg), function(p) fwrite(WT, p))
  w <- merge(WT[period == "ALL"], dcast(WT[period != "ALL"], factor ~ period, value.var = "SR"), by = "factor", all.x = TRUE, sort = FALSE)
  for (cn in c("IS", "OOS")) if (!cn %in% names(w)) set(w, j = cn, value = NA_real_)
  mi <- rbindlist(lapply(wres, function(r) r$misc), fill = TRUE)
  w <- merge(w, mi[, .(factor, names_avg, gross_avg, net_avg, first_signal)], by = "factor", all.x = TRUE, sort = FALSE)
  o <- w[, .(`잠재팩터 포트폴리오` = factor, `첫 신호` = substr(first_signal, 1L, 7L), CAGR = aif_pct(CAGR), SD = aif_pct(SD), SR = aif_num(SR), MDD = aif_pct(MDD),
             `SR(IS)` = aif_num(IS), `SR(OOS)` = aif_num(OOS), `총 노출` = aif_pct(gross_avg, 0), `순 노출` = aif_pct(net_avg, 0), `종목 수` = aif_num(names_avg, 0))]
  bmw <- { d0 <- min(vapply(wres, function(r) as.character(min(r$daily$Date)), "")); D <- ref$daily[Date >= as.Date(d0)]; i <- match(D$Date, M$dates)
    z <- aif_stats(D$bm, D$Date, M$bm[i], M$rf[i], cfg, ls = TRUE); if (is.null(z)) NULL else data.table(`잠재팩터 포트폴리오` = cfg$measure$benchmark_label, `첫 신호` = substr(d0, 1L, 7L),
      CAGR = aif_pct(z$CAGR), SD = aif_pct(z$SD), SR = aif_num(z$SR), MDD = aif_pct(z$MDD), `SR(IS)` = "", `SR(OOS)` = "", `총 노출` = "+100%", `순 노출` = "+100%", `종목 수` = "") }
  wimgs <- aif_table_png(rbind(bmw, o), file.path(OUTD, "table_latent_portfolios"), sprintf("%s 포트폴리오 성과 — 잠재팩터의 종목 비중대로 든 포트폴리오(거래비용 전)", LABEL),
                         note = paste0("비중 = 모형이 낸 잠재팩터별 종목 비중 그대로(노출 1 단위당 수익 · 월말에 다시 맞춤)\n",
                                       "총 노출 = 롱 · 숏 절댓값의 합 · 순 노출 = 롱 − 숏(100% 에 가까우면 시장 전체에 가까운 팩터)\n",
                                       "SR 은 무위험 수익을 빼지 않은 값(벤치마크 줄도 같다)\n잠재팩터는 해마다 다시 추정되므로, 같은 번호라도 해가 바뀌면 다른 팩터일 수 있다"))
  nmw <- "잠재팩터 포트폴리오"; bl0 <- cfg$measure$benchmark_label
  P <- rbindlist(lapply(names(wres), function(id) { D <- merge(wres[[id]]$daily, ref$daily[, .(Date, bm)], by = "Date", all.x = TRUE); st <- wres[[id]]$stats[period == "ALL"]
    ttl <- sprintf("%s\nCAGR %s · SR %s\nMDD %s", id, aif_pct(st$CAGR), aif_num(st$SR), aif_pct(st$MDD))
    rbind(data.table(f = ttl, Date = D$Date, s = nmw, v = aif_cum(D$ls)), data.table(f = ttl, Date = D$Date, s = bl0, v = aif_cum(D$bm))) }))
  P[, f := factor(f, levels = unique(f))]; P[, s := factor(s, levels = c(nmw, bl0))]
  g <- ggplot(P, aes(Date, v, colour = s)) + geom_line(linewidth = 0.45) + facet_wrap(~f, ncol = 3, scales = "free_y") + scale_colour_manual(values = setNames(c(AIF_COL[["ls"]], AIF_COL[["bench"]]), c(nmw, bl0))) +
    geom_vline(xintercept = as.Date(cfg$measure$is_end), linetype = "dashed", colour = "#888888", linewidth = 0.3) + scale_y_log10(labels = label_number(accuracy = NULL)) +
    labs(title = sprintf("%s 포트폴리오 누적수익 vs %s", LABEL, bl0), subtitle = "로그축 · 점선 = IS/OOS 경계(2022-12-31) · 거래비용 전") + aif_theme(10) + theme(strip.text = element_text(size = 9, hjust = 0))
  wimgs <- c(wimgs, aif_png(g, file.path(OUTD, "grid_latent_portfolios.png"), w = 1080, h = 240 + 330 * ceiling(length(wres) / 3)))
}
u <- u + 1L; aif_stage_unit(u, "잠재팩터 포트폴리오 표", root = root, cfg = cfg)

## ③ 요약(숫자는 표와 생성기 기록에서만)
C <- CT$CMN; bl <- cfg$measure$benchmark_label; g2 <- function(kk, port, per) C[kind %in% kk & portfolio == port & period == per]
num <- function(x, d = 2) formatC(x, format = "f", digits = d); best <- function(x) x[which.max(SR)]
bm <- g2("벤치마크", "top", "ALL"); tot <- C[factor == "CAT_TOTAL" & period == "ALL"]; nt <- best(g2(LABEL, "top", "ALL")); nl <- best(g2(LABEL, "ls", "ALL")); rk <- CT$ranks
logs <- strsplit(arg("logs", ""), ",", fixed = TRUE)[[1]]; logs <- logs[nzchar(logs) & file.exists(logs)]
r2 <- vapply(logs, function(p) { x <- fromJSON(p, simplifyVector = FALSE); ks <- vapply(x$retrains, function(z) as.numeric(z$K), 0)
  sprintf("%s 전체 R² %s · 예측 R² %s · 팩터 수 %d~%d", toupper(x$model), num(100 * as.numeric(x$r2_oos$total_r2 %||% NA), 1), num(100 * as.numeric(x$r2_oos$pred_r2 %||% NA), 2), as.integer(min(ks)), as.integer(max(ks))) }, "")
lines <- c(sprintf("%s — 종목 점수 팩터 %d개 · 잠재팩터 포트폴리오 %d개 측정(거래비용 전) · 공통 기간 %s ~", LABEL, length(res), length(wres), format(CT$d0, "%Y-%m")),
           sprintf("종목 점수 · 상위 분위 롱온리 SR — %s %s · 기존 전체 합성 %s · 이 묶음 최고 %s %s(기존 %d개 가운데 %d위)", bl, num(bm$SR), num(tot[portfolio == "top", SR]), nt$factor, num(nt$SR), CT$n_existing, rk[["top ALL"]][[nt$factor]]),
           sprintf("종목 점수 · 롱숏 SR — 기존 전체 합성 %s · 이 묶음 최고 %s %s(%d위)", num(tot[portfolio == "ls", SR]), nl$factor, num(nl$SR), rk[["ls ALL"]][[nl$factor]]),
           if (!is.null(WT)) { b <- WT[period == "ALL"][order(-SR)]; sprintf("잠재팩터 포트폴리오 SR 상위 — %s", paste(sprintf("%s %s", head(b$factor, 4), num(head(b$SR, 4))), collapse = " · ")) } else NULL,
           if (length(r2)) sprintf("모형 설명력(표본 밖 · %%) — %s", paste(r2, collapse = " / ")) else NULL)
charts <- c(imgs, CT$images, wimgs, grids, vapply(names(res), function(id) file.path(OUTD, sprintf("factor_%s.png", id)), ""))
cn <- c(rep(paste(LABEL, "종목 점수 성과표"), length(imgs)), rep("공통 기간 비교 · 순위", length(CT$images)), rep("잠재팩터 포트폴리오", length(wimgs)), rep("P/L 격자", length(grids)),
        sprintf("%s — P/L · 낙폭 · 5분위 · 롱숏 · 누적 IC", names(res)))
aif_write_json(list(at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"), title = sprintf("%s 성과", LABEL), lines = as.list(lines), charts = as.list(unname(charts)), chart_names = as.list(cn)),
               aif_out(sprintf("stage_summary_%s.json", SET), root = root, cfg = cfg))
aif_write_atomic(aif_results(SET, "SUMMARY.md", root = root, cfg = cfg), function(p) writeLines(c(sprintf("# %s — 결과 요약", LABEL), "", sprintf("만든 때: %s", format(Sys.time(), "%Y-%m-%d %H:%M")), "", paste0("- ", lines)), p, useBytes = TRUE))
aif_stage_end(done = identical(arg("final", "1"), "1"), root = root, cfg = cfg)
aif_log("%s — 종목 점수 %d개 · 잠재팩터 포트폴리오 %d개 · 그림 %d장", SET, length(res), length(wres), length(charts)); cat(paste0(lines, collapse = "\n"), "\n")
