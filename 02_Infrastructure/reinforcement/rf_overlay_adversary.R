#==============================================================================
# rf_overlay_adversary.R — B5(리스크 오버레이) 칸의 **사후 적대 반증** (G2 · 2026-09-17)
#
# ★왜 필요한가: B5 칸이 바닥(floor)보다 Calmar 를 올렸다는 사실 하나로 블록 승자(B4 결합의 바닥) ·
#   승격 carry · Grade A 후보로 **소비**됐다. 그런데 오버레이는 placebo/OOS/DSR 을 전부 통과하고도
#   동월 누출로 개선을 낼 수 있고(2026-07-06 BearProb 실사고 — lag1 스트레스 + strict-PIT A/B 만 판별),
#   같은 평균 노출의 임의 타이밍이나 정적 디레버리지도 Calmar 를 올릴 수 있다(변동성 끌림 감소).
#   "개선이 있다" 와 "개선이 타이밍에서 왔다" 는 다른 명제다. 이 파일은 후자를 반증 시도한다.
#
# ★경계(AX-008): 등급·essence 는 절대 건드리지 않는다. 실패 = **소비 보류**(attempt$adversary 표식)뿐이다.
#   측정은 워커(rf_cell_worker.R → run_paper_replication)가 하고 여기는 재실행 스펙을 만들고 결과를 읽는다.
#
# 검정 6종 (verdict = pass ⇔ T1 ∧ T3 ∧ [T3b] ∧ T4 ∧ [T2]):
#   T1  lag-1 (엔진 재실행 · overlay_shift=1)  — 노출을 한 달 늦게 적용해도 바닥 Calmar 를 넘는가
#   T2  strict-PIT A/B (엔진 재실행 · overlay_strict=TRUE) — 외부 패널 arm 만 · overlay_lookahead_ab
#   T3  노출 짝지은 placebo (해석적) — 바닥 일간 수익 r_t × 셀 총노출 E_t 근사 경로의 Calmar 를
#       E_t 의 **원형 블록 순열** K 개와 비교 (다중집합 보존 = 평균 노출 동일 · 블록 = 자기상관 보존)
#   T3b 횡단면 placebo (해석적 · 벡터 arm 만) — 날짜 안에서 종목별 배율 e_i 를 뒤섞는다
#   T4  정적 등가 (해석적) — 상수 노출 mean(E) 경로의 Calmar 를 넘는가
#   T5  에피소드 집중 (보고 전용) — 낙폭 감소분 중 바닥 최대 낙폭 에피소드 하나의 몫
#
# ★근사 경로의 규약(양쪽 동일 — obs 와 placebo 가 같은 근사 안에 있어야 비교가 성립한다):
#   r_t  = 바닥 산출물 03_period_returns.csv 의 ret_net(일간). 02_nav.csv 의 cash_weight/gross_exposure 는
#          계약 기본값(자리표시자)이라 쓰지 않는다 — 노출은 04_holdings.csv 의 target_weight 합에서 재도출한다.
#   E_p  = Σ target_weight(셀, 집행일 p) / Σ target_weight(바닥, 집행일 p). 하네스는 gross exposure × 정규화
#          레그 수익(replication_harness.R:54-105)이므로 비중 축소 = 곧 현금 보유이고 이 비가 총노출이다.
#   비용 = |ΔE_p| × commission(격자 fixed_axes.commission_bps, 기본 15bps) — 집행일 1회. 첫 기간 ΔE=0.
#   결측 달(셀 보유 행이 없는 집행일) = 하네스 의미론대로 **직전 보유가 이어진다**(carry-forward) — 다음 시그널이
#          없으면 hold_pool 이 다음 집행일까지 늘어난다. 첫 달부터 없으면 0.
#   Calmar = (NAV_end)^(ann/n) − 1 / max(1 − NAV/cummax NAV) — backtest_result_contract.R:401-448 과 같은 식.
#
# ★블록 길이 규칙: np::b.star(Politis & White 2004 자동 블록 길이)가 설치돼 있으면 그것(원형 블록 BStar_CB),
#   아니면 ceiling(n^(1/3)) — Hall, Horowitz & Jing (1995, Biometrika 82:561-574)의 n^{1/3} 비율.
#   실측 2026-09-17: np 미설치 → HHJ 규칙 · n=259 개월 → b=7. 어느 규칙을 썼는지 기록에 남긴다.
#
# ★재실행 부작용 격리: 워커 경로(run_paper_replication)는 모듈 등재·팩터 분석·원장 open·텔레그램·L-code 를
#   낸다. 여기서는 QVEST_RP_REGISTER=0 · QVEST_RP_NO_FACTOR_ANALYSIS=1 · QVEST_NO_LEDGER_OPEN=1(워커도 설정) ·
#   QVEST_RP_JLOG=<격리> 를 자식에 물려준다(Windows 는 system2(env=) 가 무시되므로 Sys.setenv 로).
#   텔레그램은 워커가 send_telegram=FALSE 로 부른다. ★L-code(emit_lcode, run_paper_replication.R §10)는
#   **현재 kill switch 가 없다** — 이 파일은 QVEST_RP_NO_LCODE=1 을 선제 설정하고, run_paper_replication.R 이
#   그 플래그를 읽지 않는 동안은 재실행을 **거부**한다(허용 = cfg allow_lcode_leak=TRUE 명시). 재실행 뒤에는
#   stage_artifacts/l_code 에 새 파일이 생겼는지 감사해 side_effects 에 남긴다(조용한 오염 금지).
#
# 기록: .cache/rf_overlay_adversary/<BID>/<code>/adversary.json (+ T1/ T2/ 재실행 산출) →
#       rf_record_adversary(layer, base_id, n, adversary) — attempts[[j]]$adversary (dry_run 이면 원장 미기록).
# 소비자 규약: attempt$adversary$verdict ∈ {pass, fail, error, not_candidate}. **pass 만** 블록 승자·carry·
#       Grade A 후보로 쓴다. fail/error = 소비 보류(등급 불변). not_candidate = 바닥 Calmar 를 못 넘었거나
#       자기 오버레이 층이 없어 검정 대상이 아니었던 칸(미검정 ≠ 실패). 표식 없음 = 아직 안 돌았다.
#
# 제공: rf_overlay_adversary_run / adv_calmar_from_ret / adv_block_len / adv_circular_block_perm /
#       adv_exposure_path / adv_t3_placebo / adv_t4_static / adv_t5_episode / adv_t3b_xs / .adv_make_variant_spec /
#       .adv_engine_supports / .adv_rp_honors_lcode_switch / .adv_floor_of
# 요구: data.table · jsonlite · reinforce_ledger.R(rf_load · rf_record_adversary) · rf_spec_sig.R(.spec_sig · .ov_layers)
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
if (!exists("%||%")) `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

.adv_root <- function() {
  cands <- unique(c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd()))
  is_root <- function(p) nzchar(p) && dir.exists(p) && file.exists(file.path(p, "02_Infrastructure/config.R"))
  for (p in cands) if (is_root(p)) return(normalizePath(p, winslash = "/", mustWork = TRUE))
  stop("[rf_overlay_adversary] project root 미발견 — QM_ROOT 설정 필요")
}

.adv_now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

# 의존 모듈 적재 — 원장 writer 와 스펙 서명은 정본 파일에서만 가져온다(복제 금지).
.adv_load_deps <- function(root) {
  if (!exists("rf_load") || !exists("rf_record_adversary"))
    invisible(capture.output(suppressMessages(
      source(file.path(root, "02_Infrastructure/reinforcement/reinforce_ledger.R"), local = globalenv()))))
  if (!exists(".spec_sig") || !exists(".ov_layers") || !exists(".rf_attempt_code"))
    invisible(capture.output(suppressMessages(
      source(file.path(root, "02_Infrastructure/reinforcement/rf_spec_sig.R"), local = globalenv()))))
  if (!exists("rf_record_adversary"))
    stop("[rf_overlay_adversary] reinforce_ledger.R 에 rf_record_adversary 가 없다 — writer 는 원장 파일 안에 있어야 한다")
  invisible(TRUE)
}

# ── 설정 (기본값과 함께 읽는다 — 키는 다른 패키지가 나중에 넣는다) ─────────────────
.adv_cfg <- function(root, cfg = NULL) {
  base <- list(enabled = TRUE, alpha = 0.05, n_placebo = 200L, max_candidates = 3L,
               block_rule = "auto",          # auto = np::b.star 있으면 Politis-White · 없으면 HHJ n^(1/3)
               cost_bps = NA_real_,          # NA = 격자 fixed_axes.commission_bps (없으면 15)
               min_periods = 36L,            # 이 아래는 placebo 를 세울 표본이 아니다
               allow_lcode_leak = FALSE,     # run_paper_replication 이 QVEST_RP_NO_LCODE 를 안 읽을 때 재실행 허용?
               worker_timeout_sec = NA_integer_,
               seed = 20260917L)
  fromfile <- list(); wts <- NA_integer_
  cp <- file.path(root, "06_Registry/reinforce_auto_config.json")
  if (file.exists(cp)) {
    j <- tryCatch(fromJSON(cp, simplifyVector = FALSE), error = function(e) NULL)
    if (is.list(j)) { fromfile <- j$overlay_adversary %||% list(); wts <- j$worker_timeout_sec %||% NA_integer_ }
  }
  out <- base
  for (k in names(fromfile)) out[[k]] <- fromfile[[k]]
  if (!is.null(cfg)) for (k in names(cfg)) out[[k]] <- cfg[[k]]
  if (is.na(out$cost_bps)) {
    pp <- file.path(root, "06_Registry/reinforce_program.json")
    cb <- if (file.exists(pp)) tryCatch(fromJSON(pp, simplifyVector = FALSE)$fixed_axes$commission_bps, error = function(e) NULL) else NULL
    out$cost_bps <- suppressWarnings(as.numeric(cb %||% 15))
    if (!is.finite(out$cost_bps)) out$cost_bps <- 15
  }
  if (is.na(out$worker_timeout_sec)) out$worker_timeout_sec <- suppressWarnings(as.integer(wts %||% 5400L))
  if (!is.finite(out$worker_timeout_sec)) out$worker_timeout_sec <- 5400L
  out$alpha <- as.numeric(out$alpha); out$n_placebo <- as.integer(out$n_placebo)
  out$max_candidates <- as.integer(out$max_candidates); out$cost_rate <- out$cost_bps / 1e4
  out
}

# ── 엔진·러너 지원 여부는 **소스에서 재도출**한다 (선언이 아니라 코드) ────────────────
.adv_code_lines <- function(p) {
  if (!file.exists(p)) return(character(0))
  src <- readLines(p, encoding = "UTF-8", warn = FALSE)
  sub("#.*$", "", src)
}
.adv_engine_supports <- function(root) {
  src <- .adv_code_lines(file.path(root, "02_Infrastructure/reinforcement/rf_cell_engine.R"))
  list(overlay_shift  = any(grepl("overlay_shift",  src, fixed = TRUE)),
       overlay_strict = any(grepl("overlay_strict", src, fixed = TRUE)))
}
.adv_rp_honors_lcode_switch <- function(root) {
  src <- .adv_code_lines(file.path(root, "02_Infrastructure/alpha_search/run_paper_replication.R"))
  any(grepl("QVEST_RP_NO_LCODE", src, fixed = TRUE))
}

# ── 지표 (계약과 같은 식) ────────────────────────────────────────────────────────
#' @param ret 기간 수익(일간이면 ann=252 · 월간이면 12)
adv_calmar_from_ret <- function(ret, ann = 252) {
  ret <- as.numeric(ret); ret[!is.finite(ret)] <- 0
  n <- length(ret)
  if (n < 2L) return(list(cagr = NA_real_, mdd = NA_real_, calmar = NA_real_, nav = cumprod(1 + ret)))
  nav <- cumprod(1 + ret)
  cagr <- if (nav[n] > 0) nav[n]^(ann / n) - 1 else NA_real_
  dd <- 1 - nav / cummax(nav); mdd <- max(dd)
  calmar <- if (is.finite(cagr) && is.finite(mdd) && mdd > 0) cagr / mdd else NA_real_
  list(cagr = cagr, mdd = mdd, calmar = calmar, nav = nav)
}

#' 블록 길이 — Politis-White(np::b.star, 원형 블록) 가 있으면 그것, 없으면 HHJ(1995) n^{1/3}
adv_block_len <- function(x, rule = "auto") {
  n <- length(x)
  hhj <- max(1L, as.integer(ceiling(n^(1/3))))
  if (identical(rule, "hhj1995") || n < 8L) return(list(b = hhj, rule = "hhj1995_n^(1/3)"))
  if (identical(rule, "auto") || identical(rule, "politis_white")) {
    if (requireNamespace("np", quietly = TRUE)) {
      bs <- tryCatch(suppressWarnings(np::b.star(as.numeric(x), round = TRUE)), error = function(e) NULL)
      bcb <- if (is.matrix(bs)) suppressWarnings(as.numeric(bs[1, "BStar_CB"])) else NA_real_
      if (is.finite(bcb) && bcb >= 1) return(list(b = as.integer(bcb), rule = "politis_white_2004_np::b.star_CB"))
    }
    if (identical(rule, "politis_white")) stop("[rf_overlay_adversary] block_rule=politis_white 인데 np 패키지가 없다")
  }
  list(b = hhj, rule = "hhj1995_n^(1/3)")
}

#' 원형 블록 순열 — 다중집합 보존(평균 노출 동일) · 블록 안 자기상관 보존 · 시점 정렬 파괴
adv_circular_block_perm <- function(x, b) {
  n <- length(x); b <- max(1L, min(as.integer(b), n))
  if (n <= 1L) return(x)
  s <- sample.int(n, 1L) - 1L                       # 원형 시작 오프셋
  y <- if (s > 0L) c(x[(s + 1L):n], x[1:s]) else x
  nb <- ceiling(n / b)
  blocks <- split(y, rep(seq_len(nb), each = b, length.out = n))
  unlist(blocks[sample.int(nb)], use.names = FALSE)
}

#' 노출 근사 경로 — r_t × E_{p(t)} − 집행일 |ΔE| × cost
#' @param r 일간(또는 기간) 바닥 수익 · period_of 각 r 의 기간 인덱스(1..P) · E 기간별 노출 · exec_pos 각 기간의 집행 위치(r 의 인덱스)
adv_exposure_path <- function(r, period_of, E, exec_pos, cost_rate) {
  E <- as.numeric(E); E[!is.finite(E)] <- 0
  out <- as.numeric(r) * E[period_of]
  dE <- c(0, abs(diff(E)))                          # 첫 기간 ΔE=0 — 초기 매수 비용은 바닥 r_t 에 이미 있다
  cost <- numeric(length(r)); cost[exec_pos] <- cost[exec_pos] + dE * cost_rate
  out - cost
}

.adv_with_seed <- function(seed, expr) {
  had <- exists(".Random.seed", envir = globalenv(), inherits = FALSE)
  old <- if (had) get(".Random.seed", envir = globalenv()) else NULL
  on.exit({ if (had) assign(".Random.seed", old, envir = globalenv()) else if (exists(".Random.seed", envir = globalenv(), inherits = FALSE)) rm(".Random.seed", envir = globalenv()) }, add = TRUE)
  set.seed(as.integer(seed)); force(expr)
}

#' T3 — 노출 짝지은 placebo. pass ⇔ obs > quantile(placebo, 1−alpha)
adv_t3_placebo <- function(r, period_of, E, exec_pos, cost_rate, n_placebo = 200L, alpha = 0.05,
                           seed = 20260917L, block_rule = "auto", ann = 252) {
  bl <- adv_block_len(E, block_rule)
  obs_ret <- adv_exposure_path(r, period_of, E, exec_pos, cost_rate)
  obs <- adv_calmar_from_ret(obs_ret, ann)
  plc <- .adv_with_seed(seed, vapply(seq_len(n_placebo), function(k) {
    Ep <- adv_circular_block_perm(E, bl$b)
    adv_calmar_from_ret(adv_exposure_path(r, period_of, Ep, exec_pos, cost_rate), ann)$calmar
  }, numeric(1)))
  plc_ok <- plc[is.finite(plc)]
  q <- if (length(plc_ok)) as.numeric(stats::quantile(plc_ok, 1 - alpha, names = FALSE, type = 7)) else NA_real_
  pass <- is.finite(obs$calmar) && is.finite(q) && obs$calmar > q
  pval <- if (length(plc_ok)) (1 + sum(plc_ok >= obs$calmar)) / (length(plc_ok) + 1) else NA_real_
  list(status = if (!is.finite(obs$calmar) || !is.finite(q)) "error" else if (pass) "pass" else "fail",
       obs_calmar = obs$calmar, obs_cagr = obs$cagr, obs_mdd = obs$mdd,
       placebo_q = q, placebo_mean = if (length(plc_ok)) mean(plc_ok) else NA_real_,
       placebo_sd = if (length(plc_ok)) stats::sd(plc_ok) else NA_real_,
       placebo_n_finite = length(plc_ok), p_value = pval, alpha = alpha, n_placebo = as.integer(n_placebo),
       block_len = bl$b, block_rule = bl$rule, n_periods = length(E), mean_E = mean(E), sd_E = stats::sd(E),
       decision_rule = "obs_calmar > quantile(placebo_calmar, 1 - alpha)  [평균이 아니라 분위]",
       placebo = plc, obs_ret = obs_ret)
}

#' T4 — 정적 등가: 상수 노출 mean(E) · 비용 0. pass ⇔ obs > Calmar_const
adv_t4_static <- function(r, period_of, E, exec_pos, cost_rate, obs_calmar = NULL, ann = 252) {
  Ec <- mean(as.numeric(E), na.rm = TRUE)
  cst <- adv_calmar_from_ret(as.numeric(r) * Ec, ann)
  if (is.null(obs_calmar))
    obs_calmar <- adv_calmar_from_ret(adv_exposure_path(r, period_of, E, exec_pos, cost_rate), ann)$calmar
  pass <- is.finite(obs_calmar) && is.finite(cst$calmar) && obs_calmar > cst$calmar
  list(status = if (!is.finite(obs_calmar) || !is.finite(cst$calmar)) "error" else if (pass) "pass" else "fail",
       obs_calmar = obs_calmar, const_calmar = cst$calmar, const_cagr = cst$cagr, const_mdd = cst$mdd, mean_E = Ec,
       decision_rule = "obs_calmar > calmar(mean(E) * r_t, cost 0)")
}

#' T5 — 에피소드 집중(보고 전용): 바닥 낙폭 에피소드마다 (바닥 깊이 − 같은 창의 셀 깊이) 를 재고,
#'   최대 에피소드 하나의 몫 = 그 감소분 / (바닥 MDD − 셀 MDD).
adv_t5_episode <- function(r_floor, r_cell, dates = NULL, top = 3L) {
  f <- adv_calmar_from_ret(r_floor); cst <- adv_calmar_from_ret(r_cell)
  navf <- f$nav; navc <- cst$nav
  ddf <- 1 - navf / cummax(navf)
  under <- ddf > 1e-12
  if (!any(under)) return(list(mdd_floor = f$mdd, mdd_cell = cst$mdd, reduction_total = f$mdd - cst$mdd,
                               share_largest = NA_real_, episodes = list(), note = "바닥에 낙폭 에피소드 없음"))
  rr <- rle(under); ends <- cumsum(rr$lengths); starts <- ends - rr$lengths + 1L
  eps <- list()
  for (k in which(rr$values)) {
    s <- starts[k]; e <- ends[k]; peak <- max(1L, s - 1L)
    tr <- (s:e)[which.min(navf[s:e])]
    depth_f <- 1 - navf[tr] / navf[peak]
    depth_c <- 1 - min(navc[peak:tr]) / navc[peak]
    eps[[length(eps) + 1L]] <- list(peak = if (!is.null(dates)) as.character(dates[peak]) else peak,
                                    trough = if (!is.null(dates)) as.character(dates[tr]) else tr,
                                    recovered = e < length(navf),
                                    depth_floor = depth_f, depth_cell = depth_c, reduction = depth_f - depth_c)
  }
  depths <- vapply(eps, function(z) z$depth_floor, numeric(1))
  ord <- order(depths, decreasing = TRUE)
  largest <- eps[[ord[1]]]
  total <- f$mdd - cst$mdd
  share <- if (is.finite(total) && abs(total) > 1e-12) largest$reduction / total else NA_real_
  list(mdd_floor = f$mdd, mdd_cell = cst$mdd, reduction_total = total,
       largest = largest, share_largest = share,
       n_episodes = length(eps), episodes = eps[ord[seq_len(min(top, length(eps)))]],
       note = "share_largest = 바닥 최대 낙폭 에피소드 창 [peak,trough] 에서의 (바닥 깊이 − 셀 깊이) / (바닥 MDD − 셀 MDD). >1 = 그 에피소드 밖에서는 셀이 더 나빴다")
}

#' T3b — 횡단면 placebo (벡터 arm 만). 날짜 안에서 e_i 를 뒤섞고 총노출 Σ w_i e_i 를 맞춘다.
#' @param H data.table(pid, ticker, w, e, R) — pid 기간 인덱스 · w 바닥 비중 · e 셀/바닥 배율 · R 기간 보유수익
adv_t3b_xs <- function(H, cost_rate, n_placebo = 200L, alpha = 0.05, seed = 20260917L, ann = 12) {
  H <- as.data.table(H)[is.finite(R) & is.finite(w) & is.finite(e)]
  setorder(H, pid, ticker)
  pids <- sort(unique(H$pid)); P <- length(pids)
  if (P < 2L) return(list(status = "error", reason = "기간 2 미만"))
  .path <- function(ev) {                       # ev = e 벡터(H 행 순서)
    wv <- H$w * ev
    ret <- numeric(P); prev <- NULL
    idx <- split(seq_len(nrow(H)), H$pid)
    for (k in seq_len(P)) {
      ii <- idx[[as.character(pids[k])]]
      cur <- setNames(wv[ii], H$ticker[ii])
      to  <- if (is.null(prev)) 0 else { allt <- union(names(prev), names(cur))
               a <- cur[allt]; a[is.na(a)] <- 0; b <- prev[allt]; b[is.na(b)] <- 0; sum(abs(a - b)) }
      ret[k] <- sum(wv[ii] * H$R[ii]) - to * cost_rate
      prev <- cur
    }
    ret
  }
  obs <- adv_calmar_from_ret(.path(H$e), ann)
  gid <- H$pid
  plc <- .adv_with_seed(seed, vapply(seq_len(n_placebo), function(k) {
    ep <- H$e
    for (g in split(seq_len(nrow(H)), gid)) {
      if (length(g) < 2L) next
      pe <- ep[g][sample.int(length(g))]
      tgt <- sum(H$w[g] * ep[g]); got <- sum(H$w[g] * pe)   # 노출 짝맞춤(등가중이면 배율 1)
      if (is.finite(got) && got > 0) pe <- pe * (tgt / got)
      ep[g] <- pe
    }
    adv_calmar_from_ret(.path(ep), ann)$calmar
  }, numeric(1)))
  plc_ok <- plc[is.finite(plc)]
  q <- if (length(plc_ok)) as.numeric(stats::quantile(plc_ok, 1 - alpha, names = FALSE, type = 7)) else NA_real_
  pass <- is.finite(obs$calmar) && is.finite(q) && obs$calmar > q
  list(status = if (!is.finite(obs$calmar) || !is.finite(q)) "error" else if (pass) "pass" else "fail",
       obs_calmar = obs$calmar, obs_cagr = obs$cagr, obs_mdd = obs$mdd, placebo_q = q,
       placebo_mean = if (length(plc_ok)) mean(plc_ok) else NA_real_, placebo_n_finite = length(plc_ok),
       p_value = if (length(plc_ok)) (1 + sum(plc_ok >= obs$calmar)) / (length(plc_ok) + 1) else NA_real_,
       alpha = alpha, n_placebo = as.integer(n_placebo), n_periods = P, n_rows = nrow(H),
       resolution = "monthly_period (보유기간 수익 Σ w_i e_i R_i,k − Σ|Δ(w e)|·cost · ann 12)",
       decision_rule = "obs_calmar > quantile(placebo_calmar, 1 - alpha) — 날짜 안 e_i 순열 · 총노출 짝맞춤",
       placebo = plc)
}

# ── 산출물 읽기 ──────────────────────────────────────────────────────────────
.adv_read_period_returns <- function(art) {
  p <- file.path(art, "03_period_returns.csv")
  if (!file.exists(p)) stop("03_period_returns.csv 부재: ", art)
  x <- fread(p, showProgress = FALSE)
  need <- c("date", "ret_net")
  if (!all(need %in% names(x))) stop("03_period_returns.csv 열 부족(date/ret_net): ", art)
  x[, date := as.Date(date)]
  freq <- if ("frequency" %in% names(x)) as.character(x$frequency[1]) else "daily"
  setorder(x, date)
  list(dt = x[, .(date, ret_net = as.numeric(ret_net),
                  ret_gross = if ("ret_gross" %in% names(x)) as.numeric(ret_gross) else NA_real_)],
       freq = freq, ann = if (identical(freq, "monthly")) 12 else 252)
}
.adv_read_holdings <- function(art) {
  p <- file.path(art, "04_holdings.csv")
  if (!file.exists(p)) stop("04_holdings.csv 부재: ", art)
  x <- fread(p, showProgress = FALSE)
  if (!all(c("date", "ticker", "target_weight") %in% names(x))) stop("04_holdings.csv 열 부족: ", art)
  x[, date := as.Date(date)]
  x[, .(date, ticker = as.character(ticker), w = as.numeric(target_weight))][is.finite(w)]
}

#' 바닥 vs 셀 정렬 — 기간 격자는 **바닥의 집행일**이다. 셀 결측 달은 carry-forward(하네스 의미론).
.adv_align_exposure <- function(HF, HC) {
  ef <- HF[, .(Ef = sum(w)), by = date]; ec <- HC[, .(Ec = sum(w)), by = date]
  A <- merge(ef, ec, by = "date", all.x = TRUE); setorder(A, date)
  A[, missing := is.na(Ec)]
  A[, Ec := nafill(Ec, type = "locf")]         # 직전 보유가 이어진다
  A[is.na(Ec), Ec := 0]                         # 첫 달부터 없으면 무보유
  A[, E := fifelse(Ef > 0, Ec / Ef, 0)]
  list(A = A[, .(date, Ef, Ec, E, missing)],
       n_missing = sum(A$missing), n_extra_cell_dates = sum(!ec$date %in% ef$date))
}

#' 기간 색인 — 각 수익일이 어느 집행 기간에 속하나(집행일 ≤ day < 다음 집행일)
.adv_period_index <- function(ret_dates, exec_dates) {
  pid <- findInterval(ret_dates, exec_dates)
  keep <- pid >= 1L
  exec_pos <- match(exec_dates, ret_dates)     # 집행일이 수익일 집합에 없으면 그 기간의 첫 수익일
  for (k in which(is.na(exec_pos))) { cand <- which(pid == k); exec_pos[k] <- if (length(cand)) cand[1] else NA_integer_ }
  list(pid = pid, keep = keep, exec_pos = exec_pos)
}

#' 벡터(종목별) 처치 관측 — 날짜 안 e_i 의 횡단면 산포가 어느 달이라도 0 을 넘는가(선언이 아니라 산출로)
.adv_vector_observed <- function(HF, HC, tol = 1e-8) {
  M <- merge(HF, HC[, .(date, ticker, wc = w)], by = c("date", "ticker"), all.x = TRUE)
  M[is.na(wc), wc := 0]
  M[, e := fifelse(w > 0, wc / w, NA_real_)]
  s <- M[is.finite(e), .(sd = if (.N > 1L) stats::sd(e) else 0), by = date]
  list(observed = any(s$sd > tol, na.rm = TRUE), n_dates_vary = sum(s$sd > tol, na.rm = TRUE), M = M)
}

# ── 기본 RAWDATA 로더 (T3b) — 하네스와 같은 원천(.cache/RAWDATA.parquet · Ret 열) ──────
.adv_default_rawdata_loader <- function(root) function(tickers, from, to) {
  p <- file.path(root, ".cache", "RAWDATA.parquet")
  if (!file.exists(p)) stop("RAWDATA.parquet 부재: ", p)
  R <- as.data.table(arrow::read_parquet(p, col_select = c("Date", "Ticker", "Ret")))
  R[, Date := as.Date(Date)]
  R[Ticker %in% tickers & Date >= as.Date(from) & Date <= as.Date(to), .(Date, Ticker = as.character(Ticker), Ret = as.numeric(Ret))]
}

#' 바닥 보유의 보유기간 종목수익 — 하네스처럼 exec→hold_end 창에서 일간 Ret 복리(비유한 = 0)
.adv_holding_period_returns <- function(HF, ret_dates, loader) {
  ex <- sort(unique(HF$date))
  last_day <- max(ret_dates)
  RAW <- loader(unique(HF$ticker), min(ex), last_day)
  if (!nrow(RAW)) stop("RAWDATA 에서 바닥 보유 종목의 수익이 0행")
  RAW[!is.finite(Ret), Ret := 0]
  RAW <- RAW[Date %in% ret_dates]                              # 하네스 거래일 집합
  RAW[, pid := findInterval(Date, ex)]
  RAW <- RAW[pid >= 1L]
  HP <- RAW[, .(R = prod(1 + Ret) - 1), by = .(pid, ticker = Ticker)]
  HF2 <- copy(HF)[, pid := match(date, ex)]
  merge(HF2[, .(pid, ticker, w)], HP, by = c("pid", "ticker"), all.x = TRUE)
}

# ── 스펙 조작 ──────────────────────────────────────────────────────────────────
.adv_layer_key <- function(z) paste0(as.character(z$kind %||% ""), "~", as.character(z$arm_id %||% ""))
.adv_own_layers <- function(spec, carry_overlay = NULL) {
  if (!is.null(spec$overlay_cell)) return(.ov_layers(spec$overlay_cell))
  all <- .ov_layers(spec$overlay)
  ck <- vapply(.ov_layers(carry_overlay), .adv_layer_key, character(1))
  Filter(function(z) !(.adv_layer_key(z) %in% ck), all)
}
#' 자기 층을 뺀 스펙 — ★`spec$overlay <- NULL` 로 지우면 `$` 부분 일치가 overlay_basis 를 집어
#'   서명이 어긋난다(실측 2026-09-17: B5_16~20 전부 바닥과 불일치). 이름 있는 NULL 로 둔다.
.adv_strip_own <- function(spec, own) {
  ok <- vapply(own, .adv_layer_key, character(1))
  rem <- Filter(function(z) !(.adv_layer_key(z) %in% ok), .ov_layers(spec$overlay))
  spec["overlay"] <- list(if (length(rem)) .ov_stack(rem) else NULL)
  spec
}
.adv_norm_sig <- function(spec) {
  s <- spec; s["overlay"] <- list(.ov_stack(spec$overlay))
  .spec_sig(s)
}
#' T1/T2 재실행 스펙 — 원본은 건드리지 않는다(사본 반환). 표식은 idea/label/adversary 에.
.adv_make_variant_spec <- function(spec, variant = c("T1", "T2")) {
  variant <- match.arg(variant)
  v <- spec
  if (identical(variant, "T1")) v$overlay_shift <- 1L else v$overlay_strict <- TRUE
  v$adversary <- list(variant = variant, of_code = as.character(spec$code %||% ""), at = .adv_now(),
                      note = "적대 재실행 — 원장·모듈 풀·L-code 대상 아님")
  v$idea  <- sprintf("[ADVERSARY %s] %s", variant, as.character(spec$idea %||% spec$code %||% ""))
  v$label <- sprintf("[ADV %s] %s", variant, as.character(spec$label %||% spec$code %||% ""))
  v
}

# ── 재실행 (워커 경유 · 부작용 격리) ──────────────────────────────────────────────
.adv_rerun <- function(spec, variant, code, base_id, n, root, out_root, timeout_sec) {
  vdir <- file.path(out_root, variant); dir.create(vdir, recursive = TRUE, showWarnings = FALSE)
  v <- .adv_make_variant_spec(spec, variant)
  sp <- file.path(vdir, "spec.json")
  write(toJSON(v, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA), sp)
  out <- file.path(vdir, "result.json"); lg <- file.path(vdir, "worker_log.txt")
  unlink(out, force = TRUE)
  worker <- file.path(root, "02_Infrastructure/ops/rf_cell_worker.R")
  if (!file.exists(worker)) return(list(status = "error", detail = "rf_cell_worker.R 부재", spec = sp))
  name <- sprintf("ADV_%s_%s_%s", variant, code, base_id)
  env_set <- c(QVEST_RP_REGISTER = "0", QVEST_RP_NO_FACTOR_ANALYSIS = "1", QVEST_RP_NO_LCODE = "1",
               QVEST_NO_LEDGER_OPEN = "1", QVEST_RF_ADVERSARY = "1",
               QVEST_RP_JLOG = file.path(vdir, "rmm_journal.jsonl"), QM_ROOT = root, CLAUDE_PROJECT_DIR = root)
  old <- Sys.getenv(names(env_set), unset = NA)
  do.call(Sys.setenv, as.list(env_set))
  on.exit({ for (k in names(env_set)) if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, setNames(list(old[[k]]), k)) }, add = TRUE)
  lc_dir <- file.path(root, "stage_artifacts", "l_code")
  before <- if (dir.exists(lc_dir)) list.files(lc_dir, pattern = "\\.json$", recursive = TRUE, full.names = TRUE) else character(0)
  t0 <- Sys.time()
  rc <- tryCatch(system2("Rscript", c(shQuote(worker), shQuote(sp), as.integer(n), shQuote(name), shQuote(out)),
                         stdout = lg, stderr = lg, wait = TRUE, timeout = as.integer(timeout_sec)),
                 error = function(e) -1L)
  after <- if (dir.exists(lc_dir)) list.files(lc_dir, pattern = "\\.json$", recursive = TRUE, full.names = TRUE) else character(0)
  new_lc <- setdiff(after, before)
  leak <- Filter(function(f) any(grepl(name, readLines(f, warn = FALSE), fixed = TRUE)), new_lc)
  res <- if (file.exists(out)) tryCatch(fromJSON(out, simplifyVector = FALSE), error = function(e) NULL) else NULL
  side <- list(env = as.list(env_set[setdiff(names(env_set), c("QM_ROOT", "CLAUDE_PROJECT_DIR"))]),
               lcode_leak = as.character(leak), strategy_name = name,
               elapsed_sec = round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1), rc = rc)
  if (is.null(res)) return(list(status = "error", detail = sprintf("워커 산출 부재(rc=%s · 로그 %s)", rc, lg), spec = sp, side_effects = side))
  if (!isTRUE(res$ok)) return(list(status = "error", detail = as.character(res$err %||% "?"), spec = sp, side_effects = side))
  list(status = "ok", spec = sp, result = out, artifacts = as.character(res$artifacts %||% ""),
       essence = res$essence, grade_seen = as.character(res$grade %||% ""), side_effects = side)
}

# ── 바닥 식별 ──────────────────────────────────────────────────────────────────
#' @return list(attempt, match) · match ∈ floor_code / sig / port_t_fallback / NULL(없음)
.adv_floor_of <- function(a, spec, own, attempts, block, root, base_id) {
  meas <- Filter(function(x) is.list(x$essence) && !is.null(x$essence$port_t) &&
                   suppressWarnings(as.integer(x$n)) < suppressWarnings(as.integer(a$n)), attempts)
  fc <- as.character(spec$floor_code %||% "")
  if (nzchar(fc)) {
    hit <- Filter(function(x) identical(.rf_attempt_code(x), fc), meas)
    if (length(hit)) return(list(attempt = hit[[1]], match = "floor_code"))
  }
  sig0 <- tryCatch(.adv_norm_sig(.adv_strip_own(spec, own)), error = function(e) NA_character_)
  if (!is.na(sig0)) {
    hit <- Filter(function(x) { sp <- .adv_load_spec(x, root, base_id)
      !is.null(sp) && identical(tryCatch(.adv_norm_sig(sp), error = function(e) NA_character_), sig0) }, meas)
    if (length(hit)) {
      v <- vapply(hit, function(x) suppressWarnings(as.numeric(x$essence$port_t)), numeric(1))
      return(list(attempt = hit[[which.max(replace(v, !is.finite(v), -Inf))]], match = "sig"))
    }
  }
  # 서명 불일치 — 러너가 실제로 깐 바닥(.wbest_spec = 측정된 최고 port_t)으로 폴백하되 그 사실을 남긴다
  other <- Filter(function(x) !startsWith(as.character(.rf_attempt_code(x) %||% ""), paste0(block, "_")), meas)
  if (!length(other)) return(list(attempt = NULL, match = NULL))
  v <- vapply(other, function(x) suppressWarnings(as.numeric(x$essence$port_t)), numeric(1))
  list(attempt = other[[which.max(replace(v, !is.finite(v), -Inf))]], match = "port_t_fallback")
}
.adv_load_spec <- function(a, root, base_id) {
  p <- as.character(a$essence$spec %||% "")
  if (!nzchar(p) || !file.exists(p)) {
    cd <- .rf_attempt_code(a)
    if (!is.na(cd)) p <- file.path(root, ".cache", "rf_parallel", sprintf("spec_%s__%s.json", cd, base_id))
  }
  if (!nzchar(p) || !file.exists(p)) return(NULL)
  tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
}
.adv_arm_meta <- function(kind, root) {
  p <- file.path(root, "02_Infrastructure/reinforcement/overlay_arms", paste0(kind, ".arm.json"))
  if (!file.exists(p)) return(list())
  tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) list())
}
.adv_art_dir <- function(a, root) {
  ar <- as.character(a$artifacts %||% "")
  if (nzchar(ar) && !dir.exists(ar) && !grepl("^(/|[A-Za-z]:)", gsub("\\", "/", ar, fixed = TRUE)) &&
      dir.exists(file.path(root, ar))) ar <- file.path(root, ar)
  ar
}
.adv_num <- function(x) { v <- suppressWarnings(as.numeric(x %||% NA_real_)); if (length(v)) v[1] else NA_real_ }

# ── 메인 ───────────────────────────────────────────────────────────────────────
#' @param reruns "auto" = 엔진이 옵션을 지원하고 부작용 가드가 서면 T1/T2 재실행 · "skip" = 해석적만 · "force" = 지원 검사만 하고 가드 무시
#' @param rawdata_loader function(tickers, from, to) → data.table(Date, Ticker, Ret) — T3b 원천(검사 주입용)
#' @return data.table 요약(code · n · calmar · floor · candidate · verdict · reason · 검정별 status · json)
rf_overlay_adversary_run <- function(base_id, block = "B5", layer = 1L, root = .adv_root(), cfg = NULL,
                                     dry_run = FALSE, reruns = c("auto", "skip", "force"),
                                     rawdata_loader = NULL) {
  reruns <- match.arg(reruns)
  .adv_load_deps(root)
  CF <- .adv_cfg(root, cfg)
  empty <- data.table(code = character(0), n = integer(0), calmar = numeric(0), floor_code = character(0),
                      floor_calmar = numeric(0), candidate = logical(0), verdict = character(0), reason = character(0),
                      T1 = character(0), T2 = character(0), T3 = character(0), T3b = character(0), T4 = character(0),
                      T5_share = numeric(0), json = character(0))
  if (!isTRUE(CF$enabled)) { cat("[rf_overlay_adversary] overlay_adversary.enabled=false — 무동작\n"); return(empty) }
  led <- rf_load(layer, root)
  i <- .rf_find(led, base_id)
  if (is.na(i)) stop("[rf_overlay_adversary] entry 부재: ", base_id)
  E <- led$entries[[i]]
  atts <- E$attempts %||% list()
  pat <- paste0("^", block, "_[0-9]+$")
  blk <- Filter(function(a) { cd <- .rf_attempt_code(a); !is.na(cd) && grepl(pat, cd) }, atts)
  if (!length(blk)) { cat(sprintf("[rf_overlay_adversary] %s 블록 시도 없음 (%s)\n", block, base_id)); return(empty) }
  sup <- .adv_engine_supports(root); honors <- .adv_rp_honors_lcode_switch(root)
  out_base <- file.path(root, ".cache", "rf_overlay_adversary", base_id)
  loader <- rawdata_loader %||% .adv_default_rawdata_loader(root)

  # ① 후보 판정 — 측정됨 ∧ 자기 오버레이 층 있음 ∧ calmar > 바닥 calmar → calmar 상위 max_candidates
  rows <- lapply(blk, function(a) {
    cd <- .rf_attempt_code(a); n <- suppressWarnings(as.integer(a$n))
    measured <- is.list(a$essence) && !is.null(a$essence$port_t)
    sp <- .adv_load_spec(a, root, base_id)
    own <- if (is.null(sp)) list() else .adv_own_layers(sp, E$carry$overlay)
    fl <- if (measured && !is.null(sp)) .adv_floor_of(a, sp, own, atts, block, root, base_id) else list(attempt = NULL, match = NULL)
    fcal <- if (!is.null(fl$attempt)) .adv_num(fl$attempt$essence$calmar) else NA_real_
    ccal <- if (measured) .adv_num(a$essence$calmar) else NA_real_
    reason <- if (!measured) "unmeasured" else if (is.null(sp)) "spec_missing" else if (!length(own)) "no_own_overlay_layers" else
              if (is.null(fl$attempt)) "floor_missing" else if (!is.finite(ccal) || !is.finite(fcal)) "calmar_missing" else
              if (!(ccal > fcal)) "calmar_not_above_floor" else "candidate"
    list(a = a, code = cd, n = n, spec = sp, own = own, floor = fl, floor_calmar = fcal, calmar = ccal, reason = reason)
  })
  cand_idx <- which(vapply(rows, function(r) identical(r$reason, "candidate"), logical(1)))
  if (length(cand_idx)) {
    ord <- cand_idx[order(-vapply(rows[cand_idx], function(r) r$calmar, numeric(1)))]
    keep <- ord[seq_len(min(CF$max_candidates, length(ord)))]
    for (k in setdiff(ord, keep)) rows[[k]]$reason <- "beyond_max_candidates"
    for (r in seq_along(keep)) rows[[keep[r]]]$rank <- r
  }

  summ <- list()
  for (r in rows) {
    odir <- file.path(out_base, r$code); dir.create(odir, recursive = TRUE, showWarnings = FALSE)
    fa <- r$floor$attempt
    rec <- list(schema = "rf_overlay_adversary_v1", at = .adv_now(), base_id = base_id, layer = as.integer(layer),
                block = block, n = r$n, code = r$code, dry_run = isTRUE(dry_run),
                candidate = identical(r$reason, "candidate"), candidate_rank = r$rank %||% NA_integer_,
                cell = list(calmar = r$calmar, port_t = .adv_num(r$a$essence$port_t), mdd = .adv_num(r$a$essence$mdd),
                            cagr = .adv_num(r$a$essence$cagr), grade = as.character(r$a$grade %||% ""),
                            artifacts = .adv_art_dir(r$a, root), spec = as.character(r$a$essence$spec %||% "")),
                floor = if (is.null(fa)) NULL else list(code = .rf_attempt_code(fa), n = suppressWarnings(as.integer(fa$n)),
                            calmar = r$floor_calmar, port_t = .adv_num(fa$essence$port_t), match = r$floor$match,
                            artifacts = .adv_art_dir(fa, root), spec = as.character(fa$essence$spec %||% "")),
                own_layers = lapply(r$own, function(z) { m <- .adv_arm_meta(as.character(z$kind %||% ""), root)
                  list(kind = z$kind, arm_id = z$arm_id %||% m$id %||% NA, family = m$family %||% NA,
                       external_data = isTRUE(m$external_data),
                       vector_declared = identical(as.character(m$family %||% m$action %||% ""), "cross_sectional")) }),
                engine_supports = sup, rp_honors_lcode_switch = honors,
                cfg = list(alpha = CF$alpha, n_placebo = CF$n_placebo, max_candidates = CF$max_candidates,
                           block_rule = CF$block_rule, cost_rate = CF$cost_rate, seed = CF$seed, reruns = reruns),
                tests = list(), verdict = NA_character_, analytic_verdict = NA_character_, reason = "")
    if (!identical(r$reason, "candidate")) {
      rec$verdict <- "not_candidate"; rec$reason <- r$reason
    } else {
      rec <- tryCatch(.adv_run_tests(rec, r, CF, sup, honors, reruns, root, odir, loader),
                      error = function(e) { rec$verdict <- "error"; rec$reason <- paste0("tests_failed: ", conditionMessage(e)); rec })
    }
    rec$json_path <- file.path(odir, "adversary.json")
    write(toJSON(rec, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = 8), rec$json_path)
    if (!isTRUE(dry_run)) {
      slim <- rec
      for (tn in names(slim$tests)) { slim$tests[[tn]]$placebo <- NULL; slim$tests[[tn]]$obs_ret <- NULL }
      rf_record_adversary(layer, base_id, r$n, slim, root = root)
    }
    tst <- function(k) as.character((rec$tests[[k]] %||% list())$status %||% NA_character_)
    summ[[length(summ) + 1L]] <- data.table(
      code = r$code, n = r$n, calmar = r$calmar,
      floor_code = if (is.null(fa)) NA_character_ else as.character(.rf_attempt_code(fa)), floor_calmar = r$floor_calmar,
      candidate = identical(r$reason, "candidate"), verdict = rec$verdict, reason = rec$reason,
      T1 = tst("T1"), T2 = tst("T2"), T3 = tst("T3"), T3b = tst("T3b"), T4 = tst("T4"),
      T5_share = .adv_num((rec$tests$T5 %||% list())$share_largest), json = rec$json_path)
    cat(sprintf("[rf_overlay_adversary] %s n=%s calmar %.3f vs floor %s %.3f → %s (%s)\n", r$code, r$n,
                r$calmar %||% NA, if (is.null(fa)) "?" else .rf_attempt_code(fa), r$floor_calmar %||% NA,
                rec$verdict, rec$reason))
  }
  rbindlist(summ, use.names = TRUE)
}

# 후보 1칸의 검정 전부 — rec 를 채워 돌려준다(예외는 호출자가 error verdict 로 접는다)
.adv_run_tests <- function(rec, r, CF, sup, honors, reruns, root, odir, loader) {
  fa <- r$floor$attempt
  fart <- .adv_art_dir(fa, root); cart <- .adv_art_dir(r$a, root)
  if (!dir.exists(fart)) stop("바닥 산출물 디렉터리 부재: ", fart)
  if (!dir.exists(cart)) stop("셀 산출물 디렉터리 부재: ", cart)
  PR <- .adv_read_period_returns(fart)
  HF <- .adv_read_holdings(fart); HC <- .adv_read_holdings(cart)
  al <- .adv_align_exposure(HF, HC); A <- al$A
  if (nrow(A) < CF$min_periods) stop(sprintf("기간 %d < min_periods %d", nrow(A), CF$min_periods))
  px <- .adv_period_index(PR$dt$date, A$date)
  r_d <- PR$dt$ret_net[px$keep]; pid <- px$pid[px$keep]
  exec_pos <- match(px$exec_pos, which(px$keep))
  if (anyNA(exec_pos)) stop("집행일을 수익일에 대응하지 못한 기간이 있다")
  E <- A$E
  floor_approx <- adv_calmar_from_ret(r_d, PR$ann)
  rec$approximation <- list(
    returns = "floor 03_period_returns.csv ret_net", frequency = PR$freq, ann_factor = PR$ann,
    exposure = "Σ target_weight(cell)/Σ target_weight(floor) per floor exec date",
    cost = sprintf("|ΔE_p| × %.4f at exec (first ΔE = 0)", CF$cost_rate),
    missing_month_policy = "carry_forward_prev_holdings (harness semantics)", n_missing_cell_dates = al$n_missing,
    n_extra_cell_dates = al$n_extra_cell_dates, n_periods = nrow(A), n_return_rows = length(r_d),
    floor_calmar_essence = r$floor_calmar, floor_calmar_approx = floor_approx$calmar,
    floor_approx_gap = floor_approx$calmar - r$floor_calmar,
    floor_exposure_mean = mean(A$Ef), cell_exposure_mean = mean(A$Ec), E_mean = mean(E), E_min = min(E), E_max = max(E),
    n_full_cash = sum(E <= 1e-12))
  # T3
  t3 <- adv_t3_placebo(r_d, pid, E, exec_pos, CF$cost_rate, CF$n_placebo, CF$alpha, CF$seed, CF$block_rule, PR$ann)
  obs_ret <- t3$obs_ret; t3$obs_ret <- NULL
  rec$tests$T3 <- t3
  # T4
  rec$tests$T4 <- adv_t4_static(r_d, pid, E, exec_pos, CF$cost_rate, obs_calmar = t3$obs_calmar, PR$ann)
  # T5
  rec$tests$T5 <- adv_t5_episode(r_d, obs_ret, PR$dt$date[px$keep])
  rec$tests$T5$cell_calmar_essence <- r$calmar; rec$tests$T5$cell_calmar_approx <- t3$obs_calmar
  # T3b — 벡터 처치가 **관측**될 때만
  vo <- .adv_vector_observed(HF, HC)
  rec$vector_observed <- isTRUE(vo$observed); rec$vector_dates_vary <- vo$n_dates_vary
  if (isTRUE(vo$observed)) {
    rec$tests$T3b <- tryCatch({
      HP <- .adv_holding_period_returns(HF, PR$dt$date, loader)
      M <- vo$M[, .(date, ticker, e)]; M[, pid := match(date, sort(unique(HF$date)))]
      H <- merge(HP, M[, .(pid, ticker, e)], by = c("pid", "ticker"), all.x = TRUE)
      H[is.na(e), e := 0]
      cov <- mean(is.finite(H$R))
      z <- adv_t3b_xs(H[is.finite(R)], CF$cost_rate, CF$n_placebo, CF$alpha, CF$seed, ann = 12)
      z$rawdata_coverage <- cov; z
    }, error = function(e) list(status = "error", reason = conditionMessage(e)))
  } else rec$tests$T3b <- list(status = "not_computed", reason = "scalar_exposure_only (날짜 안 e_i 산포 0)")
  # T1 / T2 — 재실행
  ext <- any(vapply(rec$own_layers, function(z) isTRUE(z$external_data), logical(1)))
  guard <- if (identical(reruns, "skip")) "skipped_by_arg" else
           if (!isTRUE(sup$overlay_shift)) "skipped_engine_unsupported (rf_cell_engine.R 에 overlay_shift 없음)" else
           if (!honors && !isTRUE(CF$allow_lcode_leak) && !identical(reruns, "force"))
             "skipped_side_effect_guard (run_paper_replication.R 이 QVEST_RP_NO_LCODE 를 읽지 않는다 — L-code 누출)" else ""
  rec$tests$T1 <- if (nzchar(guard)) list(applicable = TRUE, status = "skipped", detail = guard) else {
    z <- .adv_rerun(r$spec, "T1", r$code, rec$base_id, r$n, root, odir, CF$worker_timeout_sec)
    if (!identical(z$status, "ok")) list(applicable = TRUE, status = "error", detail = z$detail, spec = z$spec, side_effects = z$side_effects) else {
      cs <- .adv_num(z$essence$calmar)
      list(applicable = TRUE, status = if (is.finite(cs) && cs > r$floor_calmar) "pass" else "fail",
           calmar_shift = cs, floor_calmar = r$floor_calmar, port_t_shift = .adv_num(z$essence$port_t),
           artifacts = z$artifacts, spec = z$spec, side_effects = z$side_effects,
           decision_rule = "calmar(overlay_shift=1) > floor_calmar")
    }
  }
  if (!ext) rec$tests$T2 <- list(applicable = FALSE, status = "not_applicable", detail = "own layers 에 external_data=true arm 없음") else {
    g2 <- if (nzchar(guard)) guard else if (!isTRUE(sup$overlay_strict)) "skipped_engine_unsupported (overlay_strict 없음)" else ""
    rec$tests$T2 <- if (nzchar(g2)) list(applicable = TRUE, status = "skipped", detail = g2) else {
      z <- .adv_rerun(r$spec, "T2", r$code, rec$base_id, r$n, root, odir, CF$worker_timeout_sec)
      if (!identical(z$status, "ok")) list(applicable = TRUE, status = "error", detail = z$detail, spec = z$spec, side_effects = z$side_effects) else {
        cs <- .adv_num(z$essence$calmar)
        suppressMessages(source(file.path(root, "02_Infrastructure/validation/overlay_pit_guard.R"), local = TRUE))
        ab <- overlay_lookahead_ab(r$calmar, cs, "Calmar")
        list(applicable = TRUE, status = if (is.finite(cs) && cs > r$floor_calmar) "pass" else "fail",
             calmar_strict = cs, calmar_current = r$calmar, floor_calmar = r$floor_calmar,
             inflation = ab$inflation, lookahead_suspected = isTRUE(ab$lookahead_suspected), message = ab$message,
             artifacts = z$artifacts, spec = z$spec, side_effects = z$side_effects,
             decision_rule = "calmar(overlay_strict) > floor_calmar; lookahead_suspected 면 하류는 strict 값을 쓴다")
      }
    }
  }
  # 판정
  st <- function(k) as.character(rec$tests[[k]]$status %||% "missing")
  an_req <- c("T3", "T4", if (identical(st("T3b"), "not_computed")) NULL else "T3b")
  an_st <- vapply(an_req, st, character(1))
  rec$analytic_verdict <- if (all(an_st == "pass")) "pass" else if (any(an_st == "fail")) "fail" else "error"
  req <- c("T1", an_req, if (isTRUE(rec$tests$T2$applicable)) "T2" else NULL)
  rs <- vapply(req, st, character(1)); names(rs) <- req
  if (any(rs == "fail")) { rec$verdict <- "fail"; rec$reason <- paste("failed:", paste(names(rs)[rs == "fail"], collapse = ",")) }
  else if (all(rs == "pass")) { rec$verdict <- "pass"; rec$reason <- paste("all required passed:", paste(req, collapse = ",")) }
  else { bad <- names(rs)[rs != "pass"]
         rec$verdict <- "error"
         rec$reason <- paste0("required test not passed/unavailable: ",
                              paste(sprintf("%s=%s", bad, vapply(bad, function(k) {
                                d <- as.character(rec$tests[[k]]$detail %||% rec$tests[[k]]$reason %||% "")
                                if (nzchar(d)) paste0(st(k), " · ", d) else st(k) }, character(1))), collapse = "; ")) }
  rec
}

if (sys.nframe() == 0L)
  cat("[rf_overlay_adversary.R] Loaded (G2) — rf_overlay_adversary_run(base_id, block='B5', layer=1, root, cfg, dry_run, reruns) · adv_t3_placebo / adv_t4_static / adv_t5_episode / adv_t3b_xs\n")
