## aif_report.R — 측정 결과를 표 · 그림 · 비교로 정리하는 공용 함수(단계 3 · 4 의 팩터 묶음용). aif_common.R · aif_factor_perf.R · aif_charts.R 뒤에 source 한다.

## 팩터 묶음의 성과 한 표(벤치마크 · 유니버스 줄 포함 · 기간 × 포트폴리오)
aif_perf_rows <- function(res, ref, cfg) {
  row_of <- function(id, st, port, per) {
    a <- st[portfolio == port & cost == "gross" & period == per]; n <- st[portfolio == port & cost == "net" & period == per]
    d1 <- st[portfolio == port & cost == "gross_d1" & period == per]
    if (!nrow(a)) return(NULL)
    data.table(factor = id, portfolio = port, period = per, CAGR = a$CAGR, SD = a$SD, SR = a$SR, MDD = a$MDD, Calmar = a$Calmar,
               excess_CAGR = a$excess_CAGR %||% NA_real_, IR = a$IR %||% NA_real_, beta = a$beta %||% NA_real_, win_month = a$win_month,
               CAGR_net = if (nrow(n)) n$CAGR else NA_real_, SR_net = if (nrow(n)) n$SR else NA_real_,
               CAGR_d1 = if (nrow(d1)) d1$CAGR else NA_real_, SR_d1 = if (nrow(d1)) d1$SR else NA_real_)
  }
  pers <- names(aif_periods(cfg))
  tab <- rbindlist(c(lapply(pers, function(p) row_of(cfg$measure$benchmark_label, ref$stats, "benchmark", p)),
                     lapply(pers, function(p) row_of("유니버스 동일가중", ref$stats, "universe_ew", p)),
                     unlist(lapply(names(res), function(id) unlist(lapply(c("top", "ls"), function(pt) lapply(pers, function(p) row_of(id, res[[id]]$stats, pt, p))), recursive = FALSE)), recursive = FALSE)), fill = TRUE)
  ic1 <- rbindlist(lapply(res, function(r) r$ic[horizon_m == 1L, .(factor, period, IC, ICIR, IC_t)]))
  tab <- merge(tab, ic1, by = c("factor", "period"), all.x = TRUE, sort = FALSE)
  misc <- rbindlist(lapply(res, function(r) r$misc), fill = TRUE)
  merge(tab, misc[, .(factor, turnover_top, names_avg, first_signal)], by = "factor", all.x = TRUE, sort = FALSE)
}

## 성과표 그림 4종(롱온리 전기간 · IS · OOS · 롱숏 전기간)
aif_perf_tables <- function(tab, ref, cfg, out_dir, label = "신규 팩터") {
  bl <- cfg$measure$benchmark_label; ref_start <- substr(ref$stats[portfolio == "benchmark" & period == "ALL", start], 1L, 7L)
  show <- function(port, per, title, prefix) {
    x <- tab[(portfolio == port | portfolio %in% c("benchmark", "universe_ew")) & period == per]
    if (port == "ls") x <- x[!portfolio %in% c("benchmark", "universe_ew")]
    if (!nrow(x)) return(character(0))
    o <- x[, .(`팩터` = factor, `첫 신호` = ifelse(is.na(first_signal), ref_start, substr(first_signal, 1L, 7L)), CAGR = aif_pct(CAGR), SD = aif_pct(SD), SR = aif_num(SR),
               MDD = aif_pct(MDD), Calmar = aif_num(Calmar), `초과수익` = aif_pct(excess_CAGR), IR = aif_num(IR), IC = aif_num(IC, 3), ICIR = aif_num(ICIR), `SR 지연` = aif_num(SR_d1))]
    if (port == "ls") o[, c("초과수익", "IR") := NULL]
    d1n <- "SR 지연 = 매매를 하루 늦춘 판(월말 종가 대신 다음 달 첫 거래일 종가에 매매)의 SR"
    note <- if (port == "ls") paste0("롱숏 = 상위 분위 − 하위 분위(동일가중) · SR 은 무위험 수익을 빼지 않은 값 · 팩터마다 시작 시점이 다르다(첫 신호 열)\n", d1n)
            else if (per == "OOS") paste0("모두 같은 구간(2023-01 ~ 측정 끝) · 초과수익과 IR 은 ", bl, " 대비\n", d1n)
            else sprintf("%s 줄은 %s 부터, 팩터는 각자 첫 신호 다음 달부터 잰 값이다 · 초과수익과 IR 은 그 팩터와 같은 구간의 %s 대비\n같은 구간끼리의 비교는 공통 기간 표 참조 · %s", bl, ref_start, bl, d1n)
    aif_table_png(o, file.path(out_dir, prefix), title, hl_rows = which(x$portfolio %in% c("benchmark", "universe_ew")), note = note)
  }
  c(show("top", "ALL", sprintf("%s 성과 — 상위 분위 롱온리 · 전기간(거래비용 전)", label), "table_top_all"),
    show("top", "IS", sprintf("%s 성과 — 상위 분위 롱온리 · IS(~2022-12)", label), "table_top_is"),
    show("top", "OOS", sprintf("%s 성과 — 상위 분위 롱온리 · OOS(2023-01~)", label), "table_top_oos"),
    show("ls", "ALL", sprintf("%s 성과 — 상위−하위 롱숏 · 전기간(거래비용 전)", label), "table_ls_all"))
}

## 한 일별 수익 계열의 기간별 지표(d0 이후만)
aif_cstat <- function(kind, id, port, r, dts, ls, M, cfg, d0) {
  per <- aif_periods(cfg)
  rbindlist(lapply(names(per), function(p) {
    sel <- dts >= max(d0, per[[p]][1]) & dts <= per[[p]][2] & is.finite(r)
    if (sum(sel) < 60L) return(NULL)
    i <- match(dts[sel], M$dates); z <- aif_stats(r[sel], dts[sel], M$bm[i], M$rf[i], cfg, ls = ls)
    if (is.null(z)) NULL else cbind(data.table(kind = kind, factor = id, portfolio = port, period = p), as.data.table(z))
  }), fill = TRUE)
}

## 기존 팩터 DB(개별 · 합성) · 벤치마크 · 유니버스의 d0 이후 지표 — 단계 1 이 남긴 일별 수익 표에서 다시 잰다(d0 마다 한 번 · 저장)
aif_db_window <- function(M, cfg, root, d0) {
  f <- aif_out("perf", "db", sprintf("window_%s.csv", format(d0, "%Y%m%d")), root = root, cfg = cfg)
  src <- aif_out("perf", "db", "daily_top.parquet", root = root, cfg = cfg)
  if (file.exists(f) && file.mtime(f) > file.mtime(src)) return(fread(f, encoding = "UTF-8"))
  TOPW <- as.data.table(read_parquet(src)); LSW <- as.data.table(read_parquet(aif_out("perf", "db", "daily_ls.parquet", root = root, cfg = cfg)))
  MI <- fread(aif_results("stage1", "factor_db_misc.csv", root = root, cfg = cfg), encoding = "UTF-8")
  ref <- as.data.table(read_parquet(aif_out("perf", "_reference", "daily.parquet", root = root, cfg = cfg)))
  bl <- cfg$measure$benchmark_label
  x <- rbindlist(c(list(aif_cstat("벤치마크", bl, "top", ref$bm, ref$Date, FALSE, M, cfg, d0), aif_cstat("참고", "유니버스 동일가중", "top", ref$universe_ew, ref$Date, FALSE, M, cfg, d0)),
                   lapply(MI$factor, function(id) rbind(aif_cstat(MI[factor == id, kind], id, "top", TOPW[[id]], TOPW$Date, FALSE, M, cfg, d0),
                                                        aif_cstat(MI[factor == id, kind], id, "ls", LSW[[id]], LSW$Date, TRUE, M, cfg, d0), fill = TRUE))), fill = TRUE)
  aif_write_atomic(f, function(p) fwrite(x, p)); x
}

## 공통 기간 비교표(새 팩터 + 기존 합성 + 벤치마크 · SR 순)와 기존 개별 팩터 가운데 순위표
aif_compare_tables <- function(res, M, cfg, root, out_dir, label = "새 팩터", overlap = NULL) {
  d0 <- as.Date(max(vapply(res, function(r) as.numeric(min(r$daily$Date)), 0)), origin = "1970-01-01"); cm_from <- format(d0, "%Y-%m")
  DBW <- aif_db_window(M, cfg, root, d0)
  NEW <- rbindlist(lapply(names(res), function(id) rbind(aif_cstat(label, id, "top", res[[id]]$daily$top, res[[id]]$daily$Date, FALSE, M, cfg, d0),
                                                         aif_cstat(label, id, "ls", res[[id]]$daily$ls, res[[id]]$daily$Date, TRUE, M, cfg, d0), fill = TRUE)), fill = TRUE)
  CMN <- rbind(DBW, NEW, fill = TRUE)
  cmp <- function(port) {
    x <- CMN[portfolio == port & kind != "개별 팩터"]
    w <- merge(x[period == "ALL"], dcast(x[period != "ALL"], factor ~ period, value.var = c("SR", "CAGR")), by = "factor", all.x = TRUE, sort = FALSE)
    for (cn in c("SR_IS", "SR_OOS", "CAGR_OOS")) if (!cn %in% names(w)) set(w, j = cn, value = NA_real_)
    w <- rbind(w[kind %in% c("벤치마크", "참고")], w[!kind %in% c("벤치마크", "참고")][order(-SR)])
    o <- w[, .(`구분` = kind, `팩터` = sub("^CAT_", "", factor), CAGR = aif_pct(CAGR), SD = aif_pct(SD), SR = aif_num(SR), MDD = aif_pct(MDD), `초과수익` = aif_pct(excess_CAGR), IR = aif_num(IR),
               `SR(IS)` = aif_num(SR_IS), `SR(OOS)` = aif_num(SR_OOS), `CAGR(OOS)` = aif_pct(CAGR_OOS))]
    if (port == "ls") o[, c("초과수익", "IR") := NULL]
    aif_table_png(o, file.path(out_dir, sprintf("table_common_%s", port)),
                  sprintf("공통 기간 비교 — %s · %s ~ · SR 순(거래비용 전)", if (port == "top") "상위 분위 롱온리" else "상위−하위 롱숏", cm_from), hl_rows = which(w$kind == label),
                  note = sprintf("붉은 줄 = %s · 합성 = 기존 팩터 DB 카테고리 구성원의 순위 평균(TOTAL = 카테고리 합성들의 평균)\nIS = ~2022-12 · OOS = 2023-01 ~ · 초과수익과 IR 은 %s 대비", label, cfg$measure$benchmark_label))
  }
  ids <- names(res); n_ind <- CMN[kind == "개별 팩터" & portfolio == "top" & period == "ALL", .N]
  rk <- function(port, p) {
    e <- CMN[kind == "개별 팩터" & portfolio == port & period == p, SR]; n <- CMN[kind == label & portfolio == port & period == p, .(factor, SR)]
    if (!nrow(n)) return(data.table(factor = character(0), v = character(0), rank = integer(0)))
    n[, .(factor, v = sprintf("%s (%d위)", aif_num(SR), vapply(SR, function(s) 1L + sum(e > s), 1L)), rank = vapply(SR, function(s) 1L + sum(e > s), 1L))]
  }
  pt <- data.table(`팩터` = ids); RK <- list()
  for (pp in list(c("top", "ALL", "롱온리"), c("top", "IS", "롱온리 IS"), c("top", "OOS", "롱온리 OOS"), c("ls", "ALL", "롱숏"), c("ls", "IS", "롱숏 IS"), c("ls", "OOS", "롱숏 OOS"))) {
    z <- rk(pp[1], pp[2]); set(pt, j = pp[3], value = z$v[match(ids, z$factor)]); RK[[paste(pp[1], pp[2])]] <- setNames(z$rank, z$factor)
  }
  for (j in setdiff(names(pt), "팩터")) set(pt, which(is.na(pt[[j]])), j, "–")
  note <- "괄호 = 기존 개별 팩터 가운데 순위(1위 = SR 이 가장 높음) · 기존 팩터의 방향은 등록부에 선언된 방향 그대로"
  if (!is.null(overlap)) {
    set(pt, j = "최대 상관", value = aif_num(overlap$max_abs_corr[match(ids, overlap$factor)])); set(pt, j = "겹치는 기존 팩터", value = overlap$with_factor[match(ids, overlap$factor)])
    note <- paste0(note, "\n최대 상관 = 기존 개별 팩터와의 월별 순위 상관 평균 가운데 절댓값이 가장 큰 것")
  }
  p_pos <- aif_table_png(pt, file.path(out_dir, "table_position"), sprintf("%s의 SR 과 기존 개별 팩터 %d개 가운데 순위 — 공통 기간 %s ~", label, n_ind, cm_from), note = note)
  list(CMN = CMN, d0 = d0, images = c(cmp("top"), cmp("ls"), p_pos), ranks = RK, n_existing = n_ind)
}

## 새 팩터와 기존 팩터의 겹침 — 달마다 순위 상관을 내 평균한다(기존 팩터 값 = 03_export_frame.R 이 내보낸 멤버 안 순위)
aif_overlap <- function(S_list, M, root, cfg) {
  fcd <- aif_out("frame", "fc", root = root, cfg = cfg); ids <- names(S_list)
  sm <- setNames(lapply(ids, function(i) list()), ids); nn <- sm
  for (s in seq_along(M$sig_dates)) {
    p <- file.path(fcd, sprintf("fc_%s.parquet", format(M$sig_dates[s], "%Y%m")))
    if (!file.exists(p)) next
    W <- as.data.table(read_parquet(p)); ti <- match(W$Ticker, M$tickers); X <- as.matrix(W[, -1L])
    for (i in ids) {
      z <- S_list[[i]][s, ti]
      if (sum(is.finite(z)) < 30L) next
      cc <- suppressWarnings(cor(z, X, use = "pairwise.complete.obs", method = "spearman"))[1L, ]
      for (k in names(cc)[is.finite(cc)]) { sm[[i]][[k]] <- (sm[[i]][[k]] %||% 0) + cc[[k]]; nn[[i]][[k]] <- (nn[[i]][[k]] %||% 0L) + 1L }
    }
  }
  rbindlist(lapply(ids, function(i) {
    if (!length(sm[[i]])) return(data.table(factor = i, max_abs_corr = NA_real_, with_factor = NA_character_, top5 = NA_character_))
    v <- unlist(sm[[i]]) / unlist(nn[[i]])[names(unlist(sm[[i]]))]; o <- order(-abs(v))[seq_len(min(5L, length(v)))]
    data.table(factor = i, max_abs_corr = abs(v[o[1]]), with_factor = names(v)[o[1]], top5 = paste(sprintf("%s(%+.2f)", names(v)[o], v[o]), collapse = " · "))
  }))
}
