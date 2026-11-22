## 05_measure_set.R — 생성기가 낸 팩터 묶음을 측정한다(단계 3 · 4 공용).
##   입력 = 묶음 목록 json(--manifest): factors[{id, path, direction, method, desc}] — 파이썬 생성기가 쓴다
##   하는 일 = 팩터마다 측정(체크포인트) · 상세 그림 → 성과표(전기간 · IS · OOS · 롱숏) · P/L 격자 → 기존 팩터 DB 와 공통 기간 비교 · 순위 · 겹침 → 요약 json
##   실행: Rscript run/05_measure_set.R --manifest=<json> --set=<이름> --stage=<단계 키> [--from=0.8 --to=1 --label=<표 제목 머리말>]
here <- function() {   # 이 스크립트가 든 폴더의 위 폴더(연구 폴더). 경로 정규화 함수는 쓰지 않는다 — 구분자만 맞춘다
  a <- commandArgs(FALSE); f <- gsub("\\\\", "/", sub("^--file=", "", a[grepl("^--file=", a)])[1])
  if (!grepl("^([A-Za-z]:)?/", f)) f <- file.path(getwd(), f)
  dirname(dirname(f))
}
D <- here()
for (f in c("aif_common.R", "aif_factor_perf.R", "aif_status.R", "aif_charts.R", "aif_report.R")) source(file.path(D, "R", f))
A <- commandArgs(TRUE); arg <- function(k, d = NULL) { v <- sub(paste0("^--", k, "="), "", A[grepl(paste0("^--", k, "="), A)])[1]; if (is.na(v)) d else v }
root <- aif_root(); cfg <- aif_cfg(root); aif_low_priority(); setwd(root)
man <- fromJSON(arg("manifest"), simplifyVector = FALSE); SET <- arg("set"); STAGE <- arg("stage"); LABEL <- arg("label", "신규 팩터")
PART <- c(as.numeric(arg("from", "0")), as.numeric(arg("to", "1"))); facs <- man$factors
OUTD <- aif_results(SET, "charts", root = root, cfg = cfg); dir.create(OUTD, recursive = TRUE, showWarnings = FALSE)
aif_stage_begin(STAGE, unit_total = length(facs) + 3L, unit_name = "팩터", part_from = PART[1], part_to = PART[2], threads = cfg$resources$jobs$perf$threads, root = root, cfg = cfg)
M <- aif_market(root, cfg); Rx <- aif_rx(M)
ref <- list(stats = fread(aif_out("perf", "_reference", "stats.csv", root = root, cfg = cfg), encoding = "UTF-8"),
            daily = as.data.table(read_parquet(aif_out("perf", "_reference", "daily.parquet", root = root, cfg = cfg))))

res <- list(); labels <- list(); S_all <- list()
for (k in seq_along(facs)) {
  f <- facs[[k]]; src <- f$path; fp <- sprintf("%s_%s", format(file.mtime(src), "%Y%m%d%H%M%S"), file.size(src)); labels[[f$id]] <- f$id
  dt <- as.data.table(read_parquet(src, col_select = c("Date", "Ticker", "Raw_Value")))
  S <- aif_score_matrix(dt, M, direction = f$direction %||% 1); rm(dt); S_all[[f$id]] <- S
  dn <- file.path(aif_perf_dir(SET, f$id, root = root, cfg = cfg), "done.json")
  if (file.exists(dn) && identical(fromJSON(dn)$input_fp, fp) && identical(as.integer(fromJSON(dn)$measurer_version), AIF_MEASURER_VERSION)) {
    aif_log("%s — 이미 측정됨(건너뜀)", f$id); res[[f$id]] <- aif_perf_load(SET, f$id, root = root, cfg = cfg)
  } else {
    aif_status_set(detail = sprintf("%s 측정 중", f$id), root = root, cfg = cfg); t0 <- Sys.time()
    res[[f$id]] <- aif_measure_factor(f$id, S, M, Rx, cfg, all_quantiles = TRUE)
    aif_perf_save(SET, res[[f$id]], meta = list(input = f$path, input_fp = fp, measurer_version = AIF_MEASURER_VERSION, direction = f$direction %||% 1, method = f$method, desc = f$desc, match = attr(S, "match")), root = root, cfg = cfg)
    aif_log("%s — 측정 끝(%.0f초)", f$id, as.numeric(difftime(Sys.time(), t0, units = "secs")))
  }
  aif_chart_factor(res[[f$id]], ref, cfg, f$id, file.path(OUTD, sprintf("factor_%s.png", f$id)), note = sprintf("%s · %s · 점선 = IS/OOS 경계", f$method, f$desc))
  aif_stage_unit(k, sprintf("%s 측정 끝", f$id), root = root, cfg = cfg)
}
n <- length(facs)
tab <- aif_perf_rows(res, ref, cfg)
aif_write_atomic(aif_results(SET, "factors_perf.csv", root = root, cfg = cfg), function(p) fwrite(tab, p))
aif_write_atomic(aif_results(SET, "factors_ic.csv", root = root, cfg = cfg), function(p) fwrite(rbindlist(lapply(res, function(r) r$ic)), p))
aif_write_atomic(aif_results(SET, "factors_misc.csv", root = root, cfg = cfg), function(p) fwrite(rbindlist(lapply(res, function(r) r$misc), fill = TRUE), p))
imgs <- aif_perf_tables(tab, ref, cfg, OUTD, LABEL)
grids <- c(aif_chart_grid(res, labels, ref, cfg, file.path(OUTD, "grid"), what = "top"), aif_chart_grid(res, labels, ref, cfg, file.path(OUTD, "grid"), what = "ls"))
aif_stage_unit(n + 1L, "성과표 · P/L 격자", root = root, cfg = cfg)
OV <- aif_overlap(S_all, M, root, cfg); rm(S_all)
aif_write_atomic(aif_results(SET, "overlap_with_existing.csv", root = root, cfg = cfg), function(p) fwrite(OV, p))
aif_stage_unit(n + 2L, "기존 팩터와의 겹침", root = root, cfg = cfg)
CT <- aif_compare_tables(res, M, cfg, root, OUTD, label = LABEL, overlap = OV)
aif_write_atomic(aif_results(SET, "common_period_perf.csv", root = root, cfg = cfg), function(p) fwrite(CT$CMN[kind != "개별 팩터"], p))

## 요약(숫자는 표에서만) — 진행 알림의 결과 통에 실린다
C <- CT$CMN; bl <- cfg$measure$benchmark_label; g <- function(kk, port, per) C[kind %in% kk & portfolio == port & period == per]
num <- function(x, d = 2) formatC(x, format = "f", digits = d); best <- function(x) x[which.max(SR)]
bm <- g("벤치마크", "top", "ALL"); tot <- C[factor == "CAT_TOTAL" & period == "ALL"]; nt <- best(g(LABEL, "top", "ALL")); nl <- best(g(LABEL, "ls", "ALL"))
ol <- g(LABEL, "ls", "OOS")[order(-SR)]; rk <- CT$ranks
lines <- c(sprintf("%s %d개 측정(전 종목 5분위 · 거래비용 전) · 공통 기간 %s ~", LABEL, n, format(CT$d0, "%Y-%m")),
           sprintf("상위 분위 롱온리 SR — %s %s · 기존 전체 합성 %s · 이 묶음 최고 %s %s(기존 %d개 가운데 %d위)", bl, num(bm$SR), num(tot[portfolio == "top", SR]), nt$factor, num(nt$SR), CT$n_existing, rk[["top ALL"]][[nt$factor]]),
           sprintf("롱숏 SR — 기존 전체 합성 %s · 이 묶음 최고 %s %s(%d위)", num(tot[portfolio == "ls", SR]), nl$factor, num(nl$SR), rk[["ls ALL"]][[nl$factor]]),
           if (nrow(ol)) sprintf("OOS(2023-01 ~) 롱숏 SR — %s", paste(sprintf("%s %s", ol$factor, num(ol$SR)), collapse = " · ")) else NULL,
           sprintf("기존 팩터와의 겹침(최대 순위 상관) — %s", paste(sprintf("%s %s", OV$factor, num(OV$max_abs_corr)), collapse = " · ")))
charts <- c(imgs, CT$images, grids, vapply(names(res), function(id) file.path(OUTD, sprintf("factor_%s.png", id)), ""))
cn <- c(rep(paste(LABEL, "성과표"), length(imgs)), rep("공통 기간 비교 · 순위", length(CT$images)), rep("P/L 격자", length(grids)), sprintf("%s — P/L · 낙폭 · 5분위 · 롱숏 · 누적 IC", names(res)))
aif_write_json(list(at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"), title = sprintf("%s 성과", LABEL), lines = as.list(lines), charts = as.list(unname(charts)), chart_names = as.list(cn)),
               aif_out(sprintf("stage_summary_%s.json", SET), root = root, cfg = cfg))
aif_write_atomic(aif_results(SET, "SUMMARY.md", root = root, cfg = cfg), function(p) writeLines(c(sprintf("# %s — 결과 요약", LABEL), "", sprintf("만든 때: %s", format(Sys.time(), "%Y-%m-%d %H:%M")), "", paste0("- ", lines)), p, useBytes = TRUE))
aif_stage_unit(n + 3L, "비교표 · 요약", root = root, cfg = cfg)
aif_stage_end(done = identical(arg("final", "1"), "1"), root = root, cfg = cfg)
aif_log("%s — 팩터 %d개 · 그림 %d장", SET, n, length(charts)); cat(paste0(lines, collapse = "\n"), "\n")
