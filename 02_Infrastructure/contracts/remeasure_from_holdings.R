# =============================================================================
# remeasure_from_holdings.R — 보유 기반 재측정 계약 (2026-09-24 신설 · 플랜 P0-05 · 감사 D4-01·D4-11·D8-03)
# =============================================================================
# 왜: 등급 하네스의 집행 규약이 close_d_legacy(시그널일 종가 체결 근사 · 감사 D4-01)에서 close_t1
#   (06_Registry/decision_register.json id=EXEC-PRICE · 도훈 2026-09-23)로 바뀌었다. 전환 이전에 측정된 칸의
#   등급은 옛 규약 값이고, 그 사이 데이터 빈티지도 움직였다(벤치 축 이관 09-18 · 투자자 패널 · RAWDATA 개정).
#   엔진을 다시 돌리면 FDB 빈티지가 달라 **같은 보유가 안 나온다**(08_Tests/contracts/test_replication_exec_golden.R
#   머리 ③). 그래서 **저장된 보유**(bt_result.rds$holdings = 하네스 HOLDINGS_LOG 전정밀도)를 되살려
#   하네스 → build_bt_result → audit → essence 만 다시 태운다. 선정(무엇을 샀나)은 고정하고 체결 규약과
#   수익 데이터만 바뀐다 — 선정 단계의 빈티지 결함(원장 vintage_flags: fdb_*)은 이 재측정이 고치지 않는다
#   (산출에 표식을 승계한다 — rfh_select_stage1 의 vintage_flags 열).
#
# 3판 (칸마다 — rfh_triad):
#   ① 저장값            = 산출물 authoritative_remeasure.json (측정 당시 규약·빈티지·채점 코드)
#   ② legacy@현 빈티지   = close_d_legacy · 현 RAWDATA·벤치 · 현 계약     → ②−① = 빈티지(+채점 코드) 효과
#   ③ close_t1@현 빈티지 = 결정 규약 · 현 RAWDATA·벤치 · 현 계약         → ③−② = 집행 규약 효과(빈티지 통제)
#   양성 대조: 최근 빈티지 산출물은 ② 가 ① 의 bt_result 와 비트 일치해야 한다(골든 20260921_100007_6876).
#
# 복원 규약 (replication_harness.R 와 같은 달력 — 코드를 복제하지 않고 정본 함수를 부른다):
#   하네스: 시그널 d → exec = get_execution_date(d) = d 가 속한 달의 **다음 달 첫 거래일**(backtest_harness.R).
#   보유창 = 다음 시그널의 exec 까지. HOLDINGS_LOG 는 exec 일자·부호 있는 비중으로 적힌다(contract holdings
#   actual_weight = HOLDINGS_LOG$Weight 무가공). 되살리는 시그널 = **exec 직전 거래일**(exec 가 월 첫 거래일이므로
#   전월 마지막 거래일) — get_execution_date(직전 거래일) == exec 를 전수 단정한다. 원 시그널이 월말 비거래일이어도
#   exec·다음 exec·비용(Δw) 이 같으므로 하네스 산출은 같다. start_date 필터는 쓰지 않는다(보유가 이미 필터 뒤다).
#   RAWDATA 는 **저장 산출의 마지막 날**(nav 끝 = 측정 당시 데이터 끝)에서 자른다 — 마지막 보유창이 그 뒤로
#   늘어나지 않게. 칸별 부분 적재: 보유 종목 행 + 달력 표지 행(Ret NA — 하네스 .leg_daily 가 is.finite 로
#   거른다)으로 all_dates(거래일 달력)를 전체 판과 같게 유지한다(골든 비트 재현으로 실증).
#
# 조용한 통과 금지 (stop — 배치에서는 failed 목록):
#   · 저장 NAV 의 리밸 표식(is_rebalance_date = 하네스 PORTFOLIO_LOG$Exec_Date)과 보유 exec 일자 집합 불일치
#     (보유 1개월 누락이면 앞 창이 조용히 두 달로 늘어난다 — 여기서 멈춘다)
#   · 보유 (exec, 종목) 중복·비유한 비중 · exec 가 현 달력에 없음(빈티지 달력 개정) · 직전 거래일 부재
#   · 되살린 리밸을 하네스가 건너뜀(PORTFOLIO_LOG 행 수 ≠ 되살린 시그널 수 — B6 interval 칸 포함 일반 단정)
#
# 원본 불변: 산출물 디렉터리의 기존 파일은 읽기만 한다. 쓰기 = <base>/remeasure_<regime_key>/ 아래뿐 —
#   bt_result.rds · 계약 산출 CSV/JSON(save_bt_result: 00~10 · 적대검증이 03_period_returns·04_holdings 를 읽는다) ·
#   authoritative_remeasure.json(**마지막** · 원자 교체 · 완료 표식). 다시 쓸 때는 옛 완료 표식을 먼저 지운다(반쯤 쓴 판이
#   옛 표식과 짝지어지지 않게). <base> = out_dir 가 NULL 이면 산출물 디렉터리 자신, 아니면 <out_dir>/<산출물 디렉터리명>.
#   ★형제 판 위치 계약(2026-09-24 수리 · 통합 검증 L-B1): 원장 rebase writer(reinforce_ledger.R .rf_rb_sibling)는 형제 판을
#     **칸 산출물 바로 아래** remeasure_<regime>/ 에서만 받는다(in-place). 러너 폴백 3곳(reinforce_auto_run.R · rf_cell_worker.R ·
#     rf_replication_verify.R 의 recursive list.files)은 remeasure_* 하위 디렉터리를 건너뛰도록 고쳤다 — 재측정 판이 '새 측정'
#     으로 집히지 않는다. rfh_batch 는 여전히 in_place=TRUE 명시 없이는 산출물 안에 쓰지 않는다(운영 쓰기 = 별도 승인).
#
# regime 키 = measurement_regime{exec_price · harness_md5 · cost_model_version} 에서 파생:
#   "<exec_price>_<md5(exec_price|harness_md5|cost_model_version) 앞 8자리>" — 하네스 파일이 바뀌면 키가 바뀐다.
#   (경로 길이: Windows 260자 — 규약명 + 8자리로 줄였다. 전문은 JSON measurement_regime 에 싣는다.)
#   ★JSON measurement_regime$regime = 키(디렉터리 이름 remeasure_<regime> 과 같은 값 · 2026-09-24 L-B1). 원장 writer 는
#     regime → key → exec_price 순으로 읽고 디렉터리 이름과 대조한다 — 셋이 한 값이어야 rebase 된다. 체결 규약명은 exec_price.
#
# 재개 캐시(2026-09-24 수리 · 적대검증 R①): 기존 재측정을 쓰는 조건 = regime 키 ∧ 데이터 빈티지 ∧ **채점 인자**(selection_type ·
#   n_trials_cumulative) ∧ 원 산출물(of_artifact · stored_bt_md5) ∧ 채점 코드·문턱 지문(scoring_md5 = essence_score.R ·
#   backtest_result_contract.R · audit_bt_result.R · tier_graduation). 하나라도 다르면 다시 잰다 — 구판은 채점 인자를 안 봐서
#   (sweep, 500) 호출에 옛 (chain, 1) 판을 cached=TRUE 로 돌려줬다(P0-06 D-A 재채점이 조용히 틀린다).
#
# 채점 시행 회계: 기본 = **저장 산출의 기록**(auth$selection_type · n_trials_cumulative). P0-01 이전 산출은
#   러너가 chain/1 을 하드코딩했으므로(run_paper_replication.R 머리) chain/1 이 저장 기록과 같은 값이다.
#   인자로 덮을 수 있다(P0-06 rebase 가 결정 D-A 'raw 누적 시행수' 로 재채점할 때). 사용 근거는 JSON 에 남는다.
#
# PIT: 재측정은 저장 보유(시그널일 d 확정 비중)를 그대로 쓰고 하네스가 exec 이후 수익만 붙인다 — 새 정보 접근 없음.
#   C11 표식 칸은 편입하지 않는다(결정 PIT-C11-CONVENTIONS ⑧). ★판정은 입력 모양과 무관하게 **계약이 스스로** 한다
#   (2026-09-24 수리 · 적대검증 R②): rfh_pit_screen() 이 원장(L1·L2)에서 그 산출물을 가리키는 모든 참조(칸 artifacts · 기저
#   base_artifacts)의 표식과 spec/엔진 텍스트를 읽는다 — 격리 flag(pit_c11 ∪ pit_quarantine.json 효력 flag) 또는 격리 원천·팩터
#   텍스트면 rfh_remeasure 가 멈추고 rfh_batch 는 skip 으로 보고한다(구판은 문자 벡터 입력이면 skip=FALSE 로 시작해 C11 칸을
#   쟀다). 격리 밖 빈티지 표식(fdb_* 등)은 재측정 JSON remeasure$vintage_flags 에 싣는다(선정 결함은 재측정이 못 고친다).
#
# 설정 (하드코딩 금지 — 02_Infrastructure/worktask/constraint_defaults.json::remeasure · 없으면 멈춘다):
#   stage1_near_a_max_failed · batch_n_workers. 비용은 저장 manifest 의 transaction_cost_bps(측정 당시 값)를 쓴다.
#   러너 claim 경로·stale 시간 = 러너와 같은 해석(QVEST_RF_CLAIM · reinforce_auto_config.json::claim_stale_hours 읽기만).
#   리프레시 대기 상한 = refresh_barrier.R::rb_cell_wait_s()(정본 상수·근거는 그 파일 머리).
#
# 함수:
#   rfh_root · rfh_config · rfh_load_deps · rfh_regime · rfh_regime_key · rfh_load_market
#   rfh_artifact_inputs · rfh_restore_weights · rfh_remeasure · rfh_stored · rfh_triad
#   rfh_pit_screen(원장 참조 표식·텍스트 — C11 비편입 판정) · rfh_scoring_md5(캐시 채점 지문)
#   rfh_select_stage1(목록만 — 실행 안 함) · rfh_batch(claim·배리어·병렬·재개 · 칸별 채점 인자 열)
# 검사 = 08_Tests/contracts/test_remeasure_from_holdings.R (골든 양성 대조 · 보유 누락 주입 · B6 interval · 원본 불변 ·
#   재개/force · claim/배리어 연기 · 선정 C11 skip · 돌연변이 red)
# =============================================================================

suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

.rfh_or <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

# 이 파일 위치(자기 우선 — 사본 트리에서 운영 트리 코드를 섞지 않게). source() = ofile · sys.source() = file.
.RFH_SELF <- local({
  hit <- ""
  for (i in rev(seq_len(sys.nframe()))) {
    fr <- tryCatch(sys.frame(i), error = function(e) NULL)
    if (is.null(fr)) next
    for (nm in c("ofile", "file")) {
      v <- tryCatch(get0(nm, envir = fr, inherits = FALSE), error = function(e) NULL)
      if (is.character(v) && length(v) == 1L && !is.na(v) &&
          grepl("remeasure_from_holdings\\.R$", v)) { hit <- v; break }
    }
    if (nzchar(hit)) break
  }
  if (nzchar(hit) && !grepl("^([A-Za-z]:)?[/\\\\]", hit)) hit <- file.path(getwd(), hit)
  gsub("\\\\", "/", hit)
})

RFH_CAL_TICKER <- "__RFH_CAL__"          # 달력 표지 행의 종목명(Ret NA — 하네스가 is.finite 로 거른다)
RFH_VERSION    <- "remeasure_from_holdings_v1"
.RFH_EP_TAG    <- c(close_d_legacy = "leg", close_t1 = "t1", open_t1 = "ot1")   # 행 열 접두어(표기용)

# 루트: 명시 > 이 파일 위치 > QM_ROOT > CLAUDE_PROJECT_DIR > getwd. 표지 = 하네스 파일 실재.
rfh_root <- function(root = NULL) {
  cands <- c(root, if (nzchar(.RFH_SELF)) dirname(dirname(dirname(.RFH_SELF))) else character(0),
             Sys.getenv("QM_ROOT", ""), Sys.getenv("CLAUDE_PROJECT_DIR", ""), getwd())
  cands <- gsub("\\\\", "/", cands[!is.na(cands) & nzchar(cands)])
  hit <- cands[file.exists(file.path(cands, "02_Infrastructure/replication/replication_harness.R"))]
  if (!length(hit)) stop("[rfh] 프로젝트 루트를 찾지 못했다(replication_harness.R 표지) — root 인자 또는 QM_ROOT 확인")
  hit[1]
}

# 계약 함수가 QM_ROOT/CLAUDE_PROJECT_DIR·getwd 로 루트를 푸는 곳(essence_score .graduation_root · rolling_grade)이
#   이 루트를 보게 한다 — 호출 동안만(끝나면 되돌린다).
.rfh_with_root <- function(root, expr) {
  old <- c(QM_ROOT = Sys.getenv("QM_ROOT", NA), CLAUDE_PROJECT_DIR = Sys.getenv("CLAUDE_PROJECT_DIR", NA))
  owd <- getwd()
  on.exit({
    for (k in names(old)) if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, stats::setNames(list(old[[k]]), k))
    setwd(owd)
  }, add = TRUE)
  Sys.setenv(QM_ROOT = root, CLAUDE_PROJECT_DIR = root)
  setwd(root)
  force(expr)
}

# ── 설정 ─────────────────────────────────────────────────────────────────────
rfh_config <- function(root = NULL, need = character(0)) {
  root <- rfh_root(root)
  ov <- Sys.getenv("QVEST_CONSTRAINT_DEFAULTS", "")
  p <- if (nzchar(ov)) ov else file.path(root, "02_Infrastructure/worktask/constraint_defaults.json")
  if (!file.exists(p)) stop(sprintf("[rfh] 설정 부재: %s", p))
  cfg <- jsonlite::fromJSON(p, simplifyVector = TRUE)
  rm <- cfg[["remeasure"]]
  if (!is.list(rm)) stop(sprintf("[rfh] %s 에 remeasure 블록이 없다 — 기본값을 지어내지 않는다(fail-closed)", p))
  miss <- need[vapply(need, function(k) is.null(rm[[k]]) || !is.finite(suppressWarnings(as.numeric(rm[[k]][1]))),
                      logical(1))]
  if (length(miss)) stop(sprintf("[rfh] %s::remeasure 키 부재/비수치: %s (fail-closed)", p, paste(miss, collapse = ",")))
  attr(rm, "source") <- p
  rm
}

# ── 정본 정의 적재 (전용 환경 — 호출부 전역을 더럽히지 않는다) ─────────────────────
.RFH <- new.env(parent = globalenv())

.rfh_def <- function(exprs, nm, env) {
  hit <- Filter(function(e) is.call(e) && identical(as.character(e[[1]]), "<-") &&
                  identical(as.character(e[[2]]), nm), as.list(exprs))
  if (length(hit) != 1L) stop(sprintf("[rfh] 정본 정의 %s 가 %d건 — 파일 판본 확인", nm, length(hit)))
  eval(hit[[1]], envir = env)
}

#' 정본 정의 적재 — get_execution_date(backtest_harness.R · 정의만 parse→eval: 전체 source 는 적재 비용·부작용),
#'   replication_harness.R · backtest_result_contract.R · audit_bt_result.R · essence_score.R(source),
#'   run_paper_replication.R 의 .rp_strategy_spec·.rp_abs_path(정의만 — 러너 적재는 텔레그램 등 부작용).
rfh_load_deps <- function(root = NULL) {
  root <- rfh_root(root)
  if (isTRUE(.RFH$.loaded) && identical(.RFH$.root, root)) return(invisible(.RFH))
  inf <- file.path(root, "02_Infrastructure")
  .rfh_with_root(root, {
    .rfh_def(parse(file.path(inf, "backtest_harness.R"), encoding = "UTF-8", keep.source = FALSE),
             "get_execution_date", .RFH)
    capture.output(suppressMessages({
      source(file.path(inf, "replication/replication_harness.R"), local = .RFH, encoding = "UTF-8")
      source(file.path(inf, "contracts/backtest_result_contract.R"), local = .RFH, encoding = "UTF-8")
      source(file.path(inf, "contracts/audit_bt_result.R"), local = .RFH, encoding = "UTF-8")
      source(file.path(inf, "contracts/essence_score.R"), local = .RFH, encoding = "UTF-8")
      source(file.path(inf, "contracts/save_bt_result.R"), local = .RFH, encoding = "UTF-8")   # 형제 판 CSV(적대검증 입력)
    }))
    rpx <- parse(file.path(inf, "alpha_search/run_paper_replication.R"), encoding = "UTF-8", keep.source = FALSE)
    for (nm in c(".rp_abs_path", ".rp_strategy_spec")) .rfh_def(rpx, nm, .RFH)
  })
  .RFH$.root <- root; .RFH$.loaded <- TRUE
  .RFH$.harness_path <- file.path(inf, "replication/replication_harness.R")
  invisible(.RFH)
}

.rfh_md5_str <- function(s) {
  f <- tempfile("rfh_md5_"); on.exit(unlink(f), add = TRUE)
  writeBin(charToRaw(enc2utf8(as.character(s))), f)
  unname(as.character(tools::md5sum(f)))
}

# ── regime ───────────────────────────────────────────────────────────────────
rfh_regime_key <- function(exec_price, harness_md5, cost_model_version) {
  paste0(exec_price, "_", substr(.rfh_md5_str(paste(exec_price, harness_md5, cost_model_version, sep = "|")), 1L, 8L))
}

#' 규약 → measurement_regime(현 하네스 파일 md5 · 규약별 비용 기장 라벨) + 파생 키
rfh_regime <- function(exec_price, root = NULL) {
  if (is.null(exec_price) || !length(exec_price) || is.na(exec_price[1]))
    stop("[rfh] exec_price 명시 필수 — 재측정은 규약을 고르는 호출이다(설정 기본값에 기대지 않는다)")
  rfh_load_deps(root)
  ep <- .RFH$rep_resolve_exec_price(exec_price)
  hm <- unname(as.character(tools::md5sum(.RFH$.harness_path)))
  cmv <- .RFH$rep_cost_model_version(ep)
  list(exec_price = ep, harness_md5 = hm, cost_model_version = cmv, key = rfh_regime_key(ep, hm, cmv))
}

# ── 시장 데이터 (컬럼 부분 적재 1회) ─────────────────────────────────────────────
.rfh_file_fp <- function(p) {
  fi <- file.info(p)
  list(path = gsub("\\\\", "/", p), size = unname(fi$size),
       mtime = format(fi$mtime, "%Y-%m-%dT%H:%M:%S%z"))
}

#' RAWDATA(부분 열)·벤치 1회 적재. 반환 = list(RAW[keyed Ticker,Date], BM, cal, fp).
#'   exec_prices 에 open_t1 이 있으면 Open·Close 도 싣는다. 적재 전후 파일 지문이 다르면 멈춘다(쓰는 중 적재).
rfh_load_market <- function(root = NULL, exec_prices = c("close_d_legacy", "close_t1"),
                            raw_path = NULL, bm_path = NULL) {
  root <- rfh_root(root)
  suppressPackageStartupMessages(library(arrow))
  rp <- raw_path %||% file.path(root, ".cache/RAWDATA.parquet")
  bp <- bm_path %||% file.path(root, ".cache/benchmark.parquet")
  for (p in c(rp, bp)) if (!file.exists(p)) stop(sprintf("[rfh] 시장 데이터 부재: %s", p))
  cols <- c("Date", "Ticker", "Ret", if ("open_t1" %in% exec_prices) c("Open", "Close"))
  f0 <- list(raw = .rfh_file_fp(rp), bm = .rfh_file_fp(bp))
  RAW <- as.data.table(arrow::read_parquet(rp, col_select = tidyselect::all_of(cols), mmap = FALSE))
  BM  <- as.data.table(arrow::read_parquet(bp, col_select = tidyselect::all_of(c("Date", "BM_Ret")), mmap = FALSE))
  f1 <- list(raw = .rfh_file_fp(rp), bm = .rfh_file_fp(bp))
  if (!identical(f0, f1)) stop("[rfh] 적재 중 시장 데이터 파일이 바뀌었다(리프레시 경합) — 적재를 버린다")
  # 러너(run_paper_replication.R §1)와 같은 Date 변환
  if (!inherits(RAW$Date, "Date")) RAW[, Date := as.Date(Date, tz = "Asia/Seoul")]
  if (!inherits(BM$Date, "Date"))  BM[,  Date := as.Date(Date, tz = "Asia/Seoul")]
  setkeyv(RAW, c("Ticker", "Date"))          # 칸별 종목 부분집합(이진 탐색) — 하네스 산출은 행 순서 무관(dcast 정렬)
  cal <- sort(unique(RAW$Date))
  fp <- c(f1, list(raw_nrow = nrow(RAW), raw_max_date = as.character(max(cal)), raw_cols = cols,
                   bm_nrow = nrow(BM), bm_max_date = as.character(max(BM$Date))))
  list(RAW = RAW, BM = BM, cal = cal, fp = fp)
}

.rfh_market <- function(raw, root, exec_price) {
  if (is.null(raw)) return(rfh_load_market(root, exec_prices = exec_price))
  if (is.list(raw) && !is.data.frame(raw) && all(c("RAW", "BM", "cal") %in% names(raw))) return(raw)
  stop("[rfh] raw 는 rfh_load_market() 반환값(list(RAW, BM, cal, fp))이어야 한다")
}

# ── 산출물 입력 ─────────────────────────────────────────────────────────────
.rfh_norm <- function(p) sub("/+$", "", gsub("\\\\", "/", as.character(p)))

#' 저장 산출물 판독(읽기 전용). 보유는 bt_result.rds$holdings(전정밀도) — 04_holdings.csv 는 폴백(정밀도 라벨).
rfh_artifact_inputs <- function(artifact_dir) {
  ad <- .rfh_norm(artifact_dir)
  need <- file.path(ad, c("bt_result.rds", "authoritative_remeasure.json"))
  if (!all(file.exists(need))) stop(sprintf("[rfh] 산출물 불완전: %s", paste(basename(need[!file.exists(need)]), collapse = ",")))
  bt0 <- readRDS(need[1])
  auth <- jsonlite::fromJSON(need[2], simplifyVector = TRUE)
  sp_p <- file.path(ad, "01_strategy_spec.json")
  spec0 <- if (file.exists(sp_p)) jsonlite::fromJSON(sp_p, simplifyVector = TRUE) else list()
  h <- bt0$holdings; hsrc <- "bt_result.rds$holdings(actual_weight)"
  if (is.null(h) || !nrow(h) || !all(c("date", "ticker", "actual_weight") %in% names(h))) {
    hp <- file.path(ad, "04_holdings.csv")
    if (!file.exists(hp)) stop("[rfh] 보유 부재 — bt_result.rds$holdings·04_holdings.csv 둘 다 없다")
    h <- fread(hp, colClasses = list(character = "ticker")); hsrc <- "04_holdings.csv(actual_weight · CSV 정밀도)"
  }
  H <- as.data.table(h)[, .(Exec = as.Date(date), Ticker = as.character(ticker), Weight = as.numeric(actual_weight))]
  nv <- as.data.table(bt0$nav)
  if (!"is_rebalance_date" %in% names(nv)) stop("[rfh] 저장 NAV 에 is_rebalance_date 가 없다 — 리밸 달력 대조 불가(조용히 진행하지 않는다)")
  mf <- as.data.table(bt0$manifest)
  tc <- suppressWarnings(as.numeric(mf$transaction_cost_bps[1]))
  if (!is.finite(tc)) stop("[rfh] 저장 manifest transaction_cost_bps 부재 — 비용을 지어내지 않는다")
  mr <- auth$measurement_regime
  list(dir = ad, run_dir = basename(ad), bt0 = bt0, auth = auth, spec0 = spec0, H = H, holdings_source = hsrc,
       nav_dates = as.Date(nv$date), rebal_flag = sort(unique(as.Date(nv$date[nv$is_rebalance_date %in% TRUE]))),
       end = max(as.Date(nv$date)), start = min(as.Date(nv$date)), commission = tc / 1e4, tc_bps = tc,
       run_id = as.character(.rfh_or(auth$run_id, .rfh_or(mf$run_id[1], basename(ad))))[1],
       strategy_id = as.character(.rfh_or(auth$strategy_id, .rfh_or(mf$strategy_id[1], NA)))[1],
       stored_exec_price = as.character(.rfh_or(mr$exec_price, "close_d_legacy"))[1],
       stored_exec_basis = if (is.null(mr$exec_price)) "implicit_pre_p0_04(하네스 인자화 이전 = close_d_legacy 동작)" else "measurement_regime",
       stored_harness_md5 = as.character(.rfh_or(mr$harness_md5, NA))[1],
       stored_selection_type = as.character(.rfh_or(auth$selection_type, "chain"))[1],
       stored_n_trials = suppressWarnings(as.integer(.rfh_or(auth$n_trials_cumulative, 1L))[1]))
}

#' 보유(exec 일자) → WEIGHTS(시그널일) 복원 + 달력 대조. 어긋나면 stop(조용한 통과 금지).
#' @param H data.table(Exec, Ticker, Weight) · cal 현 거래일 달력(END 이하) · rebal_flag 저장 NAV 리밸 표식 · nav_start 저장 NAV 첫날
rfh_restore_weights <- function(H, cal, rebal_flag, nav_start) {
  if (!nrow(H)) stop("[rfh] 보유 0행")
  if (anyNA(H$Exec) || anyNA(H$Ticker) || any(!nzchar(H$Ticker))) stop("[rfh] 보유 exec/종목 결측")
  if (any(!is.finite(H$Weight))) stop("[rfh] 보유 비중 비유한")
  if (anyDuplicated(H[, .(Exec, Ticker)])) stop("[rfh] 보유 (exec, 종목) 중복 — HOLDINGS_LOG 는 exec 당 종목 1행이다")
  ex <- sort(unique(H$Exec))
  # 저장 리밸 달력 대조 — 표식(PORTFOLIO_LOG$Exec_Date ∩ NAV 일자)은 모두 보유에 있어야 하고,
  #   보유에만 있는 exec 는 NAV 시작 전(close_t1 첫 집행일 — 그날 수익 행이 없다) 1건까지만 허용한다.
  miss <- rebal_flag[!rebal_flag %in% ex]                          # (setdiff 는 Date 클래스를 떨군다)
  extra <- ex[!ex %in% rebal_flag]
  bad_extra <- extra[extra >= nav_start]
  if (length(miss) || length(bad_extra) || length(extra) > 1L)
    stop(sprintf(paste0("[rfh] 보유 복원 불일치 — 저장 NAV 리밸 표식 %d건 · 보유 exec %d건 · 표식에만 %d건(%s) · ",
                        "보유에만(NAV 안) %d건(%s). 보유 누락이면 앞 보유창이 조용히 늘어난다 — 재측정하지 않는다"),
                 length(rebal_flag), length(ex), length(miss), paste(head(format(miss), 3), collapse = ","),
                 length(bad_extra), paste(head(format(bad_extra), 3), collapse = ",")))
  nc <- ex[!ex %in% cal]
  if (length(nc)) stop(sprintf("[rfh] exec %d건이 현 거래일 달력에 없다(빈티지 달력 개정): %s",
                               length(nc), paste(head(format(nc), 3), collapse = ",")))
  pos <- findInterval(as.numeric(ex) - 1, as.numeric(cal))       # exec 보다 엄격히 앞선 마지막 거래일
  if (any(pos < 1L)) stop("[rfh] 첫 exec 앞에 거래일이 없다 — 시그널일 복원 불가")
  sig <- cal[pos]
  back <- as.Date(vapply(sig, function(s) as.numeric(.RFH$get_execution_date(s, cal)), numeric(1)))
  if (!identical(as.numeric(back), as.numeric(ex)))
    stop(sprintf("[rfh] get_execution_date(직전 거래일) ≠ exec %d건 — exec 가 월 첫 거래일이 아니다(하네스 규약 밖 산출): %s",
                 sum(as.numeric(back) != as.numeric(ex)), paste(head(format(ex[as.numeric(back) != as.numeric(ex)]), 3), collapse = ",")))
  m <- data.table(Exec = ex, Date = sig)
  W <- merge(H, m, by = "Exec", sort = FALSE)[, .(Date, Ticker, Weight)]
  setorder(W, Date)
  attr(W, "n_signals") <- length(ex)
  attr(W, "n_rebal_flag") <- length(rebal_flag)
  W
}

.rfh_subset_raw <- function(mk, tickers, end) {
  sub <- mk$RAW[.(unique(tickers)), on = "Ticker", nomatch = NULL][Date <= end]
  cal <- mk$cal[mk$cal <= end]
  pad <- data.table(Date = cal, Ticker = RFH_CAL_TICKER)
  for (cc in setdiff(names(sub), c("Date", "Ticker"))) set(pad, j = cc, value = NA_real_)
  list(RAW = rbind(sub, pad, use.names = TRUE), cal = cal)
}

.rfh_out_dir <- function(inp, key, out_dir) {
  base <- if (is.null(out_dir)) inp$dir else file.path(.rfh_norm(out_dir), inp$run_dir)
  file.path(base, paste0("remeasure_", key))
}

.rfh_atomic_write <- function(target, writer) {
  tmp <- paste0(target, ".tmp")
  # Windows MAX_PATH(260 · 종단 NUL 포함) — 넘으면 gzfile 이 "cannot open the connection" 만 남긴다(원인 불명 실패).
  #   (경로는 호출부가 절대경로로 만든다 — 정규화 함수는 쓰지 않는다: 한글 경로 규약)
  if (identical(.Platform$OS.type, "windows") && nchar(tmp) > 259L)
    stop(sprintf("[rfh] 경로 길이 %d > 259 (Windows MAX_PATH) — out_dir 를 짧게: %s", nchar(tmp), tmp))
  on.exit(if (file.exists(tmp)) unlink(tmp), add = TRUE)
  writer(tmp)
  if (file.exists(target)) unlink(target)
  if (!file.rename(tmp, target)) stop(sprintf("[rfh] 원자 교체 실패: %s", target))
  invisible(target)
}

# 재개 — 같은 regime 키 ∧ 같은 데이터 빈티지(RAWDATA·벤치 파일 크기·mtime)일 때만 기존 재측정을 쓴다.
#   빈티지가 바뀐 뒤의 재개는 한 배치 안에 두 빈티지를 섞는다 — 다시 잰다(빈티지 효과 분리가 이 계약의 일이다).
.rfh_fp_now <- function(raw, root) {
  if (!is.null(raw) && !is.null(raw$fp)) return(raw$fp[c("raw", "bm")])
  list(raw = .rfh_file_fp(file.path(root, ".cache/RAWDATA.parquet")), bm = .rfh_file_fp(file.path(root, ".cache/benchmark.parquet")))
}
.rfh_fp_same <- function(a, b) {
  f <- function(x) c(as.character(x$raw$size), as.character(x$raw$mtime), as.character(x$bm$size), as.character(x$bm$mtime))
  isTRUE(tryCatch(identical(f(a), f(b)), error = function(e) FALSE))
}
#' 채점 지문 — 등급·지표를 정하는 코드(essence_score.R · backtest_result_contract.R · audit_bt_result.R)와 문턱(tier_graduation)의 md5.
#'   캐시가 이것을 대조한다(구판은 하네스 md5·데이터만 봐서 채점 코드·문턱이 바뀐 뒤 재개하면 등급이 섞였다 — 적대검증 R①·MAJOR).
rfh_scoring_md5 <- function(root = NULL) {
  root <- rfh_root(root)
  rfh_load_deps(root)
  fs <- file.path(root, "02_Infrastructure/contracts", c("essence_score.R", "backtest_result_contract.R", "audit_bt_result.R"))
  if (!all(file.exists(fs))) stop("[rfh] 채점 코드 파일 부재 — 채점 지문을 만들 수 없다")
  gp <- .rfh_with_root(root, .RFH$.graduation_params(refresh = TRUE, root = root))
  txt <- paste(c(unname(as.character(tools::md5sum(fs))),
                 as.character(jsonlite::toJSON(gp, auto_unbox = TRUE, digits = NA, null = "null", na = "null"))), collapse = "|")
  .rfh_md5_str(txt)
}

#' 캐시 판독 — 같은 키 ∧ 빈티지 ∧ 채점 인자 ∧ 원 산출물 ∧ 채점 지문일 때만 기존 판을 돌려준다(그 밖은 NULL = 다시 잰다).
#' @param want list(selection_type, n_trials_cumulative, of_artifact, stored_bt_md5, scoring_md5) — NULL 원소는 대조하지 않는다
#'   (호출부 rfh_remeasure 는 다섯 개를 전부 채운다 — 대조를 끄는 경로가 없다).
.rfh_cached <- function(p, key, fp_now = NULL, want = list()) {
  if (!file.exists(p)) return(NULL)
  j <- tryCatch(jsonlite::fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(j) || !identical(as.character(j$measurement_regime$key %||% ""), key) || is.null(j$remeasure)) return(NULL)
  if (!is.null(fp_now) && !.rfh_fp_same(j$measurement_regime$data_vintage, fp_now)) return(NULL)
  mr <- j$measurement_regime; rm <- j$remeasure
  got <- list(selection_type = as.character(mr$selection_type %||% NA)[1],
              n_trials_cumulative = suppressWarnings(as.integer(mr$n_trials_cumulative %||% NA)[1]),
              of_artifact = tolower(.rfh_norm(rm$of_artifact %||% "")),
              stored_bt_md5 = as.character(rm$stored_bt_md5 %||% NA)[1],
              scoring_md5 = as.character(mr$scoring_md5 %||% NA)[1])
  for (k in names(want)) {
    w <- want[[k]]; if (is.null(w)) next
    if (identical(k, "of_artifact")) w <- tolower(.rfh_norm(w))
    if (identical(k, "n_trials_cumulative")) w <- suppressWarnings(as.integer(w)[1])
    if (!isTRUE(identical(got[[k]], w))) return(NULL)
  }
  jsonlite::fromJSON(p, simplifyVector = TRUE)
}
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

# ── PIT 표식 판정 (결정 PIT-C11-CONVENTIONS ⑧ · 2026-09-24 수리 R②) ─────────────────────────
#   격리 flag = "pit_c11"(결정 ⑧ 상수 — 원장 writer RF_REBASE_BLOCK_FLAGS 와 같은 값) ∪ pit_quarantine.json 효력 항목 flag.
#   텍스트 = 칸 spec(attempt essence$spec) · 기저 engine_path 가 격리 원천 정규식·격리 팩터 id 를 참조하는가(rfh_select_stage1 과 같은 판정).
RFH_BLOCK_FLAGS <- c("pit_c11")
.rfh_pit_ctx <- function(root) {
  pq <- new.env(parent = globalenv())
  sys.source(file.path(root, "02_Infrastructure/validation/pit_quarantine.R"), envir = pq, keep.source = FALSE)
  qf <- unique(c(RFH_BLOCK_FLAGS, vapply(pq$pitq_load(root), function(x) as.character(x$flag %||% "")[1], character(1))))
  list(pq = pq, qflags = qf[!is.na(qf) & nzchar(qf)], qfac = pq$pitq_factor_ids(root), root = root)
}
.rfh_txt_hits <- function(P, p, check_text = TRUE) {
  if (!isTRUE(check_text) || is.null(p) || length(p) != 1L || is.na(p) || !nzchar(p)) return(character(0))
  if (!grepl("^([A-Za-z]:[/\\\\]|/)", p)) p <- file.path(P$root, p)          # 상대경로 = 루트 기준(cwd 아님)
  if (!file.exists(p)) return(character(0))
  tx <- paste(readLines(p, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  c(P$pq$pitq_source_hits(tx, P$root),
    P$qfac[vapply(P$qfac, function(f) grepl(paste0("\\b", f, "\\b"), tx, perl = TRUE), logical(1))])
}
.rfh_path_key <- function(p, root) {
  p <- .rfh_norm(p); p <- p[!is.na(p)]
  rel <- nzchar(p) & !grepl("^([A-Za-z]:[/\\\\]|/)", p)
  p[rel] <- file.path(root, p[rel])
  if (identical(.Platform$OS.type, "windows")) tolower(p) else p
}
.rfh_ledgers <- function(root, ledger = NULL, layers = c(1L, 2L)) {
  rd <- function(x) if (is.character(x)) jsonlite::fromJSON(x, simplifyVector = FALSE) else x
  if (!is.null(ledger)) return(if (is.character(ledger)) lapply(ledger, rd) else if (!is.null(ledger$entries)) list(ledger) else lapply(ledger, rd))
  ps <- file.path(root, "06_Registry", sprintf("reinforce_ledger_l%d.json", as.integer(layers)))
  lapply(ps[file.exists(ps)], rd)
}

#' 산출물별 PIT 판정 — 원장(기본 L1·L2 운영 파일 · ledger 로 사본 주입)에서 그 산출물을 가리키는 참조 전부를 모은다.
#' @return data.table(artifact, n_refs, c11, flags(격리 밖 표식 · 쉼표), quarantine_flags(걸린 격리 flag), text_hit, skip, skip_reason)
#'   참조 0 인 산출물(원장 밖 — 골든 사본 등)은 표식을 알 수 없다: c11 = FALSE · n_refs = 0 으로 남긴다(원장 writer 가 따로 막는다).
rfh_pit_screen <- function(artifacts, root = NULL, ledger = NULL, layers = c(1L, 2L), check_text = TRUE) {
  root <- rfh_root(root)
  P <- .rfh_pit_ctx(root)
  arts <- unique(.rfh_norm(artifacts))
  keys <- .rfh_path_key(arts, root)
  acc <- stats::setNames(lapply(keys, function(k) list(n = 0L, fl = character(0), tx = character(0))), keys)
  hit <- function(k, fl, txp) {
    if (is.null(acc[[k]])) return(invisible(NULL))
    acc[[k]]$n <<- acc[[k]]$n + 1L
    acc[[k]]$fl <<- unique(c(acc[[k]]$fl, .rfh_flags(fl)))
    acc[[k]]$tx <<- unique(c(acc[[k]]$tx, .rfh_txt_hits(P, as.character(txp %||% NA)[1], check_text)))
  }
  for (L in .rfh_ledgers(root, ledger, layers)) for (e in L$entries %||% list()) {
    ba <- e$base_artifacts
    if (is.character(ba) && length(ba) == 1L && nzchar(ba)) hit(.rfh_path_key(ba, root), e$base_vintage_flags, e$engine_path)
    for (a in e$attempts %||% list()) {
      ar <- a$artifacts
      if (!is.character(ar) || length(ar) != 1L || !nzchar(ar)) next
      hit(.rfh_path_key(ar, root), a$vintage_flags, (a[["essence"]] %||% list())$spec)
    }
  }
  out <- rbindlist(lapply(seq_along(arts), function(i) { x <- acc[[keys[i]]]
    qh <- intersect(x$fl, P$qflags)
    data.table(artifact = arts[i], n_refs = x$n, c11 = length(qh) > 0L,
               flags = paste(setdiff(x$fl[nzchar(x$fl)], P$qflags), collapse = ","),
               quarantine_flags = paste(qh, collapse = ","), text_hit = paste(x$tx, collapse = "|")) }))
  out[, skip := c11 | nzchar(text_hit)]
  out[, skip_reason := fifelse(c11, paste0("pit_c11(PIT-C11-CONVENTIONS ⑧ 비편입 · ", quarantine_flags, ")"),
                        fifelse(nzchar(text_hit), paste0("pit_quarantine_text:", text_hit), ""))]
  attr(out, "quarantine_flags") <- P$qflags
  out[]
}

.rfh_ess_keys <- c(pt = "portfolio_alpha_t_nw_lag3", calmar = "calmar", cagr = "cagr", sr = "net_sharpe",
                   mdd = "mdd", oos = "oos_retention", ir = "net_ir", dsr = "dsr")
.rfh_ess_vec <- function(es) {
  vapply(.rfh_ess_keys, function(k) { v <- suppressWarnings(as.numeric(es[[k]])); if (length(v) == 1L) v else NA_real_ },
         numeric(1))
}

#' 칸 1개 × 규약 1개 재측정.
#' @param artifact_dir 저장 산출물 디렉터리(원본 — 읽기만)
#' @param exec_price "close_d_legacy" | "close_t1" | "open_t1" (명시 필수)
#' @param raw rfh_load_market() 반환값(배치에서 1회 적재해 넘긴다). NULL 이면 여기서 적재.
#' @param out_dir NULL = <artifact>/remeasure_<key>/ · 아니면 <out_dir>/<run_dir>/remeasure_<key>/
#' @param selection_type,n_trials_cumulative NULL = 저장 기록(auth) 승계. ★캐시 대조 대상(R① — 다르면 다시 잰다)
#' @param write FALSE = 파일 쓰기 없음(검사·드라이런) · force TRUE = 기존 재측정 덮어쓰기
#' @param pit rfh_pit_screen() 의 이 산출물 행(배치가 1회 판정해 넘긴다). NULL = 여기서 운영 원장으로 판정. C11·격리 텍스트면 stop.
#' @param n_trials_basis 채점 N 의 근거 문구(호출자 — 예: 드라이버의 D-A 재집계). NULL = 저장 기록/인자 여부로 자동.
#' @return list(auth, bt, sim_diag, out, cached, vs_stored)
rfh_remeasure <- function(artifact_dir, exec_price, raw = NULL, out_dir = NULL, root = NULL,
                          selection_type = NULL, n_trials_cumulative = NULL,
                          write = TRUE, force = FALSE, keep_bt = TRUE, pit = NULL, n_trials_basis = NULL) {
  root <- rfh_root(root)
  rfh_load_deps(root)
  if (missing(exec_price) || is.null(exec_price)) stop("[rfh] exec_price 명시 필수")
  reg <- rfh_regime(exec_price, root)
  inp <- rfh_artifact_inputs(artifact_dir)
  # ★PIT 비편입(결정 ⑧) — 입력 모양과 무관하게 계약이 판정한다(R②). 판정 행이 없으면 운영 원장으로 판정한다.
  if (is.null(pit)) pit <- rfh_pit_screen(inp$dir, root)
  pit <- as.data.table(pit)[tolower(.rfh_norm(artifact)) == tolower(inp$dir)]
  if (nrow(pit) != 1L) stop("[rfh] PIT 판정 행이 이 산출물과 짝지어지지 않는다(판정 없이 재지 않는다): ", inp$dir)
  if (isTRUE(pit$skip)) stop(sprintf("[rfh] PIT 비편입 칸 — %s (결정 PIT-C11-CONVENTIONS ⑧ · 재측정하지 않는다): %s", pit$skip_reason, inp$dir))
  vflags <- if (nzchar(pit$flags)) strsplit(pit$flags, ",", fixed = TRUE)[[1]] else character(0)
  st <- as.character(selection_type %||% inp$stored_selection_type)[1]
  nt <- suppressWarnings(as.integer(n_trials_cumulative %||% inp$stored_n_trials)[1])
  if (!st %in% c("chain", "sweep") || !is.finite(nt) || nt < 1L) stop("[rfh] 시행 회계 불량(selection_type/n_trials)")
  scm <- rfh_scoring_md5(root)
  bt_md5 <- unname(as.character(tools::md5sum(file.path(inp$dir, "bt_result.rds"))))
  od <- .rfh_out_dir(inp, reg$key, out_dir)
  ap <- file.path(od, "authoritative_remeasure.json")
  if (write && !force) {
    cj <- .rfh_cached(ap, reg$key, .rfh_fp_now(raw, root),
                      want = list(selection_type = st, n_trials_cumulative = nt, of_artifact = inp$dir,
                                  stored_bt_md5 = bt_md5, scoring_md5 = scm))
    if (!is.null(cj)) return(list(auth = cj, bt = NULL, out = od, cached = TRUE, vs_stored = cj$remeasure$vs_stored))
  }
  mk <- .rfh_market(raw, root, reg$exec_price)
  if (identical(reg$exec_price, "open_t1") && !all(c("Open", "Close") %in% names(mk$RAW)))
    stop("[rfh] open_t1 은 RAWDATA Open·Close 가 필요하다 — rfh_load_market(exec_prices = 'open_t1')")

  S <- .rfh_subset_raw(mk, inp$H$Ticker, inp$end)
  W <- rfh_restore_weights(inp$H, S$cal, inp$rebal_flag, min(inp$nav_dates))
  res <- .rfh_with_root(root, {
    sim <- NULL
    capture.output(sim <- suppressMessages(.RFH$run_replication_simulation(
      S$RAW, mk$BM, W, commission = inp$commission, start_date = NULL, exec_price = reg$exec_price)))
    # 되살린 리밸은 전부 하네스가 처리해야 한다 — 건너뜀 = 앞 창이 늘거나 구간이 빈다(재측정 거부).
    #   예외 1건: **마지막** 리밸의 보유창이 데이터 끝에서 2거래일 미만이면 하네스가 그 창을 기장하지 않는다
    #   (창 0일 = hold_pool 비어 next · 창 1일 = Return.portfolio 1관측 실패 → .leg_daily NULL → next).
    #   2026-09-24 실측: 20260903_110631_13904 close_t1 — exec 2026-09-01 · 끝 2026-09-02 → 창 1일 미기장
    #   (legacy 창 [09-01, 09-02] = 2일은 처리). 하네스 동작(P0-04 소관)이지 복원 결함이 아니므로 허용하되 JSON 에 남긴다.
    ex_all <- sort(unique(inp$H$Exec)); ex_last <- max(ex_all)
    tail_win <- switch(reg$exec_price, close_t1 = S$cal[S$cal > ex_last], S$cal[S$cal >= ex_last])
    unbooked <- ex_all[!ex_all %in% as.Date(sim$PORTFOLIO_LOG$Exec_Date)]
    tail_ok <- length(unbooked) == 1L && identical(as.numeric(unbooked), as.numeric(ex_last)) && length(tail_win) < 2L
    if (length(unbooked) && !tail_ok)
      stop(sprintf("[rfh] 하네스가 되살린 리밸 %d건 중 %d건만 처리(미기장 %s · 마지막 창 %d일) — 창이 조용히 합쳐진다(재측정 거부)",
                   attr(W, "n_signals"), nrow(sim$PORTFOLIO_LOG), paste(head(format(unbooked), 3), collapse = ","),
                   length(tail_win)))
    s0 <- inp$spec0
    pspec <- list(construction = s0$construction %||% "top_n_long", weighting = s0$weight_method %||% "paper",
                  rebalance = s0$rebalance %||% "monthly")
    sp <- .RFH$.rp_strategy_spec(as.character(s0$strategy_name %||% inp$auth$strategy_name %||% inp$run_dir)[1],
                                 as.character(s0$strategy_idea %||% "")[1], pspec, s0$universe %||% NULL, sim,
                                 as.character(s0$source_paper_url %||% NA)[1], s0$factor_engine_path %||% NA_character_)
    bt <- NULL
    capture.output(bt <- suppressMessages(.RFH$build_bt_result(
      sim, sp, run_id = inp$run_id, strategy_id = inp$strategy_id,
      benchmark_id = "KOSPI200", benchmark_name = "KOSPI 200",
      transaction_cost_bps = inp$tc_bps, slippage_bps = 0, frequency = "daily", annualization_factor = 252,
      universe_id = s0$universe %||% NA_character_, code_version = "run_paper_replication_v10",
      created_by_agent = "Replication")))
    capture.output(bt <- suppressMessages(.RFH$audit_bt_result(bt)))
    es <- NULL
    capture.output(es <- suppressWarnings(suppressMessages(.RFH$essence_score(
      bt, n_trials_cumulative = nt, selection_type = st, sidecar_log = FALSE))))
    list(sim = sim, bt = bt, es = es, tail_win = tail_win, unbooked = unbooked)
  })
  sim <- res$sim; bt <- res$bt; es <- res$es; tail_win <- res$tail_win; unbooked <- res$unbooked

  # 저장본 대조 (같은 규약이면 비트 일치가 양성 대조 · 다르면 규약 효과의 크기)
  pr1 <- as.data.table(bt$period_returns); pr0 <- as.data.table(inp$bt0$period_returns)
  same_days <- identical(as.Date(pr1$date), as.Date(pr0$date))
  jn <- merge(pr1[, .(date, a = ret_net)], pr0[, .(date, b = ret_net)], by = "date")
  vs <- list(same_regime = identical(reg$exec_price, inp$stored_exec_price),
             n_days_stored = nrow(pr0), n_days_new = nrow(pr1), same_days = same_days,
             ret_net_identical = same_days && identical(pr1$ret_net, pr0$ret_net),
             nav_net_identical = identical(bt$nav$nav_net, inp$bt0$nav$nav_net),
             metrics_identical = identical(bt$metrics$metric_value, inp$bt0$metrics$metric_value),
             benchmark_identical = identical(bt$benchmark_returns$benchmark_ret, inp$bt0$benchmark_returns$benchmark_ret),
             max_abs_dret_common_days = if (nrow(jn)) max(abs(jn$a - jn$b)) else NA_real_,
             n_common_days = nrow(jn))
  integrity <- tryCatch(if (nrow(bt$audit[severity == "critical" & status == "FAIL"])) "FAIL" else "OK",
                        error = function(e) "UNKNOWN")
  grade <- as.character(es$grade %||% NA)
  auth <- list(
    status = if (identical(es$metric_type, "backtested") && !identical(integrity, "FAIL")) "OK" else "FAIL",
    kind = "remeasure_from_holdings",
    strategy_id = inp$strategy_id, strategy_name = as.character(inp$auth$strategy_name %||% NA)[1],
    run_id = inp$run_id, remeasured_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    bt_result_path = file.path(od, "bt_result.rds"),
    metric_type = es$metric_type, essence_grade = grade, grade_basis = paste0("remeasure_", st),
    essence = es$essence, hard_fail = es$hard_fail, structural_drawdown = es$structural_drawdown,
    selection_type = es$selection_type, dsr_gate_applied = es$dsr_gate_applied,
    n_trials_cumulative = es$n_trials_cumulative, dsr = es$essence$dsr,
    measurement_regime = list(key = reg$key, regime = reg$key, exec_price = sim$diagnostics$exec_price,
                              exec_price_basis = "argument(rfh_remeasure)",
                              cost_model_version = sim$cost_model_version, harness_md5 = reg$harness_md5,
                              selection_type = st, n_trials_cumulative = nt,
                              n_trials_basis = as.character(n_trials_basis %||% (
                                if (is.null(n_trials_cumulative) && is.null(selection_type))
                                  sprintf("stored_auth(%s/%d — 저장 기록 승계 · P0-01 이전 칸은 러너 하드코딩 chain/1)", st, nt)
                                else "argument"))[1],
                              scoring_md5 = scm,
                              data_vintage = mk$fp, data_end = as.character(inp$end)),
    grade_base = es$grade_base, recent_regime_rescued = es$recent_regime_rescued,
    recent_regime_label = es$recent_regime_label, rolling_grade = es$rolling_grade,
    defensive_score = es$defensive_score, reasons = es$reasons,
    remeasure = list(
      version = RFH_VERSION, of_artifact = inp$dir, of_run_id = inp$run_id,
      method = "holdings_replay — 저장 보유(시그널일 확정 비중) → replication_harness → build_bt_result → audit → essence",
      holdings_source = inp$holdings_source, signal_rule = "exec 직전 거래일(get_execution_date 역상 전수 단정)",
      n_signals_restored = attr(W, "n_signals"), n_rebal_flag_stored = attr(W, "n_rebal_flag"),
      n_rebal_sim = nrow(sim$PORTFOLIO_LOG), commission = inp$commission,
      tail_window_days = length(tail_win),
      tail_rebal_unbooked = if (length(unbooked)) format(unbooked) else NULL,
      stored = list(essence_grade = inp$auth$essence_grade, essence = inp$auth$essence,
                    exec_price = inp$stored_exec_price, exec_price_basis = inp$stored_exec_basis,
                    harness_md5 = inp$stored_harness_md5, selection_type = inp$stored_selection_type,
                    n_trials_cumulative = inp$stored_n_trials),
      stored_bt_md5 = bt_md5,
      contract_md5 = if (nzchar(.RFH_SELF) && file.exists(.RFH_SELF)) unname(as.character(tools::md5sum(.RFH_SELF))) else NA_character_,
      # 선정 단계 빈티지 표식(격리 밖 — fdb_* 등) 승계: 재측정은 보유(선정)를 고정하므로 선정 결함을 고치지 못한다(R②)
      vintage_flags = if (length(vflags)) as.list(vflags) else list(),
      pit_screen = list(n_ledger_refs = as.integer(pit$n_refs), c11 = isTRUE(pit$c11), text_hit = as.character(pit$text_hit)),
      vs_stored = vs),
    replication = list(n_max = sim$diagnostics$n_max, has_short = sim$diagnostics$has_short),
    contract = list(integrity_status = integrity, cagr = es$essence$cagr, sharpe = es$essence$net_sharpe,
                    mdd = es$essence$mdd, calmar = es$essence$calmar))
  if (write) {
    dir.create(od, recursive = TRUE, showWarnings = FALSE)
    # 완료 표식(JSON)을 먼저 지운다 — 아래 쓰기가 중간에 죽으면 옛 표식이 새 CSV 와 짝지어지지 않게(재개는 표식 없음 = 다시 잰다)
    if (file.exists(ap) && !isTRUE(unlink(ap) == 0L && !file.exists(ap)))
      stop("[rfh] 기존 완료 표식을 지우지 못했다 — 반쯤 쓴 판을 만들지 않는다: ", ap)
    if (identical(.Platform$OS.type, "windows") && nchar(file.path(od, "05_benchmark_returns.csv")) > 259L)
      stop(sprintf("[rfh] 경로 길이 > 259 (Windows MAX_PATH) — out_dir 를 짧게: %s", od))
    # 계약 산출 CSV/JSON(정본 writer save_bt_result — run_paper_replication 과 같은 파일 모양). 적대검증이 형제 판에서
    #   03_period_returns·04_holdings 를 읽는다(통합 검증 I2 — 구판은 두 파일이 없어 rebase 칸 해석이 옛 산출물로 갔다).
    capture.output(suppressMessages(.RFH$save_bt_result(bt, od, save_xlsx = FALSE)))
    need_csv <- file.path(od, c("bt_result.rds", "01_strategy_spec.json", "03_period_returns.csv", "04_holdings.csv"))
    if (!all(file.exists(need_csv))) stop(sprintf("[rfh] 형제 판 산출 파일 누락: %s", paste(basename(need_csv[!file.exists(need_csv)]), collapse = ",")))
    .rfh_atomic_write(ap, function(p) jsonlite::write_json(auth, p, auto_unbox = TRUE, pretty = TRUE,
                                                           digits = NA, na = "null", null = "null"))
  }
  list(auth = auth, bt = if (keep_bt) bt else NULL, sim_diag = sim$diagnostics, out = od, cached = FALSE, vs_stored = vs)
}

#' 저장값(① 판) — authoritative_remeasure.json 그대로
rfh_stored <- function(artifact_dir) {
  a <- jsonlite::fromJSON(file.path(.rfh_norm(artifact_dir), "authoritative_remeasure.json"), simplifyVector = TRUE)
  list(grade = as.character(a$essence_grade %||% NA)[1], essence = .rfh_ess_vec(a$essence %||% list()),
       exec_price = as.character(a$measurement_regime$exec_price %||% "close_d_legacy")[1],
       status = as.character(a$status %||% NA)[1])
}

#' 칸 1개의 3판 — 저장 / legacy@현 / close_t1@현 (exec_prices 로 바꿀 수 있다). 반환 = 1행 data.table.
rfh_triad <- function(artifact_dir, raw, exec_prices = c("close_d_legacy", "close_t1"), out_dir = NULL,
                      root = NULL, write = TRUE, force = FALSE, pit = NULL, ...) {
  s <- rfh_stored(artifact_dir)
  row <- list(artifact = .rfh_norm(artifact_dir), run_dir = basename(.rfh_norm(artifact_dir)),
              st_grade = s$grade, st_exec = s$exec_price)
  for (k in names(s$essence)) row[[paste0("st_", k)]] <- unname(s$essence[[k]])
  if (is.null(pit)) pit <- rfh_pit_screen(artifact_dir, root)          # 규약마다 원장을 다시 읽지 않게 1회
  for (ep in exec_prices) {
    tg <- .RFH_EP_TAG[[ep]]
    r <- rfh_remeasure(artifact_dir, ep, raw = raw, out_dir = out_dir, root = root, write = write,
                       force = force, keep_bt = FALSE, pit = pit, ...)
    v <- .rfh_ess_vec(r$auth$essence)
    row[[paste0(tg, "_grade")]] <- as.character(r$auth$essence_grade %||% NA)[1]
    for (k in names(v)) row[[paste0(tg, "_", k)]] <- unname(v[[k]])
    row[[paste0(tg, "_status")]] <- as.character(r$auth$status %||% NA)[1]
    row[[paste0(tg, "_cached")]] <- isTRUE(r$cached)
    # 빈티지 효과의 출처를 가른다 — 전략 수익(보유 종목 Ret) 쪽 / 벤치 쪽. 전부 같아야 비트 일치다.
    #   (2026-09-24 30칸 실측: 전략 수익은 같은데 벤치만 바뀌어 PORT_t 가 0.006 움직인 칸이 있다 — 벤치 축 이관·복원)
    row[[paste0(tg, "_ret_identical")]] <- isTRUE(r$vs_stored$ret_net_identical) && isTRUE(r$vs_stored$nav_net_identical)
    row[[paste0(tg, "_bench_identical")]] <- isTRUE(r$vs_stored$benchmark_identical)
    row[[paste0(tg, "_bit_identical")]] <- row[[paste0(tg, "_ret_identical")]] && row[[paste0(tg, "_bench_identical")]] &&
      isTRUE(r$vs_stored$metrics_identical)
    row[[paste0(tg, "_max_abs_dret")]] <- as.numeric(r$vs_stored$max_abs_dret_common_days %||% NA)[1]
    row[[paste0(tg, "_key")]] <- as.character(r$auth$measurement_regime$key %||% NA)[1]
  }
  if (all(c("close_d_legacy", "close_t1") %in% exec_prices))
    for (k in c("pt", "calmar", "cagr", "sr", "mdd", "oos")) {
      row[[paste0("d_vint_", k)]] <- row[[paste0("leg_", k)]] - row[[paste0("st_", k)]]   # ②−① 빈티지(+채점 코드)
      row[[paste0("d_conv_", k)]] <- row[[paste0("t1_", k)]] - row[[paste0("leg_", k)]]   # ③−② 집행 규약
    }
  as.data.table(row)
}

# ── 1단계 대상 선정 (원장 재도출 — 목록만 · 실행 안 함) ─────────────────────────
.rfh_attempt_fail_count <- function(es, gp) {
  v <- function(k) suppressWarnings(as.numeric(es[[k]] %||% NA)[1])
  chk <- c(pt = v("port_t") >= gp$port_t_min, calmar = v("calmar") >= gp$calmar_min,
           sr = v("net_sharpe") >= gp$sharpe_min, cagr = v("cagr") >= gp$cagr_min,
           oos = v("oos_retention") >= gp$oos_min)
  if (identical(as.character(es$selection_type %||% "")[1], "sweep")) chk <- c(chk, dsr = v("dsr") >= gp$dsr_min)
  chk[is.na(chk)] <- FALSE            # 결측 = 미충족(보수 — 근접 판정을 부풀리지 않는다)
  sum(!chk)
}

.rfh_flags <- function(x) {
  fl <- x %||% list()
  unique(vapply(fl, function(z) as.character(z$flag %||% "")[1], character(1)))
}

#' 1단계 대상 목록 — near-A · 계보(entry) 최고 · 활성 바닥 · 승격 바닥 · carry · entry 기저.
#'   원장은 읽기만. 반환 = data.table(artifact, reasons, base_ids, codes, n_refs, port_t, calmar, grade,
#'   vintage_flags, skip, skip_reason). skip = C11 표식(원장 vintage_flags·base_vintage_flags 의 격리 flag) ·
#'   spec/엔진 텍스트가 격리 원천·팩터를 참조 · 산출물 불완전. 같은 산출물을 여럿이 가리키면 하나로 합치고,
#'   하나라도 격리면 skip(측정 자체가 오염이다).
#' @param near_a_max_failed NULL = constraint_defaults.json::remeasure.stage1_near_a_max_failed
rfh_select_stage1 <- function(layer = 1L, root = NULL, ledger = NULL, near_a_max_failed = NULL,
                              check_text = TRUE) {
  root <- rfh_root(root)
  rfh_load_deps(root)
  k <- near_a_max_failed %||% rfh_config(root, need = "stage1_near_a_max_failed")$stage1_near_a_max_failed
  k <- as.integer(k)[1]
  L <- if (is.null(ledger)) jsonlite::fromJSON(file.path(root, "06_Registry", sprintf("reinforce_ledger_l%d.json", as.integer(layer))),
                                               simplifyVector = FALSE)
       else if (is.character(ledger)) jsonlite::fromJSON(ledger, simplifyVector = FALSE) else ledger
  gp <- .rfh_with_root(root, .RFH$.graduation_params(refresh = TRUE, root = root))
  pq <- new.env(parent = globalenv())
  sys.source(file.path(root, "02_Infrastructure/validation/pit_quarantine.R"), envir = pq, keep.source = FALSE)
  qflags <- unique(vapply(pq$pitq_load(root), function(x) as.character(x$flag %||% "")[1], character(1)))
  qflags <- qflags[nzchar(qflags)]
  qfac <- pq$pitq_factor_ids(root)
  .txt_hits <- function(p) {
    if (!isTRUE(check_text) || is.null(p) || is.na(p) || !nzchar(p) || !file.exists(p)) return(character(0))
    tx <- paste(readLines(p, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
    c(pq$pitq_source_hits(tx, root),
      qfac[vapply(qfac, function(f) grepl(paste0("\\b", f, "\\b"), tx, perl = TRUE), logical(1))])
  }
  E <- L$entries %||% list()
  byid <- stats::setNames(E, vapply(E, function(e) as.character(e$base_id %||% "")[1], character(1)))
  rows <- list()
  add <- function(art, e, a, reason) {
    es <- if (is.null(a)) list() else (a$essence %||% list())
    fl <- if (is.null(a)) .rfh_flags(e$base_vintage_flags) else .rfh_flags(a$vintage_flags)
    tx <- if (is.null(a)) .txt_hits(as.character(e$engine_path %||% NA)[1]) else .txt_hits(as.character(es$spec %||% NA)[1])
    rows[[length(rows) + 1L]] <<- data.table(
      artifact = .rfh_norm(art), base_id = as.character(e$base_id)[1],
      n = if (is.null(a)) NA_integer_ else as.integer(a$n %||% NA)[1],
      code = if (is.null(a)) "base" else as.character(es$cell_code %||% a$cell_code %||% paste0("n", a$n))[1],
      grade = if (is.null(a)) as.character(e$base_grade %||% NA)[1] else as.character(a$grade %||% NA)[1],
      port_t = suppressWarnings(as.numeric(es$port_t %||% NA)[1]),
      calmar = suppressWarnings(as.numeric(es$calmar %||% NA)[1]),
      reason = reason, flags = paste(fl, collapse = ","),
      c11 = any(fl %in% qflags), text_hit = paste(unique(tx), collapse = "|"))
  }
  .measured <- function(e) Filter(function(a) {
    v <- a$essence$port_t
    is.numeric(v) && length(v) == 1L && is.finite(v) && nzchar(as.character(a$artifacts %||% "")[1])
  }, e$attempts %||% list())
  .pick_max <- function(as) if (length(as)) as[[which.max(vapply(as, function(a) a$essence$port_t, numeric(1)))]] else NULL
  .adv_ok <- function(a) { v <- as.character((a$adversary %||% list())$verdict %||% "")[1]; is.na(v) || !nzchar(v) || identical(v, "pass") }
  for (e in E) {
    if (nzchar(as.character(e$base_artifacts %||% "")[1])) add(e$base_artifacts, e, NULL, "base")
    ms <- .measured(e)
    b <- .pick_max(ms); if (!is.null(b)) add(b$artifacts, e, b, "lineage_best")
    for (a in ms) if (.rfh_attempt_fail_count(a$essence, gp) <= k) add(a$artifacts, e, a, "near_a")
    if (identical(as.character(e$status %||% "")[1], "active")) {
      f <- .pick_max(Filter(.adv_ok, ms)); if (!is.null(f)) add(f$artifacts, e, f, "floor_active")
    }
    pid <- as.character(e$parent$base_id %||% "")[1]
    if (nzchar(pid) && !is.null(byid[[pid]])) {
      pms <- .measured(byid[[pid]])
      csp <- .rfh_norm(as.character(e$carry$source_spec %||% "")[1])
      for (a in pms) {
        if (nzchar(csp) && identical(.rfh_norm(as.character(a$essence$spec %||% "")[1]), csp)) add(a$artifacts, byid[[pid]], a, "carry")
        if (identical(as.character(a$essence$cell_code %||% "")[1], as.character(e$parent$cell %||% "")[1]) &&
            isTRUE(abs(a$essence$port_t - suppressWarnings(as.numeric(e$parent$best_port_t %||% NA))) < 5e-4))
          add(a$artifacts, byid[[pid]], a, "floor_promotion")
      }
    }
  }
  if (!length(rows)) return(data.table())
  R <- rbindlist(rows)
  R[, complete := file.exists(file.path(artifact, "bt_result.rds")) & file.exists(file.path(artifact, "authoritative_remeasure.json"))]
  out <- R[, .(reasons = paste(unique(reason), collapse = "+"), base_ids = paste(unique(base_id), collapse = ";"),
               codes = paste(unique(code), collapse = ";"), n_refs = .N,
               port_t = suppressWarnings(max(port_t, na.rm = TRUE)), calmar = suppressWarnings(max(calmar, na.rm = TRUE)),
               grade = paste(unique(na.omit(grade)), collapse = ";"),
               vintage_flags = paste(setdiff(unique(unlist(strsplit(flags[nzchar(flags)], ","))), qflags), collapse = ","),
               c11 = any(c11), text_hit = paste(unique(text_hit[nzchar(text_hit)]), collapse = "|"),
               complete = all(complete)), by = artifact]
  out[!is.finite(port_t), port_t := NA_real_]; out[!is.finite(calmar), calmar := NA_real_]
  out[, skip := c11 | nzchar(text_hit) | !complete]
  out[, skip_reason := fifelse(c11, "pit_c11(PIT-C11-CONVENTIONS ⑧ 비편입)",
                        fifelse(nzchar(text_hit), paste0("pit_quarantine_text:", text_hit),
                        fifelse(!complete, "artifact_incomplete", "")))]
  setorder(out, skip, -port_t, na.last = TRUE)
  attr(out, "near_a_max_failed") <- k
  attr(out, "quarantine_flags") <- qflags
  out[]
}

# ── 배치 (claim · 배리어 · 병렬 · 재개) ───────────────────────────────────────
.rfh_claim_path <- function(root, claim = NULL) {
  claim %||% { e <- Sys.getenv("QVEST_RF_CLAIM", ""); if (nzchar(e)) e else file.path(root, ".cache", "reinforce_auto.claim") }
}
.rfh_claim_owned <- function(claim, pid) {
  o <- tryCatch(jsonlite::fromJSON(file.path(claim, "owner.json"), simplifyVector = TRUE), error = function(e) NULL)
  !is.null(o) && identical(as.integer(o$pid %||% NA), as.integer(pid)) && !file.exists(file.path(claim, "released.json"))
}
# 하트비트 — 새 디렉터리 항목 생성(rename)이 claim 디렉터리 mtime 을 갱신한다. 러너의 시간 폴백(stale_hours ·
#   rf_claim.R 나이 = 디렉터리 mtime)이 살아 있는 긴 배치를 뺏지 않게 칸마다 부른다.
.rfh_claim_heartbeat <- function(claim) {
  tmp <- file.path(claim, sprintf("hb_%d.tmp", Sys.getpid()))
  tryCatch({
    writeLines(format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), tmp)
    hb <- file.path(claim, "heartbeat.txt"); if (file.exists(hb)) unlink(hb)
    file.rename(tmp, hb)
  }, error = function(e) FALSE)
}

# 칸 과제 1개 — it = list(artifact, pit(판정 1행), selection_type, n_trials_cumulative, n_trials_basis) (채점 인자 NULL = 저장 기록)
.rfh_task <- function(it, exec_prices, out_dir, force, root, claim, owner_pid, mk = NULL) {
  a <- it$artifact
  mk <- mk %||% get0(".RFH_MARKET", envir = globalenv(), inherits = FALSE)
  if (!is.null(claim) && !.rfh_claim_owned(claim, owner_pid))
    return(list(artifact = a, status = "claim_lost", error = "러너 claim 소유권 상실 — 재개 대상"))
  t0 <- Sys.time()
  r <- tryCatch(rfh_triad(a, raw = mk, exec_prices = exec_prices, out_dir = out_dir, root = root,
                          write = TRUE, force = force, pit = it$pit, selection_type = it$selection_type,
                          n_trials_cumulative = it$n_trials_cumulative, n_trials_basis = it$n_trials_basis),
                error = function(e) structure(list(msg = conditionMessage(e)), class = "rfh_err"))
  if (!is.null(claim)) .rfh_claim_heartbeat(claim)
  if (inherits(r, "rfh_err")) return(list(artifact = a, status = "failed", error = r$msg))
  cached <- all(unlist(r[, grep("_cached$", names(r)), with = FALSE]))
  list(artifact = a, status = if (cached) "cached" else "done", row = r,
       secs = round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1))
}

#' 배치 재측정.
#' @param artifacts 문자 벡터 또는 data.frame(artifact [, skip, skip_reason, selection_type, n_trials_cumulative, n_trials_basis,
#'   reasons, base_ids, codes, vintage_flags]) — rfh_select_stage1() 반환 포함. 채점 열이 있으면 칸별로 그 인자로 채점한다
#'   (NA = 저장 기록). ★PIT 판정은 입력과 무관하게 여기서 다시 한다(rfh_pit_screen · 호출자 skip=FALSE 가 판정을 끄지 못한다 · R②).
#' @param out_dir 쓰기 루트. NULL 이면 in_place=TRUE 가 있어야 산출물 안에 쓴다(운영 쓰기 = 별도 승인)
#' @param n_workers NULL = constraint_defaults.json::remeasure.batch_n_workers · 1 = 이 프로세스에서
#' @param claim NULL = 러너 claim(QVEST_RF_CLAIM · <root>/.cache/reinforce_auto.claim) · FALSE = claim 없이(검사 전용)
#' @param barrier TRUE = refresh_barrier 판정(잠금 중 대기 → 만료 시 미측정 종료)
#' @param ledger PIT 판정에 쓸 원장(경로·객체 · 검사가 사본을 주입) — NULL = 운영 L1·L2
#' @return list(status, manifest, rows, skipped, failed)
rfh_batch <- function(artifacts, exec_prices = c("close_d_legacy", "close_t1"), out_dir = NULL, in_place = FALSE,
                      n_workers = NULL, claim = NULL, force = FALSE, root = NULL, barrier = TRUE,
                      barrier_wait_s = NULL, manifest_path = NULL, raw_path = NULL, bm_path = NULL,
                      stale_hours = NULL, ledger = NULL) {
  root <- rfh_root(root)
  rfh_load_deps(root)
  started <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  if (is.null(out_dir) && !isTRUE(in_place))
    stop("[rfh] out_dir 가 없으면 in_place=TRUE 명시가 필요하다 — 운영 stage_artifacts 쓰기는 별도 승인")
  for (ep in exec_prices) rfh_regime(ep, root)                       # 규약 검증(허용 밖이면 여기서 멈춘다)
  sel <- if (is.data.frame(artifacts)) as.data.table(artifacts) else data.table(artifact = .rfh_norm(artifacts), skip = FALSE, skip_reason = "")
  if (!"skip" %in% names(sel)) sel[, skip := FALSE]
  if (!"skip_reason" %in% names(sel)) sel[, skip_reason := ""]
  for (cc in c("selection_type", "n_trials_basis")) if (!cc %in% names(sel)) sel[, (cc) := NA_character_]
  if (!"n_trials_cumulative" %in% names(sel)) sel[, n_trials_cumulative := NA_integer_]
  sel[, artifact := .rfh_norm(artifact)]
  sel <- unique(sel, by = "artifact")
  # ★PIT 자기 판정(R②) — 호출자 skip 과 OR(판정이 skip 을 해제하지 않는다 · 호출자 skip 도 존중)
  pit <- rfh_pit_screen(sel$artifact, root, ledger = ledger)
  sel <- merge(sel, pit[, .(artifact, pit_skip = skip, pit_reason = skip_reason, pit_flags = flags)], by = "artifact",
               all.x = TRUE, sort = FALSE)
  if (anyNA(sel$pit_skip)) stop("[rfh] PIT 판정이 빠진 산출물이 있다 — 판정 없이 재지 않는다")
  sel[pit_skip == TRUE & !skip, `:=`(skip = TRUE, skip_reason = pit_reason)]
  if (!"vintage_flags" %in% names(sel)) sel[, vintage_flags := pit_flags]
  sel[!skip & !(file.exists(file.path(artifact, "bt_result.rds")) & file.exists(file.path(artifact, "authoritative_remeasure.json"))),
      `:=`(skip = TRUE, skip_reason = "artifact_incomplete")]
  skipped <- sel[skip == TRUE, .(artifact, reason = skip_reason)]
  todo <- sel[skip == FALSE]$artifact
  .na_null <- function(v) if (length(v) != 1L || is.na(v) || (is.character(v) && !nzchar(v))) NULL else v
  tasks <- lapply(todo, function(a) { r <- sel[artifact == a][1]
    list(artifact = a, pit = pit[artifact == a], selection_type = .na_null(as.character(r$selection_type)),
         n_trials_cumulative = .na_null(suppressWarnings(as.integer(r$n_trials_cumulative))),
         n_trials_basis = .na_null(as.character(r$n_trials_basis))) })
  mdir <- if (!is.null(out_dir)) .rfh_norm(out_dir) else file.path(root, ".cache", "remeasure")
  manifest_path <- manifest_path %||% file.path(mdir, sprintf("rfh_batch_%s_%d.json", format(Sys.time(), "%Y%m%d_%H%M%S"), Sys.getpid()))
  regimes <- lapply(stats::setNames(exec_prices, exec_prices), function(ep) rfh_regime(ep, root))
  man <- list(schema = "rfh_batch_v1", version = RFH_VERSION, started_at = started, root = root,
              out_dir = out_dir %||% "(in_place)", exec_prices = exec_prices, regimes = regimes,
              n_input = nrow(sel), n_todo = length(todo), force = force)
  .finish <- function(status, rows = list(), failed = list(), extra = list()) {
    man$status <- status; man$finished_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
    man$skipped <- skipped; man$failed <- failed
    rt <- rbindlist(lapply(rows, function(x) x$row), fill = TRUE)
    # 선정 메타(사유·원장 참조·빈티지 표식) 승계 — 재측정은 선정 단계 빈티지 결함(fdb_* 표식)을 고치지 않으므로
    #   그 표식이 결과 행을 따라가야 한다(rfh_select_stage1 의 vintage_flags 열).
    meta <- intersect(c("reasons", "base_ids", "codes", "vintage_flags"), names(sel))
    if (nrow(rt) && length(meta)) rt <- merge(rt, sel[, c("artifact", meta), with = FALSE], by = "artifact", all.x = TRUE, sort = FALSE)
    man$n_done <- sum(vapply(rows, function(x) identical(x$status, "done"), logical(1)))
    man$n_cached <- sum(vapply(rows, function(x) identical(x$status, "cached"), logical(1)))
    man$n_failed <- length(failed); man$n_skipped <- nrow(skipped)
    man <- utils::modifyList(man, extra)
    man$rows <- rt
    dir.create(dirname(manifest_path), recursive = TRUE, showWarnings = FALSE)
    .rfh_atomic_write(manifest_path, function(p) jsonlite::write_json(man, p, auto_unbox = TRUE, pretty = TRUE,
                                                                      digits = NA, na = "null", null = "null"))
    if (nrow(rt)) .rfh_atomic_write(sub("\\.json$", ".csv", manifest_path), function(p) fwrite(rt, p))
    list(status = status, manifest = manifest_path, rows = rt, skipped = skipped, failed = failed)
  }

  # ── claim (러너와 같은 mutex) ──
  use_claim <- !identical(claim, FALSE)
  cpath <- if (use_claim) .rfh_claim_path(root, if (is.character(claim)) claim else NULL) else NULL
  if (use_claim) {
    cl_env <- new.env(parent = globalenv())
    sys.source(file.path(root, "02_Infrastructure/ops/rf_claim.R"), envir = cl_env, keep.source = FALSE)
    sh <- stale_hours %||% {
      cf <- tryCatch(jsonlite::fromJSON(file.path(root, "06_Registry/reinforce_auto_config.json"), simplifyVector = TRUE),
                     error = function(e) list())
      as.numeric(cf$claim_stale_hours %||% NA)
    }
    if (!is.finite(sh)) stop("[rfh] claim_stale_hours 를 읽지 못했다(reinforce_auto_config.json) — stale_hours 인자로 명시")
    dir.create(dirname(cpath), recursive = TRUE, showWarnings = FALSE)
    ac <- cl_env$rf_claim_acquire(cpath, stale_hours = sh)
    if (!isTRUE(ac$ok)) return(.finish("claimed", extra = list(claim = list(path = cpath, acquired = FALSE, reason = ac$reason,
                                                                             owner_pid = ac$owner_pid %||% NA))))
    on.exit(cl_env$rf_claim_release(cpath), add = TRUE)
    man$claim <- list(path = cpath, acquired = TRUE, note = ac$note %||% "", stale_hours = sh)
  } else man$claim <- list(path = NULL, acquired = FALSE, note = "claim=FALSE(검사 전용)")

  # ── 리프레시 배리어 (적재 전 대기 · 적재 후 재판정) ──
  rb <- NULL
  if (isTRUE(barrier)) {
    rb <- new.env(parent = globalenv())
    sys.source(file.path(root, "02_Infrastructure/ops/refresh_barrier.R"), envir = rb, keep.source = FALSE)
    w <- rb$rb_wait(barrier_wait_s %||% rb$rb_cell_wait_s(), root = root)
    man$barrier <- list(pre = rb$rb_fields(w$status), waited_s = w$waited_s)
    if (!isTRUE(w$proceed)) return(.finish("deferred_refresh_lock"))
  }
  if (!length(todo)) return(.finish("empty"))

  nw <- as.integer(n_workers %||% rfh_config(root, need = "batch_n_workers")$batch_n_workers)[1]
  nw <- max(1L, min(nw, length(todo)))
  me <- Sys.getpid()
  if (nw <= 1L) {
    mk <- rfh_load_market(root, exec_prices, raw_path, bm_path)
    man$market <- mk$fp
    if (!is.null(rb) && isTRUE(rb$rb_status(root)$blocking)) return(.finish("deferred_refresh_lock"))
    res <- lapply(tasks, function(it) .rfh_task(it, exec_prices, out_dir, force, root, cpath, me, mk = mk))
  } else {
    src <- file.path(root, "02_Infrastructure/contracts/remeasure_from_holdings.R")
    if (nzchar(.RFH_SELF) && file.exists(.RFH_SELF)) src <- .RFH_SELF
    cl <- parallel::makePSOCKcluster(nw)
    on.exit(parallel::stopCluster(cl), add = TRUE)
    lf <- function(src, root, eps, rp, bp) {
      options(rfh.verbose = FALSE)
      source(src, encoding = "UTF-8")
      assign(".RFH_MARKET", rfh_load_market(root, eps, rp, bp), envir = globalenv())
      get(".RFH_MARKET", envir = globalenv())$fp
    }
    environment(lf) <- globalenv()
    fps <- parallel::clusterCall(cl, lf, src, root, exec_prices, raw_path, bm_path)
    if (length(unique(lapply(fps, function(f) f[c("raw", "bm", "raw_nrow", "raw_max_date")]))) != 1L)
      return(.finish("aborted_vintage_split", extra = list(market = fps)))
    man$market <- fps[[1]]
    if (!is.null(rb) && isTRUE(rb$rb_status(root)$blocking)) return(.finish("deferred_refresh_lock"))
    wf <- function(it, eps, od, fo, rt, cp, op) .rfh_task(it, eps, od, fo, rt, cp, op)
    environment(wf) <- globalenv()                   # 배치 프레임(클러스터 객체 등)을 칸마다 직렬화하지 않게
    res <- parallel::parLapplyLB(cl, tasks, wf, exec_prices, out_dir, force, root, cpath, me)
  }
  ok <- Filter(function(x) x$status %in% c("done", "cached"), res)
  bad <- Filter(function(x) !x$status %in% c("done", "cached"), res)
  failed <- lapply(bad, function(x) list(artifact = x$artifact, status = x$status, error = x$error))
  st <- if (any(vapply(bad, function(x) identical(x$status, "claim_lost"), logical(1)))) "claim_lost"
        else if (length(bad)) "done_with_failures" else "done"
  .finish(st, rows = ok, failed = failed)
}

if (sys.nframe() == 0L || isTRUE(getOption("rfh.verbose", TRUE)))
  cat("[remeasure_from_holdings.R] Loaded (P0-05) — rfh_remeasure / rfh_triad / rfh_select_stage1 / rfh_batch\n")
