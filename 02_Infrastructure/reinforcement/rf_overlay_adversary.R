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
# ★집행 규약 (2026-09-24 · 플랜 P0-04 후속 · 결정 EXEC-PRICE). 하네스(replication_harness.R)가 exec_price 로 보유창을
#   가른다 — close_d_legacy = [exec, next_exec)(새 보유가 집행일 수익을 가짐 · 비용 = 집행일 가산) · close_t1 =
#   (exec, next_exec](집행일 수익은 **직전 보유**가 드리프트 비중으로 · 비용 = 새 보유 첫 날에 곱). 구판 해석 경로
#   (.adv_period_index · .adv_holding_period_returns)는 legacy 창(집행일 ≤ 수익일 < 다음 집행일)을 **가정**했다 —
#   close_t1 칸에 그대로 쓰면 집행일 수익을 새 노출 E_{p+1} 로 곱해 한 기간 어긋난 경로를 잰다.
#   이제 칸의 규약을 **산출물에서** 읽는다(.adv_attempt_exec): 선언 = authoritative_remeasure.json::measurement_regime.exec_price
#   (> 01_strategy_spec.json::exec_price) · 검산 = 산출 창(첫 수익일 = 첫 집행일 ⇒ 집행일 포함 창 · 첫 수익일 > 첫 집행일 ⇒
#   (exec, …] 창). 선언이 없으면(P0-01 이전 산출) 산출 창에서 재도출한다 — 인자화 전 하네스는 legacy 뿐이었다.
#   선언과 산출 창이 어긋나면 conflict. 원장 essence 에 규약 표식이 있으면(P0-06 rebase 이후) 그것과도 대조하고,
#   원장 essence Calmar 가 산출물 Calmar 와 직렬화 오차(ADV_SER_TOL) 밖으로 다르면 conflict — 재측정이 essence 만 바꾸고
#   attempt$artifacts 가 옛 산출물을 가리키는 경우(후보 판정과 해석 경로가 다른 측정)를 표식 없이도 막는다.
#   ★규약이 다른 칸끼리는 비교하지 않는다: 셀과 바닥의 규약이 다르면(또는 open_t1 · 모순) 후보 판정(Calmar 비교)부터
#   거부하고 verdict "error"(reason regime_*) — 소비 보류다(not_candidate 가 아니다: 기전의 음성 증거가 아니므로).
#   규약을 판독할 수 없으면(산출물 부재) 행 단계는 구판 경로로 두고 검정 단계에서 다시 판독해 같지 않으면 멈춘다.
#   T1/T2 재실행은 칸의 규약으로 **고정**한다 — 워커는 exec_price 를 넘기지 않으므로(설정 기본값을 쓴다) 자식 프로세스에
#   QVEST_CONSTRAINT_DEFAULTS(replication_harness.R::rep_execution_config 의 명시 레버)로 execution.exec_price 만 바꾼
#   사본을 가리킨다. 재실행 산출물의 실현 규약(measurement_regime.exec_price)이 칸과 다르면 그 검정은 error(비교 거부).
#   legacy 칸은 legacy 로 — 해석 경로·재실행 모두 구판과 같은 창이다(비트 동일 · 검사 08_Tests/reinforcement/test_rf_adversary_exec_regime.R).
#   ★rebase 칸(2026-09-24 · 통합 검증 I2): 산출물 = 원장 표식 measurement_regime$remeasure_path 의 디렉터리(P0-05 형제 판 — 03/04 CSV
#   포함 · .adv_art_dir). 원장 essence 와 해석 경로가 같은 판이 되어 rebase 칸·rebase 된 바닥 위 B5 칸이 같은 규약으로 검정된다.
#   ★바닥 출처(G-F1): 셀 스펙 floor_source 가 carry/none 이면 바닥 없음(not_candidate · floor_carry/floor_missing) · PORT_t 폴백 금지
#   (floor_unidentified) — .adv_floor_of 머리 주석.
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
#       ★deferred_refresh_lock (2026-09-24 · OPS-RUNNER-REFRESH-BARRIER 수리) = 리프레시 배리어로 검정이 멈춘 칸 —
#       판정이 아니라 '다시 돌려라' 표식이다. pass 가 아니므로 소비 보류(rf_adversary_ok·rf_grade_a_hold·rf_promote 가
#       이미 그렇게 읽는다)이고, 러너가 그 entry 를 다시 잡는 첫 tick 에 승자 해석보다 앞에서 재실행한다.
#       ★표식 없이 멈추면 안 된다 — 표식 없음 = 구 attempt 호환으로 **소비 가능**이라 검증 없는 오버레이가 승자·바닥·carry 로 샌다.
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
#' @param r 일간(또는 기간) 바닥 수익 · period_of 각 r 의 기간 인덱스(1..P) · E 기간별 노출 · exec_pos 각 기간의 비용 기장 위치(r 의 인덱스)
#' @param cost_booking "additive"(legacy — 집행일 행 가산 차감 Rn = R − c) | "multiplicative"(close_t1 — 새 보유 첫 날에
#'   곱: Rn = (1 − c)(1 + R) − 1 · replication_harness.R 의 cost_booking 과 같은 기장). 기본값 = 구판 호출 호환.
adv_exposure_path <- function(r, period_of, E, exec_pos, cost_rate, cost_booking = "additive") {
  E <- as.numeric(E); E[!is.finite(E)] <- 0
  out <- as.numeric(r) * E[period_of]
  dE <- c(0, abs(diff(E)))                          # 첫 기간 ΔE=0 — 초기 매수 비용은 바닥 r_t 에 이미 있다
  if (identical(cost_booking, "multiplicative")) {
    if (anyDuplicated(exec_pos)) stop("[rf_overlay_adversary] 곱 기장인데 두 기간이 같은 기장 위치를 가진다")
    out[exec_pos] <- (1 - dE * cost_rate) * (1 + out[exec_pos]) - 1
    return(out)
  }
  if (!identical(cost_booking, "additive")) stop("[rf_overlay_adversary] 미지 cost_booking: ", cost_booking)
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
                           seed = 20260917L, block_rule = "auto", ann = 252, cost_booking = "additive") {
  bl <- adv_block_len(E, block_rule)
  obs_ret <- adv_exposure_path(r, period_of, E, exec_pos, cost_rate, cost_booking)
  obs <- adv_calmar_from_ret(obs_ret, ann)
  plc <- .adv_with_seed(seed, vapply(seq_len(n_placebo), function(k) {
    Ep <- adv_circular_block_perm(E, bl$b)
    adv_calmar_from_ret(adv_exposure_path(r, period_of, Ep, exec_pos, cost_rate, cost_booking), ann)$calmar
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
adv_t4_static <- function(r, period_of, E, exec_pos, cost_rate, obs_calmar = NULL, ann = 252, cost_booking = "additive") {
  Ec <- mean(as.numeric(E), na.rm = TRUE)
  cst <- adv_calmar_from_ret(as.numeric(r) * Ec, ann)
  if (is.null(obs_calmar))
    obs_calmar <- adv_calmar_from_ret(adv_exposure_path(r, period_of, E, exec_pos, cost_rate, cost_booking), ann)$calmar
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
.adv_read_dates <- function(p) {
  if (!file.exists(p)) return(NULL)
  x <- tryCatch(fread(p, select = "date", showProgress = FALSE), error = function(e) NULL)
  if (is.null(x) || !nrow(x)) return(NULL)
  as.Date(x$date)
}

# ── 집행 규약 판독 (P0-04 후속 · 2026-09-24 — 머리 주석 ★집행 규약) ───────────────────────
#   이 파일이 해석 경로를 가진 규약만 지원한다. open_t1 은 집행일 수익이 겹밤(직전 보유)·장중(새 보유)으로 갈려
#   날짜당 노출 하나(E_p)로 표현할 수 없다 — 판독되면 unsupported 로 거부한다(민감도 전용 규약 · 러너는 쓰지 않는다).
ADV_EXEC_SUPPORTED <- c("close_d_legacy", "close_t1")
.adv_exec_window <- function(ep) switch(as.character(ep)[1], close_d_legacy = "[exec, next_exec)",
                                         close_t1 = "(exec, next_exec]", NA_character_)
.adv_exec_cost_booking <- function(ep) if (identical(ep, "close_t1")) "multiplicative" else "additive"

#' 선언된 규약 — authoritative_remeasure.json::measurement_regime.exec_price > 01_strategy_spec.json::exec_price.
#'   둘 다 있는데 다르면 conflict(선언끼리 모순).
.adv_declared_exec <- function(art) {
  rd1 <- function(f, get) { p <- file.path(art, f)
    if (!nzchar(art) || !file.exists(p)) return(NA_character_)
    j <- tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
    v <- tryCatch(as.character(get(j) %||% "")[1], error = function(e) "")
    if (length(v) && !is.na(v) && nzchar(v)) v else NA_character_ }
  a <- rd1("authoritative_remeasure.json", function(j) (j$measurement_regime %||% list())$exec_price)
  s <- rd1("01_strategy_spec.json", function(j) j$exec_price)
  if (!is.na(a) && !is.na(s) && !identical(a, s))
    return(list(value = NA_character_, source = sprintf("선언 모순: authoritative_remeasure %s ≠ 01_strategy_spec %s", a, s), conflict = TRUE))
  if (!is.na(a)) return(list(value = a, source = "authoritative_remeasure.json::measurement_regime.exec_price", conflict = FALSE))
  if (!is.na(s)) return(list(value = s, source = "01_strategy_spec.json::exec_price", conflict = FALSE))
  list(value = NA_character_, source = "absent", conflict = FALSE)
}

#' 산출 창 — 첫 수익일과 첫 집행일(04_holdings date)의 관계. 선언이 아니라 **배출된 값**에서 읽는다.
#'   exec_inclusive = 첫 집행일에 수익 행이 있다(새 보유가 집행일 수익을 가진다 — legacy)
#'   exec_exclusive = 첫 수익 행이 첫 집행일 뒤 · 둘째 집행일 이하(첫 창 (exec_1, exec_2] — close_t1)
#'   unknown = 그 밖(파일 부재 · 보유가 수익보다 늦게 시작 등 — 추정하지 않는다)
.adv_derived_window <- function(ret_dates, exec_dates) {
  rd <- sort(unique(as.Date(ret_dates))); ed <- sort(unique(as.Date(exec_dates)))
  if (!length(rd) || !length(ed) || anyNA(rd[1]) || anyNA(ed[1])) return("unknown")
  if (rd[1] == ed[1]) return("exec_inclusive")
  if (rd[1] > ed[1] && (length(ed) < 2L || rd[1] <= ed[2])) return("exec_exclusive")
  "unknown"
}
.adv_window_compatible <- function(ep, win) (identical(ep, "close_d_legacy") && identical(win, "exec_inclusive")) ||
                                            (identical(ep, "close_t1") && identical(win, "exec_exclusive")) ||
                                            (identical(ep, "open_t1") && identical(win, "exec_inclusive"))

#' 산출물 하나의 규약 — 선언 + 산출 창 대조. ret_dates/exec_dates 를 주면 파일을 다시 안 읽는다.
#' @return list(exec_price(NA 가능), status ∈ declared_verified/declared_only/derived/conflict/unknown, source, window)
.adv_resolve_exec <- function(art, ret_dates = NULL, exec_dates = NULL) {
  dec <- .adv_declared_exec(art)
  if (is.null(ret_dates) && nzchar(art)) ret_dates <- .adv_read_dates(file.path(art, "03_period_returns.csv"))
  if (is.null(exec_dates) && nzchar(art)) exec_dates <- .adv_read_dates(file.path(art, "04_holdings.csv"))
  win <- .adv_derived_window(ret_dates, exec_dates)
  mk <- function(ep, st, src) list(exec_price = ep, status = st, source = src, window = win)
  if (isTRUE(dec$conflict)) return(mk(NA_character_, "conflict", dec$source))
  if (!is.na(dec$value)) {
    if (identical(win, "unknown")) return(mk(dec$value, "declared_only", paste0(dec$source, " (산출 창 판독 불가)")))
    if (.adv_window_compatible(dec$value, win)) return(mk(dec$value, "declared_verified", paste0(dec$source, " + 산출 창 ", win)))
    return(mk(NA_character_, "conflict", sprintf("선언 %s(%s) ≠ 산출 창 %s", dec$value, dec$source, win)))
  }
  if (identical(win, "exec_inclusive"))
    return(mk("close_d_legacy", "derived", "선언 부재(P0-01 이전 산출) + 산출 창 exec_inclusive — 인자화(P0-04) 전 하네스의 유일 규약"))
  if (identical(win, "exec_exclusive"))
    return(mk("close_t1", "derived", "선언 부재 + 산출 창 exec_exclusive"))
  mk(NA_character_, "unknown", "선언 부재 · 산출 창 판독 불가")
}

#' 원장 essence 의 규약 표식(있으면) — P0-06 rebase 가 essence 를 새 규약 값으로 바꾸고 표식을 남기는 자리들.
#'   표식이 없으면 NA(구 attempt · 산출물이 정본).
.adv_essence_exec <- function(a) {
  es <- a$essence %||% list()
  for (v in list(es$exec_price, (es$measurement_regime %||% list())$exec_price, (a$measurement_regime %||% list())$exec_price)) {
    v <- tryCatch(as.character(v %||% "")[1], error = function(e) "")
    if (length(v) && !is.na(v) && nzchar(v)) return(v)
  }
  NA_character_
}

#' 직렬화 허용오차 — 원장 essence(.rf_write · jsonlite digits=6)와 산출물 authoritative_remeasure.json(write_json digits=6)은
#'   같은 수를 소수 6자리로 **각각** 반올림한다(각 ≤ 5e-7 → 합 ≤ 1e-6). 연구 수치가 아니라 두 직렬화의 산술 상한이다.
#'   실측(2026-09-24 원장 사본): 측정 칸 1,228 전부 이 오차 안(불일치 0 · 산출물 부재 8).
ADV_SER_TOL <- 1e-6
.adv_artifact_calmar <- function(art) {
  p <- file.path(art, "authoritative_remeasure.json")
  if (!nzchar(art) || !file.exists(p)) return(NA_real_)
  j <- tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
  v <- suppressWarnings(as.numeric((j$essence %||% list())$calmar %||% NA)); if (length(v)) v[1] else NA_real_
}

#' attempt 의 규약 — 산출물 판독 + 원장 대조 2종(다르면 conflict: 등급 수치와 해석 경로가 다른 측정이다)
#'   ① essence 규약 표식(있으면) ≠ 산출물 규약 ② essence Calmar ≠ 산출물 Calmar(직렬화 오차 밖) — ②는 표식이 없어도
#'   잡는다: 재측정·rebase(P0-05/06)가 essence 만 바꾸고 attempt$artifacts 가 옛 산출물을 가리키면 후보 판정(essence)과
#'   T3·T1(산출물 경로)이 다른 규약을 섞는다. 그때는 비교하지 않는다(fail-closed).
.adv_attempt_exec <- function(a, art, ret_dates = NULL, exec_dates = NULL) {
  has_art <- nzchar(art) && dir.exists(art)
  rr <- if (has_art) .adv_resolve_exec(art, ret_dates, exec_dates) else
          list(exec_price = NA_character_, status = "unknown", source = "산출물 디렉터리 부재", window = "unknown")
  et <- .adv_essence_exec(a)
  if (!is.na(et)) {
    if (!is.na(rr$exec_price) && !identical(et, rr$exec_price)) {
      rr$source <- sprintf("원장 essence 규약 %s ≠ 산출물 %s (%s)", et, rr$exec_price, rr$source)
      rr$exec_price <- NA_character_; rr$status <- "conflict"
    } else if (is.na(rr$exec_price) && !identical(rr$status, "conflict")) {
      rr$exec_price <- et; rr$status <- "essence_only"; rr$source <- paste0("원장 essence 표식 (산출물: ", rr$source, ")")
    }
  }
  ac <- if (has_art) .adv_artifact_calmar(art) else NA_real_
  lc <- suppressWarnings(as.numeric((a$essence %||% list())$calmar %||% NA))[1]
  if (!identical(rr$status, "conflict") && length(lc) && is.finite(ac) && is.finite(lc) && abs(ac - lc) > ADV_SER_TOL * max(1, abs(ac))) {
    rr$source <- sprintf("원장 essence Calmar %.6f ≠ 산출물 Calmar %.6f — 등급 수치와 해석 경로가 다른 측정(재측정·rebase 뒤 산출물 경로 미갱신 등) (%s)",
                         lc, ac, rr$source)
    rr$exec_price <- NA_character_; rr$status <- "conflict"
  }
  rr
}

#' 셀·바닥 규약 쌍 — same 일 때만 같은 해석 경로·같은 Calmar 비교가 성립한다.
#'   conflict > undetermined(한쪽 판독 불가) > unsupported > mismatch > same
.adv_regime_pair <- function(cell, floor) {
  st <- if (identical(cell$status, "conflict") || identical(floor$status, "conflict")) "conflict" else
        if (is.na(cell$exec_price) || is.na(floor$exec_price)) "undetermined" else
        if (!(cell$exec_price %in% ADV_EXEC_SUPPORTED) || !(floor$exec_price %in% ADV_EXEC_SUPPORTED)) "unsupported" else
        if (!identical(cell$exec_price, floor$exec_price)) "mismatch" else "same"
  list(status = st, exec_price = if (identical(st, "same")) cell$exec_price else NA_character_, cell = cell, floor = floor)
}
.adv_regime_detail <- function(rp) sprintf("regime_%s: cell=%s[%s] floor=%s[%s] — 규약이 다른(또는 판독 불가·미지원) 칸끼리 Calmar·수익 경로를 비교하지 않는다",
                                           rp$status, rp$cell$exec_price %||% NA, rp$cell$source %||% "", rp$floor$exec_price %||% NA, rp$floor$source %||% "")
.adv_regime_rec <- function(rp) list(status = rp$status, exec_price = rp$exec_price,
                                     holding_window = .adv_exec_window(rp$exec_price),
                                     cell = rp$cell[c("exec_price", "status", "window", "source")],
                                     floor = rp$floor[c("exec_price", "status", "window", "source")])

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

#' 기간 색인 — 각 수익일이 어느 집행 기간에 속하나 · 각 기간의 비용 기장 위치
#'   close_d_legacy : 집행일 ≤ day < 다음 집행일 · 기장 = 집행일(없으면 그 기간 첫 수익일) — 구판 그대로
#'   close_t1       : 집행일 < day ≤ 다음 집행일 · 기장 = 그 기간 첫 수익일(= 새 보유 첫 날 · 하네스 cost_date)
#'   기본값 = 구판 호출 호환(검사 픽스처). 운영 경로(.adv_run_tests)는 칸의 규약을 **항상 명시**한다.
.adv_period_index <- function(ret_dates, exec_dates, exec_price = "close_d_legacy") {
  if (identical(exec_price, "close_t1")) {
    pid <- findInterval(ret_dates, exec_dates, left.open = TRUE)   # exec_k < day ≤ exec_{k+1} — 집행일 수익은 직전 보유
    return(list(pid = pid, keep = pid >= 1L, exec_pos = match(seq_along(exec_dates), pid)))
  }
  if (!identical(exec_price, "close_d_legacy")) stop("[rf_overlay_adversary] 해석 경로가 없는 집행 규약: ", exec_price)
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

#' 바닥 보유의 보유기간 종목수익 — 하네스처럼 보유창에서 일간 Ret 복리(비유한 = 0)
#'   창은 규약을 따른다(.adv_period_index 와 같은 경계): legacy [exec, next) · close_t1 (exec, next]
.adv_holding_period_returns <- function(HF, ret_dates, loader, exec_price = "close_d_legacy") {
  if (!(exec_price %in% ADV_EXEC_SUPPORTED)) stop("[rf_overlay_adversary] 해석 경로가 없는 집행 규약: ", exec_price)
  ex <- sort(unique(HF$date))
  last_day <- max(ret_dates)
  RAW <- loader(unique(HF$ticker), min(ex), last_day)
  if (!nrow(RAW)) stop("RAWDATA 에서 바닥 보유 종목의 수익이 0행")
  RAW[!is.finite(Ret), Ret := 0]
  RAW <- RAW[Date %in% ret_dates]                              # 하네스 거래일 집합
  RAW[, pid := findInterval(Date, ex, left.open = identical(exec_price, "close_t1"))]
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
.adv_make_variant_spec <- function(spec, variant = c("T1", "T2"), exec_price = NULL) {
  variant <- match.arg(variant)
  v <- spec
  if (identical(variant, "T1")) v$overlay_shift <- 1L else v$overlay_strict <- TRUE
  v$adversary <- list(variant = variant, of_code = as.character(spec$code %||% ""), at = .adv_now(),
                      note = "적대 재실행 — 원장·모듈 풀·L-code 대상 아님")
  # 기록만(소비자 없음) — 고정은 QVEST_CONSTRAINT_DEFAULTS 사본이 한다(.adv_rerun). 실현값은 재실행 산출물에서 대조한다.
  if (!is.null(exec_price)) v$adversary$exec_price_pin <- as.character(exec_price)
  v$idea  <- sprintf("[ADVERSARY %s] %s", variant, as.character(spec$idea %||% spec$code %||% ""))
  v$label <- sprintf("[ADV %s] %s", variant, as.character(spec$label %||% spec$code %||% ""))
  v
}

# ── 재실행 규약 고정 (P0-04 후속 · 2026-09-24) ─────────────────────────────────────
#   워커(rf_cell_worker.R)는 run_paper_replication 에 exec_price 를 넘기지 않는다 → 하네스가 설정 기본값을 쓴다.
#   칸과 다른 규약으로 재실행하면 T1/T2 가 바닥 Calmar(칸 규약)와 다른 규약의 수치를 비교하게 된다.
#   하네스의 명시 레버 QVEST_CONSTRAINT_DEFAULTS(rep_execution_config — 이 경로만 읽고 execution 블록만 쓴다)에
#   execution.exec_price 만 바꾼 사본을 물린다. 원본 설정은 건드리지 않는다. 원본 경로 = 이미 레버가 서 있으면 그 파일
#   (검사가 사본을 가리킨 경우) · 아니면 <root>/02_Infrastructure/worktask/constraint_defaults.json. 없으면 멈춘다.
.adv_pin_exec_config <- function(root, exec_price, dir) {
  if (!(as.character(exec_price)[1] %in% ADV_EXEC_SUPPORTED)) stop("고정할 수 없는 규약: ", exec_price)
  src <- Sys.getenv("QVEST_CONSTRAINT_DEFAULTS", "")
  if (!nzchar(src)) src <- file.path(root, "02_Infrastructure", "worktask", "constraint_defaults.json")
  if (!file.exists(src)) stop("constraint_defaults.json 부재: ", src)
  j <- fromJSON(src, simplifyVector = FALSE)
  ex <- j$execution
  if (!is.list(ex)) stop("execution 블록 부재 — 규약 고정 불가(기본값을 지어내지 않는다): ", src)
  ex$exec_price <- as.character(exec_price)[1]
  p <- file.path(dir, "cdef_exec_pin.json")   # 짧은 이름 — .cache/rf_overlay_adversary/<BID>/<code>/T1/ 아래라 Windows 경로 260자 여유
  write(toJSON(list(execution = ex,
                    `_pinned_by` = list(tool = "rf_overlay_adversary.R::.adv_pin_exec_config", from = src,
                                        exec_price = ex$exec_price, at = .adv_now(),
                                        note = "적대 재실행 전용 사본 — execution.exec_price 만 칸 규약으로 바꿨다(replication_harness.R 는 execution 블록만 읽는다)")),
               auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA), p)
  list(path = p, from = src, exec_price = ex$exec_price)
}

# ── 재실행 (워커 경유 · 부작용 격리) ──────────────────────────────────────────────
#' @param exec_price NULL = 고정 없음(설정 기본값 — 구판 호출 호환) · 규약 문자열 = 그 규약으로 고정하고 실현값을 돌려준다
.adv_rerun <- function(spec, variant, code, base_id, n, root, out_root, timeout_sec, exec_price = NULL) {
  vdir <- file.path(out_root, variant); dir.create(vdir, recursive = TRUE, showWarnings = FALSE)
  v <- .adv_make_variant_spec(spec, variant, exec_price)
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
  pin <- NULL
  if (!is.null(exec_price)) {
    pin <- tryCatch(.adv_pin_exec_config(root, exec_price, vdir), error = function(e) e)
    if (inherits(pin, "error"))
      return(list(status = "error", detail = paste0("exec_price 고정 실패 — 재실행하지 않는다: ", conditionMessage(pin)), spec = sp))
    env_set <- c(env_set, QVEST_CONSTRAINT_DEFAULTS = pin$path)
  }
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
  # ★리프레시 배리어로 미측정 종료한 워커(deferred)는 실패 판정이 아니다 — 판정을 쓰지 않도록 위로 올린다(2026-09-24)
  if (identical(as.character(res$deferred %||% ""), "refresh_lock"))
    stop(sprintf("[refresh_barrier] %s 재실행 워커가 리프레시 잠금으로 미측정 종료 — %s", variant, as.character(res$err %||% "")))
  if (!isTRUE(res$ok)) return(list(status = "error", detail = as.character(res$err %||% "?"), spec = sp, side_effects = side))
  rart <- as.character(res$artifacts %||% "")
  list(status = "ok", spec = sp, result = out, artifacts = rart,
       essence = res$essence, grade_seen = as.character(res$grade %||% ""), side_effects = side,
       exec_price_requested = if (is.null(exec_price)) NA_character_ else as.character(exec_price)[1],
       exec_price_realized = .adv_declared_exec(rart)$value,    # 재실행 산출물의 실현 규약(하네스가 실제로 쓴 값)
       exec_pin = if (is.null(pin)) NULL else pin[c("path", "from")])
}

# ── 바닥 식별 ──────────────────────────────────────────────────────────────────
#' ★바닥 출처 (2026-09-24 수리 · 적대검증 G-F1): 러너가 셀 스펙에 floor_source 를 적는다(reinforce_auto_parallel.R —
#'   "attempt" = entry 안 자격 칸(floor_code) · "carry" = P0-10 이 바닥을 carry 구성으로 고정 · "none" = 자격 칸 없음).
#'   carry·none 바닥은 **이 entry 의 측정 칸이 아니다** — 대응하는 측정 산출물이 없어 T3/T4 의 r_t 도, T1/T2 의 비교 Calmar 도 없다.
#'   구판은 floor_source 를 읽지 않고 서명 불일치 → PORT_t 최대 칸으로 폴백해, P0-10 이 배제한 바로 그 희석 칸(14760 promo3 B1_3
#'   3.133)과 비교했다(pass 가 나면 승자·바닥·carry·A 로 샌다). 이제 carry·none 이면 바닥 없음(floor_carry/floor_missing ·
#'   not_candidate — 미검정 · 소비 보류). PORT_t 폴백은 더 이상 바닥으로 쓰지 않는다(floor_unidentified — 짐작한 바닥 위의 pass 금지).
#' @return list(attempt, match, refused) · match ∈ floor_code / sig / NULL · refused = 바닥 없음 사유(floor_carry · floor_missing ·
#'   floor_unidentified) 또는 NULL
.adv_floor_of <- function(a, spec, own, attempts, block, root, base_id) {
  fs <- as.character(spec$floor_source %||% "")[1]
  if (identical(fs, "carry"))
    return(list(attempt = NULL, match = "floor_source_carry", refused = "floor_carry",
                carry_cell = as.character(spec$floor_carry_cell %||% "")[1]))
  if (identical(fs, "none")) return(list(attempt = NULL, match = "floor_source_none", refused = "floor_missing"))
  meas <- Filter(function(x) is.list(x[["essence"]]) && !is.null(x[["essence"]]$port_t) &&
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
  # 서명 불일치 — 구판은 PORT_t 최대 칸으로 폴백했다. 러너의 바닥 규칙(규약·유니버스·창·적대검증 필터 · P0-10 carry 게이트)은
  #   그 argmax 와 다르다 → 폴백 칸은 '러너가 깐 바닥' 이 아니라 짐작이다. 짐작한 바닥으로는 검정하지 않는다(G-F1).
  other <- Filter(function(x) !startsWith(as.character(.rf_attempt_code(x) %||% ""), paste0(block, "_")), meas)
  if (!length(other)) return(list(attempt = NULL, match = NULL, refused = "floor_missing"))
  list(attempt = NULL, match = "port_t_fallback_refused", refused = "floor_unidentified")
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
#' 칸의 측정 산출물 디렉터리. ★rebase 된 칸(P0-06 · 원장 measurement_regime$remeasure_path)은 **그 형제 재측정 판 디렉터리**
#'   (2026-09-24 수리 · 통합 검증 I2): 원장 essence 가 그 판의 값이므로 해석 경로(03_period_returns·04_holdings)도 같은 판에서 읽어야
#'   한다. 구판은 attempt$artifacts(옛 규약 산출물)를 읽어 규약 판독이 conflict(원장 표식 close_t1 ≠ 산출물 legacy · Calmar 불일치)로
#'   막혔다 — rebase 칸과 rebase 된 바닥 위의 B5 칸이 전부 error. 형제 판은 P0-05 가 03/04 CSV 까지 쓴다(remeasure_from_holdings.R).
#'   형제 판 파일이 없으면 그 경로를 그대로 돌려준다(검정 단계가 '파일 부재' 로 멈춘다 — 옛 산출물로 조용히 되돌아가지 않는다).
.adv_art_dir <- function(a, root) {
  rp <- as.character(((if (is.list(a[["measurement_regime"]])) a[["measurement_regime"]] else list())$remeasure_path) %||% "")[1]
  if (!is.na(rp) && nzchar(rp)) {
    d <- dirname(gsub("\\", "/", rp, fixed = TRUE))
    if (!grepl("^(/|[A-Za-z]:)", d)) d <- file.path(root, d)
    return(d)
  }
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
                      T5_share = numeric(0), json = character(0), exec_regime = character(0))
  if (!isTRUE(CF$enabled)) { cat("[rf_overlay_adversary] overlay_adversary.enabled=false — 무동작\n"); return(empty) }
  # ★리프레시 배리어 (도훈 결정 OPS-RUNNER-REFRESH-BARRIER · 2026-09-24) — 기본 로더는 .cache/RAWDATA.parquet 를 직접 읽고(T3b)
  #   T1/T2 는 워커를 다시 띄운다. daily_refresh·아침 writer 잠금이 살아 있으면 셀 대기와 같은 상한(rb_cell_wait_s) 동안
  #   기다리고, 그래도 막히면 검정을 하지 않고 멈춘다. 주입 로더(합성)·dry_run 은 대상 아님.
  #   ★수리(2026-09-24 적대검증 3인 BLOCKING): 초판은 **아무 판정도 기록하지 않고** 멈췄다. 그런데 표식 없음 = 소비 가능
  #   (rf_runner_gates.R::rf_adversary_ok 구 attempt 호환)이라 검증 안 된 B5 칸이 다음 tick 에 블록 승자·B4 바닥·승격 carry 로
  #   소비됐다(fail-open). 이제 블록 칸 전부에 verdict "deferred_refresh_lock" 을 남기고 멈춘다(원장은 RAWDATA 가 아니다 —
  #   잠금 중 읽기·쓰기 무해). 재실행은 러너가 한다(reinforce_auto_parallel.R 적대검증 연기분 재실행).
  .rb_block <- NULL
  if (is.null(rawdata_loader) && !isTRUE(dry_run)) {
    .rbf <- file.path(root, "02_Infrastructure/ops/refresh_barrier.R")
    if (!file.exists(.rbf)) .rbf <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/ops/refresh_barrier.R"
    .rbx <- new.env()
    .rbw <- tryCatch({ sys.source(.rbf, envir = .rbx, keep.source = FALSE); .rbx$rb_wait(.rbx$rb_cell_wait_s(), root = root) },
                     error = function(e) list(proceed = FALSE, waited_s = 0, status = list(state = "error", reason = conditionMessage(e))))
    if (!isTRUE(.rbw$proceed))
      .rb_block <- sprintf("[refresh_barrier] 적대검증 착수 대기 %s초 뒤에도 %s(lock=%s pid=%s reason=%s) — 검정 연기(deferred_refresh_lock 표식)",
                           .rbw$waited_s, .rbw$status$state %||% "?", .rbw$status$lock %||% "", .rbw$status$pid %||% "",
                           .rbw$status$reason %||% "")
  }
  led <- rf_load(layer, root)
  i <- .rf_find(led, base_id)
  if (is.na(i)) stop("[rf_overlay_adversary] entry 부재: ", base_id)
  E <- led$entries[[i]]
  atts <- E$attempts %||% list()
  pat <- paste0("^", block, "_[0-9]+$")
  blk <- Filter(function(a) { cd <- .rf_attempt_code(a); !is.na(cd) && grepl(pat, cd) }, atts)
  if (!length(blk)) { cat(sprintf("[rf_overlay_adversary] %s 블록 시도 없음 (%s)\n", block, base_id)); return(empty) }
  if (!is.null(.rb_block)) {
    .adv_mark_deferred(layer, base_id, block, blk, .rb_block, root)
    stop(.rb_block)
  }
  sup <- .adv_engine_supports(root); honors <- .adv_rp_honors_lcode_switch(root)
  out_base <- file.path(root, ".cache", "rf_overlay_adversary", base_id)
  loader <- rawdata_loader %||% .adv_default_rawdata_loader(root)

  # ① 후보 판정 — 측정됨 ∧ 자기 오버레이 층 있음 ∧ [셀·바닥 같은 집행 규약] ∧ calmar > 바닥 calmar → calmar 상위 max_candidates
  #   ★규약 대조(P0-04 후속)는 바닥이 정해진 칸에서만 한다(앞 사유 칸은 산출물을 안 읽는다 — 구판 경로 그대로).
  #   규약이 다르면(또는 모순·미지원) Calmar 비교 자체가 성립하지 않으므로 calmar 사유보다 **앞에서** 거부한다.
  #   판독 불가(undetermined)는 여기서 거부하지 않는다 — 검정 단계가 실제 파일로 다시 판독하고 같지 않으면 멈춘다.
  rows <- lapply(blk, function(a) {
    cd <- .rf_attempt_code(a); n <- suppressWarnings(as.integer(a$n))
    measured <- is.list(a$essence) && !is.null(a$essence$port_t)
    sp <- .adv_load_spec(a, root, base_id)
    own <- if (is.null(sp)) list() else .adv_own_layers(sp, E$carry$overlay)
    fl <- if (measured && !is.null(sp)) .adv_floor_of(a, sp, own, atts, block, root, base_id) else list(attempt = NULL, match = NULL)
    fcal <- if (!is.null(fl$attempt)) .adv_num(fl$attempt$essence$calmar) else NA_real_
    ccal <- if (measured) .adv_num(a$essence$calmar) else NA_real_
    rp <- if (measured && !is.null(sp) && length(own) && !is.null(fl$attempt))
            .adv_regime_pair(.adv_attempt_exec(a, .adv_art_dir(a, root)), .adv_attempt_exec(fl$attempt, .adv_art_dir(fl$attempt, root))) else NULL
    reason <- if (!measured) "unmeasured" else if (is.null(sp)) "spec_missing" else if (!length(own)) "no_own_overlay_layers" else
              if (is.null(fl$attempt)) (fl$refused %||% "floor_missing") else
              if (rp$status %in% c("conflict", "unsupported", "mismatch")) paste0("regime_", rp$status) else
              if (!is.finite(ccal) || !is.finite(fcal)) "calmar_missing" else
              if (!(ccal > fcal)) "calmar_not_above_floor" else "candidate"
    list(a = a, code = cd, n = n, spec = sp, own = own, floor = fl, floor_calmar = fcal, calmar = ccal, reason = reason, regime = rp)
  })
  cand_idx <- which(vapply(rows, function(r) identical(r$reason, "candidate"), logical(1)))
  if (length(cand_idx)) {
    ord <- cand_idx[order(-vapply(rows[cand_idx], function(r) r$calmar, numeric(1)))]
    keep <- ord[seq_len(min(CF$max_candidates, length(ord)))]
    for (k in setdiff(ord, keep)) rows[[k]]$reason <- "beyond_max_candidates"
    for (r in seq_along(keep)) rows[[keep[r]]]$rank <- r
  }

  summ <- list()
  .rb_mid <- NULL   # 검정 도중 배리어 미측정 메시지 — 서면 이 칸 표식 뒤 남은 칸도 표식하고 멈춘다
  for (ri in seq_along(rows)) {
    r <- rows[[ri]]
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
    if (!is.null(r$regime)) rec$exec_regime <- .adv_regime_rec(r$regime)
    # 바닥 판별 경로(G-F1 · 2026-09-24) — floor_code / sig / floor_source_carry / floor_source_none / port_t_fallback_refused
    rec$floor_resolution <- list(match = r$floor$match %||% NA_character_, refused = r$floor$refused %||% NA_character_,
                                 floor_source = as.character((r$spec %||% list())$floor_source %||% NA)[1],
                                 carry_cell = r$floor$carry_cell %||% NA_character_)
    if (startsWith(r$reason, "regime_")) {
      # ★규약 거부는 not_candidate 가 아니다 — '바닥을 못 넘었다(기전 음성)' 가 아니라 '비교가 성립하지 않는다'. 소비 보류(error).
      rec$verdict <- "error"; rec$reason <- .adv_regime_detail(r$regime)
    } else if (!identical(r$reason, "candidate")) {
      rec$verdict <- "not_candidate"; rec$reason <- r$reason
    } else {
      rec <- tryCatch(.adv_run_tests(rec, r, CF, sup, honors, reruns, root, odir, loader),
                      error = function(e) {
                        # ★리프레시 배리어 미측정은 판정이 아니다 — verdict "error" 가 아니라 연기 표식을 남기고(아래 기록 경로 그대로)
                        #   남은 칸도 표식한 뒤 호출자에게 올린다(2026-09-24 · 표식 없이 올리면 소비 가능으로 샌다 — 머리 주석)
                        if (grepl("[refresh_barrier]", conditionMessage(e), fixed = TRUE)) {
                          .rb_mid <<- conditionMessage(e)
                          rec$verdict <- ADV_DEFERRED_VERDICT; rec$reason <- paste0("refresh_barrier: ", conditionMessage(e))
                          rec$deferred <- TRUE; return(rec) }
                        rec$verdict <- "error"; rec$reason <- paste0("tests_failed: ", conditionMessage(e)); rec })
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
      T5_share = .adv_num((rec$tests$T5 %||% list())$share_largest), json = rec$json_path,
      exec_regime = if (is.null(rec$exec_regime)) NA_character_ else
                      as.character(if (identical(rec$exec_regime$status, "same")) rec$exec_regime$exec_price else paste0("regime_", rec$exec_regime$status)))
    cat(sprintf("[rf_overlay_adversary] %s n=%s calmar %.3f vs floor %s %.3f → %s (%s)\n", r$code, r$n,
                r$calmar %||% NA, if (is.null(fa)) "?" else .rf_attempt_code(fa), r$floor_calmar %||% NA,
                rec$verdict, rec$reason))
    if (!is.null(.rb_mid)) {
      # 앞 칸들은 이번 실행의 판정이 이미 기록됐다(유지). 이 칸은 위에서 표식됐고, 남은 칸은 판정 없이 두면 소비 가능으로 샌다.
      .rest <- if (ri < length(rows)) lapply(rows[(ri + 1L):length(rows)], function(z) z$a) else list()
      if (!isTRUE(dry_run) && length(.rest)) .adv_mark_deferred(layer, base_id, block, .rest, .rb_mid, root)
      stop(.rb_mid)
    }
  }
  rbindlist(summ, use.names = TRUE)
}

# ── 리프레시 배리어 연기 표식 (2026-09-24 · OPS-RUNNER-REFRESH-BARRIER 수리) ──────────────────────────
#   판정이 아니다 — 검정을 못 돈 칸에 '다시 돌려라'를 남긴다. pass 가 아니라 소비 보류이고(머리 주석 소비자 규약),
#   러너가 이 verdict 를 보고 다음 tick 에 재실행한다. 기록 경로는 판정과 같은 writer(rf_record_adversary · 이력 보존).
ADV_DEFERRED_VERDICT <- "deferred_refresh_lock"
.adv_mark_deferred <- function(layer, base_id, block, attempts, why, root) {
  for (a in attempts) {
    n <- suppressWarnings(as.integer(a$n))
    if (!length(n) || is.na(n)) next
    rf_record_adversary(layer, base_id, n,
      list(schema = "rf_overlay_adversary_v1", at = .adv_now(), base_id = base_id, layer = as.integer(layer),
           block = block, n = n, code = as.character(.rf_attempt_code(a) %||% ""), dry_run = FALSE,
           verdict = ADV_DEFERRED_VERDICT, deferred = TRUE, reason = paste0("refresh_barrier: ", as.character(why))),
      root = root)
  }
  invisible(length(attempts))
}

# 후보 1칸의 검정 전부 — rec 를 채워 돌려준다(예외는 호출자가 error verdict 로 접는다)
.adv_run_tests <- function(rec, r, CF, sup, honors, reruns, root, odir, loader) {
  fa <- r$floor$attempt
  fart <- .adv_art_dir(fa, root); cart <- .adv_art_dir(r$a, root)
  if (!dir.exists(fart)) stop("바닥 산출물 디렉터리 부재: ", fart)
  if (!dir.exists(cart)) stop("셀 산출물 디렉터리 부재: ", cart)
  PR <- .adv_read_period_returns(fart)
  HF <- .adv_read_holdings(fart); HC <- .adv_read_holdings(cart)
  # ★집행 규약 (P0-04 후속) — 실제로 읽은 파일로 다시 판독한다(행 단계 판독과 독립). 같지 않으면 검정하지 않는다.
  rp <- .adv_regime_pair(.adv_attempt_exec(r$a, cart, .adv_read_dates(file.path(cart, "03_period_returns.csv")), HC$date),
                         .adv_attempt_exec(fa, fart, PR$dt$date, HF$date))
  rec$exec_regime <- .adv_regime_rec(rp)
  if (!identical(rp$status, "same")) stop(.adv_regime_detail(rp))
  EP <- rp$exec_price; CB <- .adv_exec_cost_booking(EP)
  al <- .adv_align_exposure(HF, HC); A <- al$A
  if (nrow(A) < CF$min_periods) stop(sprintf("기간 %d < min_periods %d", nrow(A), CF$min_periods))
  px <- .adv_period_index(PR$dt$date, A$date, EP)
  r_d <- PR$dt$ret_net[px$keep]; pid <- px$pid[px$keep]
  exec_pos <- match(px$exec_pos, which(px$keep))
  if (anyNA(exec_pos)) stop("집행일을 수익일에 대응하지 못한 기간이 있다")
  E <- A$E
  floor_approx <- adv_calmar_from_ret(r_d, PR$ann)
  rec$approximation <- list(
    returns = "floor 03_period_returns.csv ret_net", frequency = PR$freq, ann_factor = PR$ann,
    exposure = "Σ target_weight(cell)/Σ target_weight(floor) per floor exec date",
    cost = if (identical(EP, "close_t1")) sprintf("(1 − |ΔE_p| × %.4f)(1 + r) − 1 at first holding day after exec (first ΔE = 0)", CF$cost_rate) else
             sprintf("|ΔE_p| × %.4f at exec (first ΔE = 0)", CF$cost_rate),
    exec_price = EP, holding_window = .adv_exec_window(EP), cost_booking = CB,
    missing_month_policy = "carry_forward_prev_holdings (harness semantics)", n_missing_cell_dates = al$n_missing,
    n_extra_cell_dates = al$n_extra_cell_dates, n_periods = nrow(A), n_return_rows = length(r_d),
    floor_calmar_essence = r$floor_calmar, floor_calmar_approx = floor_approx$calmar,
    floor_approx_gap = floor_approx$calmar - r$floor_calmar,
    floor_exposure_mean = mean(A$Ef), cell_exposure_mean = mean(A$Ec), E_mean = mean(E), E_min = min(E), E_max = max(E),
    n_full_cash = sum(E <= 1e-12))
  # T3
  t3 <- adv_t3_placebo(r_d, pid, E, exec_pos, CF$cost_rate, CF$n_placebo, CF$alpha, CF$seed, CF$block_rule, PR$ann, cost_booking = CB)
  obs_ret <- t3$obs_ret; t3$obs_ret <- NULL
  rec$tests$T3 <- t3
  # T4
  rec$tests$T4 <- adv_t4_static(r_d, pid, E, exec_pos, CF$cost_rate, obs_calmar = t3$obs_calmar, PR$ann, cost_booking = CB)
  # T5
  rec$tests$T5 <- adv_t5_episode(r_d, obs_ret, PR$dt$date[px$keep])
  rec$tests$T5$cell_calmar_essence <- r$calmar; rec$tests$T5$cell_calmar_approx <- t3$obs_calmar
  # T3b — 벡터 처치가 **관측**될 때만
  vo <- .adv_vector_observed(HF, HC)
  rec$vector_observed <- isTRUE(vo$observed); rec$vector_dates_vary <- vo$n_dates_vary
  if (isTRUE(vo$observed)) {
    rec$tests$T3b <- tryCatch({
      HP <- .adv_holding_period_returns(HF, PR$dt$date, loader, EP)
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
  # ★재실행 규약 대조 — 재실행 산출물의 실현 규약이 칸(=바닥) 규약과 다르면 floor_calmar 와 비교하지 않는다(error)
  .rerun_regime_bad <- function(z) if (identical(as.character(z$exec_price_realized %||% NA)[1], EP)) NULL else
    list(applicable = TRUE, status = "error",
         detail = sprintf("regime_mismatch_rerun: 재실행 실현 규약 %s ≠ 칸 %s — 바닥 Calmar 와 비교 거부", as.character(z$exec_price_realized %||% NA)[1], EP),
         exec_price = EP, exec_price_realized = z$exec_price_realized %||% NA, artifacts = z$artifacts, spec = z$spec, side_effects = z$side_effects)
  rec$tests$T1 <- if (nzchar(guard)) list(applicable = TRUE, status = "skipped", detail = guard) else {
    z <- .adv_rerun(r$spec, "T1", r$code, rec$base_id, r$n, root, odir, CF$worker_timeout_sec, exec_price = EP)
    if (!identical(z$status, "ok")) list(applicable = TRUE, status = "error", detail = z$detail, spec = z$spec, side_effects = z$side_effects) else
    .rerun_regime_bad(z) %||% {
      cs <- .adv_num(z$essence$calmar)
      list(applicable = TRUE, status = if (is.finite(cs) && cs > r$floor_calmar) "pass" else "fail",
           calmar_shift = cs, floor_calmar = r$floor_calmar, port_t_shift = .adv_num(z$essence$port_t),
           exec_price = EP, exec_price_realized = z$exec_price_realized, exec_pin = z$exec_pin,
           artifacts = z$artifacts, spec = z$spec, side_effects = z$side_effects,
           decision_rule = "calmar(overlay_shift=1) > floor_calmar  [같은 집행 규약]")
    }
  }
  if (!ext) rec$tests$T2 <- list(applicable = FALSE, status = "not_applicable", detail = "own layers 에 external_data=true arm 없음") else {
    g2 <- if (nzchar(guard)) guard else if (!isTRUE(sup$overlay_strict)) "skipped_engine_unsupported (overlay_strict 없음)" else ""
    rec$tests$T2 <- if (nzchar(g2)) list(applicable = TRUE, status = "skipped", detail = g2) else {
      z <- .adv_rerun(r$spec, "T2", r$code, rec$base_id, r$n, root, odir, CF$worker_timeout_sec, exec_price = EP)
      if (!identical(z$status, "ok")) list(applicable = TRUE, status = "error", detail = z$detail, spec = z$spec, side_effects = z$side_effects) else
      .rerun_regime_bad(z) %||% {
        cs <- .adv_num(z$essence$calmar)
        suppressMessages(source(file.path(root, "02_Infrastructure/validation/overlay_pit_guard.R"), local = TRUE))
        ab <- overlay_lookahead_ab(r$calmar, cs, "Calmar")
        list(applicable = TRUE, status = if (is.finite(cs) && cs > r$floor_calmar) "pass" else "fail",
             calmar_strict = cs, calmar_current = r$calmar, floor_calmar = r$floor_calmar,
             inflation = ab$inflation, lookahead_suspected = isTRUE(ab$lookahead_suspected), message = ab$message,
             exec_price = EP, exec_price_realized = z$exec_price_realized, exec_pin = z$exec_pin,
             artifacts = z$artifacts, spec = z$spec, side_effects = z$side_effects,
             decision_rule = "calmar(overlay_strict) > floor_calmar  [같은 집행 규약]; lookahead_suspected 면 하류는 strict 값을 쓴다")
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
