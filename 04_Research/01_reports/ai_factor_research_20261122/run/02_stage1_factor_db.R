## 02_stage1_factor_db.R — 단계 1 뒷부분: 기존 팩터 DB(사람이 정의한 팩터)와 카테고리 합성 · 전체 합성을 같은 측정기로 잰다(비교 기준표).
##   읽기는 정본 접근자 load_month_factors(direction = "registry")만 쓴다(저장 파일을 직접 읽지 않는다 · 방향 = 등록부 선언 방향).
##   A 단계: 달마다 팩터를 읽어 분위 · IC · 새 팩터와의 겹침을 모은다(24달마다 체크포인트).
##   B 단계: 팩터마다 상위 · 하위 분위의 일별 수익을 Return.portfolio 로 만들어 지표를 낸다(20개마다 체크포인트).
##   실행: Rscript run/02_stage1_factor_db.R   (감시 셸 ops/aif_run.py 가 띄운다)
here <- function() {   # 이 스크립트가 든 폴더의 위 폴더(연구 폴더). 경로 정규화 함수는 쓰지 않는다 — 구분자만 맞춘다
  a <- commandArgs(FALSE); f <- gsub("\\\\", "/", sub("^--file=", "", a[grepl("^--file=", a)])[1])
  if (!grepl("^([A-Za-z]:)?/", f)) f <- file.path(getwd(), f)
  dirname(dirname(f))
}
D <- here()
for (f in c("aif_common.R", "aif_factor_perf.R", "aif_status.R", "aif_charts.R")) source(file.path(D, "R", f))
root <- aif_root(); cfg <- aif_cfg(root); aif_low_priority(); setwd(root)
nq <- cfg$measure$n_quantiles; mn <- cfg$measure$min_names; hz <- as.character(unlist(cfg$measure$ic_horizons_m))
M <- aif_market(root, cfg); Rx <- aif_rx(M); ns <- length(M$sig_dates); nt <- length(M$tickers)
OUTD <- aif_out("perf", "db", root = root, cfg = cfg); dir.create(OUTD, recursive = TRUE, showWarnings = FALSE)
RES <- function(...) aif_results("stage1", ..., root = root, cfg = cfg)

invisible(capture.output(suppressMessages(source(file.path(root, "02_Infrastructure", "factor_db", "factor_db_connector.R")))))
reg <- fromJSON(file.path(root, "02_Infrastructure", "factor_db", "factor_registry.json"), simplifyVector = FALSE)
if (!is.null(reg$factors)) reg <- reg$factors
reg <- reg[vapply(reg, function(v) is.list(v) && !is.null(v$category), TRUE)]
cat_of <- vapply(reg, function(v) as.character(v$category), ""); def_of <- vapply(reg, function(v) as.character(v$definition %||% ""), "")
## 차입금 빈칸 수리(판 표식 FUNDAMENTAL-DEBT-ZEROFILL-20261117)가 팩터 DB 월별 파일에 아직 반영되지 않았다 → 단기 · 장기 차입을 따로 쓰는 팩터는 잠정으로 표시
prov <- names(def_of)[grepl("단기차입|장기차입|Piotroski|F-Score|F_Score", def_of)]

new_ids <- vapply(cfg$new_factors_existing, function(f) f$id, "")
Snew <- lapply(cfg$new_factors_existing, function(f) {
  dt <- as.data.table(read_parquet(file.path(root, f$path), col_select = c("Date", "Ticker", "Raw_Value"))); aif_score_matrix(dt, M, f$direction)
}); names(Snew) <- new_ids

## ── A 단계 ───────────────────────────────────────────────────────────────────
CKA <- file.path(OUTD, "phaseA.rds"); sig_use <- which(M$hold_ok)
A <- if (file.exists(CKA)) readRDS(CKA) else list(done = integer(0), top = list(), bot = list(), ic = list(), qm = list(), nn = list(), ac = list(), ovs = list(), ovn = list(), skipped = list())
todo <- setdiff(sig_use, A$done)
aif_stage_begin("perf_base", unit_total = length(sig_use), unit_name = "달", part_from = 0.20, part_to = 0.50, threads = cfg$resources$jobs$perf$threads, root = root, cfg = cfg)
if (length(A$done)) aif_stage_unit(length(A$done), "이어서 읽는 중", root = root, cfg = cfg)
slot <- function(lst, id, make) { if (is.null(lst[[id]])) make() else lst[[id]] }
prev <- NULL
for (s in todo) {
  sd <- M$sig_dates[s]
  L <- tryCatch({ x <- NULL; invisible(capture.output(x <- load_month_factors(sd, direction = "registry"))); x },   # 접근자가 달마다 찍는 안내 줄은 로그에 남기지 않는다
                error = function(e) { A$skipped[[as.character(sd)]] <<- conditionMessage(e); NULL })
  asof <- if (is.null(L)) as.Date(NA) else as.Date(attr(L, "factor_db_asof_date"))
  if (is.null(L) || is.na(asof) || format(asof, "%Y%m") != format(sd, "%Y%m")) {       # 그 달 파일이 없거나 다른 달 것이면 쓰지 않는다
    if (!is.null(L)) A$skipped[[as.character(sd)]] <- sprintf("월 파일 기준일 %s", asof)
    A$done <- c(A$done, s); prev <- NULL; next
  }
  ti <- match(L$Ticker, M$tickers); fs <- unique(L$Factor_Name); ok <- !is.na(ti)
  Z <- matrix(NA_real_, nt, length(fs)); Z[cbind(ti[ok], match(L$Factor_Name[ok], fs))] <- L$Z_Score_Aligned[ok]
  Z[!M$MEM[s, ], ] <- NA_real_                                                          # 유니버스 멤버만
  Rk <- apply(Z, 2L, function(z) { o <- is.finite(z); n <- sum(o); r <- rep(NA_real_, nt); if (n >= mn) r[o] <- (rank(z[o]) - 1) / (n - 1) * 2 - 1; r })
  colnames(Rk) <- fs
  cats <- cat_of[fs]; cats[is.na(cats)] <- "unregistered"
  comp <- vapply(split(seq_along(fs), cats), function(ix) { v <- rowMeans(Rk[, ix, drop = FALSE], na.rm = TRUE); v[is.nan(v)] <- NA_real_; v }, numeric(nt))
  colnames(comp) <- paste0("CAT_", colnames(comp))
  tot <- rowMeans(comp, na.rm = TRUE); tot[is.nan(tot)] <- NA_real_                      # 전체 합성 = 카테고리 합성의 평균(카테고리 균형)
  ALL <- cbind(Rk, comp, CAT_TOTAL = tot)
  f1 <- M$FWD[["1"]][s, ]
  for (j in seq_len(ncol(ALL))) {
    id <- colnames(ALL)[j]; z <- ALL[, j]; o <- which(is.finite(z)); n <- length(o)
    if (n < mn) next
    q <- as.integer(ceiling(rank(z[o], ties.method = "first") * nq / n))
    tp <- slot(A$top, id, function() vector("list", ns)); tp[[s]] <- o[q == nq]; A$top[[id]] <- tp
    bt <- slot(A$bot, id, function() vector("list", ns)); bt[[s]] <- o[q == 1L]; A$bot[[id]] <- bt
    icm <- slot(A$ic, id, function() matrix(NA_real_, ns, length(hz), dimnames = list(NULL, hz)))
    for (h in hz) { f <- M$FWD[[h]][s, o]; k <- is.finite(f); if (sum(k) >= mn) icm[s, h] <- suppressWarnings(cor(rank(z[o][k]), rank(f[k]))) }
    A$ic[[id]] <- icm
    qmm <- slot(A$qm, id, function() matrix(NA_real_, ns, nq)); qmm[s, ] <- vapply(seq_len(nq), function(g) mean(f1[o][q == g], na.rm = TRUE), 0); A$qm[[id]] <- qmm
    nv <- slot(A$nn, id, function() rep(NA_integer_, ns)); nv[s] <- n; A$nn[[id]] <- nv
    if (!is.null(prev) && id %in% colnames(prev)) {
      b <- is.finite(z) & is.finite(prev[, id])
      av <- slot(A$ac, id, function() rep(NA_real_, ns)); if (sum(b) >= mn) av[s] <- suppressWarnings(cor(rank(z[b]), rank(prev[b, id]))); A$ac[[id]] <- av
    }
  }
  ## 새 팩터와의 겹침 — 달마다 순위 상관을 모은다
  for (nid in new_ids) {
    zn <- Snew[[nid]][s, ]; zn[!M$MEM[s, ]] <- NA_real_
    if (sum(is.finite(zn)) < mn) next
    cc <- suppressWarnings(cor(zn, ALL, use = "pairwise.complete.obs", method = "spearman"))[1L, ]
    for (id in names(cc)[is.finite(cc)]) {
      A$ovs[[nid]][[id]] <- (A$ovs[[nid]][[id]] %||% 0) + cc[[id]]; A$ovn[[nid]][[id]] <- (A$ovn[[nid]][[id]] %||% 0L) + 1L
    }
  }
  prev <- ALL; A$done <- c(A$done, s)
  if (length(A$done) %% 24L == 0L || s == todo[length(todo)]) {
    aif_write_atomic(CKA, function(p) saveRDS(A, p, compress = FALSE))
    aif_stage_unit(length(A$done), sprintf("%s 까지 읽음 · 팩터 %d개", format(sd, "%Y-%m"), length(A$top)), root = root, cfg = cfg)
  }
}
if (length(todo)) aif_write_atomic(CKA, function(p) saveRDS(A, p, compress = FALSE))
ids <- names(A$top); aif_log("A 단계 끝 — 팩터 · 합성 %d개 · 건너뛴 달 %d", length(ids), length(A$skipped))

## ── B 단계 ───────────────────────────────────────────────────────────────────
CKB <- file.path(OUTD, "phaseB.rds")
B <- if (file.exists(CKB)) readRDS(CKB) else list(stats = list(), ic = list(), misc = list(), top = list(), ls = list())
aif_stage_begin("perf_base", unit_total = length(ids), unit_name = "팩터", part_from = 0.50, part_to = 0.97, threads = cfg$resources$jobs$perf$threads, root = root, cfg = cfg)
mask_of <- function(lst) { m <- matrix(FALSE, ns, nt); for (s in which(!vapply(lst, is.null, TRUE))) m[s, lst[[s]]] <- TRUE; m }
kdone <- sum(ids %in% names(B$stats))
for (id in setdiff(ids, names(B$stats))) {
  top <- mask_of(A$top[[id]]); bot <- mask_of(A$bot[[id]])
  mm <- aif_measure_masks(id, top, bot, M, Rx, cfg)
  B$stats[[id]] <- mm$stats
  B$ic[[id]] <- rbindlist(lapply(hz, function(h) cbind(data.table(factor = id, horizon_m = as.integer(h)), aif_ic_summary(A$ic[[id]][, h], M$sig_dates, cfg))))
  rows <- which(!vapply(A$top[[id]], is.null, TRUE)); qm <- colMeans(A$qm[[id]][rows, , drop = FALSE], na.rm = TRUE)
  B$misc[[id]] <- data.table(factor = id, category = if (startsWith(id, "CAT_")) "합성" else (cat_of[id] %||% NA_character_),
                             kind = if (id == "CAT_TOTAL") "전체 합성" else if (startsWith(id, "CAT_")) "카테고리 합성" else "개별 팩터",
                             provisional = id %in% prov, first_signal = as.character(M$sig_dates[min(rows)]), n_months = length(rows),
                             names_avg = mean(A$nn[[id]][rows], na.rm = TRUE), turnover_top = mean(mm$tr_top[rows][-1L], na.rm = TRUE) / 2,
                             rank_autocorr = mean(A$ac[[id]], na.rm = TRUE), monotonic = suppressWarnings(cor(seq_len(nq), qm, method = "spearman")))
  B$top[[id]] <- mm$daily[, .(Date, v = top)]; B$ls[[id]] <- mm$daily[, .(Date, v = ls)]
  kdone <- kdone + 1L
  if (kdone %% 20L == 0L || kdone == length(ids)) {
    aif_write_atomic(CKB, function(p) saveRDS(B, p, compress = FALSE))
    aif_stage_unit(kdone, sprintf("%s 까지 측정", id), root = root, cfg = cfg)
  }
}

## ── 표 · 그림 ────────────────────────────────────────────────────────────────
aif_stage_begin("perf_base", unit_total = 3L, unit_name = "정리", part_from = 0.97, part_to = 1.0, threads = cfg$resources$jobs$perf$threads, root = root, cfg = cfg)
ST <- rbindlist(B$stats, fill = TRUE); IC <- rbindlist(B$ic, fill = TRUE); MI <- rbindlist(B$misc, fill = TRUE)
ST <- merge(ST, MI[, .(factor, category, kind, provisional)], by = "factor", all.x = TRUE, sort = FALSE)
aif_write_atomic(RES("factor_db_perf.csv"), function(p) fwrite(ST, p))
aif_write_atomic(RES("factor_db_ic.csv"), function(p) fwrite(IC, p))
aif_write_atomic(RES("factor_db_misc.csv"), function(p) fwrite(MI, p))
wide <- function(lst) { d <- data.table(Date = M$dates[seq_len(nrow(Rx))]); for (id in names(lst)) set(d, j = id, value = lst[[id]]$v[match(d$Date, lst[[id]]$Date)]); d }
aif_write_atomic(file.path(OUTD, "daily_top.parquet"), function(p) write_parquet(wide(B$top), p))
aif_write_atomic(file.path(OUTD, "daily_ls.parquet"), function(p) write_parquet(wide(B$ls), p))
aif_stage_unit(1L, "기존 팩터 성과표 저장", root = root, cfg = cfg)

## 새 팩터와 기존 팩터의 겹침(달 평균 순위 상관의 최대 절댓값)
OV <- rbindlist(lapply(new_ids, function(nid) {
  v <- unlist(A$ovs[[nid]]) / unlist(A$ovn[[nid]])[names(unlist(A$ovs[[nid]]))]; v <- v[!startsWith(names(v), "CAT_")]
  o <- order(-abs(v))[seq_len(min(5L, length(v)))]
  data.table(factor = nid, max_abs_corr = abs(v[o[1]]), with_factor = names(v)[o[1]], with_category = cat_of[names(v)[o[1]]],
             top5 = paste(sprintf("%s(%+.2f)", names(v)[o], v[o]), collapse = " · "))
}))
aif_write_atomic(RES("new_vs_db_overlap.csv"), function(p) fwrite(OV, p))

## 통합 비교 — 새 팩터가 기존 개별 팩터 분포에서 선 자리(공통 기간 = 새 팩터의 측정 구간으로 기존 팩터를 다시 잰다)
newres <- lapply(new_ids, function(id) aif_perf_load("new", id, root = root, cfg = cfg)); names(newres) <- new_ids
ref <- list(stats = fread(aif_out("perf", "_reference", "stats.csv", root = root, cfg = cfg)),
            daily = as.data.table(read_parquet(aif_out("perf", "_reference", "daily.parquet", root = root, cfg = cfg))))
indiv <- MI[kind == "개별 팩터", factor]; cats <- MI[kind != "개별 팩터", factor]; TOPW <- wide(B$top); LSW <- wide(B$ls); bl <- cfg$measure$benchmark_label
## 아래 두 표는 계산이 몇 분 걸린다 — 측정 결과(B 단계 · 새 팩터)보다 나중에 만든 파일이 있으면 그대로 쓴다
src_time <- max(file.mtime(CKB), file.mtime(vapply(new_ids, function(id) file.path(aif_perf_dir("new", id, root = root, cfg = cfg), "done.json"), "")))
fresh <- function(f) file.exists(f) && file.mtime(f) > src_time
common <- function(nid, W, ls) {            # 새 팩터의 측정 구간에서 기존 팩터들의 SR · CAGR · MDD
  dd <- newres[[nid]]$daily$Date; i <- match(dd, M$dates); k <- match(dd, W$Date)
  rbindlist(lapply(indiv, function(id) { z <- aif_stats(W[[id]][k], dd, M$bm[i], M$rf[i], cfg, ls = ls); if (is.null(z)) NULL else data.table(factor = id, SR = z$SR, CAGR = z$CAGR, MDD = z$MDD) }))
}
POS <- if (fresh(RES("new_vs_db_position.csv"))) fread(RES("new_vs_db_position.csv"), encoding = "UTF-8") else {
  x <- rbindlist(lapply(new_ids, function(nid) {
    a <- newres[[nid]]$stats[portfolio == "top" & cost == "gross" & period == "ALL"]; l <- newres[[nid]]$stats[portfolio == "ls" & cost == "gross" & period == "ALL"]
    ct <- common(nid, TOPW, FALSE); cl <- common(nid, LSW, TRUE)
    data.table(factor = nid, n_existing = nrow(ct), SR_top = a$SR, rank_top = 1L + sum(ct$SR > a$SR), pct_top = mean(ct$SR < a$SR),
               SR_ls = l$SR, rank_ls = 1L + sum(cl$SR > l$SR), pct_ls = mean(cl$SR < l$SR), median_SR_top_existing = median(ct$SR), median_SR_ls_existing = median(cl$SR))
  }))
  x <- merge(x, OV[, .(factor, max_abs_corr, with_factor)], by = "factor", sort = FALSE)
  aif_write_atomic(RES("new_vs_db_position.csv"), function(p) fwrite(x, p)); x
}

## 공통 기간 비교 — 새 팩터 · 기존 팩터 · 합성 · 벤치마크를 같은 구간에서 다시 잰다(시작 = 가장 늦게 시작한 새 팩터의 첫 날 · 거래비용 전)
d0 <- as.Date(max(vapply(new_ids, function(id) as.numeric(min(newres[[id]]$daily$Date)), 0)), origin = "1970-01-01"); per <- aif_periods(cfg)
cstat <- function(kind, id, port, r, dts, ls) rbindlist(lapply(names(per), function(p) {
  sel <- dts >= max(d0, per[[p]][1]) & dts <= per[[p]][2] & is.finite(r)
  if (sum(sel) < 60L) return(NULL)
  i <- match(dts[sel], M$dates); z <- aif_stats(r[sel], dts[sel], M$bm[i], M$rf[i], cfg, ls = ls)
  if (is.null(z)) NULL else cbind(data.table(kind = kind, factor = id, portfolio = port, period = p), as.data.table(z))
}), fill = TRUE)
both <- function(kind, id, rt, rl, dts) rbind(cstat(kind, id, "top", rt, dts, FALSE), cstat(kind, id, "ls", rl, dts, TRUE), fill = TRUE)
CMN <- if (fresh(RES("common_period_perf.csv"))) fread(RES("common_period_perf.csv"), encoding = "UTF-8") else {
  x <- rbindlist(c(list(cstat("벤치마크", bl, "top", ref$daily$bm, ref$daily$Date, FALSE), cstat("참고", "유니버스 동일가중", "top", ref$daily$universe_ew, ref$daily$Date, FALSE)),
                   lapply(new_ids, function(id) both("새 팩터", id, newres[[id]]$daily$top, newres[[id]]$daily$ls, newres[[id]]$daily$Date)),
                   lapply(c(cats, indiv), function(id) both(MI[factor == id, kind], id, TOPW[[id]], LSW[[id]], TOPW$Date))), fill = TRUE)
  aif_write_atomic(RES("common_period_perf.csv"), function(p) fwrite(x, p)); x
}
cm_from <- format(d0, "%Y-%m")
aif_stage_unit(2L, "새 팩터 vs 기존 팩터 비교표", root = root, cfg = cfg)

## 그림 ① 기존 개별 팩터의 SR 분포 위에 새 팩터 위치 ② SR × MDD 산점도 ③ 카테고리 합성 · 새 팩터 · KOSPI200 P/L — 모두 공통 기간
E <- CMN[kind == "개별 팩터" & period == "ALL"]; N <- CMN[kind == "새 팩터" & period == "ALL"]
dist1 <- function(port, ttl) ggplot(E[portfolio == port], aes(SR)) + geom_histogram(bins = 40, fill = "#c9d1d9", colour = "white") +
  geom_vline(data = N[portfolio == port], aes(xintercept = SR, colour = factor), linewidth = 0.7) + scale_colour_brewer(palette = "Dark2") +
  labs(title = ttl, subtitle = sprintf("회색 = 기존 팩터 DB 개별 팩터 %d개 · 세로선 = 새 팩터 · 공통 기간 %s~ · 거래비용 전", E[portfolio == port, .N], cm_from)) + aif_theme(10)
sc <- ggplot(E[portfolio == "top"], aes(MDD, SR)) + geom_point(colour = "#b0b8c1", size = 1.1, alpha = 0.8) +
  geom_point(data = N[portfolio == "top"], aes(colour = factor), size = 3) + scale_colour_brewer(palette = "Dark2") + scale_x_continuous(labels = label_percent(accuracy = 1)) +
  labs(title = "SR × MDD — 상위 분위 롱온리", subtitle = sprintf("회색 = 기존 개별 팩터 · 색 = 새 팩터 · 공통 기간 %s~", cm_from)) + aif_theme(10) + theme(axis.title = element_text(size = 9)) + xlab("MDD") + ylab("SR")
p_dist <- aif_png(dist1("top", "기존 팩터 DB 의 SR 분포 vs 새 팩터 — 상위 분위 롱온리") / dist1("ls", "기존 팩터 DB 의 SR 분포 vs 새 팩터 — 상위−하위 롱숏") / sc, RES("charts", "compare_distribution.png"), w = 1080, h = 1900)
PL <- rbind(rbindlist(lapply(cats, function(id) data.table(Date = TOPW$Date, s = id, g = "기존 카테고리 합성", r = TOPW[[id]]))),
            rbindlist(lapply(new_ids, function(id) data.table(Date = newres[[id]]$daily$Date, s = id, g = "새 팩터", r = newres[[id]]$daily$top))),
            data.table(Date = ref$daily$Date, s = bl, g = bl, r = ref$daily$bm))
d0 <- max(vapply(new_ids, function(id) as.numeric(min(newres[[id]]$daily$Date)), 0)); PL <- PL[as.numeric(Date) >= d0 & is.finite(r)]   # 공통 기간
PL[, v := aif_cum(r), by = s]
p_pl <- aif_png(ggplot(PL, aes(Date, v, group = s, colour = g, linewidth = g)) + geom_line() + scale_y_log10(labels = label_number(accuracy = 0.1)) +
  geom_vline(xintercept = as.Date(cfg$measure$is_end), linetype = "dashed", colour = "#888888", linewidth = 0.3) +
  scale_colour_manual(values = setNames(c("#c2c9d1", "#d62728", "#222222"), c("기존 카테고리 합성", "새 팩터", bl))) +
  scale_linewidth_manual(values = setNames(c(0.35, 0.6, 0.8), c("기존 카테고리 합성", "새 팩터", bl))) +
  labs(title = sprintf("P/L 비교 — 새 팩터 vs 기존 카테고리 합성 vs %s", bl), subtitle = "상위 분위 롱온리 · 공통 기간 · 로그축 · 점선 = IS/OOS 경계 · 거래비용 전") + aif_theme(11),
  RES("charts", "compare_pl.png"), w = 1080, h = 900)
## 표 ① 공통 기간 비교(새 팩터 + 기존 합성 + 벤치마크 · SR 순) ② 새 팩터가 기존 개별 팩터 가운데 선 자리(공통 기간 · 전기간/IS/OOS)
cmp_tab <- function(port) {
  x <- CMN[portfolio == port & kind != "개별 팩터"]
  w <- merge(x[period == "ALL"], dcast(x[period != "ALL"], factor ~ period, value.var = c("SR", "CAGR")), by = "factor", all.x = TRUE, sort = FALSE)
  w <- rbind(w[kind %in% c("벤치마크", "참고")], w[!kind %in% c("벤치마크", "참고")][order(-SR)])
  o <- w[, .(`구분` = kind, `팩터` = sub("^CAT_", "", factor), CAGR = aif_pct(CAGR), SD = aif_pct(SD), SR = aif_num(SR), MDD = aif_pct(MDD), `초과수익` = aif_pct(excess_CAGR), IR = aif_num(IR),
             `SR(IS)` = aif_num(SR_IS), `SR(OOS)` = aif_num(SR_OOS), `CAGR(OOS)` = aif_pct(CAGR_OOS))]
  if (port == "ls") o[, c("초과수익", "IR") := NULL]
  aif_table_png(o, RES("charts", sprintf("table_common_%s", port)),
                sprintf("공통 기간 비교 — %s · %s ~ · SR 순(거래비용 전)", if (port == "top") "상위 분위 롱온리" else "상위−하위 롱숏", cm_from), hl_rows = which(w$kind == "새 팩터"),
                note = "붉은 줄 = 새 팩터 · 합성 = 기존 팩터 DB 카테고리 구성원의 순위 평균(TOTAL = 카테고리 합성들의 평균)\nIS = ~2022-12 · OOS = 2023-01 ~ · 초과수익과 IR 은 KOSPI200 대비")
}
p_tb <- c(cmp_tab("top"), cmp_tab("ls"))
rk <- function(port, p) {
  e <- CMN[kind == "개별 팩터" & portfolio == port & period == p, SR]; n <- CMN[kind == "새 팩터" & portfolio == port & period == p, .(factor, SR)]
  n[, .(factor, v = sprintf("%s (%d위)", aif_num(SR), vapply(SR, function(s) 1L + sum(e > s), 1L)))]
}
pt <- data.table(`새 팩터` = new_ids)
for (pp in list(c("top", "ALL", "롱온리"), c("top", "IS", "롱온리 IS"), c("top", "OOS", "롱온리 OOS"), c("ls", "ALL", "롱숏"), c("ls", "IS", "롱숏 IS"), c("ls", "OOS", "롱숏 OOS"))) {
  z <- rk(pp[1], pp[2]); set(pt, j = pp[3], value = z$v[match(new_ids, z$factor)])
}
set(pt, j = "최대 상관", value = aif_num(OV$max_abs_corr[match(new_ids, OV$factor)])); set(pt, j = "겹치는 기존 팩터", value = OV$with_factor[match(new_ids, OV$factor)])
p_pos <- aif_table_png(pt, RES("charts", "table_position"), sprintf("새 팩터의 SR 과 기존 개별 팩터 %d개 가운데 순위 — 공통 기간 %s ~", length(indiv), cm_from),
                       note = "괄호 = 기존 개별 팩터 가운데 순위(1위 = SR 이 가장 높음) · 기존 팩터의 방향은 등록부에 선언된 방향 그대로\n최대 상관 = 기존 개별 팩터와의 월별 순위 상관 평균 가운데 절댓값이 가장 큰 것")
for (f in Sys.glob(RES("charts", "table_compare_composites_*.png"))) unlink(f)   # 기간이 서로 다른 옛 비교표는 남기지 않는다

aif_write_json(list(at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"), title = "기존 팩터 DB 와 성과 비교",
                    lines = c(sprintf("기존 개별 팩터 %d개 · 카테고리 합성 %d개 · 전체 합성 1개를 같은 측정기로 쟀습니다", length(indiv), length(cats) - 1L),
                              sprintf("비교는 공통 기간(%s ~)에서 했습니다 — 새 팩터 %d개의 순위 · 분포 위치 · 겹침은 아래 그림 참조", cm_from, length(new_ids)),
                              sprintf("잠정 표시 %d개: 차입금 빈칸 수리가 팩터 DB 에 아직 반영되지 않음", sum(MI$provisional))),
                    charts = as.list(c(p_tb, p_pos, p_dist, p_pl)),
                    chart_names = as.list(c(rep("공통 기간 비교표(새 팩터 vs 기존 합성 vs 벤치마크)", length(p_tb)), rep("새 팩터의 순위", length(p_pos)), "SR 분포와 SR × MDD", "P/L 비교(벤치마크 포함)"))),
               aif_out("stage_summary_perf_db.json", root = root, cfg = cfg))
aif_stage_unit(3L, "비교 그림", root = root, cfg = cfg)
aif_stage_end(done = TRUE, root = root, cfg = cfg)
aif_log("단계 1 끝 — 기존 팩터 %d개 · 합성 %d개 · 잠정 %d개 · 건너뛴 달 %d", length(indiv), length(cats), sum(MI$provisional), length(A$skipped))
