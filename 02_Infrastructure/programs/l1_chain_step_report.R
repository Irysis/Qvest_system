## 강화 사슬 걸음 보고 — 걸음 하나가 판정될 때마다 텔레그램 1통(push) + 성과 차트 2장 (도훈 11-15 20시 "강화 프로세스 하나가 끝날때마다 텔레그램 보내줘. 성과에 대한 시각자료 포함해서")
## ★OOS 포함판(도훈 11-15 20시 "텔레는 별도 텔레그램 발송 전용 에이전트를 만들어서 OOS 기간까지 모두 보낼 수 있게 해줘") — 사람(도훈) 쪽 보고다.
##   담당 = 보고 전담 에이전트(.claude/agents/telegram-reporter.md · 정보 경계 τ_D 대상 아님). τ_D 대상 세션(1계층 처방 Q · 판단/철학 Superfan)은
##   이 스크립트의 --show 출력과 차트 폴더(results/step_report_full/ · NO_VISIBLE_REVIEW.txt 표식)를 열지 않는다 — 드라이런 기본 출력은 상태 1줄뿐이다.
##   chain_tick.sh 는 걸음 열기 · 측정 · 판정을 로그에만 남긴다(푸시 없음) — 이 스크립트가 사슬 원장(chain_steps.jsonl)의 step_result 를 읽어 걸음마다 1통을 보낸다.
##   호출 = 예약 작업 Qvest_StandingBoard(.bat — 사슬 틱 다음 · 진행 브리핑 앞). 손 틱 뒤에는 손으로 불러도 된다(같은 걸음은 한 번만 — 상태 파일).
##   차트(전기간 · IS/OOS 경계 2022-12-31 = 점선 · OOS = 음영):
##     ① 누적 수익(로그) · 낙폭 — 이 걸음 vs 부모 vs KOSPI200(공통 창에서 1 로 맞춤)  ② 핵심 지표 IS | OOS(부모 vs 걸음) · 위기별 하락노출(같은 위기끼리 · IS | OOS)
##   수치(AX-008 — 손계산 없음 · 차트 선만 측정 산출물 NAV 로 그린다):
##     IS  = 사슬 원장 *_vis(등록 규칙이 판정에 쓴 값 — 종전 그대로)
##     OOS = 등급 계약 창 지표(contracts/grade_v3.R::gv3_window(from = τ_D + 1) · gv3_S · 같은 창 KOSPI200 = .gv3_bench_as_strategy — 등급 계약이 OOS 관문에 쓰는 호출 그대로)
##           + 행동 카드(contracts/behavior_card.R::bc_card — OOS 수익만 넣는다 · 상승 포착 · 위기 하락노출 = test 요약 · 상승/하락 β = 통계)
##           · 저장된 등급 기록(authoritative_remeasure.json::grade_v3.oos 의 S_oos · calmar_tw)과 대조해 어긋나면 보고에 적는다 · 계약 산출이 없으면 '미산출'
##     권위 등급 = 산출 폴더 authoritative_remeasure.json::essence_grade(전기간) · A 라우팅 = 같은 폴더 a_route.json::status
##   상태 = .cache/l1_chain_step_report_state.json(보낸 걸음 '사슬:k' 목록). 상태가 없으면 지금까지의 걸음은 기준선(보낸 것으로) — 다음 걸음부터 보낸다.
##     발송이 실패한(ok = FALSE) 걸음은 상태에 적지 않는다 — 다음 틱이 다시 보낸다.
## 사용: Rscript 02_Infrastructure/programs/l1_chain_step_report.R [--send] [--chain <사슬 id> --k <걸음>] [--tag <제목 꼬리표>] [--show]
##   --send 없으면 드라이런(차트는 만들고 상태는 안 씀 · 출력 = 걸음마다 상태 1줄) · --show = 드라이런 본문까지 출력(보고 전담 에이전트 · 사람만)
##   --chain/--k = 그 걸음 한 통(보낸 적 있어도) · --tag = 제목 꼬리표(예: --tag "OOS 포함판 · 재발송")
a <- commandArgs(trailingOnly = TRUE); SEND <- "--send" %in% a; SHOW <- "--show" %in% a
argv <- function(k) if (k %in% a) a[which(a == k) + 1L] else NA_character_
ONE_CHAIN <- argv("--chain"); ONE_K <- suppressWarnings(as.integer(argv("--k"))); TAG <- argv("--tag")
ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")); setwd(ROOT)
suppressMessages({ library(jsonlite); library(data.table); library(ggplot2); library(patchwork) })
STP <- Sys.getenv("L1SR_STATE", ".cache/l1_chain_step_report_state.json")
rj <- function(p) tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
rjl <- function(p) { L <- tryCatch(readLines(p, encoding = "UTF-8", warn = FALSE), error = function(e) character(0)); L <- L[nzchar(trimws(L))]
  Filter(Negate(is.null), lapply(L, function(x) tryCatch(fromJSON(x, simplifyVector = FALSE), error = function(e) NULL))) }
num <- function(x) { v <- suppressWarnings(as.numeric(unlist(x))[1]); if (length(v) && is.finite(v)) v else NA_real_ }
f2 <- function(x) { v <- num(x); if (is.na(v)) "NA" else formatC(v, format = "f", digits = 2) }
pc <- function(x) { v <- num(x); if (is.na(v)) "NA" else paste0(formatC(100 * v, format = "f", digits = 1), "%") }
pcn <- function(x) { v <- num(x); if (is.na(v)) "NA" else paste0("−", formatC(100 * abs(v), format = "f", digits = 1), "%") }   # 최대낙폭 = 음수 %(SKILL §0.2)
sg <- function(x, d = 2) { v <- num(x); if (is.na(v)) "NA" else paste0(if (v >= 0) "+" else "−", formatC(abs(v), format = "f", digits = d)) }
mn <- function(s) sub("^-", "−", s)                                 # 음수 부호 = '−'(SKILL §0.2 표기)
na_or <- function(x, f) if (is.na(num(x))) "미산출" else mn(f(x))   # OOS 값 — 계약 산출이 없으면 '미산출'(지어내지 않는다)
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
clean_txt <- function(x) { x <- gsub("보는 창", "IS", x, fixed = TRUE); x <- gsub("시험 창", "OOS", x, fixed = TRUE); x <- gsub("등가중", "동일가중", x, fixed = TRUE)
  x <- gsub("가족", "카테고리", x, fixed = TRUE); gsub("기저 칸", "기저 전략", x, fixed = TRUE) }
ROUTE <- c(not_candidate = "A 후보 아님(IS 등록 채택 규칙이 고르지 않은 걸음 — 기록 · 알림만)", eligible = "A 후보 — Judge(PIT) 요청 발행",
           held = "A 보류(관문 사유 코드 — a_route.json)", not_a_after = "선택 현실 점검 재채점 뒤 A 아님")
fam <- ""; fdir <- c(file.path(Sys.getenv("LOCALAPPDATA"), "Microsoft", "Windows", "Fonts"), file.path(Sys.getenv("WINDIR", "C:/Windows"), "Fonts"))
fM <- file.path(fdir, "현대하모니+M.ttf"); fM <- fM[file.exists(fM)][1]
if (!is.na(fM)) { try(systemfonts::register_font(name = "HDHM", plain = fM), silent = TRUE); fam <- "HDHM" }
OOS_FILL <- "#EEF1F6"; FULL_MARK <- "NO_VISIBLE_REVIEW.txt"
FULL_AUDIENCE <- "사람 쪽 보고 전용(전기간 · τ_D 2022-12-31 이후 OOS 포함) — 보고 전담 에이전트(telegram-reporter)가 쓴다 · τ_D 대상(1계층 처방 Q · 판단 Superfan · 철학 P1 · P2 · P4 · 처방 레인) 열람 금지"

## 전기간 NAV(순) · KOSPI200 — 차트 선만(지표는 아래 계약이 낸다)
full_nav <- function(art) {
  x <- tryCatch(fread(file.path(art, "02_nav.csv"), select = c("date", "nav_net")), error = function(e) NULL); if (is.null(x)) return(NULL)
  x[, date := as.Date(date)]; x[is.finite(nav_net)]
}
full_bench <- function(art) {   # KOSPI200 누적 = 측정 산출물 benchmark_nav 열 그대로(그 열이 없는 구판 산출물만 benchmark_ret 누적곱)
  x <- tryCatch(fread(file.path(art, "05_benchmark_returns.csv")), error = function(e) NULL); if (is.null(x) || !"date" %in% names(x)) return(NULL)
  x[, date := as.Date(date)]
  if ("benchmark_nav" %in% names(x)) return(x[is.finite(benchmark_nav), .(date, nav = benchmark_nav)])
  if (!"benchmark_ret" %in% names(x)) return(NULL)
  x[is.finite(benchmark_ret), .(date, nav = cumprod(1 + benchmark_ret))]
}

## ── 계약(한 번 싣는다) ─────────────────────────────────────────────────────────────
.K <- new.env()
contracts <- function() {
  if (isTRUE(.K$ok)) return(.K)
  invisible(capture.output(suppressMessages({
    G <- new.env(parent = globalenv())
    sys.source("02_Infrastructure/contracts/grade_v3.R", envir = G, keep.source = FALSE)
    E <- G$.gv3_deps(ROOT)
    .K$G <- G; .K$E <- E; .K$bc <- E$bc_cfg(ROOT); .K$th <- G$gv3_thresholds(ROOT); .K$cf <- G$gv3_cfg(ROOT); .K$bh <- G$gv3_bench_history(ROOT)
  })))
  .K$ok <- TRUE; .K
}
## OOS 묶음 — 산출 폴더 하나의 OOS 창 지표(등급 계약) · 행동 카드(OOS 수익만) · 권위 등급 · A 라우팅. 실패해도 보고는 나간다(값 = 미산출).
oos_pack <- function(art, tau) {
  o <- list(ok = FALSE, v = list(), err = NA_character_, from = as.Date(NA), to = as.Date(NA), crises = data.table(), parity_bad = character(0),
            grade = NA_character_, rules = NA_character_, route = NULL, stale = FALSE)
  art <- as.character(unlist(art))[1]
  if (is.na(art) || !nzchar(art)) { o$err <- "산출 폴더 기록 없음"; return(o) }
  ar <- rj(file.path(art, "authoritative_remeasure.json"))
  if (!is.null(ar)) {
    o$grade <- as.character(unlist(ar$essence_grade %||% NA))[1]; o$rules <- as.character(unlist(ar$grade_v3$rules_version %||% NA))[1]
    o$stale <- isTRUE(as.logical(unlist(ar$factor_db_vintage$stale_at_measure))[1])
  }
  o$route <- rj(file.path(art, "a_route.json"))
  r <- tryCatch({
    K <- contracts(); G <- K$G
    f <- function(n) { p <- file.path(art, n); if (!file.exists(p)) stop("산출물 없음: ", n); p }
    X <- G$.gv3_prep(fread(f("03_period_returns.csv")), fread(f("05_benchmark_returns.csv")), fread(f("02_nav.csv")),
                     data.table(metric_name = character(0), metric_value = numeric(0)), data.table(metric_name = character(0), active_value = numeric(0)))
    if (!nrow(X$pr[date > tau])) stop("OOS 행 없음")
    w <- G$gv3_window(X$pr, X$br, X$nv, from = tau + 1, root = ROOT)
    S <- G$gv3_S(w$calmar, w$port_t, K$th, K$cf$weights)
    B <- G$.gv3_bench_as_strategy(X$br, freq = as.character(X$pr$frequency[1]))
    bw <- G$gv3_window(B$pr, B$pr[, .(date, benchmark_ret = ret_net, benchmark_id = as.character(X$br$benchmark_id[1]))], B$nv, from = tau + 1, root = ROOT)
    last_d <- max(X$pr$date)
    card <- tryCatch(K$E$bc_card(X$pr[date > tau, .(date, ret_net)], X$br[date > tau, .(date, benchmark_ret)], cfg = K$bc,
                                 bm_hist = if (is.null(K$bh)) NULL else K$bh[date <= last_d], root = ROOT), error = function(e) NULL)
    ct <- if (is.null(card)) list() else card$test; cs <- if (is.null(card)) list() else card$stats
    cc <- if (!is.null(card) && NROW(card$crises)) as.data.table(card$crises) else data.table()
    list(v = list(S = S, port_t = w$port_t, calmar = w$calmar, sharpe = w$sharpe, cagr = w$cagr, mdd = w$mdd,
                  uc = num(ct$bull_up_capture_median), dd_med = num(ct$crisis_dd_capture_median), n_crisis = num(ct$n_crisis),
                  beta_up = num(cs$beta_up), beta_down = num(cs$beta_down), bench_calmar = bw$calmar),
         from = min(X$pr$date[X$pr$date > tau]), to = last_d,
         crises = if (nrow(cc)) cc[window == "test", .(peak = format(as.Date(peak_date)), cap = as.numeric(dd_capture), ongoing = ongoing %in% TRUE)] else data.table())
  }, error = function(e) e)
  if (inherits(r, "error")) { o$err <- conditionMessage(r); return(o) }
  o$ok <- TRUE; o$v <- r$v; o$from <- r$from; o$to <- r$to; o$crises <- r$crises
  ## 저장된 등급 기록과 대조(같은 계약 · 같은 산출이면 같아야 한다 — 기록은 소수 넷째 자리 반올림)
  so <- if (is.null(ar)) list() else ar$grade_v3$oos
  chk <- function(nm, x, y) { x <- num(x); y <- num(y); if (!is.na(x) && !is.na(y) && abs(x - y) > 1e-3) nm else NULL }
  o$parity_bad <- c(chk("종합점수 S", r$v$S, so$S_oos), chk("Calmar", r$v$calmar, so$calmar_tw))
  o
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
  ## OOS(사람 쪽) — 부모 · 걸음 산출 폴더마다 계약으로
  OP <- oos_pack(part_art, tau); OS <- oos_pack(res$artifacts, tau)
  odir <- file.path(cdir, "results", "step_report_full"); dir.create(odir, recursive = TRUE, showWarnings = FALSE)
  if (!file.exists(file.path(odir, FULL_MARK))) writeLines(FULL_AUDIENCE, file.path(odir, FULL_MARK), useBytes = TRUE)
  charts <- character(0); nm_step <- sprintf("걸음 %d(%s)", k, parts)
  cols <- setNames(c("#D9822B", "#3B6FB6", "#555555"), c(nm_step, par_name, "KOSPI200"))
  ## ── 차트 ① 전기간 누적 수익(로그) · 낙폭 — IS/OOS 경계 점선 · OOS 음영 ──
  A <- full_nav(part_art); B <- full_nav(res$artifacts); K <- full_bench(res$artifacts)
  if (!is.null(A) && !is.null(B) && nrow(A) && nrow(B)) {
    hasK <- !is.null(K) && nrow(K)
    d0 <- max(min(A$date), min(B$date), if (hasK) min(K$date) else min(A$date)); d1 <- min(max(A$date), max(B$date), if (hasK) max(K$date) else max(A$date))
    reb <- function(x, col, who) { x <- x[date >= d0 & date <= d1]; v <- x[[col]] / x[[col]][1]; data.table(date = x$date, v = v, dd = v / cummax(v) - 1, who = who) }
    L <- rbindlist(list(reb(A, "nav_net", par_name), reb(B, "nav_net", nm_step), if (hasK) reb(K, "nav", "KOSPI200")))
    L[, who := factor(who, levels = c(nm_step, par_name, "KOSPI200"))]
    oos <- d1 > tau
    ## 음영 — 로그 축은 ymin = 0(log10 → −Inf = 패널 아래 끝 · −Inf 를 넣으면 NaN 으로 빠진다) · 선형 축은 −Inf
    shade_log <- if (oos) annotate("rect", xmin = tau, xmax = d1, ymin = 0, ymax = Inf, fill = OOS_FILL) else NULL
    shade <- if (oos) annotate("rect", xmin = tau, xmax = d1, ymin = -Inf, ymax = Inf, fill = OOS_FILL) else NULL
    vl <- if (oos) geom_vline(xintercept = tau, linetype = "dashed", colour = "#666666", linewidth = 0.5) else NULL
    io <- if (oos) list(annotate("text", x = tau, y = Inf, label = "IS  ", hjust = 1, vjust = 1.5, size = 3.6, family = fam, colour = "#555555"),
                        annotate("text", x = tau, y = Inf, label = "  OOS", hjust = 0, vjust = 1.5, size = 3.6, family = fam, colour = "#555555")) else NULL
    th <- theme_minimal(base_family = fam, base_size = 12) + theme(legend.position = "top", legend.title = element_blank(), panel.grid.minor = element_blank(),
                                                                   plot.title = element_text(size = 14), plot.subtitle = element_text(size = 10, colour = "#555555"),
                                                                   plot.caption = element_text(size = 8.2, colour = "#777777"), plot.title.position = "plot")
    lt <- scale_linetype_manual(values = setNames(c("solid", "solid", "dashed"), names(cols)))
    g1 <- ggplot(L, aes(date, v, colour = who, linetype = who)) + shade_log + vl + geom_line(linewidth = 0.7) + io + scale_y_log10() +
      scale_colour_manual(values = cols) + lt +
      labs(title = if (oos) "누적 수익(로그) — IS + OOS" else "누적 수익(로그) — IS(OOS 구간 없음)", subtitle = sprintf("%s vs %s vs KOSPI200", nm_step, par_name), x = NULL, y = NULL) + th
    g2 <- ggplot(L, aes(date, dd, colour = who, linetype = who)) + shade + vl + geom_line(linewidth = 0.6) + scale_y_continuous(labels = scales::percent) +
      scale_colour_manual(values = cols) + lt +
      labs(title = "낙폭", x = NULL, y = NULL,
           caption = sprintf("전기간 %s ~ %s(공통 창 · 1 로 맞춤) · 순수익(15bps)%s", format(d0, "%Y-%m"), format(d1, "%Y-%m"),
                             if (oos) sprintf(" · 점선 = IS/OOS 경계 %s · 음영 = OOS(사람 쪽 보고 · 판정 아님)", format(tau)) else "")) +
      th + theme(legend.position = "none")
    p1 <- file.path(odir, sprintf("k%d_cum_dd_is_oos.png", k))
    withCallingHandlers(ggsave(p1, g1 / g2 + plot_layout(heights = c(3, 2)), width = 8.6, height = 6.6, dpi = 140, device = ragg::agg_png),
                        warning = function(w) if (grepl("infinite values", conditionMessage(w), fixed = TRUE)) invokeRestart("muffleWarning"))   # 로그 축 음영 ymin = 0 의 예정된 경고만
    charts[[sprintf("누적 수익 · 낙폭 — 걸음 %d vs %s vs KOSPI200 · %s", k, par_name, if (oos) sprintf("IS + OOS(점선 = %s)", format(tau)) else "IS(OOS 구간 없음)")]] <- p1
  }
  ## ── 차트 ② 핵심 지표 IS | OOS · 위기별 하락노출(IS | OOS) ──
  mets <- list("종합점수 S" = c("S_vis", "S"), "PORT_t" = c("port_t_vis", "port_t"), "Calmar" = c("calmar_vis", "calmar"), "Sharpe" = c("sharpe_vis", "sharpe"),
               "CAGR" = c("cagr_vis", "cagr"), "최대낙폭" = c("mdd_vis", "mdd"), "상승 포착" = c("uc_vis", "uc"), "위기 하락노출 중앙" = c("dd_capture_median_vis", "dd_med"),
               "상승 β" = c("beta_up_vis", "beta_up"), "하락 β" = c("beta_down_vis", "beta_down"))
  ov <- function(o, key) if (isTRUE(o$ok)) num(o$v[[key]]) else NA_real_
  MB <- rbindlist(lapply(names(mets), function(n) { kk <- mets[[n]]
    data.table(metric = n, win = c("IS", "IS", "OOS", "OOS"), who = c(par_name, nm_step, par_name, nm_step),
               v = c(num(pm[[kk[1]]]), num(m[[kk[1]]]), ov(OP, kk[2]), ov(OS, kk[2]))) }))
  MB[metric == "최대낙폭", v := -abs(v)]
  MB[, lab := vapply(seq_len(.N), function(i) if (is.na(v[i])) "미산출" else if (metric[i] == "최대낙폭") pcn(v[i]) else if (metric[i] == "CAGR") mn(pc(v[i])) else mn(f2(v[i])), "")]
  MB[, vp := fifelse(is.na(v), 0, v)]
  MB[, metric := factor(metric, levels = names(mets))]; MB[, win := factor(win, levels = c("IS", "OOS"))]; MB[, who := factor(who, levels = c(par_name, nm_step))]
  fills <- scale_fill_manual(values = setNames(c("#3B6FB6", "#D9822B"), c(par_name, nm_step)))
  g3 <- ggplot(MB, aes(win, vp, fill = who)) + geom_blank() +
    annotate("rect", xmin = 1.5, xmax = 2.5, ymin = -Inf, ymax = Inf, fill = OOS_FILL) + geom_hline(yintercept = 0, colour = "#999999", linewidth = 0.3) +
    geom_col(position = position_dodge(0.8), width = 0.72) +
    geom_text(aes(label = lab, vjust = ifelse(vp >= 0, -0.35, 1.3)), position = position_dodge(0.8), size = 3.1, family = fam) +
    facet_wrap(~metric, ncol = 2, scales = "free_y") + fills + scale_y_continuous(expand = expansion(mult = c(0.2, 0.25))) +
    labs(title = "핵심 지표 — IS | OOS", subtitle = sprintf("%s vs %s · 음영 = OOS(%s ~ · 사람 쪽 보고 · 판정 아님)", par_name, nm_step, format(tau + 1, "%Y-%m")), x = NULL, y = NULL,
         caption = "IS = 사슬 원장(등록 규칙이 판정에 쓴 값) · OOS = 등급 계약 창 지표(gv3_window) + 행동 카드(bc_card · OOS 수익만)\n막대 위 숫자 = 값(축 눈금 생략) · 최대낙폭 = 음수 %") +
    theme_minimal(base_family = fam, base_size = 11) +
    theme(legend.position = "top", legend.title = element_blank(), panel.grid = element_blank(), axis.text.y = element_blank(),
          strip.text = element_text(size = 11, face = "bold"), plot.title = element_text(size = 14), plot.subtitle = element_text(size = 10, colour = "#555555"),
          plot.caption = element_text(size = 8.2, colour = "#777777"), plot.title.position = "plot")
  cr <- function(x) { z <- x$crises_vis %||% list(); if (!length(z)) return(data.table())
    rbindlist(lapply(z, function(c) data.table(peak = as.character(c$peak_date), cap = num(c$dd_capture)))) }
  CP <- cr(pm); CS <- cr(m); g <- g3; IS_N <- 0L
  CI <- if (nrow(CP) && nrow(CS)) { z <- merge(CP, CS, by = "peak", suffixes = c("_p", "_s")); z[as.Date(peak) <= tau][, `:=`(win = "IS", ongoing = FALSE)][] } else data.table()
  CO <- if (nrow(OP$crises) && nrow(OS$crises)) { z <- merge(OP$crises[, .(peak, cap_p = cap)], OS$crises[, .(peak, cap_s = cap, ongoing)], by = "peak"); z[as.Date(peak) > tau][, win := "OOS"][] } else data.table()
  CC <- rbindlist(list(CI, CO), use.names = TRUE, fill = TRUE)
  if (nrow(CC)) {
    CC <- CC[order(as.Date(peak))]; IS_N <- sum(CC$win == "IS")
    CC[, x := paste0(substr(peak, 1, 7), ifelse(ongoing %in% TRUE, "*", ""))]; CC[, x := factor(x, levels = unique(x))]
    CL <- rbind(CC[, .(x, who = par_name, cap = cap_p)], CC[, .(x, who = nm_step, cap = cap_s)]); CL[, who := factor(who, levels = c(par_name, nm_step))]
    both <- IS_N > 0L && IS_N < nrow(CC)
    g4 <- ggplot(CL, aes(x, cap, fill = who)) + geom_blank() +
      (if (IS_N < nrow(CC)) annotate("rect", xmin = IS_N + 0.5, xmax = nrow(CC) + 0.5, ymin = -Inf, ymax = Inf, fill = OOS_FILL) else NULL) +
      (if (both) geom_vline(xintercept = IS_N + 0.5, linetype = "dashed", colour = "#666666", linewidth = 0.5) else NULL) +
      geom_col(position = position_dodge(0.75), width = 0.7) + geom_hline(yintercept = 1, linetype = "dashed", colour = "#444444") + fills +
      labs(title = sprintf("위기별 하락노출(전략 낙폭 ÷ 시장 낙폭 · 1 = 시장만큼) — %s", if (both) "IS | OOS" else if (IS_N > 0L)
                             (if (isTRUE(OP$ok) && isTRUE(OS$ok)) "IS(OOS 위기 없음)" else "IS(OOS 위기 미산출)") else "OOS"),
           x = "위기 고점(연-월 · * = 진행 중)", y = NULL,
           caption = paste0("IS = 사슬 원장 IS 기록(등록 규칙이 판정에 쓴 값) · OOS = 행동 카드(bc_card · OOS 수익만)\n위기 = KOSPI200 Lunde-Timmermann 20/20 · 같은 위기끼리 비교",
                            if (both) " · 점선 = IS/OOS 경계 · 음영 = OOS" else "")) +
      theme_minimal(base_family = fam, base_size = 11) + theme(legend.position = "none", panel.grid.minor = element_blank(), axis.text.x = element_text(angle = 45, hjust = 1),
                                                               plot.title = element_text(size = 13), plot.caption = element_text(size = 8.2, colour = "#777777"), plot.title.position = "plot")
    g <- g3 / g4 + plot_layout(heights = c(5, 2))
  }
  p2 <- file.path(odir, sprintf("k%d_metrics_crises_is_oos.png", k))
  ggsave(p2, g, width = 8.6, height = if (nrow(CC)) 12.4 else 9.2, dpi = 140, device = ragg::agg_png)
  charts[[sprintf("핵심 지표 · 위기별 하락노출 — IS | OOS · 걸음 %d vs %s", k, par_name)]] <- p2
  ## ── 본문 ──
  ok <- names(rl)[vapply(rl, function(v) isTRUE(v), TRUE)]; bad <- names(rl)[vapply(rl, function(v) isFALSE(v), TRUE)]
  dec <- if (identical(res$decision, "accept")) "채택" else "기각"
  vline <- sprintf("%s — %s%s", dec,
                   if (length(bad)) paste0("미달: ", paste(unname(RULE[intersect(names(RULE), bad)]), collapse = " · ")) else "등록 규칙 전부 통과",
                   if (length(ok)) paste0(" | 통과: ", paste(unname(RULE[intersect(names(RULE), ok)]), collapse = " · ")) else "")
  kv <- c(sprintf("종합점수 S %s → %s(%s · %s)", f2(pm$S_vis), f2(m$S_vis), sg(t$dS_vis), if (identical(res$r7, "noise")) "잡음 범위" else if (identical(res$r7, "signal")) "신호" else "판독 없음"),
          sprintf("CAGR %s → %s · 최대낙폭 %s → %s · Calmar %s → %s", pc(pm$cagr_vis), pc(m$cagr_vis), pcn(pm$mdd_vis), pcn(m$mdd_vis), f2(pm$calmar_vis), f2(m$calmar_vis)),
          sprintf("상승 포착 %s → %s · 위기 하락노출 중앙 %s → %s · 상승/하락 β %s/%s → %s/%s", f2(pm$uc_vis), f2(m$uc_vis), f2(pm$dd_capture_median_vis), f2(m$dd_capture_median_vis),
                  f2(pm$beta_up_vis), f2(pm$beta_down_vis), f2(m$beta_up_vis), f2(m$beta_down_vis)))
  dd_better <- isTRUE(num(t$d_dd_capture_median_vis) < 0); uc_drop <- isTRUE(num(t$d_uc_vis) < -0.2)
  rd <- c(if (dd_better && isFALSE(rl$beta_asym)) "위기 하락노출은 줄었지만 하락 β 가 상승 β 보다 커서, 선택 실력이 아니라 전체 β 를 낮춘 효과로 읽힌다(사슬 반증 조건 'β 만 낮춘 방어' 쪽)." else NULL,
          if (!dd_better && isTRUE(num(t$dS_vis) > 0)) "수익 쪽은 올랐지만 위기 하락노출은 줄지 않았다 — 위기 방어 비대칭은 생기지 않았다." else NULL,
          if (uc_drop) "줄어든 낙폭만큼 강세 참여를 내줬다." else NULL,
          if (identical(res$decision, "accept")) "다음 걸음은 이 구성 위에 부품을 하나 더 얹는다." else NULL)
  if (!length(rd)) rd <- "등록 규칙 판정 그대로 — 추가 판독 없음."
  ## OOS(사람 쪽 · 판정 아님) — 계약 값만 · 없으면 미산출
  oo <- function(key, f) sprintf("%s → %s", na_or(ov(OP, key), f), na_or(ov(OS, key), f))
  ow <- if (isTRUE(OS$ok)) sprintf("%s ~ %s", format(OS$from, "%Y-%m"), format(OS$to, "%Y-%m")) else "미산출"
  okv <- if (!isTRUE(OP$ok) && !isTRUE(OS$ok)) sprintf("OOS 계약 산출 없음(미산출) — %s", OS$err %||% OP$err %||% "사유 미상") else
    c(sprintf("종합점수 S %s · PORT_t %s · Sharpe %s", oo("S", f2), oo("port_t", f2), oo("sharpe", f2)),
      sprintf("CAGR %s · 최대낙폭 %s · Calmar %s(같은 OOS KOSPI200 Calmar %s)", oo("cagr", pc), oo("mdd", pcn), oo("calmar", f2), na_or(ov(OS, "bench_calmar"), f2)),
      sprintf("상승 포착 %s · 위기 하락노출 중앙 %s(%s) · 상승/하락 β %s/%s → %s/%s", oo("uc", f2), oo("dd_med", f2),
              if (is.na(ov(OS, "n_crisis"))) "OOS 위기 수 미산출" else sprintf("OOS 위기 %d건", as.integer(ov(OS, "n_crisis"))),
              na_or(ov(OP, "beta_up"), f2), na_or(ov(OP, "beta_down"), f2), na_or(ov(OS, "beta_up"), f2), na_or(ov(OS, "beta_down"), f2)),
      if (length(c(OP$parity_bad, OS$parity_bad))) sprintf("⚠ OOS 재산출이 저장된 등급 기록과 다름(%s) — 확인 필요", paste(unique(c(OP$parity_bad, OS$parity_bad)), collapse = " · ")) else NULL)
  rt <- OS$route; rs <- as.character(unlist(rt$status %||% NA))[1]
  rtx <- if (is.na(rs) || identical(rs, "skip")) "" else sprintf(" · A 라우팅: %s", if (!is.na(ROUTE[rs])) unname(ROUTE[rs]) else rs)
  gline <- sprintf("걸음 %d = %s · %s = %s(등급 %s · 전기간 IS + OOS · 걸음 판정(IS 등록 규칙)과 별개)%s%s · 측정 산출물 %s", k, na_or_chr(OS$grade), par_name, na_or_chr(OP$grade),
                   na_or_chr(if (!is.na(OS$rules)) OS$rules else OP$rules), rtx, if (isTRUE(OS$stale)) " · 팩터 DB 수리 전 측정(A 자격 보류)" else "", as.character(unlist(res$artifacts))[1])
  hyp <- clean_txt(as.character(op$hypothesis %||% ""))
  max_steps <- as.integer(spec$budget$max_steps %||% NA)
  nx <- format(if (as.integer(format(Sys.time(), "%M")) < 37L) Sys.time() else Sys.time() + 3600, "%H:37")
  nxt <- if (file.exists(file.path(cdir, "tick_hold"))) "다음 걸음 — 사슬 보류 중(tick_hold · 세션이 풀면 다음 틱부터 재개) · 결과는 이 형식으로 1통" else
    sprintf("다음 걸음 — 다음 틱 %s(메모리 관문이 열리면) · 결과는 이 형식으로 1통", nx)
  invisible(capture.output(suppressMessages(source("02_Infrastructure/programs/program_report.R"))))
  ex <- list(list(heading = "가설(걸음 설계)", type = "text", body = hyp),
             list(heading = sprintf("IS 핵심 수치 — %s → 걸음 %d", par_name, k), type = "bullet", items = kv),
             list(heading = "판독(IS)", type = if (length(rd) >= 2L) "bullet" else "text", items = if (length(rd) >= 2L) rd else NULL, body = if (length(rd) < 2L) rd else NULL),
             list(heading = sprintf("OOS(사람 쪽 보고 · 판정 아님) %s — %s → 걸음 %d", ow, par_name, k), type = if (length(okv) >= 2L) "bullet" else "text",
                  items = if (length(okv) >= 2L) okv else NULL, body = if (length(okv) < 2L) okv else NULL),
             list(heading = "권위 등급(전기간)", type = "text", body = gline))
  tgt <- sprintf("%s 걸음 %d — %s%s", label, k, parts, if (!is.na(TAG) && nzchar(TAG)) paste0(" · ", TAG) else "")
  call_send <- function() prep_send(program = "강화 사슬", target = tgt,
            status = list(stage = "P4 강화 사슬 걸음 판정(IS · 등록 규칙) · OOS = 사람 쪽 보고", position = sprintf("걸음 %d(최대 %s) · 채택 %d · 기각 %d", k, if (is.na(max_steps)) "?" else max_steps, acc, rej),
                          previous = sprintf("비교 기준 = %s", par_name)),
            verdict_line = vline, extra = ex, next_step = nxt, artifact = odir, charts = charts, push = TRUE, dry_run = !SEND)
  r <- if (SEND || SHOW) call_send() else { invisible(capture.output(rr <- call_send())); rr }   # 드라이런 기본 = 본문을 찍지 않는다(OOS 값 · 전기간 등급)
  okk <- is.list(r) && isTRUE(r$ok)
  cat(sprintf("[걸음 보고] %s · %s:%d · 본문 %s bytes · 차트 %d장 · ok=%s%s\n", if (SEND) "발송" else "드라이런", id, k, as.character(r$bytes %||% "?"), length(charts), okk,
              if (!SEND) paste0(" · 차트 폴더 ", sub(paste0("^", ROOT, "/?"), "", gsub("\\\\", "/", odir))) else ""))
  invisible(okk)
}
na_or_chr <- function(x) { x <- as.character(unlist(x))[1]; if (is.na(x) || !nzchar(x)) "미산출" else x }

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
  r <- tryCatch(report_one(td$cdir, td$R, td$res), error = function(e) { cat("[걸음 보고] 실패", td$key, conditionMessage(e), "\n"); FALSE })
  if (isTRUE(r)) done <- c(done, td$key)
}
if (SEND && length(done)) {
  st <- list(schema = "l1_chain_step_report_state_v1", reported = as.list(unique(c(sent, done))))
  tmp <- paste0(STP, ".tmp"); writeLines(toJSON(st, auto_unbox = TRUE, pretty = TRUE), tmp, useBytes = TRUE); file.rename(tmp, STP)
}
cat(sprintf("[걸음 보고] %s · 대상 %d · 성공 %d\n", if (SEND) "발송" else "드라이런", length(todo), length(done)))
