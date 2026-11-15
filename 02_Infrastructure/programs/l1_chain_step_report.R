## 강화 사슬 걸음 보고 — 걸음 하나가 판정될 때마다 텔레그램 1통(push) + IS 성과 차트 2장 (도훈 11-15 20시 "강화 프로세스 하나가 끝날때마다 텔레그램 보내줘. 성과에 대한 시각자료 포함해서")
##   chain_tick.sh 는 걸음 열기 · 측정 · 판정을 로그에만 남긴다(푸시 없음) — 이 스크립트가 사슬 원장(chain_steps.jsonl)의 step_result 를 읽어 걸음마다 1통을 보낸다.
##   호출 = 예약 작업 Qvest_StandingBoard(.bat — 사슬 틱 다음 · 진행 브리핑 앞). 손 틱 뒤에는 손으로 불러도 된다(같은 걸음은 한 번만 — 상태 파일).
##   차트(IS 만 — 산출물 CSV 를 읽자마자 사슬 판의 tau_d(2022-12-31) 뒤 행을 버린다 · OOS 값은 그리지도 싣지도 않는다):
##     ① 누적 수익(로그) · 낙폭 — 기저 vs 이 걸음 vs KOSPI200(공통 IS 창에서 1 로 맞춤)  ② 핵심 지표(기저 vs 걸음) · 위기별 하락노출(같은 위기끼리)
##   수치 = 사슬 원장 *_vis(등록 규칙이 판정에 쓴 IS 값) · 원장에 없는 값은 계산하지 않는다(AX-008 — 차트 선만 NAV 로 그린다).
##   상태 = .cache/l1_chain_step_report_state.json(보낸 걸음 '사슬:k' 목록). 상태가 없으면 지금까지의 걸음은 기준선(보낸 것으로) — 다음 걸음부터 보낸다.
## 사용: Rscript 02_Infrastructure/programs/l1_chain_step_report.R [--send] [--chain <사슬 id> --k <걸음>]
##   --send 없으면 드라이런(차트는 만들고 상태는 안 씀) · --chain/--k = 그 걸음 한 통(보낸 적 있어도)
a <- commandArgs(trailingOnly = TRUE); SEND <- "--send" %in% a
argv <- function(k) if (k %in% a) a[which(a == k) + 1L] else NA_character_
ONE_CHAIN <- argv("--chain"); ONE_K <- suppressWarnings(as.integer(argv("--k")))
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
suppressMessages({ library(jsonlite); library(data.table); library(ggplot2); library(patchwork) })
STP <- Sys.getenv("L1SR_STATE", ".cache/l1_chain_step_report_state.json")
rj <- function(p) tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
rjl <- function(p) { L <- tryCatch(readLines(p, encoding = "UTF-8", warn = FALSE), error = function(e) character(0)); L <- L[nzchar(trimws(L))]
  Filter(Negate(is.null), lapply(L, function(x) tryCatch(fromJSON(x, simplifyVector = FALSE), error = function(e) NULL))) }
num <- function(x) { v <- suppressWarnings(as.numeric(unlist(x))[1]); if (length(v) && is.finite(v)) v else NA_real_ }
f2 <- function(x) { v <- num(x); if (is.na(v)) "NA" else formatC(v, format = "f", digits = 2) }
pc <- function(x) { v <- num(x); if (is.na(v)) "NA" else paste0(formatC(100 * v, format = "f", digits = 1), "%") }
sg <- function(x, d = 2) { v <- num(x); if (is.na(v)) "NA" else paste0(if (v >= 0) "+" else "−", formatC(abs(v), format = "f", digits = d)) }
CAT <- c(value = "밸류", growth = "성장", consensus = "컨센서스", accrual = "발생액", crowding = "쏠림", defense = "방어", investor_flow = "수급",
         leverage = "레버리지", liquidity = "유동성", momentum = "모멘텀", quality = "퀄리티", regime = "국면", risk = "위험", technical = "기술적")
eng_label <- function(p) {
  b <- basename(dirname(as.character(p)))
  if (grepl("^FC_FAM_", b)) { k <- sub("^FC_FAM_", "", b); ic <- grepl("_ICW$", k); k <- sub("_ICW$", "", k)
    l <- unname(CAT[k]); if (is.na(l)) l <- k; return(paste0(l, if (ic) "(IC 가중)" else "")) }
  if (grepl("^FC_TOTAL", b)) return("토탈")
  sub("^RP_AUTO_(CLEAN_)?", "", b)
}
RULE <- c(improve = "종합점수 S 개선", uc_floor = "상승 포착 하한", crisis_no_worse = "위기 하락노출 비악화", bull_segments = "강세 구간별 참여",
          deep_crisis = "깊은 위기 과반 비악화", beta_asym = "하락 β ≤ 상승 β(β 로 산 방어 아님)", concentration = "종목 집중")
clean_txt <- function(x) { x <- gsub("보는 창", "IS", x, fixed = TRUE); x <- gsub("등가중", "동일가중", x, fixed = TRUE)
  x <- gsub("가족", "카테고리", x, fixed = TRUE); gsub("기저 칸", "기저 전략", x, fixed = TRUE) }
fam <- ""; fdir <- c(file.path(Sys.getenv("LOCALAPPDATA"), "Microsoft", "Windows", "Fonts"), file.path(Sys.getenv("WINDIR", "C:/Windows"), "Fonts"))
fM <- file.path(fdir, "현대하모니+M.ttf"); fM <- fM[file.exists(fM)][1]
if (!is.na(fM)) { try(systemfonts::register_font(name = "HDHM", plain = fM), silent = TRUE); fam <- "HDHM" }

## IS NAV(순) — 읽자마자 tau 뒤 행을 버린다
is_nav <- function(art, tau) {
  x <- tryCatch(fread(file.path(art, "02_nav.csv"), select = c("date", "nav_net")), error = function(e) NULL); if (is.null(x)) return(NULL)
  x[, date := as.Date(date)]; x <- x[date <= tau & is.finite(nav_net)]; stopifnot(!nrow(x) || max(x$date) <= tau); x
}
is_bench <- function(art, tau) {
  x <- tryCatch(fread(file.path(art, "05_benchmark_returns.csv"), select = c("date", "benchmark_ret")), error = function(e) NULL); if (is.null(x)) return(NULL)
  x[, date := as.Date(date)]; x <- x[date <= tau & is.finite(benchmark_ret)]; x[, nav := cumprod(1 + benchmark_ret)]; x[, .(date, nav)]
}

report_one <- function(cdir, R, res) {
  id <- basename(cdir); spec <- rj(file.path(cdir, "chain_spec.json")); tau <- as.Date(spec$tau_d %||% "2022-12-31")
  ev <- vapply(R, function(r) as.character(r$event %||% ""), ""); k <- as.integer(res$k)
  base_lab <- if (!is.null(spec$base$engine_path)) eng_label(spec$base$engine_path) else "?"
  blend <- identical(unlist(spec$step_policy$blocks), "blend"); label <- sprintf("%s 사슬(%s 기저)", if (blend) "블렌딩" else "강화", base_lab)
  op <- Filter(function(r) identical(r$event, "step_open") && identical(as.integer(r$k), k), R)[[1]]
  cs <- rj(op$cell_spec_path); paths <- unlist(cs$base_signal$paths); parts <- if (length(paths)) paste(vapply(paths, eng_label, ""), collapse = " + ") else "?"
  bm <- Filter(function(r) identical(r$event, "base_measured"), R); bm <- bm[[length(bm)]]
  allres <- R[ev == "step_result"]; acc <- sum(vapply(allres, function(r) identical(r$decision, "accept"), TRUE)); rej <- sum(vapply(allres, function(r) identical(r$decision, "reject"), TRUE))
  ## 비교 기준 = 부모(채택된 앞 걸음이 있으면 그 걸음 · 없으면 기저) — 원장 parent_basis 그대로
  par_k <- as.integer(op$parent %||% 0L)
  par_res <- if (par_k > 0L) Filter(function(r) identical(r$event, "step_result") && identical(as.integer(r$k), par_k), R)[[1]] else NULL
  pm <- if (is.null(par_res)) bm$metrics else par_res$metrics; part_art <- if (is.null(par_res)) bm$artifacts else par_res$artifacts
  par_name <- if (is.null(par_res)) sprintf("기저(%s)", base_lab) else sprintf("걸음 %d", par_k)
  m <- res$metrics; t <- res$table %||% list(); rl <- res$rules %||% list()
  ## ── 차트 ① 누적 수익(로그) · 낙폭 ──
  A <- is_nav(part_art, tau); B <- is_nav(res$artifacts, tau); K <- is_bench(res$artifacts, tau)
  charts <- character(0); odir <- file.path(cdir, "results", "step_report"); dir.create(odir, recursive = TRUE, showWarnings = FALSE)
  nm_step <- sprintf("걸음 %d(%s)", k, parts)
  if (!is.null(A) && !is.null(B) && nrow(A) && nrow(B)) {
    d0 <- max(min(A$date), min(B$date), if (!is.null(K) && nrow(K)) min(K$date) else min(A$date))
    reb <- function(x, col, who) { x <- x[date >= d0]; v <- x[[col]] / x[[col]][1]; data.table(date = x$date, v = v, dd = v / cummax(v) - 1, who = who) }
    L <- rbindlist(list(reb(A, "nav_net", par_name), reb(B, "nav_net", nm_step), if (!is.null(K) && nrow(K)) reb(K, "nav", "KOSPI200")))
    L[, who := factor(who, levels = c(nm_step, par_name, "KOSPI200"))]
    cols <- setNames(c("#D9822B", "#3B6FB6", "#555555"), c(nm_step, par_name, "KOSPI200"))
    th <- theme_minimal(base_family = fam, base_size = 12) + theme(legend.position = "top", legend.title = element_blank(), panel.grid.minor = element_blank(),
                                                                   plot.title = element_text(size = 14), plot.caption = element_text(size = 8.2, colour = "#777777"))
    g1 <- ggplot(L, aes(date, v, colour = who, linetype = who)) + geom_line(linewidth = 0.7) + scale_y_log10() +
      scale_colour_manual(values = cols) + scale_linetype_manual(values = setNames(c("solid", "solid", "dashed"), names(cols))) +
      labs(title = sprintf("IS 누적 수익(로그) — %s vs %s vs KOSPI200", nm_step, par_name), x = NULL, y = NULL) + th
    g2 <- ggplot(L, aes(date, dd, colour = who, linetype = who)) + geom_line(linewidth = 0.6) + scale_y_continuous(labels = scales::percent) +
      scale_colour_manual(values = cols) + scale_linetype_manual(values = setNames(c("solid", "solid", "dashed"), names(cols))) +
      labs(title = "IS 낙폭", x = NULL, y = NULL,
           caption = sprintf("IS %s ~ %s(공통 창 · 1 로 맞춤) · 순수익(15bps) · IS/OOS 경계 %s · OOS 는 이 차트에 없음", format(d0, "%Y-%m"), format(tau, "%Y-%m"), format(tau))) +
      th + theme(legend.position = "none")
    p1 <- file.path(odir, sprintf("k%d_is_cum_dd.png", k))
    ggsave(p1, g1 / g2 + plot_layout(heights = c(3, 2)), width = 8.6, height = 6.4, dpi = 140, device = ragg::agg_png)
    charts[[sprintf("IS 누적 수익 · 낙폭 — 걸음 %d vs %s vs KOSPI200", k, par_name)]] <- p1
  }
  ## ── 차트 ② 핵심 지표 · 위기별 하락노출 ──
  mets <- c("종합점수 S" = "S_vis", "Calmar" = "calmar_vis", "CAGR" = "cagr_vis", "MDD" = "mdd_vis", "상승 포착" = "uc_vis",
            "위기 하락노출 중앙" = "dd_capture_median_vis", "상승 β" = "beta_up_vis", "하락 β" = "beta_down_vis")
  MB <- rbindlist(lapply(names(mets), function(n) data.table(metric = n, who = c(par_name, nm_step), v = c(num(pm[[mets[[n]]]]), num(m[[mets[[n]]]])))))
  MB[, metric := factor(metric, levels = names(mets))]; MB[, who := factor(who, levels = c(par_name, nm_step))]
  pct <- c("CAGR", "MDD"); MB[, lab := ifelse(metric %in% pct, pc(v), f2(v)), by = seq_len(nrow(MB))]
  g3 <- ggplot(MB, aes(who, v, fill = who)) + geom_col(width = 0.6) + geom_text(aes(label = lab), vjust = -0.3, size = 3.3, family = fam) +
    facet_wrap(~metric, nrow = 2, scales = "free_y") + scale_fill_manual(values = setNames(c("#3B6FB6", "#D9822B"), c(par_name, nm_step))) +
    scale_y_continuous(expand = expansion(mult = c(0, 0.18))) + labs(title = sprintf("IS 핵심 지표 — %s vs %s", par_name, nm_step), x = NULL, y = NULL) +
    theme_minimal(base_family = fam, base_size = 11) + theme(legend.position = "top", legend.title = element_blank(), axis.text.x = element_blank(),
                                                             panel.grid.minor = element_blank(), panel.grid.major.x = element_blank(), plot.title = element_text(size = 14))
  cr <- function(x) { z <- x$crises_vis %||% list(); if (!length(z)) return(data.table())
    rbindlist(lapply(z, function(c) data.table(peak = as.character(c$peak_date), cap = num(c$dd_capture)))) }
  CP <- cr(pm); CS <- cr(m); g <- g3
  if (nrow(CP) && nrow(CS)) {
    CC <- merge(CP, CS, by = "peak", suffixes = c("_p", "_s")); CC <- CC[as.Date(peak) <= tau][order(peak)]
    if (nrow(CC)) {
      CL <- rbind(data.table(peak = CC$peak, who = par_name, cap = CC$cap_p), data.table(peak = CC$peak, who = nm_step, cap = CC$cap_s))
      CL[, crisis := factor(substr(peak, 1, 7), levels = unique(substr(CC$peak, 1, 7)))]; CL[, who := factor(who, levels = c(par_name, nm_step))]
      g4 <- ggplot(CL, aes(crisis, cap, fill = who)) + geom_col(position = position_dodge(0.75), width = 0.7) + geom_hline(yintercept = 1, linetype = "dashed", colour = "#444444") +
        scale_fill_manual(values = setNames(c("#3B6FB6", "#D9822B"), c(par_name, nm_step))) +
        labs(title = "IS 위기별 하락노출(전략 낙폭 ÷ 시장 낙폭 · 1 = 시장만큼)", x = "위기 고점(연-월)", y = NULL,
             caption = "출처: 사슬 원장 IS 기록(등록 규칙이 판정에 쓴 값) · 위기 = KOSPI200 Lunde-Timmermann 20/20 · 같은 위기끼리 비교") +
        theme_minimal(base_family = fam, base_size = 11) + theme(legend.position = "none", panel.grid.minor = element_blank(), axis.text.x = element_text(angle = 45, hjust = 1),
                                                                 plot.title = element_text(size = 13), plot.caption = element_text(size = 8.2, colour = "#777777"))
      g <- g3 / g4 + plot_layout(heights = c(3, 2))
    }
  }
  p2 <- file.path(odir, sprintf("k%d_is_metrics_crises.png", k)); ggsave(p2, g, width = 8.6, height = 7.4, dpi = 140, device = ragg::agg_png)
  charts[[sprintf("IS 핵심 지표 · 위기별 하락노출 — 걸음 %d vs %s", k, par_name)]] <- p2
  ## ── 본문 ──
  ok <- names(rl)[vapply(rl, function(v) isTRUE(v), TRUE)]; bad <- names(rl)[vapply(rl, function(v) isFALSE(v), TRUE)]
  dec <- if (identical(res$decision, "accept")) "채택" else "기각"
  vline <- sprintf("%s — %s%s", dec,
                   if (length(bad)) paste0("미달: ", paste(unname(RULE[intersect(names(RULE), bad)]), collapse = " · ")) else "등록 규칙 전부 통과",
                   if (length(ok)) paste0(" | 통과: ", paste(unname(RULE[intersect(names(RULE), ok)]), collapse = " · ")) else "")
  kv <- c(sprintf("종합점수 S %s → %s(%s · %s)", f2(pm$S_vis), f2(m$S_vis), sg(t$dS_vis), if (identical(res$r7, "noise")) "잡음 범위" else if (identical(res$r7, "signal")) "신호" else "판독 없음"),
          sprintf("CAGR %s → %s · MDD %s → %s · Calmar %s → %s", pc(pm$cagr_vis), pc(m$cagr_vis), pc(pm$mdd_vis), pc(m$mdd_vis), f2(pm$calmar_vis), f2(m$calmar_vis)),
          sprintf("상승 포착 %s → %s · 위기 하락노출 중앙 %s → %s · 상승/하락 β %s/%s → %s/%s", f2(pm$uc_vis), f2(m$uc_vis), f2(pm$dd_capture_median_vis), f2(m$dd_capture_median_vis),
                  f2(pm$beta_up_vis), f2(pm$beta_down_vis), f2(m$beta_up_vis), f2(m$beta_down_vis)))
  dd_better <- isTRUE(num(t$d_dd_capture_median_vis) < 0); uc_drop <- isTRUE(num(t$d_uc_vis) < -0.2)
  rd <- c(if (dd_better && isFALSE(rl$beta_asym)) "위기 하락노출은 줄었지만 하락 β 가 상승 β 보다 커서, 선택 실력이 아니라 전체 β 를 낮춘 효과로 읽힌다(사슬 반증 조건 'β 만 낮춘 방어' 쪽)." else NULL,
          if (!dd_better && isTRUE(num(t$dS_vis) > 0)) "수익 쪽은 올랐지만 위기 하락노출은 줄지 않았다 — 위기 방어 비대칭은 생기지 않았다." else NULL,
          if (uc_drop) "줄어든 낙폭만큼 강세 참여를 내줬다." else NULL,
          if (identical(res$decision, "accept")) "다음 걸음은 이 구성 위에 부품을 하나 더 얹는다." else NULL)
  if (!length(rd)) rd <- "등록 규칙 판정 그대로 — 추가 판독 없음."
  hyp <- clean_txt(as.character(op$hypothesis %||% ""))
  max_steps <- as.integer(spec$budget$max_steps %||% NA)
  nx <- format(if (as.integer(format(Sys.time(), "%M")) < 37L) Sys.time() else Sys.time() + 3600, "%H:37")
  invisible(capture.output(suppressMessages(source("02_Infrastructure/programs/program_report.R"))))
  ex <- list(list(heading = "가설(걸음 설계)", type = "text", body = hyp),
             list(heading = sprintf("IS 핵심 수치 — %s → 걸음 %d", par_name, k), type = "bullet", items = kv),
             list(heading = "판독", type = if (length(rd) >= 2L) "bullet" else "text", items = if (length(rd) >= 2L) rd else NULL, body = if (length(rd) < 2L) rd else NULL))
  prep_send(program = "강화 사슬", target = sprintf("%s 걸음 %d — %s", label, k, parts),
            status = list(stage = "P4 강화 사슬 걸음 판정(IS · 등록 규칙)", position = sprintf("걸음 %d(최대 %s) · 채택 %d · 기각 %d", k, if (is.na(max_steps)) "?" else max_steps, acc, rej),
                          previous = sprintf("비교 기준 = %s", par_name)),
            verdict_line = vline, extra = ex, next_step = sprintf("다음 걸음 — 다음 틱 %s(메모리 관문이 열리면) · 결과는 이 형식으로 1통", nx),
            artifact = odir, charts = charts, push = TRUE, dry_run = !SEND)
  invisible(TRUE)
}

## ── 무엇을 보낼지 ─────────────────────────────────────────────────────────────────────
st0 <- rj(STP); sent <- unlist(st0$reported %||% list())
todo <- list(); all_keys <- character(0)
for (sp in Sys.glob("04_Research/programs/P4_ASSEMBLY/*/chain_steps.jsonl")) {
  cdir <- dirname(sp); id <- basename(cdir); R <- rjl(sp)
  for (r in Filter(function(r) identical(r$event, "step_result"), R)) {
    key <- sprintf("%s:%s", id, r$k); all_keys <- c(all_keys, key)
    one <- !is.na(ONE_CHAIN) && identical(id, ONE_CHAIN) && identical(as.integer(r$k), ONE_K)
    if (one || (is.na(ONE_CHAIN) && !is.null(st0) && !(key %in% sent))) todo[[length(todo) + 1L]] <- list(cdir = cdir, R = R, res = r, key = key)
  }
}
if (is.null(st0) && is.na(ONE_CHAIN)) {   # 첫 실행 = 기준선(지금까지의 걸음은 보낸 것으로)
  if (SEND) { tmp <- paste0(STP, ".tmp"); writeLines(toJSON(list(schema = "l1_chain_step_report_state_v1", reported = as.list(all_keys)), auto_unbox = TRUE, pretty = TRUE), tmp, useBytes = TRUE); file.rename(tmp, STP) }
  cat(sprintf("[걸음 보고] 첫 실행 — 기준선 %d걸음(보내지 않음)%s\n", length(all_keys), if (SEND) "" else " · 드라이런"))
  quit(status = 0)
}
done <- character(0)
for (td in todo) {
  r <- tryCatch({ report_one(td$cdir, td$R, td$res); TRUE }, error = function(e) { cat("[걸음 보고] 실패", td$key, conditionMessage(e), "\n"); FALSE })
  if (isTRUE(r)) done <- c(done, td$key)
}
if (SEND && length(done)) {
  st <- list(schema = "l1_chain_step_report_state_v1", reported = as.list(unique(c(sent, done))))
  tmp <- paste0(STP, ".tmp"); writeLines(toJSON(st, auto_unbox = TRUE, pretty = TRUE), tmp, useBytes = TRUE); file.rename(tmp, STP)
}
cat(sprintf("[걸음 보고] %s · 대상 %d · 성공 %d\n", if (SEND) "발송" else "드라이런", length(todo), length(done)))
