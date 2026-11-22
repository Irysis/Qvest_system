## 07_final_report.R — 종합 보고: 끝난 단계의 신규 팩터 전부를 한 표 · 한 묶음 그림 · 한 파일 보고서로 모은다.
##   새로 재지 않는다 — 단계별 측정(05 · 06)이 저장한 결과(.cache/aif_research/perf/<묶음>/<팩터>/)를 읽어 모은다. 아직 안 끝난 묶음은 '미완' 으로 적는다.
##   산출(results/final/): final_report.html(그림이 들어간 한 파일) · factor_perf_summary.csv · latent_portfolios_perf.csv · common_period_perf.csv · integrated_ranking.csv · charts/*.png
##   실행: Rscript run/07_final_report.R [--stage=final_report]   (--stage 를 주면 진행 상태를 갱신하고 텔레그램 결과 요약 파일도 쓴다)
here <- function() {   # 이 스크립트가 든 폴더의 위 폴더(연구 폴더). 경로 정규화 함수는 쓰지 않는다 — 구분자만 맞춘다
  a <- commandArgs(FALSE); f <- gsub("\\\\", "/", sub("^--file=", "", a[grepl("^--file=", a)])[1])
  if (!grepl("^([A-Za-z]:)?/", f)) f <- file.path(getwd(), f)
  dirname(dirname(f))
}
D <- here()
for (f in c("aif_common.R", "aif_factor_perf.R", "aif_status.R", "aif_charts.R", "aif_report.R")) source(file.path(D, "R", f))
A <- commandArgs(TRUE); arg <- function(k, d = NULL) { v <- sub(paste0("^--", k, "="), "", A[grepl(paste0("^--", k, "="), A)])[1]; if (is.na(v)) d else v }
root <- aif_root(); cfg <- aif_cfg(root); aif_low_priority(); setwd(root)
STAGE <- arg("stage", ""); OUT <- aif_results("final", root = root, cfg = cfg); CH <- file.path(OUT, "charts"); dir.create(CH, recursive = TRUE, showWarnings = FALSE)
if (nzchar(STAGE)) aif_stage_begin(STAGE, unit_total = 6L, unit_name = "보고서 부분", threads = cfg$resources$jobs$perf$threads, root = root, cfg = cfg)
step_done <- function(k, msg) { aif_log("%s", msg); if (nzchar(STAGE)) aif_stage_unit(k, msg, root = root, cfg = cfg) }   # 이름을 unit 으로 두면 grid::unit 을 가려 표 그림이 깨진다
RES <- function(...) aif_results(..., root = root, cfg = cfg); CACHE <- function(...) aif_out(..., root = root, cfg = cfg)
bl <- cfg$measure$benchmark_label; PER <- c(ALL = "전기간", IS = "IS(~2022-12)", OOS = "OOS(2023-01~)")

## ── 묶음 목록(보고 순서) ────────────────────────────────────────────────────
SETS <- list(list(set = "new", label = "1판(이미 있던 새 팩터)", what = "재무 204개로 학습한 예측 모형 결합 1판 4개와 수식 탐색 2판 2개 — 이 연구 전에 만들어 둔 것"),
             list(set = "stage3_enumerate", label = "체계적 열거", what = "재무 원계정 쌍에 비율 · 변화 · 성장 형태를 기계적으로 적용해 그때까지의 순위 IC 로 고른 식"),
             list(set = "stage3_fboost", label = "특징 부스팅", what = "중요한 특성 40개의 쌍 연산 가운데 기준 모형의 잔차를 더 줄이는 것"),
             list(set = "stage3_nn", label = "예측 모형 · 신경망", what = "특성 약 640개 → 다음 1개월 · 12개월 수익 순위(3층 신경망 · 씨앗 10개)"),
             list(set = "stage3_tree", label = "예측 모형 · 트리 AutoML", what = "같은 입력 · 표적을 FLAML 이 고른 트리 · 선형 모형으로(+ 신경망과의 평균)"),
             list(set = "stage3_gp", label = "수식 탐색 3판", what = "유전 프로그래밍이 일별 단말 30개로 진화시킨 연산자 수식"),
             list(set = "stage4_latent", label = "잠재팩터 · PCA · IPCA", what = "특성으로 만든 관리 포트폴리오의 주성분 · 특성이 노출을 정하는 잠재팩터"),
             list(set = "stage4_cae", label = "잠재팩터 · 조건부 오토인코더", what = "노출이 특성의 비선형 함수인 잠재팩터(신경망)"))
load_set <- function(s) {
  d <- CACHE("perf", s$set); ids <- if (dir.exists(d)) list.dirs(d, full.names = FALSE, recursive = FALSE) else character(0)
  ids <- ids[file.exists(file.path(d, ids, "done.json"))]; ids <- ids[order(grepl("_TOP[0-9]+$|_F[0-9]+$", ids), ids)]
  o <- list(score = list(), weights = list(), meta = list())
  for (id in ids) {
    m <- fromJSON(file.path(d, id, "done.json"), simplifyVector = FALSE); o$meta[[id]] <- m
    if (identical(m$kind, "weights")) o$weights[[id]] <- list(id = id, stats = fread(file.path(d, id, "stats.csv")), daily = as.data.table(read_parquet(file.path(d, id, "daily.parquet"))), misc = fread(file.path(d, id, "misc.csv")))
    else o$score[[id]] <- aif_perf_load(s$set, id, root = root, cfg = cfg)
  }
  o
}
L <- lapply(SETS, function(s) c(s, load_set(s))); done <- vapply(L, function(x) length(x$score) + length(x$weights) > 0L, TRUE)
if (!any(done)) stop("[aif] 측정이 끝난 묶음이 없다")
res <- list(); grp <- character(0); meta <- list(); setof <- character(0); wres <- list(); wgrp <- character(0)
for (x in L[done]) {
  for (id in names(x$score)) { res[[id]] <- x$score[[id]]; grp[[id]] <- x$label; meta[[id]] <- x$meta[[id]]; setof[[id]] <- x$set }
  for (id in names(x$weights)) { wres[[id]] <- x$weights[[id]]; wgrp[[id]] <- x$label; meta[[id]] <- x$meta[[id]] }
}
GL <- unique(grp); missing_sets <- vapply(L[!done], function(x) x$label, "")
aif_log("끝난 묶음 %d개(%s) · 종목 점수 팩터 %d개 · 잠재팩터 포트폴리오 %d개 · 미완 %s", sum(done), paste(vapply(L[done], function(x) x$set, ""), collapse = ","), length(res), length(wres),
        if (length(missing_sets)) paste(missing_sets, collapse = ", ") else "없음")
M <- aif_market(root, cfg)
ref <- list(stats = fread(CACHE("perf", "_reference", "stats.csv"), encoding = "UTF-8"), daily = as.data.table(read_parquet(CACHE("perf", "_reference", "daily.parquet"))))
pc0 <- function(x) ifelse(is.finite(x), sprintf("%.0f%%", 100 * x), "–")

## ── ① 신규 팩터 성과표(전부) ─────────────────────────────────────────────────
tab <- aif_perf_rows(res, ref, cfg); tab[, method := ifelse(factor %in% names(grp), grp[factor], "기준")]
aif_write_atomic(file.path(OUT, "factor_perf_summary.csv"), function(p) fwrite(tab, p, bom = TRUE))
imgs_tab <- aif_perf_tables(tab, ref, cfg, CH, "신규 팩터 전체")
labels <- as.list(setNames(names(res), names(res)))
grids <- c(aif_chart_grid(res, labels, ref, cfg, file.path(CH, "grid"), what = "top"), aif_chart_grid(res, labels, ref, cfg, file.path(CH, "grid"), what = "ls"))
show_tab <- function(port, per) {
  x <- tab[(portfolio == port | portfolio %in% c("benchmark", "universe_ew")) & period == per]
  o <- x[, .(`방법` = method, `팩터` = factor, `첫 신호` = ifelse(is.na(first_signal), "", substr(first_signal, 1L, 7L)), CAGR = aif_pct(CAGR), SD = aif_pct(SD), SR = aif_num(SR), MDD = aif_pct(MDD),
             Calmar = aif_num(Calmar), `초과수익` = aif_pct(excess_CAGR), IR = aif_num(IR), `β` = aif_num(beta), `월 승률` = pc0(win_month), `회전율(월)` = pc0(turnover_top),
             IC = aif_num(IC, 3), ICIR = aif_num(ICIR), `SR(비용 후)` = aif_num(SR_net), `SR(하루 지연)` = aif_num(SR_d1))]
  if (port == "ls") o[, c("초과수익", "IR", "β", "회전율(월)") := NULL]
  list(o = o, hl = which(x$portfolio %in% c("benchmark", "universe_ew")))
}
step_done(1L, "신규 팩터 성과표")

## ── ② 기존 팩터 DB 와 비교(공통 기간) ────────────────────────────────────────
ovf <- c(RES("stage1", "new_vs_db_overlap.csv"), vapply(SETS, function(s) RES(s$set, "overlap_with_existing.csv"), ""))
OV <- rbindlist(lapply(ovf[file.exists(ovf)], function(p) fread(p, encoding = "UTF-8")[, .(factor, max_abs_corr, with_factor, top5)]), fill = TRUE); OV <- unique(OV[factor %in% names(res)], by = "factor")
CT <- aif_compare_tables(res, M, cfg, root, CH, label = "새 팩터", overlap = OV); C <- CT$CMN; cm_from <- format(CT$d0, "%Y-%m")
aif_write_atomic(file.path(OUT, "common_period_perf.csv"), function(p) fwrite(C, p, bom = TRUE))
wide <- function(port) C[portfolio == port & period == "ALL" & !kind %in% c("벤치마크", "참고"), .(kind, factor, SR, CAGR, SD, MDD)]
RK <- merge(wide("top"), wide("ls"), by = c("kind", "factor"), suffixes = c("_top", "_ls"), all = TRUE)
oos <- dcast(C[period == "OOS" & !kind %in% c("벤치마크", "참고"), .(factor, portfolio, SR)], factor ~ portfolio, value.var = "SR")
for (cn in c("top", "ls")) if (!cn %in% names(oos)) set(oos, j = cn, value = NA_real_)
setnames(oos, c("top", "ls"), c("SR_top_OOS", "SR_ls_OOS")); RK <- merge(RK, oos, by = "factor", all.x = TRUE)
RK[, method := ifelse(kind == "새 팩터", grp[factor], kind)]; RK[, max_corr := OV$max_abs_corr[match(factor, OV$factor)]]
RK[, rank_top := frank(-SR_top, ties.method = "min", na.last = "keep")]; RK[, rank_ls := frank(-SR_ls, ties.method = "min", na.last = "keep")]; setorder(RK, rank_ls)
aif_write_atomic(file.path(OUT, "integrated_ranking.csv"), function(p) fwrite(RK, p, bom = TRUE))
rk_show <- function(x) x[, .(`순위(롱숏)` = rank_ls, `순위(롱온리)` = rank_top, `구분` = method, `팩터` = sub("^CAT_", "합성 ", factor), `롱숏 SR` = aif_num(SR_ls), `롱숏 CAGR` = aif_pct(CAGR_ls), `롱숏 MDD` = aif_pct(MDD_ls),
                         `롱숏 SR(OOS)` = aif_num(SR_ls_OOS), `롱온리 SR` = aif_num(SR_top), `롱온리 CAGR` = aif_pct(CAGR_top), `롱온리 MDD` = aif_pct(MDD_top), `롱온리 SR(OOS)` = aif_num(SR_top_OOS))]
rk_img <- function(x, prefix, ttl) aif_table_png(rk_show(x)[, c(1:8)], file.path(CH, prefix), ttl, hl_rows = which(x$kind == "새 팩터"),
                                                note = sprintf("붉은 줄 = 새 팩터 · 대상 = 새 팩터 %d개 + 기존 개별 팩터 %d개 + 기존 합성 · 공통 기간 %s ~ · 거래비용 전", RK[kind == "새 팩터", .N], CT$n_existing, cm_from))
imgs_rank <- rk_img(RK[seq_len(min(.N, 28L))], "table_rank_ls", sprintf("통합 순위(롱숏 SR 순 · 상위 28) — 새 팩터 + 기존 팩터 DB · 공통 기간 %s ~", cm_from))
E <- C[kind == "개별 팩터" & period == "ALL"]; N <- C[kind == "새 팩터" & period == "ALL"]; N[, method := factor(grp[factor], levels = GL)]
pal <- setNames(scales::brewer_pal(palette = "Dark2")(max(3L, length(GL)))[seq_along(GL)], GL)
dist1 <- function(port, ttl) ggplot(E[portfolio == port], aes(SR)) + geom_histogram(bins = 40, fill = "#c9d1d9", colour = "white") +
  geom_vline(data = N[portfolio == port], aes(xintercept = SR, colour = method), linewidth = 0.6) + scale_colour_manual(values = pal, name = NULL) +
  labs(title = ttl, subtitle = sprintf("회색 = 기존 팩터 DB 개별 팩터 %d개 · 세로선 = 새 팩터(색 = 만든 방법) · 공통 기간 %s~ · 거래비용 전", E[portfolio == port, .N], cm_from)) + aif_theme(10)
sc <- ggplot(E[portfolio == "top"], aes(MDD, SR)) + geom_point(colour = "#b0b8c1", size = 1.1, alpha = 0.8) + geom_point(data = N[portfolio == "top"], aes(colour = method), size = 2.6) +
  scale_colour_manual(values = pal, name = NULL) + scale_x_continuous(labels = label_percent(accuracy = 1)) +
  labs(title = "SR × MDD — 상위 분위 롱온리", subtitle = sprintf("회색 = 기존 개별 팩터 · 색 = 새 팩터 · 공통 기간 %s~", cm_from)) + aif_theme(10) + theme(axis.title = element_text(size = 9)) + xlab("MDD") + ylab("SR")
p_dist <- aif_png(dist1("top", "기존 팩터 DB 의 SR 분포 vs 새 팩터 — 상위 분위 롱온리") / dist1("ls", "기존 팩터 DB 의 SR 분포 vs 새 팩터 — 상위−하위 롱숏") / sc, file.path(CH, "compare_distribution.png"), w = 1080, h = 2000)
TOPW <- as.data.table(read_parquet(CACHE("perf", "db", "daily_top.parquet"))); LSW <- as.data.table(read_parquet(CACHE("perf", "db", "daily_ls.parquet"))); cats <- grep("^CAT_", names(TOPW), value = TRUE)
pl_all <- function(col, W, ttl, file) {
  PL <- rbind(rbindlist(lapply(cats, function(id) data.table(Date = W$Date, s = id, g = "기존 카테고리 합성", r = W[[id]]))),
              rbindlist(lapply(names(res), function(id) data.table(Date = res[[id]]$daily$Date, s = id, g = grp[[id]], r = res[[id]]$daily[[col]]))),
              data.table(Date = ref$daily$Date, s = bl, g = bl, r = ref$daily$bm))
  PL <- PL[Date >= CT$d0 & is.finite(r)]; PL[, v := aif_cum(r), by = s]; PL[, g := factor(g, levels = c("기존 카테고리 합성", GL, bl))]
  g <- ggplot(PL, aes(Date, v, group = s, colour = g, linewidth = g)) + geom_line() + scale_y_log10(labels = label_number(accuracy = NULL)) +
    geom_vline(xintercept = as.Date(cfg$measure$is_end), linetype = "dashed", colour = "#888888", linewidth = 0.3) +
    scale_colour_manual(values = c(c(`기존 카테고리 합성` = "#c9d1d9"), pal, setNames("#111111", bl)), name = NULL) +
    scale_linewidth_manual(values = c(c(`기존 카테고리 합성` = 0.3), setNames(rep(0.5, length(GL)), GL), setNames(0.95, bl)), guide = "none") +
    labs(title = ttl, subtitle = sprintf("공통 기간 %s ~ · 로그축 · 점선 = IS/OOS 경계 · 거래비용 전\n회색 = 기존 팩터 DB 카테고리 합성 · 검정 = %s", cm_from, bl)) + aif_theme(11) + guides(colour = guide_legend(nrow = 3))
  aif_png(g, file.path(CH, file), w = 1080, h = 1000)
}
p_all <- c(pl_all("top", TOPW, sprintf("신규 팩터 전체 P/L — 상위 분위 롱온리 vs %s", bl), "all_top.png"), pl_all("ls", LSW, sprintf("신규 팩터 전체 P/L — 상위−하위 롱숏 vs %s", bl), "all_ls.png"))
step_done(2L, "기존 팩터 DB 비교")

## ── ③ 잠재팩터(포트폴리오 · 모형 설명력 · 구성) ──────────────────────────────
WT <- if (length(wres)) rbindlist(lapply(wres, function(r) r$stats), fill = TRUE) else NULL
if (!is.null(WT)) aif_write_atomic(file.path(OUT, "latent_portfolios_perf.csv"), function(p) fwrite(WT, p, bom = TRUE))
lat_tab <- if (is.null(WT)) NULL else {
  w <- merge(WT[period == "ALL"], dcast(WT[period != "ALL"], factor ~ period, value.var = "SR"), by = "factor", all.x = TRUE, sort = FALSE)
  for (cn in c("IS", "OOS")) if (!cn %in% names(w)) set(w, j = cn, value = NA_real_)
  mi <- rbindlist(lapply(wres, function(r) r$misc), fill = TRUE); w <- merge(w, mi[, .(factor, names_avg, gross_avg, net_avg, first_signal)], by = "factor", all.x = TRUE, sort = FALSE)
  w[, .(`방법` = wgrp[factor], `잠재팩터 포트폴리오` = factor, `첫 신호` = substr(first_signal, 1L, 7L), CAGR = aif_pct(CAGR), SD = aif_pct(SD), SR = aif_num(SR), MDD = aif_pct(MDD),
        `SR(IS)` = aif_num(IS), `SR(OOS)` = aif_num(OOS), `총 노출` = pc0(gross_avg), `순 노출` = aif_pct(net_avg, 0))]
}
mlogs <- c(RES("stage4_latent", sprintf("model_log_%s.json", c("pca", "rppca", "ipca"))), RES("stage4_cae", "model_log_cae.json")); mlogs <- mlogs[file.exists(mlogs)]
ML <- lapply(mlogs, function(p) fromJSON(p, simplifyVector = FALSE)); names(ML) <- vapply(ML, function(x) toupper(x$model), "")
r2_tab <- if (!length(ML)) NULL else rbindlist(lapply(ML, function(x) { ks <- vapply(x$retrains, function(z) as.numeric(z$K), 0); kt <- table(ks)
  data.table(`모형` = toupper(x$model), `전체 R²(표본 밖)` = sprintf("%.1f%%", 100 * as.numeric(x$r2_oos$total_r2 %||% NA)), `예측 R²(표본 밖)` = sprintf("%+.2f%%", 100 * as.numeric(x$r2_oos$pred_r2 %||% NA)),
             `고른 팩터 수(해 수)` = paste(sprintf("%s개 × %d해", names(kt), as.integer(kt)), collapse = " · "), `재추정` = sprintf("%d회", length(x$retrains))) }))
load_tab <- if (!length(ML)) NULL else rbindlist(lapply(ML, function(x) { z <- x$retrains[[length(x$retrains)]]; lt <- z$loadings_top; cc <- unlist(z$const_corr)
  rbindlist(lapply(seq_along(lt), function(j) data.table(`모형` = toupper(x$model), `추정 해` = z$year, `잠재팩터` = names(lt)[j], `시장 전체와의 상관` = if (length(cc) >= j) sprintf("%+.2f", cc[j]) else "",
                                                       `상관이 큰 특성(상관)` = paste(vapply(lt[[j]][seq_len(min(8L, length(lt[[j]])))], function(e) sprintf("%s %+.2f", e[[1]], as.numeric(e[[2]])), ""), collapse = " · ")))) }))
step_done(3L, "잠재팩터 정리")

## ── ④ 무엇으로 만들어졌나(뽑힌 식 · 중요 특성) ───────────────────────────────
formulas <- function(set) { p <- RES(set, "selected_formulas.csv"); if (!file.exists(p)) return(NULL); x <- fread(p, encoding = "UTF-8")
  if (!all(c("year_selected", "pick", "formula") %in% names(x))) return(list(raw = x[seq_len(min(.N, 20L))]))
  list(freq = x[, .(`뽑힌 해 수` = .N, `처음` = min(year_selected), `마지막` = max(year_selected), `가장 높은 순번` = min(pick)), by = .(`식` = formula)][order(-`뽑힌 해 수`, `가장 높은 순번`)][seq_len(min(.N, 15L))],
       last = x[year_selected == max(year_selected)][order(pick)][seq_len(min(.N, 10L)), .(`순번` = pick, `식` = formula, `방향` = if ("direction" %in% names(x)) direction else NA)], year = max(x$year_selected)) }
importance <- function(p) { if (!file.exists(p)) return(NULL); x <- fromJSON(p, simplifyVector = FALSE)$retrains
  z <- tryCatch(rbindlist(lapply(x, function(r) rbindlist(lapply(r$importance_top, function(e) data.table(feature = as.character(e[[1]]), v = as.numeric(e[[2]])))))), error = function(e) NULL)
  if (is.null(z) || !nrow(z)) return(NULL)
  z[, .(`상위 30 안에 든 해 수` = .N, `평균 중요도` = formatC(mean(v), format = "g", digits = 3)), by = .(`특성` = feature)][order(-`상위 30 안에 든 해 수`)][seq_len(min(.N, 15L))] }
FORM <- list(`체계적 열거` = formulas("stage3_enumerate"), `특징 부스팅` = formulas("stage3_fboost"), `수식 탐색 3판` = formulas("stage3_gp"))
IMP <- list(`신경망 · 1개월 표적` = importance(RES("stage3_nn", "retrain_log_1m.json")), `신경망 · 12개월 표적` = importance(RES("stage3_nn", "retrain_log_12m.json")),
            `트리 AutoML · 1개월 표적` = importance(RES("stage3_tree", "retrain_log_1m.json")), `트리 AutoML · 12개월 표적` = importance(RES("stage3_tree", "retrain_log_12m.json")))
step_done(4L, "구성 정리")

## ── ⑤ 요약 줄(숫자는 위 표에서만) ────────────────────────────────────────────
A0 <- tab[period == "ALL"]; O0 <- tab[period == "OOS"]; num <- function(x, d = 2) ifelse(is.finite(x), formatC(x, format = "f", digits = d), "–")
ln_method <- vapply(GL, function(g) { ids <- names(grp)[grp == g]; t1 <- A0[factor %in% ids & portfolio == "top"][which.max(SR)]; l1 <- A0[factor %in% ids & portfolio == "ls"][which.max(SR)]
  sprintf("%s(%d개) — 롱온리 SR 최고 %s %s · 롱숏 SR 최고 %s %s(OOS %s)", g, length(ids), t1$factor, num(t1$SR), l1$factor, num(l1$SR), num(O0[factor == l1$factor & portfolio == "ls", SR][1])) }, "")
rl <- CT$ranks[["ls ALL"]]; rt <- CT$ranks[["top ALL"]]; bmc <- C[kind == "벤치마크" & portfolio == "top" & period == "ALL"]; tot <- C[factor == "CAT_TOTAL" & period == "ALL"]
bestl <- N[portfolio == "ls"][which.max(SR)]; bestt <- N[portfolio == "top"][which.max(SR)]
ln_head <- c(sprintf("신규 팩터 %d개(종목 점수) + 잠재팩터 포트폴리오 %d개 — 끝난 묶음 %d개%s", length(res), length(wres), sum(done), if (length(missing_sets)) sprintf(" · 아직 안 끝난 묶음: %s", paste(missing_sets, collapse = ", ")) else ""),
             sprintf("공통 기간 %s ~ · 상위 분위 롱온리 SR — %s %s · 기존 전체 합성 %s · 신규 최고 %s %s(기존 개별 %d개 가운데 %d위)", cm_from, bl, num(bmc$SR), num(tot[portfolio == "top", SR]), bestt$factor, num(bestt$SR), CT$n_existing, rt[[bestt$factor]]),
             sprintf("공통 기간 롱숏 SR — 기존 전체 합성 %s · 신규 최고 %s %s(%d위) · 기존 개별 팩터를 모두 앞선 신규 %d개 · 10위 안 %d개 · 기존 중간값 아래 %d개", num(tot[portfolio == "ls", SR]), bestl$factor, num(bestl$SR), rl[[bestl$factor]],
                     sum(rl == 1L), sum(rl <= 10L), sum(rl > CT$n_existing / 2)))
lines <- c(ln_head, ln_method)
step_done(5L, "요약")

## ── ⑥ 보고서 파일(한 파일 · 그림 포함) ───────────────────────────────────────
esc <- function(x) gsub(">", "&gt;", gsub("<", "&lt;", gsub("&", "&amp;", as.character(x), fixed = TRUE), fixed = TRUE), fixed = TRUE)
htab <- function(dt, hl = integer(0)) {
  if (is.null(dt) || !nrow(dt)) return("<p class='mute'>(없음)</p>")
  X <- as.matrix(dt[, lapply(.SD, as.character)]); X[is.na(X)] <- ""
  rows <- vapply(seq_len(nrow(X)), function(i) sprintf("<tr%s>%s</tr>", if (i %in% hl) " class='hl'" else "", paste0("<td>", esc(X[i, ]), "</td>", collapse = "")), "")
  paste0("<div class='tw'><table><tr>", paste0("<th>", esc(names(dt)), "</th>", collapse = ""), "</tr>", paste(rows, collapse = ""), "</table></div>")
}
img <- function(p) if (length(p) && file.exists(p)) sprintf("<img src='data:image/png;base64,%s'>", gsub("[\r\n]", "", jsonlite::base64_enc(readBin(p, "raw", file.size(p))))) else ""
sec <- function(id, title, ...) paste0(sprintf("<h2 id='%s'>%s</h2>", id, esc(title)), paste0(..., collapse = ""))
det <- function(title, ...) paste0("<details><summary>", esc(title), "</summary>", paste0(..., collapse = ""), "</details>")
fchart <- function(id) { s <- if (identical(setof[[id]], "new")) "stage1" else setof[[id]]; RES(s, "charts", sprintf("factor_%s.png", id)) }
perf_html <- paste0(unlist(lapply(c("top", "ls"), function(pt) lapply(names(PER), function(p) { z <- show_tab(pt, p)
  paste0(sprintf("<h3>%s · %s</h3>", if (pt == "top") "상위 분위 롱온리" else "상위−하위 롱숏", PER[[p]]), htab(z$o, z$hl)) }))), collapse = "")
cmn_html <- paste0(unlist(lapply(c("top", "ls"), function(pt) { x <- C[portfolio == pt & kind != "개별 팩터"]
  w <- merge(x[period == "ALL"], dcast(x[period != "ALL"], factor ~ period, value.var = c("SR", "CAGR")), by = "factor", all.x = TRUE, sort = FALSE)
  for (cn in c("SR_IS", "SR_OOS", "CAGR_OOS")) if (!cn %in% names(w)) set(w, j = cn, value = NA_real_)
  w <- rbind(w[kind %in% c("벤치마크", "참고")], w[!kind %in% c("벤치마크", "참고")][order(-SR)])
  o <- w[, .(`구분` = ifelse(kind == "새 팩터", grp[factor], kind), `팩터` = sub("^CAT_", "합성 ", factor), CAGR = aif_pct(CAGR), SD = aif_pct(SD), SR = aif_num(SR), MDD = aif_pct(MDD), `초과수익` = aif_pct(excess_CAGR), IR = aif_num(IR),
             `SR(IS)` = aif_num(SR_IS), `SR(OOS)` = aif_num(SR_OOS), `CAGR(OOS)` = aif_pct(CAGR_OOS))]
  if (pt == "ls") o[, c("초과수익", "IR") := NULL]
  paste0(sprintf("<h3>%s — 새 팩터 + 기존 합성 + %s · SR 순</h3>", if (pt == "top") "상위 분위 롱온리" else "상위−하위 롱숏", bl), htab(o, which(w$kind == "새 팩터"))) })), collapse = "")
pos <- data.table(`방법` = grp[names(res)], `팩터` = names(res))
for (pp in list(c("top ALL", "롱온리"), c("top IS", "롱온리 IS"), c("top OOS", "롱온리 OOS"), c("ls ALL", "롱숏"), c("ls IS", "롱숏 IS"), c("ls OOS", "롱숏 OOS"))) {
  port <- strsplit(pp[1], " ")[[1]]; v <- C[kind == "새 팩터" & portfolio == port[1] & period == port[2]]; r <- CT$ranks[[pp[1]]]
  set(pos, j = pp[2], value = ifelse(names(res) %in% v$factor, sprintf("%s (%d위)", aif_num(v$SR[match(names(res), v$factor)]), r[names(res)]), "–"))
}
set(pos, j = "최대 상관", value = aif_num(OV$max_abs_corr[match(names(res), OV$factor)])); set(pos, j = "가장 겹치는 기존 팩터", value = OV$with_factor[match(names(res), OV$factor)])
form_html <- paste0(unlist(lapply(names(FORM), function(k) { z <- FORM[[k]]; if (is.null(z)) return(sprintf("<h3>%s</h3><p class='mute'>(아직 결과 없음)</p>", k))
  if (!is.null(z$raw)) return(paste0(sprintf("<h3>%s — 뽑힌 식(앞 20줄)</h3>", k), htab(z$raw)))
  paste0(sprintf("<h3>%s — 여러 해에 걸쳐 자주 뽑힌 식</h3>", k), htab(z$freq), sprintf("<h3>%s — 마지막 선택(%d년 말)의 앞 10개</h3>", k, z$year), htab(z$last)) })), collapse = "")
imp_html <- paste0(unlist(lapply(names(IMP), function(k) if (is.null(IMP[[k]])) "" else paste0(sprintf("<h3>%s — 해마다 중요도 상위 30 에 자주 든 특성</h3>", k), htab(IMP[[k]])))), collapse = "")
lat_imgs <- c(RES("stage4_latent", "charts", "grid_latent_portfolios.png"), RES("stage4_cae", "charts", "grid_latent_portfolios.png"))
css <- "body{font-family:'Malgun Gothic','Apple SD Gothic Neo',sans-serif;max-width:1180px;margin:24px auto;padding:0 16px;color:#1c2430;line-height:1.55}h1{font-size:24px}h2{font-size:19px;margin-top:38px;border-bottom:2px solid #1c2430;padding-bottom:4px}h3{font-size:15px;margin:22px 0 6px}
.tw{overflow-x:auto}table{border-collapse:collapse;font-size:12.5px;white-space:nowrap}th{background:#2b3a4f;color:#fff;padding:5px 8px;text-align:center}td{padding:4px 8px;border-bottom:1px solid #e6e9ee;text-align:right}td:nth-child(1),td:nth-child(2){text-align:left}
tr.hl td{background:#fdecec}img{max-width:100%;display:block;margin:10px 0}.mute{color:#6b7684;font-size:13px}details{margin:8px 0}summary{cursor:pointer;font-weight:600}ul{padding-left:20px}.note{background:#f4f6f9;padding:10px 14px;border-radius:6px;font-size:13px}"
html <- paste0("<!doctype html><html lang='ko'><head><meta charset='utf-8'><title>AI 팩터 연구 — 종합 보고</title><style>", css, "</style></head><body>",
  sprintf("<h1>AI 팩터 연구 — %s</h1><p class='mute'>만든 때 %s · 측정 = 전 종목 5분위 · 월말 신호 · 거래비용 전(따로 적은 곳 제외) · IS = ~2022-12 · OOS = 2023-01~ · 벤치마크 = %s</p>",
          if (length(missing_sets)) "중간 종합 보고(끝난 단계까지)" else "종합 보고", format(Sys.time(), "%Y-%m-%d %H:%M"), bl),
  sec("s1", "1. 한 장 요약", "<ul>", paste0("<li>", esc(lines), "</li>", collapse = ""), "</ul>",
      htab(rbindlist(lapply(L, function(x) data.table(`묶음` = x$label, `상태` = if (length(x$score) + length(x$weights)) "끝남" else "아직 안 끝남", `종목 점수 팩터` = length(x$score), `잠재팩터 포트폴리오` = length(x$weights), `무엇인가` = x$what))))),
  sec("s2", "2. 신규 팩터 성과표 — 전부", "<p class='note'>팩터 줄은 각자 첫 신호 다음 달부터 잰 값이고, 벤치마크 줄은 그 기간 전체다. 초과수익 · IR · β 는 그 팩터와 같은 구간의 ", esc(bl),
      " 대비. 같은 구간끼리의 비교는 4절(공통 기간). 'SR(하루 지연)' = 월말 종가 대신 다음 달 첫 거래일 종가에 매매한 판 · 'SR(비용 후)' = 편도 15bp 를 뺀 판. 롱숏의 SR 은 무위험 수익을 빼지 않았다.</p>", perf_html),
  sec("s3", "3. P/L 그래프 — 벤치마크 포함", "<h3>신규 팩터 전체 — 한 그림</h3>", img(p_all[1]), img(p_all[2]), "<h3>팩터별(한 장에 6개)</h3>", paste0(vapply(grids, img, ""), collapse = ""),
      "<h3>팩터별 상세 — P/L · 낙폭 · 5분위 · 롱숏 · 누적 IC</h3>", paste0(vapply(GL, function(g) det(sprintf("%s (%d개)", g, sum(grp == g)), paste0(vapply(names(grp)[grp == g], function(id) img(fchart(id)), ""), collapse = "")), ""), collapse = "")),
  sec("s4", sprintf("4. 기존 팩터 DB 와 비교 — 공통 기간 %s ~", cm_from), "<p class='note'>기존 팩터 DB 의 팩터(월간 값이 있는 ", CT$n_existing, "개)와 카테고리 합성을 같은 측정기 · 같은 유니버스 · 같은 구간에서 잰 값이다. 기존 팩터의 방향은 등록부에 선언된 방향 그대로.</p>",
      cmn_html, "<h3>새 팩터의 SR 과 기존 개별 팩터 가운데 순위</h3>", htab(pos), img(p_dist), "<h3>P/L 비교 — 새 팩터 vs 기존 카테고리 합성</h3><p class='mute'>3절의 전체 P/L 그림에 회색 선으로 함께 그렸다.</p>",
      det(sprintf("통합 순위표 전체(새 팩터 + 기존 개별 · 합성 %d줄 · 롱숏 SR 순)", nrow(RK)), htab(rk_show(RK), which(RK$kind == "새 팩터")))),
  sec("s5", "5. 잠재팩터", "<h3>모형 설명력과 팩터 수</h3>", htab(r2_tab), "<p class='mute'>전체 R² = 그 달 횡단면 회귀로 구한 팩터 수익이 종목 수익을 설명하는 비율 · 예측 R² = 그때까지의 팩터 평균 수익만으로 설명하는 비율(0 아래면 0 을 예측하는 것보다 못하다).</p>",
      "<h3>잠재팩터 포트폴리오 성과</h3>", htab(lat_tab), "<p class='mute'>비중 = 모형이 낸 종목 비중 그대로(노출 1 단위당 수익). 순 노출이 +100% 에 가까우면 시장 전체에 가까운 팩터다. 잠재팩터는 해마다 다시 추정되므로 같은 번호라도 해가 바뀌면 다른 팩터일 수 있다.</p>",
      paste0(vapply(lat_imgs, img, ""), collapse = ""), "<h3>마지막 추정에서 각 잠재팩터와 상관이 큰 특성</h3>", htab(load_tab)),
  sec("s6", "6. 무엇으로 만들어졌나", form_html, imp_html),
  sec("s7", "7. 한계와 다음", "<ul><li>OOS 는 2023-01 부터 약 4년이다. 이 구간은 대형주 지수가 크게 오른 때라, 전 종목 동일가중 5분위로 만든 롱온리는 ", esc(bl), " 대비 초과수익이 대부분 음수다(유니버스 동일가중 자체가 지수에 크게 뒤졌다).</li>",
      "<li>롱숏 성과의 큰 부분이 하위 분위(매도 쪽)에서 나온다. 한국 시장에서 소형주 매도는 실제로 하기 어렵다 — 실행 가능한 성과는 상위 분위 롱온리 줄로 본다.</li>",
      "<li>거래비용은 편도 15bp 만 뺐다(시장 충격 · 호가 차이 없음). 회전율이 높은 팩터일수록 실제 성과와의 차이가 크다.</li>",
      "<li>식 · 모형 · 팩터 수는 해마다 그때까지의 자료로만 고르고 다음 해에만 썼다. 다만 방법 자체(어떤 생성기를 쓸지 · 설정값)는 한 번에 정한 것이라, 여러 방법 가운데 좋은 것만 보면 성과가 부풀어 보일 수 있다.</li>",
      "<li>다음: 동적 팩터 배분(국면별 조합)은 이 결과를 보고 따로 정한다.</li></ul>"),
  "</body></html>")
aif_write_atomic(file.path(OUT, "final_report.html"), function(p) writeLines(html, p, useBytes = TRUE))
charts <- c(imgs_tab, p_all, CT$images, imgs_rank, p_dist, grids, RES("stage4_latent", "charts", "table_latent_portfolios_01.png"), RES("stage4_cae", "charts", "table_latent_portfolios_01.png"), lat_imgs); ok <- file.exists(charts)
cn <- c(rep("신규 팩터 전체 성과표", length(imgs_tab)), rep("신규 팩터 전체 P/L", length(p_all)), rep("공통 기간 비교 · 순위", length(CT$images)), rep("통합 순위", length(imgs_rank)), "기존 팩터 분포 속 위치",
        rep("P/L 격자", length(grids)), rep("잠재팩터 포트폴리오", 2L + length(lat_imgs)))
aif_write_json(list(at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"), title = if (length(missing_sets)) "중간 종합 보고" else "종합 보고 — 신규 팩터 전체", lines = as.list(lines), charts = as.list(unname(charts[ok])), chart_names = as.list(cn[ok])),
               CACHE("stage_summary_final.json"))
if (nzchar(STAGE)) { aif_stage_unit(6L, "보고서 파일", root = root, cfg = cfg); aif_stage_end(done = !length(missing_sets), root = root, cfg = cfg) }
aif_log("종합 보고 — 팩터 %d개 · 그림 %d장 · %s (%.1f MB)", length(res), sum(ok), file.path(OUT, "final_report.html"), file.size(file.path(OUT, "final_report.html")) / 2^20); cat(paste0(lines, collapse = "\n"), "\n")
