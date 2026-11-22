## 01_stage1_new_factors.R — 단계 1 앞부분: 측정기 자가 시험 → 비교 기준(KOSPI200 · 유니버스 동일가중) → 이미 만든 새 팩터 6개 측정 · 그래프 · 성과표
##   실행: Rscript run/01_stage1_new_factors.R   (감시 셸 ops/aif_run.py 가 띄운다 · QM_ROOT 필요)
##   팩터 하나 = 체크포인트 하나. 다시 띄우면 끝난 팩터는 건너뛴다(입력 파일이 바뀌었으면 다시 잰다).
here <- function() {   # 이 스크립트가 든 폴더의 위 폴더(연구 폴더). 경로 정규화 함수는 쓰지 않는다 — 구분자만 맞춘다
  a <- commandArgs(FALSE); f <- gsub("\\\\", "/", sub("^--file=", "", a[grepl("^--file=", a)])[1])
  if (!grepl("^([A-Za-z]:)?/", f)) f <- file.path(getwd(), f)
  dirname(dirname(f))
}
D <- here()
for (f in c("aif_common.R", "aif_factor_perf.R", "aif_status.R", "aif_charts.R")) source(file.path(D, "R", f))
root <- aif_root(); cfg <- aif_cfg(root); aif_low_priority()
SET <- "new"; facs <- cfg$new_factors_existing
PART <- c(0, 0.20)                                   # 이 실행이 맡는 단계 진행 구간(나머지 0.20~1 = 기존 팩터 DB 측정)
aif_stage_begin("perf_base", unit_total = length(facs) + 2L, unit_name = "측정 단위", part_from = PART[1], part_to = PART[2], threads = cfg$resources$jobs$perf$threads, root = root, cfg = cfg)

M <- aif_market(root, cfg); Rx <- aif_rx(M)

## ① 자가 시험(답을 아는 입력)
aif_status_set(detail = "측정기 자가 시험", root = root, cfg = cfg)
source(file.path(D, "tests", "selftest_measurer_fn.R"))
stt <- aif_selftest_measurer(M, Rx, cfg, root)
if (!isTRUE(stt$all_pass)) stop("[aif] 측정기 자가 시험 실패 — results/selftest_measurer.json")
aif_stage_unit(1L, "자가 시험 통과", root = root, cfg = cfg)

## ② 비교 기준
ref <- aif_reference(M, Rx, cfg)
dir.create(aif_out("perf", "_reference", root = root, cfg = cfg), recursive = TRUE, showWarnings = FALSE)
aif_write_atomic(aif_out("perf", "_reference", "stats.csv", root = root, cfg = cfg), function(p) fwrite(ref$stats, p))
aif_write_atomic(aif_out("perf", "_reference", "daily.parquet", root = root, cfg = cfg), function(p) write_parquet(ref$daily, p))
aif_stage_unit(2L, "비교 기준(KOSPI200 · 유니버스 동일가중)", root = root, cfg = cfg)

## ③ 팩터마다 측정 → 저장 → 그래프
res <- list(); labels <- list()
for (k in seq_along(facs)) {
  f <- facs[[k]]; src <- file.path(root, f$path); fp <- sprintf("%s_%s", format(file.mtime(src), "%Y%m%d%H%M%S"), file.size(src))
  labels[[f$id]] <- f$id
  dn <- file.path(aif_perf_dir(SET, f$id, root = root, cfg = cfg), "done.json")
  if (file.exists(dn) && identical(fromJSON(dn)$input_fp, fp) && identical(as.integer(fromJSON(dn)$measurer_version), AIF_MEASURER_VERSION)) {
    aif_log("%s — 이미 측정됨(건너뜀)", f$id); res[[f$id]] <- aif_perf_load(SET, f$id, root = root, cfg = cfg)
  } else {
    aif_status_set(detail = sprintf("%s 측정 중", f$id), root = root, cfg = cfg)
    t0 <- Sys.time()
    dt <- as.data.table(read_parquet(src, col_select = c("Date", "Ticker", "Raw_Value")))
    S <- aif_score_matrix(dt, M, direction = f$direction); rm(dt)
    res[[f$id]] <- aif_measure_factor(f$id, S, M, Rx, cfg, all_quantiles = TRUE)
    aif_perf_save(SET, res[[f$id]], meta = list(input = f$path, input_fp = fp, measurer_version = AIF_MEASURER_VERSION, direction = f$direction, method = f$method, desc = f$desc, match = attr(S, "match")), root = root, cfg = cfg)
    aif_log("%s — 측정 끝(%.0f초)", f$id, as.numeric(difftime(Sys.time(), t0, units = "secs")))
  }
  aif_chart_factor(res[[f$id]], ref, cfg, f$id, aif_results("stage1", "charts", sprintf("factor_%s.png", f$id), root = root, cfg = cfg),
                   note = sprintf("%s · %s · 점선 = IS/OOS 경계", f$method, f$desc))
  aif_stage_unit(2L + k, sprintf("%s 측정 끝", f$id), root = root, cfg = cfg)
}

## ④ 성과표(벤치마크 줄을 맨 위에) · 격자 그래프
row_of <- function(id, st, port, per) {
  a <- st[portfolio == port & cost == "gross" & period == per]; n <- st[portfolio == port & cost == "net" & period == per]
  d1 <- st[portfolio == port & cost == "gross_d1" & period == per]                       # 매매를 하루 늦춘 판(신규 팩터만 있다)
  if (!nrow(a)) return(NULL)
  data.table(factor = id, portfolio = port, period = per, CAGR = a$CAGR, SD = a$SD, SR = a$SR, MDD = a$MDD, Calmar = a$Calmar,
             excess_CAGR = a$excess_CAGR %||% NA_real_, IR = a$IR %||% NA_real_, beta = a$beta %||% NA_real_, win_month = a$win_month,
             CAGR_net = if (nrow(n)) n$CAGR else NA_real_, SR_net = if (nrow(n)) n$SR else NA_real_,
             CAGR_d1 = if (nrow(d1)) d1$CAGR else NA_real_, SR_d1 = if (nrow(d1)) d1$SR else NA_real_)
}
pers <- names(aif_periods(cfg))
tab <- rbindlist(c(
  lapply(pers, function(p) row_of(cfg$measure$benchmark_label, ref$stats, "benchmark", p)),
  lapply(pers, function(p) row_of("유니버스 동일가중", ref$stats, "universe_ew", p)),
  unlist(lapply(names(res), function(id) unlist(lapply(c("top", "ls"), function(pt) lapply(pers, function(p) row_of(id, res[[id]]$stats, pt, p))), recursive = FALSE)), recursive = FALSE)), fill = TRUE)
ic1 <- rbindlist(lapply(res, function(r) r$ic[horizon_m == 1L, .(factor, period, IC, ICIR, IC_t)]))
tab <- merge(tab, ic1, by = c("factor", "period"), all.x = TRUE, sort = FALSE)
misc <- rbindlist(lapply(res, function(r) r$misc), fill = TRUE)
tab <- merge(tab, misc[, .(factor, turnover_top, names_avg, first_signal)], by = "factor", all.x = TRUE, sort = FALSE)
aif_write_atomic(aif_results("stage1", "new_factors_perf.csv", root = root, cfg = cfg), function(p) fwrite(tab, p))
aif_write_atomic(aif_results("stage1", "new_factors_ic.csv", root = root, cfg = cfg), function(p) fwrite(rbindlist(lapply(res, function(r) r$ic)), p))
aif_write_atomic(aif_results("stage1", "new_factors_misc.csv", root = root, cfg = cfg), function(p) fwrite(misc, p))

ref_start <- substr(ref$stats[portfolio == "benchmark" & period == "ALL", start], 1L, 7L)
show <- function(port, per, title, prefix) {
  x <- tab[(portfolio == port | portfolio %in% c("benchmark", "universe_ew")) & period == per]
  if (port == "ls") x <- x[!portfolio %in% c("benchmark", "universe_ew")]
  o <- x[, .(`팩터` = factor, `첫 신호` = ifelse(is.na(first_signal), ref_start, substr(first_signal, 1L, 7L)), CAGR = aif_pct(CAGR), SD = aif_pct(SD), SR = aif_num(SR),
             MDD = aif_pct(MDD), Calmar = aif_num(Calmar), `초과수익` = aif_pct(excess_CAGR), IR = aif_num(IR), IC = aif_num(IC, 3), ICIR = aif_num(ICIR),
             `SR 지연` = aif_num(SR_d1))]
  if (port == "ls") o[, c("초과수익", "IR") := NULL]
  d1n <- "SR 지연 = 매매를 하루 늦춘 판(월말 종가 대신 다음 달 첫 거래일 종가에 매매)의 SR"
  note <- if (port == "ls") paste0("롱숏 = 상위 분위 − 하위 분위(동일가중) · SR 은 무위험 수익을 빼지 않은 값 · 팩터마다 시작 시점이 다르다(첫 신호 열)\n", d1n)
          else if (per == "OOS") paste0("모두 같은 구간(2023-01 ~ 측정 끝) · 초과수익과 IR 은 KOSPI200 대비\n", d1n)
          else sprintf("%s 줄은 %s 부터, 팩터는 각자 첫 신호 다음 달부터 잰 값이다 · 초과수익과 IR 은 그 팩터와 같은 구간의 %s 대비\n같은 구간끼리의 비교는 공통 기간 표 참조 · %s", cfg$measure$benchmark_label, ref_start, cfg$measure$benchmark_label, d1n)
  aif_table_png(o, aif_results("stage1", "charts", prefix, root = root, cfg = cfg), title, hl_rows = which(x$portfolio %in% c("benchmark", "universe_ew")), note = note)
}
imgs <- c(show("top", "ALL", "신규 팩터 성과 — 상위 분위 롱온리 · 전기간(거래비용 전)", "table_top_all"),
          show("top", "IS", "신규 팩터 성과 — 상위 분위 롱온리 · IS(~2022-12)", "table_top_is"),
          show("top", "OOS", "신규 팩터 성과 — 상위 분위 롱온리 · OOS(2023-01~)", "table_top_oos"),
          show("ls", "ALL", "신규 팩터 성과 — 상위−하위 롱숏 · 전기간(거래비용 전)", "table_ls_all"))
grids <- c(aif_chart_grid(res, labels, ref, cfg, aif_results("stage1", "charts", "grid", root = root, cfg = cfg), what = "top"),
           aif_chart_grid(res, labels, ref, cfg, aif_results("stage1", "charts", "grid", root = root, cfg = cfg), what = "ls"))

## 진행 알림이 '단계 중간 결과' 통에 실을 것(그림 경로 · 한 줄 설명)
aif_write_json(list(at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"), title = "이미 만든 새 팩터 6개 성과",
                    lines = c(sprintf("대상 %d개: %s", length(res), paste(names(res), collapse = " · ")),
                              sprintf("측정 구간 끝 %s · IS/OOS 경계 %s", M$last_hold_end, cfg$measure$is_end),
                              "성과표와 그래프는 아래 그림 참조(거래비용 전 · 상위 분위 롱온리와 롱숏)"),
                    charts = as.list(c(imgs, grids, vapply(names(res), function(id) aif_results("stage1", "charts", sprintf("factor_%s.png", id), root = root, cfg = cfg), ""))),
                    chart_names = as.list(c(rep("신규 팩터 성과표", length(imgs)), rep("신규 팩터 P/L 격자", length(grids)), sprintf("%s — P/L · 낙폭 · 5분위 · 롱숏 · 누적 IC", names(res))))),
               aif_out("stage_summary_perf_new.json", root = root, cfg = cfg))
aif_stage_end(done = FALSE, root = root, cfg = cfg)   # 단계 1 은 기존 팩터 DB 측정까지 끝나야 끝난다
aif_log("단계 1 앞부분 끝 — 표 %s · 그림 %d장", aif_results("stage1", "new_factors_perf.csv", root = root, cfg = cfg), length(imgs) + length(grids) + length(res))
