# test_remeasure_from_holdings.R — 보유 기반 재측정 계약 검사 (2026-09-24 · 플랜 P0-05)
#   대상 = 02_Infrastructure/contracts/remeasure_from_holdings.R
#
# A 설정·regime   : remeasure 블록 fail-closed(블록·키 부재 → stop) · regime 키 결정론·하네스 md5 민감 · exec_price 명시 강제
# B 복원 단위     : 합성 달력 — 시그널 = exec 직전 거래일 · get_execution_date 역상 · 위반 주입(보유 1개월 누락 · 중복 ·
#                   비유한 · 월 첫 거래일 아닌 exec · close_t1 첫 집행일 1건 허용/2건 거부)
# C 골든 양성 대조 : stage_artifacts/replication/20260921_100007_6876
#                   legacy@현 빈티지 = 저장 bt_result 비트 일치(ret_net·nav·metrics·benchmark) + essence = 저장 auth(3자리)
#                   close_t1 = B · PT 3.777 · Calmar .433 (P0-04 골든 close_t1 판 — test_replication_exec_golden.R 머리 실측)
#                   쓰기 = out_dir 아래 2디렉터리뿐(계약 산출 CSV·스펙·bt·JSON) · 원본 md5 불변 · 재개(cached)·force·빈티지 불일치 재측정
#                   위반 주입: 골든 사본 보유 1개월 삭제 → stop · 돌연변이 M1(달력 대조 제거 → 조용히 통과) ·
#                   M2(END 절단 제거 → 비트 일치 깨짐 = 양성 대조가 잡는다)
# D B6 interval   : 20260921_155730_10736 (B6_34 interval k=3) — 되살린 시그널 = 저장 리밸 표식 = 하네스 리밸(87) · 간격 3개월
#   + 마지막 창 1일(20260903_110631_13904 close_t1 — 하네스 미기장 허용·JSON 기록) · 중간 창 미기장(합성) → stop
# E 1단계 선정    : 합성 원장 — base·lineage_best·near_a(k)·floor_active(적대검증 fail 제외)·carry·floor_promotion ·
#                   C11 표식 skip(attempt·base) · 격리 팩터 텍스트 skip · 불완전 skip · 중복 합침 · 돌연변이 M3(C11 무시 → red)
# F 배치          : in_place 가드 · claim 점유 → claimed(쓰기 0) · 배리어 held → deferred(쓰기 0 · claim 해제) · skip 목록 통과 ·
#                   PSOCK 2워커 경로(시장 1회 적재 · 캐시 재개) · 하트비트가 claim mtime 갱신 · 소유권 상실 → claim_lost
# ★2026-09-24 수리(적대검증 R①·R② · 통합 검증 L-B1·I2):
# C6 재개 캐시 = 채점 인자까지 대조 — (sweep, 500) 호출은 (chain, 1) 캐시를 받지 않는다 · 같은 인자 재호출 = 캐시 · 채점 지문 불일치 = 불채택 ·
#    돌연변이 M4(구 캐시 판독기 — 채점 인자 무시) → red
# C3 형제 판 = 계약 산출 CSV(03·04 — 적대검증 입력)·01_strategy_spec.json + JSON measurement_regime$regime = 키(원장 writer 계약)
# G PIT 자기 판정 — 합성 원장(골든 사본 2개: pit_c11 표식 · fdb 표식): 문자 벡터 입력 배치도 C11 칸 skip · 직접 호출 stop ·
#    fdb 표식은 재측정 JSON remeasure$vintage_flags 로 승계 · 돌연변이 M5(자기 판정 제거 = 구판) → C11 칸이 skip 에서 빠진다(red)
#
# 쓰기 0 (운영) — 산출은 전부 tempdir 아래. 운영 원장·stage_artifacts·.cache 에 쓰지 않는다(원장은 E 에서 읽지 않는다 —
#   합성 원장만. 운영 원장 판독은 INFO 1줄). 재료 부재(골든·RAWDATA 캐시) = 해당 절 SKIP(미측정 — PASS 아님).
# 소요 ≈ 4~5분 (골든 3판 ≈ 80초 · M2 ≈ 40초 · B6 ≈ 30초 · PSOCK 워커 적재).
# 실행: Rscript 08_Tests/contracts/test_remeasure_from_holdings.R

.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else "."
}, error = function(e) ".")
# 정규화 함수 금지(한글 경로 — 프로젝트 규약) — 절대화 후 접미 경로를 떼어 루트를 얻는다
.sa <- gsub("\\\\", "/", .self); if (!grepl("^([A-Za-z]:)?/", .sa)) .sa <- file.path(gsub("\\\\", "/", getwd()), .sa)
root <- sub("/08_Tests/contracts/?$", "", sub("/\\.$", "", .sa))
if (!file.exists(file.path(root, "02_Infrastructure", "config.R")))
  root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(root)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

pass <- 0L; fail <- 0L; skipped <- 0L
ok <- function(m) { cat(sprintf("  [PASS] %s\n", m)); pass <<- pass + 1L }
ng <- function(m) { cat(sprintf("  [FAIL] %s\n", m)); fail <<- fail + 1L }
sk <- function(m) { cat(sprintf("  [SKIP] %s\n", m)); skipped <<- skipped + 1L }
chk <- function(cond, m_ok, m_ng = m_ok) if (isTRUE(cond)) ok(m_ok) else ng(m_ng)
errmsg <- function(expr) tryCatch({ force(expr); "" }, error = function(e) conditionMessage(e))
finish <- function() {
  cat(sprintf("결과: PASS=%d FAIL=%d SKIP=%d\n", pass, fail, skipped))
  cat(sprintf('{"test":"remeasure_from_holdings","pass":%d,"fail":%d,"total":%d,"skipped":%d}\n', pass, fail, pass + fail, skipped))
  unlink(TMP, recursive = TRUE)
  if (fail > 0L) quit(status = 1L)
  quit(status = 0L)
}
# 돌연변이 — 함수 본문 문자열 치환(같은 환경). 패턴이 없으면 검사 자체가 낡은 것 → FAIL 로 드러낸다.
mutant <- function(f, pattern, replacement) {
  src <- paste(deparse(f, width.cutoff = 500L), collapse = "\n")
  if (!grepl(pattern, src, fixed = TRUE)) return(NULL)
  g <- eval(parse(text = sub(pattern, replacement, src, fixed = TRUE), encoding = "UTF-8"))
  environment(g) <- environment(f); g
}

# ★짧은 이름 — Windows MAX_PATH(260): <TMP>/o/<run_dir>/remeasure_<키>/bt_result.rds.tmp 가 TMPDIR 이 길면 넘는다
#   (2026-09-24 실측: 긴 scratch TMPDIR 아래 rfh_t_* 로 gzfile 열기 실패). 계약은 넘으면 명시 오류로 멈춘다.
TMP <- gsub("\\\\", "/", tempfile("rt"))
dir.create(TMP, recursive = TRUE)
options(rfh.verbose = FALSE)
source(file.path(root, "02_Infrastructure/contracts/remeasure_from_holdings.R"), encoding = "UTF-8")
rfh_load_deps(root)
qd <- function(expr) { out <- NULL; capture.output(out <- suppressWarnings(suppressMessages(expr))); out }

# ── A 설정·regime ────────────────────────────────────────────────────────────
cat("[A] 설정·regime\n")
cfg <- rfh_config(root, need = c("stage1_near_a_max_failed", "batch_n_workers"))
chk(is.numeric(cfg$stage1_near_a_max_failed) && is.numeric(cfg$batch_n_workers),
    sprintf("A1 remeasure 블록 판독: near_a_max_failed=%s · n_workers=%s", cfg$stage1_near_a_max_failed, cfg$batch_n_workers))
cd <- fromJSON(file.path(root, "02_Infrastructure/worktask/constraint_defaults.json"), simplifyVector = FALSE)
cd0 <- cd; cd0$remeasure <- NULL
p0 <- file.path(TMP, "cd_noblock.json"); write_json(cd0, p0, auto_unbox = TRUE)
cd1 <- cd; cd1$remeasure$batch_n_workers <- NULL
p1 <- file.path(TMP, "cd_nokey.json"); write_json(cd1, p1, auto_unbox = TRUE)
Sys.setenv(QVEST_CONSTRAINT_DEFAULTS = p0); e0 <- errmsg(rfh_config(root))
Sys.setenv(QVEST_CONSTRAINT_DEFAULTS = p1); e1 <- errmsg(rfh_config(root, need = "batch_n_workers"))
Sys.unsetenv("QVEST_CONSTRAINT_DEFAULTS")
chk(grepl("remeasure 블록이 없다", e0) && grepl("batch_n_workers", e1),
    "A2 fail-closed — 블록 부재·키 부재 모두 stop(리터럴 폴백 없음)", sprintf("A2 fail-closed 아님: '%s' / '%s'", e0, e1))
rg1 <- rfh_regime("close_t1", root); rg2 <- rfh_regime("close_t1", root); rgl <- rfh_regime("close_d_legacy", root)
kx <- rfh_regime_key("close_t1", paste0(substr(rg1$harness_md5, 1, 31), "0"), rg1$cost_model_version)
chk(identical(rg1$key, rg2$key) && !identical(rg1$key, rgl$key) && !identical(rg1$key, kx) &&
      grepl("^close_t1_[0-9a-f]{8}$", rg1$key),
    sprintf("A3 regime 키 결정론 · 규약·하네스 md5 민감: %s / %s", rg1$key, rgl$key))
ea <- errmsg(rfh_regime(NULL, root)); eb <- errmsg(rfh_regime("close_t2", root))
chk(grepl("명시 필수", ea) && grepl("허용값", eb), "A4 exec_price NULL·허용 밖 → stop (설정 기본값에 기대지 않는다)")

# ── B 복원 단위 (합성) ────────────────────────────────────────────────────────
cat("[B] 복원 단위(합성 달력)\n")
cal <- seq(as.Date("2020-01-01"), as.Date("2020-12-31"), by = "day")
cal <- cal[!format(cal, "%u") %in% c("6", "7")]                        # 평일 달력
ex_all <- unname(as.Date(tapply(cal, format(cal, "%Y-%m"), min)[-1], origin = "1970-01-01"))   # 2~12월 첫 거래일
H <- rbindlist(lapply(ex_all, function(d) data.table(Exec = d, Ticker = c("A1", "A2"), Weight = c(0.5, 0.5))))
W <- rfh_restore_weights(H, cal, ex_all, min(ex_all))
sg <- sort(unique(W$Date))
back <- as.Date(vapply(sg, function(s) as.numeric(.RFH$get_execution_date(s, cal)), numeric(1)))
prev_td <- unname(vapply(ex_all, function(d) as.numeric(max(cal[cal < d])), numeric(1)))
chk(identical(as.numeric(back), as.numeric(ex_all)) && identical(as.numeric(sg), prev_td) && attr(W, "n_signals") == 11L,
    "B1 시그널 = exec 직전 거래일 · get_execution_date(시그널) = exec (11 리밸)")
eB2 <- errmsg(rfh_restore_weights(H[Exec != ex_all[5]], cal, ex_all, min(ex_all)))
chk(grepl("보유 복원 불일치", eB2), "B2 위반 주입: 보유 1개월 누락 → stop(앞 창이 조용히 늘어나지 않는다)", paste("B2", eB2))
eB3 <- c(errmsg(rfh_restore_weights(rbind(H, H[1]), cal, ex_all, min(ex_all))),
         errmsg(rfh_restore_weights(copy(H)[1, Weight := NA_real_], cal, ex_all, min(ex_all))),
         errmsg(rfh_restore_weights(copy(H)[Exec == ex_all[3], Exec := Exec + 1], cal,
                                    sort(c(ex_all[-3], ex_all[3] + 1)), min(ex_all))))
chk(grepl("중복", eB3[1]) && grepl("비유한", eB3[2]) && grepl("월 첫 거래일이 아니다", eB3[3]),
    "B3 중복 (exec,종목)·비유한 비중·월 첫 거래일 아닌 exec → stop", paste("B3", paste(eB3, collapse = " | ")))
W4 <- rfh_restore_weights(H, cal, ex_all[-1], ex_all[1] + 1)          # close_t1 저장: 첫 exec 은 NAV 시작 전(표식 없음)
eB4 <- errmsg(rfh_restore_weights(H, cal, ex_all[-(1:2)], ex_all[2] + 1))
chk(attr(W4, "n_signals") == 11L && grepl("보유 복원 불일치", eB4),
    "B4 close_t1 저장본: NAV 시작 전 첫 집행일 1건 허용 · 2건 이상 거부")
# 돌연변이 M1 — 달력 대조를 끄면 보유 누락이 조용히 통과한다(= B2 가 이 가드를 잰다)
m1 <- mutant(rfh_restore_weights, "if (length(miss) || length(bad_extra) || length(extra) > 1L)", "if (FALSE)")
if (is.null(m1)) ng("M1 돌연변이 패턴 부재 — 검사가 코드와 어긋났다") else {
  eM1 <- errmsg(m1(H[Exec != ex_all[5]], cal, ex_all, min(ex_all)))
  chk(identical(eM1, ""), "M1 돌연변이(달력 대조 제거) → 보유 누락이 조용히 통과 = B2 가 이 가드를 잡는다(red 실증)",
      paste("M1 돌연변이가 여전히 멈춘다 — 가드 소재 오판:", eM1))
}

# ── C 골든 양성 대조 ───────────────────────────────────────────────────────────
cat("[C] 골든 양성 대조\n")
GOLD <- file.path(root, "stage_artifacts/replication/20260921_100007_6876")
RAWP <- file.path(root, ".cache/RAWDATA.parquet"); BMP <- file.path(root, ".cache/benchmark.parquet")
have_gold <- all(file.exists(c(file.path(GOLD, c("bt_result.rds", "authoritative_remeasure.json")), RAWP, BMP)))
mk <- NULL
if (!have_gold) { sk("C 재료 부재(골든·RAWDATA 캐시)") } else {
  t0 <- Sys.time(); mk <- qd(rfh_load_market(root)); tl <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  md5_0 <- tools::md5sum(list.files(GOLD, full.names = TRUE, recursive = TRUE))
  OUT <- file.path(TMP, "o")
  t0 <- Sys.time(); L <- qd(rfh_remeasure(GOLD, "close_d_legacy", raw = mk, out_dir = OUT, root = root))
  tL <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  v <- L$vs_stored
  chk(isTRUE(v$same_regime) && isTRUE(v$ret_net_identical) && isTRUE(v$nav_net_identical) && isTRUE(v$metrics_identical) &&
        isTRUE(v$benchmark_identical) && identical(v$max_abs_dret_common_days, 0),
      sprintf("C1 legacy@현 빈티지 = 저장 bt 비트 일치(ret_net·nav·metrics·benchmark · %d일 · 적재 %.0fs · 계약 %.0fs)",
              v$n_days_new, tl, tL),
      sprintf("C1 비트 불일치 — %s", paste(names(v), unlist(v), sep = "=", collapse = " ")))
  au <- fromJSON(file.path(GOLD, "authoritative_remeasure.json"), simplifyVector = TRUE)
  ks <- c("cagr", "net_sharpe", "mdd", "calmar", "portfolio_alpha_t_nw_lag3", "oos_retention", "net_ir")
  v1 <- unlist(L$auth$essence[ks]); va <- unlist(au$essence[ks])
  chk(identical(L$auth$essence_grade, au$essence_grade) && all(abs(round(v1, 3) - va) < 1e-9),
      sprintf("C1 essence = 저장 authoritative(3자리): %s · PT %.3f · Calmar %.3f", au$essence_grade, va[5], va[4]))
  T1 <- qd(rfh_remeasure(GOLD, "close_t1", raw = mk, out_dir = OUT, root = root))
  e <- T1$auth$essence
  chk(identical(T1$auth$essence_grade, "B") && abs(e$portfolio_alpha_t_nw_lag3 - 3.777) < 5e-4 && abs(e$calmar - 0.433) < 5e-4 &&
        T1$vs_stored$n_days_new == v$n_days_new - 1L && !isTRUE(T1$vs_stored$same_regime),
      sprintf("C2 close_t1 = B · PT %.3f · Calmar %.3f (P0-04 골든 3.777/.433) · 관측 %d일 = legacy − 1",
              e$portfolio_alpha_t_nw_lag3, e$calmar, T1$vs_stored$n_days_new),
      sprintf("C2 close_t1 불일치 — %s PT %s Calmar %s", T1$auth$essence_grade, e$portfolio_alpha_t_nw_lag3, e$calmar))
  fs <- sort(list.files(OUT, recursive = TRUE))
  dirs2 <- file.path("20260921_100007_6876", paste0("remeasure_", c(rgl$key, rg1$key)))
  need <- c("authoritative_remeasure.json", "bt_result.rds", "01_strategy_spec.json", "03_period_returns.csv", "04_holdings.csv")
  md5_1 <- tools::md5sum(list.files(GOLD, full.names = TRUE, recursive = TRUE))
  chk(all(dirname(fs) %in% dirs2) && all(file.path(rep(dirs2, each = length(need)), need) %in% fs) &&
        identical(md5_0, md5_1) && !any(grepl("^remeasure_", list.files(GOLD))),
      sprintf("C3 쓰기 = out_dir 아래 2디렉터리뿐(각 %d파일 — 계약 산출 CSV·스펙 포함) · 원본 %d파일 md5 불변 · 산출물 안 remeasure_ 0",
              sum(dirname(fs) == dirs2[2]), length(md5_1)),
      sprintf("C3 쓰기 범위 이탈 — %s", paste(fs, collapse = ",")))
  aj <- fromJSON(file.path(OUT, "20260921_100007_6876", paste0("remeasure_", rg1$key), "authoritative_remeasure.json"), simplifyVector = TRUE)
  chk(identical(aj$measurement_regime$key, rg1$key) && identical(aj$measurement_regime$exec_price, "close_t1") &&
        identical(aj$measurement_regime$regime, rg1$key) && grepl("^[0-9a-f]{32}$", aj$measurement_regime$scoring_md5 %||% "") &&
        identical(aj$measurement_regime$harness_md5, rg1$harness_md5) && identical(aj$remeasure$n_signals_restored, 260L) &&
        identical(aj$remeasure$n_rebal_sim, 260L) && identical(aj$remeasure$stored$essence_grade, "B") &&
        identical(aj$kind, "remeasure_from_holdings") && !is.null(aj$remeasure$pit_screen),
      "C3 JSON 필드: regime{regime=key·key·exec_price·harness_md5·scoring_md5} · 복원 260 = 하네스 260 · 저장값 승계 · kind 표지 · PIT 판정 기록")
  # 적대검증 입력(I2) — 형제 판 03/04 가 그 규약의 창을 담는다(close_t1: 첫 수익일 > 첫 집행일 · legacy: 같다)
  d1 <- file.path(OUT, dirs2[2]); d0 <- file.path(OUT, dirs2[1])
  pr1 <- fread(file.path(d1, "03_period_returns.csv")); h1 <- fread(file.path(d1, "04_holdings.csv"))
  pr0 <- fread(file.path(d0, "03_period_returns.csv")); h0 <- fread(file.path(d0, "04_holdings.csv"))
  chk(min(as.Date(pr1$date)) > min(as.Date(h1$date)) && min(as.Date(pr0$date)) == min(as.Date(h0$date)) &&
        isTRUE(all.equal(pr1$ret_net, T1$bt$period_returns$ret_net %||% pr1$ret_net)),
      "C3b 형제 판 03/04 = 그 규약의 창(close_t1 첫 수익일 > 첫 집행일 · legacy 같은 날) — 적대검증이 규약을 산출에서 재도출할 수 있다")
  t0 <- Sys.time(); Lc <- rfh_remeasure(GOLD, "close_d_legacy", raw = mk, out_dir = OUT, root = root)
  tc <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  mk_alt <- mk; mk_alt$fp$raw$mtime <- "1999-01-01T00:00:00+0900"
  cpth <- file.path(OUT, "20260921_100007_6876", paste0("remeasure_", rgl$key), "authoritative_remeasure.json")
  cj_alt <- .rfh_cached(cpth, rgl$key, mk_alt$fp[c("raw", "bm")])
  cj_same <- .rfh_cached(cpth, rgl$key, mk$fp[c("raw", "bm")])
  cj_key <- .rfh_cached(cpth, rg1$key, mk$fp[c("raw", "bm")])
  chk(isTRUE(Lc$cached) && tc < 5 && is.null(cj_alt) && !is.null(cj_same) && is.null(cj_key),
      sprintf("C4 재개: 같은 regime·빈티지 = 캐시(%.2fs) · 빈티지 지문 불일치·regime 키 불일치 = 캐시 불채택(다시 잰다)", tc))
  Lf <- qd(rfh_remeasure(GOLD, "close_t1", raw = mk, out_dir = OUT, root = root, force = TRUE))
  chk(!isTRUE(Lf$cached) && abs(Lf$auth$essence$portfolio_alpha_t_nw_lag3 - 3.777) < 5e-4,
      "C4 force=TRUE → 캐시 무시 재측정(같은 값 재현 — 결정론)")
  # ── C6 ★R① 재개 캐시 = 채점 인자까지 대조 (적대검증 재현: 기본 채점 뒤 (sweep, 500) 호출이 cached=TRUE · chain · N 1 을 받았다) ──
  Ls <- qd(rfh_remeasure(GOLD, "close_t1", raw = mk, out_dir = OUT, root = root, selection_type = "sweep", n_trials_cumulative = 500L))
  chk(!isTRUE(Ls$cached) && identical(Ls$auth$selection_type, "sweep") && identical(as.integer(Ls$auth$n_trials_cumulative), 500L) &&
        isTRUE(Ls$auth$dsr_gate_applied) && identical(Ls$auth$measurement_regime$n_trials_basis, "argument") &&
        abs(Ls$auth$essence$portfolio_alpha_t_nw_lag3 - 3.777) < 5e-4,
      sprintf("C6a (sweep, 500) 호출 → 캐시(chain/1) 불채택 · 다시 채점: %s/%s · dsr_gate %s · PT 불변 %.3f",
              Ls$auth$selection_type, Ls$auth$n_trials_cumulative, Ls$auth$dsr_gate_applied, Ls$auth$essence$portfolio_alpha_t_nw_lag3),
      sprintf("C6a 옛 채점 판을 돌려줌 — cached=%s %s/%s", Ls$cached, Ls$auth$selection_type, Ls$auth$n_trials_cumulative))
  Ls2 <- rfh_remeasure(GOLD, "close_t1", raw = mk, out_dir = OUT, root = root, selection_type = "sweep", n_trials_cumulative = 500L)
  chk(isTRUE(Ls2$cached) && identical(as.integer(Ls2$auth$n_trials_cumulative), 500L), "C6b 같은 채점 인자 재호출 = 캐시(재개 유지)")
  cp1 <- file.path(OUT, "20260921_100007_6876", paste0("remeasure_", rg1$key), "authoritative_remeasure.json")
  scm <- rfh_scoring_md5(root); bmd <- unname(tools::md5sum(file.path(GOLD, "bt_result.rds")))
  w_ok <- list(selection_type = "sweep", n_trials_cumulative = 500L, of_artifact = GOLD, stored_bt_md5 = bmd, scoring_md5 = scm)
  bad <- function(k, v) { w <- w_ok; w[[k]] <- v; is.null(.rfh_cached(cp1, rg1$key, mk$fp[c("raw", "bm")], want = w)) }
  chk(!is.null(.rfh_cached(cp1, rg1$key, mk$fp[c("raw", "bm")], want = w_ok)) && bad("selection_type", "chain") &&
        bad("n_trials_cumulative", 499L) && bad("scoring_md5", strrep("0", 32)) && bad("stored_bt_md5", strrep("1", 32)) &&
        bad("of_artifact", file.path(TMP, "other")),
      "C6c 캐시 판독기 — 채점 유형·N·채점 지문(essence_score 등·문턱)·원 bt md5·원 산출물 중 하나라도 다르면 불채택")
  # 돌연변이 M4 — 구 캐시 판독기(키·빈티지만 · 채점 인자 무시)로 바꾸면 기본 채점 호출이 (sweep, 500) 캐시를 받는다 = C6 이 잡는다
  .cache_new <- .rfh_cached
  .cache_old <- function(p, key, fp_now = NULL, want = list()) {
    if (!file.exists(p)) return(NULL)
    j <- tryCatch(jsonlite::fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(j) || !identical(as.character(j$measurement_regime$key %||% ""), key) || is.null(j$remeasure)) return(NULL)
    if (!is.null(fp_now) && !.rfh_fp_same(j$measurement_regime$data_vintage, fp_now)) return(NULL)
    jsonlite::fromJSON(p, simplifyVector = TRUE) }
  assign(".rfh_cached", .cache_old, envir = environment(rfh_remeasure))
  Lm4 <- tryCatch(rfh_remeasure(GOLD, "close_t1", raw = mk, out_dir = OUT, root = root), error = function(e) NULL)
  assign(".rfh_cached", .cache_new, envir = environment(rfh_remeasure))
  chk(!is.null(Lm4) && isTRUE(Lm4$cached) && identical(as.integer(Lm4$auth$n_trials_cumulative), 500L),
      "M4 돌연변이(구 캐시 판독기) → 기본 채점(chain/1) 호출이 (sweep, 500) 캐시를 받는다 = C6a/C6d 가 이 결함을 잡는다(red 실증)",
      "M4 돌연변이에도 다시 쟀다 — 가드 소재 오판")
  Ld <- qd(rfh_remeasure(GOLD, "close_t1", raw = mk, out_dir = OUT, root = root))   # 기본(저장 기록) 채점으로 되돌린다(F4 캐시 전제)
  chk(!isTRUE(Ld$cached) && identical(Ld$auth$selection_type, "chain") && identical(as.integer(Ld$auth$n_trials_cumulative), 1L),
      "C6d 기본 채점(저장 기록 chain/1) 호출 → (sweep, 500) 캐시 불채택 · 다시 채점")
  # 위반 주입 — 골든 사본의 보유 1개월 삭제(원본 무접촉)
  INJ <- file.path(TMP, "inj", "20260921_100007_6876")
  dir.create(INJ, recursive = TRUE)
  file.copy(file.path(GOLD, c("authoritative_remeasure.json", "01_strategy_spec.json")), INJ)
  b <- readRDS(file.path(GOLD, "bt_result.rds"))
  dd <- sort(unique(b$holdings$date)); b$holdings <- b$holdings[date != dd[100]]
  saveRDS(b, file.path(INJ, "bt_result.rds"))
  eC5 <- errmsg(qd(rfh_remeasure(INJ, "close_d_legacy", raw = mk, root = root, write = FALSE)))
  chk(grepl("보유 복원 불일치", eC5) && !dir.exists(file.path(INJ, paste0("remeasure_", rgl$key))),
      sprintf("C5 위반 주입(골든 사본 보유 %s 삭제) → stop · 쓰기 0", dd[100]), paste("C5 조용히 통과:", eC5))
  # 돌연변이 M2 — END 절단 제거(현 빈티지 끝까지 마지막 창 연장) → 비트 일치가 깨져야 한다(= C1 이 잡는다)
  m2 <- mutant(.rfh_subset_raw, "[Date <= end]", "[Date <= as.Date(\"2100-01-01\")]")
  m2 <- if (is.null(m2)) NULL else mutant(m2, "cal <- mk$cal[mk$cal <= end]", "cal <- mk$cal")
  if (is.null(m2)) ng("M2 돌연변이 패턴 부재") else if (max(mk$cal) <= max(as.Date(b$nav$date))) {
    sk("M2 현 RAWDATA 끝 = 저장 끝 — END 절단 돌연변이가 식별 불가(빈티지 전진 후 재실행)") } else {
    .orig <- .rfh_subset_raw; assign(".rfh_subset_raw", m2, envir = environment(rfh_remeasure))
    Lm <- tryCatch(qd(rfh_remeasure(GOLD, "close_d_legacy", raw = mk, root = root, write = FALSE)), error = function(e) NULL)
    assign(".rfh_subset_raw", .orig, envir = environment(rfh_remeasure))
    chk(!is.null(Lm) && !isTRUE(Lm$vs_stored$ret_net_identical),
        sprintf("M2 돌연변이(END 절단 제거) → 비트 일치 깨짐(%d일 vs 저장 %d일) = C1 양성 대조가 잡는다",
                .rfh_or(Lm$vs_stored$n_days_new, NA), .rfh_or(Lm$vs_stored$n_days_stored, NA)),
        "M2 돌연변이가 비트 일치를 유지 — END 절단이 검사되지 않는다")
  }
}

# ── D B6 interval ─────────────────────────────────────────────────────────────
cat("[D] B6 interval 칸\n")
B6 <- file.path(root, "stage_artifacts/replication/20260921_155730_10736")
if (is.null(mk) || !file.exists(file.path(B6, "bt_result.rds"))) sk("D 재료 부재(B6_34 산출물·시장 데이터)") else {
  b6 <- readRDS(file.path(B6, "bt_result.rds"))
  R6 <- qd(rfh_remeasure(B6, "close_d_legacy", raw = mk, root = root, write = FALSE))
  ex6 <- sort(unique(as.Date(b6$holdings$date)))
  gap <- diff(as.integer(format(ex6, "%Y")) * 12L + as.integer(format(ex6, "%m")))
  a6 <- R6$auth$remeasure
  chk(a6$n_signals_restored == length(ex6) && a6$n_rebal_flag_stored == sum(b6$nav$is_rebalance_date) &&
        a6$n_rebal_sim == length(ex6) && all(gap == 3L),
      sprintf("D1 B6_34 interval k=3: 복원 시그널 %d = 저장 리밸 표식 %d = 하네스 리밸 %d · 간격 전부 3개월",
              a6$n_signals_restored, a6$n_rebal_flag_stored, a6$n_rebal_sim),
      sprintf("D1 불일치 — 복원 %s · 표식 %s · 하네스 %s · 간격 %s", a6$n_signals_restored, a6$n_rebal_flag_stored,
              a6$n_rebal_sim, paste(unique(gap), collapse = ",")))
  cat(sprintf("  [INFO] D B6_34 legacy@현 빈티지 비트 일치 = %s (max|Δret| %s) · grade %s (저장 %s)\n",
              isTRUE(R6$vs_stored$ret_net_identical), format(R6$vs_stored$max_abs_dret_common_days),
              R6$auth$essence_grade, a6$stored$essence_grade))
}

TAILA <- file.path(root, "stage_artifacts/replication/20260903_110631_13904")
if (is.null(mk) || !file.exists(file.path(TAILA, "bt_result.rds"))) sk("D2 재료 부재(20260903_110631_13904)") else {
  RT <- tryCatch(qd(rfh_remeasure(TAILA, "close_t1", raw = mk, root = root, write = FALSE)), error = function(e) e)
  at <- if (inherits(RT, "error")) NULL else RT$auth$remeasure
  chk(!is.null(at) && identical(at$tail_rebal_unbooked, "2026-09-01") && identical(at$tail_window_days, 1L) &&
        at$n_rebal_sim == at$n_signals_restored - 1L,
      sprintf("D2 마지막 창 1일(exec 2026-09-01 · 끝 09-02): 하네스 미기장 1건 허용 · JSON tail_rebal_unbooked 기록 (%s/%s)",
              .rfh_or(at$n_rebal_sim, NA), .rfh_or(at$n_signals_restored, NA)),
      sprintf("D2 %s", if (inherits(RT, "error")) conditionMessage(RT) else "필드 불일치"))
}
# D3 합성 — 중간 리밸의 close_t1 창에 보유 종목 데이터가 없으면 하네스가 그 리밸을 건너뛴다 → 재측정 거부(조용한 창 합병 금지)
cal3 <- seq(as.Date("2020-01-01"), as.Date("2020-12-31"), by = "day"); cal3 <- cal3[!format(cal3, "%u") %in% c("6", "7")]
ex3 <- unname(as.Date(tapply(cal3, format(cal3, "%Y-%m"), min)[-1], origin = "1970-01-01"))
H3 <- rbindlist(lapply(seq_along(ex3), function(k) data.table(date = ex3[k], ticker = if (k == 4L) c("B1", "B2") else c("A1", "A2"),
                                                              actual_weight = c(0.5, 0.5))))
RAW3 <- rbind(data.table(Date = rep(cal3, 2), Ticker = rep(c("A1", "A2"), each = length(cal3)), Ret = 0.001),
              data.table(Date = ex3[4], Ticker = c("B1", "B2"), Ret = 0.01))       # B 는 집행일 하루만 행이 있다
setkeyv(RAW3, c("Ticker", "Date"))
mk3 <- list(RAW = RAW3, BM = data.table(Date = cal3, BM_Ret = 0), cal = cal3,
            fp = list(raw = list(size = 1, mtime = "synthetic"), bm = list(size = 1, mtime = "synthetic")))
A3 <- file.path(TMP, "syn", "20200101_000000_1"); dir.create(A3, recursive = TRUE)
nav3 <- data.table(date = cal3[cal3 >= ex3[1]]); nav3[, is_rebalance_date := date %in% ex3][, nav_net := 1]
saveRDS(list(holdings = H3, nav = nav3, manifest = data.table(transaction_cost_bps = 15, run_id = "syn", strategy_id = "RP_syn"),
             period_returns = data.table(date = nav3$date, ret_net = 0)), file.path(A3, "bt_result.rds"))
write_json(list(run_id = "syn", strategy_id = "RP_syn", essence_grade = "C", essence = list(port_t = 0)), file.path(A3, "authoritative_remeasure.json"),
           auto_unbox = TRUE)
eD3 <- errmsg(qd(rfh_remeasure(A3, "close_t1", raw = mk3, root = root, write = FALSE)))
chk(grepl("미기장 2020-05-01", eD3), "D3 합성: 중간 리밸(2020-05) close_t1 창 데이터 없음 → 하네스 건너뜀 → 재측정 거부(마지막 창 예외 아님)",
    paste("D3", eD3))

# ── E 1단계 선정 (합성 원장) ────────────────────────────────────────────────────
cat("[E] 1단계 선정(합성 원장)\n")
ART <- file.path(TMP, "arts"); SPD <- file.path(TMP, "specs"); dir.create(SPD, recursive = TRUE)
mkart <- function(nm, complete = TRUE) {
  d <- file.path(ART, nm); dir.create(d, recursive = TRUE, showWarnings = FALSE)
  if (complete) { file.create(file.path(d, "bt_result.rds")); file.create(file.path(d, "authoritative_remeasure.json")) }
  d
}
mkspec <- function(nm, fac) { p <- file.path(SPD, paste0(nm, ".json")); write_json(list(factors = list(list(kind = "db", id = fac))), p, auto_unbox = TRUE); p }
es <- function(pt, cal, sr, cagr, oos, code, spec, dsr = NULL, st = "chain")
  list(cell_code = code, port_t = pt, calmar = cal, net_sharpe = sr, cagr = cagr, oos_retention = oos, dsr = dsr,
       selection_type = st, spec = spec)
c11f <- list(list(flag = "pit_c11", verdict = "consumed", evidence = "test"))
fdbf <- list(list(flag = "fdb_202608_v1", verdict = "consumed", evidence = "test"))
aN <- function(n, e, art, grade = "B", adv = NULL, vf = NULL)
  c(list(n = n, grade = grade, essence = e, artifacts = art), if (!is.null(adv)) list(adversary = list(verdict = adv)),
    if (!is.null(vf)) list(vintage_flags = vf))
sp1 <- mkspec("s1", "M01_Mom_12_1"); sp2 <- mkspec("s2", "V14_EBIT_EV"); spq <- mkspec("sq", "D32_Beta_VIX")
sp6 <- mkspec("s6", "Q35_CashBased_OpProf")
LED <- list(schema_version = "reinforce_ledger_v2", entries = list(
  list(base_id = "E1", base_grade = "C", status = "active", base_artifacts = mkart("base1"), engine_path = "",
       attempts = list(
         aN(1, es(3.0, 0.45, 0.9, 0.20, 0.20, "B1_1", sp1), mkart("a1"), vf = fdbf),   # 미충족 2(calmar·oos) → near_a(k=2)
         aN(2, es(3.8, 0.50, 1.0, 0.25, 0.10, "B1_2", sp2), mkart("a2"), vf = c11f),   # 최고 PT · C11 표식
         aN(3, es(3.6, 0.30, 0.9, 0.20, 0.10, "B5_3", sp2), mkart("a3"), adv = "fail"),# near_a · 적대검증 fail → 바닥 제외
         aN(4, es(1.0, 0.10, 0.3, 0.05, 0.10, "B2_4", sp2), mkart("a4"), grade = "C"),  # 사유 없음
         aN(5, es(3.0, 0.40, 0.9, 0.20, 0.30, "B1_5", spq), mkart("a5")),              # near_a · 격리 팩터 참조(표식 없음)
         aN(6, es(3.1, 0.66, 0.9, 0.20, 0.10, "B3_6", sp6), mkart("a6", complete = FALSE)))), # 미충족 1(oos) → near_a(k=1 도) · 불완전
  list(base_id = "E1_promo1", base_grade = "B", status = "exhausted", base_artifacts = file.path(ART, "a1"), engine_path = "",
       parent = list(base_id = "E1", cell = "B1_1", best_port_t = 3.0),
       carry = list(source_spec = sp1, source_cell = "B1_1"), attempts = list()),
  list(base_id = "E3", base_grade = "B", status = "exhausted", base_artifacts = mkart("base3"), engine_path = "",
       base_vintage_flags = c11f, attempts = list())))
LP <- file.path(TMP, "ledger_synth.json"); write_json(LED, LP, auto_unbox = TRUE, null = "null")
X2 <- rfh_select_stage1(root = root, ledger = LP, near_a_max_failed = 2L)
X1 <- rfh_select_stage1(root = root, ledger = LP, near_a_max_failed = 1L)
g <- function(X, nm) X[basename(artifact) == nm]
chk(nrow(X2) == 7L && nrow(X1) == 5L && !any(c("a3", "a5") %in% basename(X1$artifact)) && "a6" %in% basename(X1$artifact),
    sprintf("E1 합성 원장 산출물 수: k=2 → %d (기대 7) · k=1 → %d (기대 5 — 미충족 2개 칸 a3·a5 탈락 · 1개 칸 a6 유지)",
            nrow(X2), nrow(X1)))
chk(grepl("lineage_best", g(X2, "a2")$reasons) && grepl("floor_active", g(X2, "a2")$reasons) && isTRUE(g(X2, "a2")$skip) &&
      grepl("pit_c11", g(X2, "a2")$skip_reason),
    "E2 최고 PT(a2) = lineage_best·floor_active 이지만 C11 표식 → skip(PIT-C11-CONVENTIONS ⑧)",
    sprintf("E2 a2: %s / %s", g(X2, "a2")$reasons, g(X2, "a2")$skip_reason))
chk(!grepl("floor_active", g(X2, "a3")$reasons) && grepl("near_a", g(X2, "a3")$reasons) && !g(X2, "a3")$skip,
    "E3 적대검증 fail 칸(a3) = near_a 이나 floor_active 아님(러너 바닥 술어와 같다)")
chk(identical(sort(strsplit(g(X2, "a1")$reasons, "+", fixed = TRUE)[[1]]), sort(c("near_a", "base", "carry", "floor_promotion"))) &&
      g(X2, "a1")$n_refs >= 4L && identical(g(X2, "a1")$vintage_flags, "fdb_202608_v1") && !g(X2, "a1")$skip,
    sprintf("E4 carry·승격 바닥·승격 기저·near_a 가 한 산출물(a1)로 합쳐짐(%s) · fdb 표식 승계(skip 아님)", g(X2, "a1")$reasons))
chk(isTRUE(g(X2, "a5")$skip) && grepl("pit_quarantine_text", g(X2, "a5")$skip_reason) && nrow(g(X2, "a4")) == 0L,
    "E5 격리 팩터(D32_Beta_VIX) 참조 spec(표식 없음) → skip · 사유 없는 칸(a4) 미선정")
chk(isTRUE(g(X2, "a6")$skip) && identical(g(X2, "a6")$skip_reason, "artifact_incomplete") &&
      isTRUE(g(X2, "base3")$skip) && grepl("pit_c11", g(X2, "base3")$skip_reason) && !g(X2, "base1")$skip,
    "E6 불완전 산출물 skip · base_vintage_flags C11 기저 skip · 정상 기저 선정")
m3 <- mutant(rfh_select_stage1, "c11 = any(fl %in% qflags)", "c11 = FALSE")
if (is.null(m3)) ng("M3 돌연변이 패턴 부재") else {
  Xm <- m3(root = root, ledger = LP, near_a_max_failed = 2L)
  chk(!isTRUE(g(Xm, "a2")$skip), "M3 돌연변이(C11 표식 무시) → a2 가 skip 에서 빠진다 = E2 가 이 가드를 잡는다(red 실증)",
      "M3 돌연변이에도 a2 skip — 가드 소재 오판")
}
LIVE <- file.path(root, "06_Registry/reinforce_ledger_l1.json")
if (file.exists(LIVE)) {
  XL <- tryCatch(rfh_select_stage1(root = root), error = function(e) NULL)   # 읽기만 · 설정 k
  if (!is.null(XL)) cat(sprintf("  [INFO] 운영 원장(읽기만) 1단계: %d 산출물 · 실행 %d · skip %d(%s)\n", nrow(XL), sum(!XL$skip),
                                sum(XL$skip), paste(names(table(XL[skip == TRUE]$skip_reason)), table(XL[skip == TRUE]$skip_reason),
                                                     sep = "=", collapse = " ")))
}

# ── F 배치 ───────────────────────────────────────────────────────────────────
cat("[F] 배치\n")
eF1 <- errmsg(rfh_batch(GOLD, root = root, claim = FALSE, barrier = FALSE))
chk(grepl("in_place=TRUE", eF1), "F1 out_dir 없이 in_place 미명시 → stop(운영 산출물 쓰기 = 별도 승인)")
CL <- file.path(TMP, "c", "claim"); dir.create(CL, recursive = TRUE)
writeLines(toJSON(list(pid = Sys.getpid(), started_at = "x"), auto_unbox = TRUE), file.path(CL, "owner.json"))
OF <- file.path(TMP, "of")
rF2 <- qd(rfh_batch(GOLD, out_dir = OF, root = root, claim = CL, stale_hours = 6, barrier = FALSE, n_workers = 1L))
chk(identical(rF2$status, "claimed") && !length(list.files(OF, pattern = "^remeasure_", recursive = TRUE, include.dirs = TRUE)) &&
      file.exists(rF2$manifest),
    "F2 claim 점유(살아 있는 owner) → status claimed · 재측정 쓰기 0 · manifest 만")
unlink(CL, recursive = TRUE)
fake <- file.path(TMP, "rb_held.sh")
writeLines(c("#!/usr/bin/env bash", "printf 'RB\\tstate=held\\tlock=refresh\\tpid=4242\\twinpid=\\treason=test_injected\\tage_s=1\\ttag=\\tpath=/tmp/x\\n'",
             "exit 10"), fake)
Sys.setenv(QVEST_RB_SH = fake)
rF3 <- qd(rfh_batch(GOLD, out_dir = OF, root = root, claim = CL, stale_hours = 6, barrier = TRUE, barrier_wait_s = 0, n_workers = 1L))
Sys.unsetenv("QVEST_RB_SH")
mf3 <- fromJSON(rF3$manifest, simplifyVector = TRUE)
chk(identical(rF3$status, "deferred_refresh_lock") && identical(mf3$barrier$pre$state, "held") &&
      !length(list.files(OF, pattern = "^remeasure_", recursive = TRUE, include.dirs = TRUE)) &&
      (!dir.exists(CL) || file.exists(file.path(CL, "released.json"))),
    "F3 배리어 held(주입) → deferred_refresh_lock · 재측정 쓰기 0 · claim 해제",
    sprintf("F3 %s · barrier %s · claim 잔존 %s", rF3$status, mf3$barrier$pre$state, dir.exists(CL)))
if (!have_gold) sk("F4~F5 재료 부재") else {
  selF <- data.table(artifact = c(GOLD, file.path(ART, "a6"), file.path(ART, "a2")), skip = c(FALSE, FALSE, TRUE),
                     skip_reason = c("", "", "pit_c11(test)"))
  rF4 <- qd(rfh_batch(selF, out_dir = OUT, root = root, claim = CL, stale_hours = 6, barrier = FALSE, n_workers = 1L))
  mf4 <- fromJSON(rF4$manifest, simplifyVector = TRUE)
  chk(identical(rF4$status, "done") && nrow(rF4$rows) == 1L && isTRUE(rF4$rows$leg_cached) && isTRUE(rF4$rows$t1_cached) &&
        nrow(rF4$skipped) == 2L && setequal(rF4$skipped$reason, c("artifact_incomplete", "pit_c11(test)")) &&
        identical(mf4$n_cached, 1L) && isTRUE(rF4$rows$leg_bit_identical) && isTRUE(rF4$rows$leg_ret_identical) &&
        isTRUE(rF4$rows$leg_bench_identical) && !isTRUE(rF4$rows$t1_ret_identical) && abs(rF4$rows$d_conv_pt - (3.777 - 4.349)) < 1e-9,
      sprintf("F4 skip 목록 통과(불완전·C11) · 골든 캐시 재개 · 3판 행 d_conv_pt %.3f · manifest n_cached=1", rF4$rows$d_conv_pt),
      sprintf("F4 %s · rows %d · skipped %d", rF4$status, nrow(rF4$rows), nrow(rF4$skipped)))
  t0 <- Sys.time()
  rF5 <- qd(rfh_batch(c(GOLD, B6), exec_prices = "close_d_legacy", out_dir = OUT, root = root, claim = CL, stale_hours = 6,
                      barrier = FALSE, n_workers = 2L))
  t5 <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  mf5 <- fromJSON(rF5$manifest, simplifyVector = TRUE)
  chk(identical(rF5$status, "done") && nrow(rF5$rows) == 2L && identical(mf5$market$raw_nrow, mk$fp$raw_nrow) &&
        isTRUE(rF5$rows[run_dir == basename(GOLD)]$leg_cached) &&
        file.exists(file.path(OUT, basename(B6), paste0("remeasure_", rgl$key), "authoritative_remeasure.json")),
      sprintf("F5 PSOCK 2워커: 워커별 시장 1회 적재(%s행) · 골든 캐시 + B6 신규 측정 · %.0fs", format(mf5$market$raw_nrow), t5),
      sprintf("F5 %s · rows %d · failed %s", rF5$status, nrow(rF5$rows), paste(unlist(rF5$failed), collapse = " ")))
}
HB <- file.path(TMP, "c", "hb"); dir.create(HB, recursive = TRUE)
Sys.setFileTime(HB, Sys.time() - 7 * 3600); m0 <- file.info(HB)$mtime
.rfh_claim_heartbeat(HB); m1 <- file.info(HB)$mtime
chk(as.numeric(difftime(m1, m0, units = "hours")) > 6.9 && file.exists(file.path(HB, "heartbeat.txt")),
    sprintf("F6 하트비트 → claim 디렉터리 mtime 갱신(%.1fh 전 → 지금) — 러너 시간 폴백이 긴 배치를 뺏지 않는다",
            as.numeric(difftime(Sys.time(), m0, units = "hours"))))
writeLines(toJSON(list(pid = Sys.getpid() + 1L), auto_unbox = TRUE), file.path(HB, "owner.json"))
r7 <- .rfh_task(list(artifact = GOLD), "close_d_legacy", file.path(TMP, "o7"), FALSE, root, HB, Sys.getpid(), mk = mk)
chk(identical(r7$status, "claim_lost") && !dir.exists(file.path(TMP, "o7")),
    "F7 claim 소유권 상실 → 칸 실행 없이 claim_lost(재개 대상)")

# ── G ★R② PIT 자기 판정 (합성 원장 — 골든 사본 2개) ───────────────────────────────────────────────────────
cat("[G] PIT 자기 판정(합성 원장)\n")
if (!have_gold || is.null(mk)) sk("G 재료 부재(골든·시장 데이터)") else {
  mkcopy <- function(nm) { d <- file.path(TMP, "g", nm); dir.create(d, recursive = TRUE)
    file.copy(file.path(GOLD, c("bt_result.rds", "authoritative_remeasure.json", "01_strategy_spec.json")), d); gsub("\\\\", "/", d) }
  GC <- mkcopy("20260921_100007_c11"); GF <- mkcopy("20260921_100007_fdb")
  LG <- list(schema_version = "reinforce_ledger_v2", entries = list(
    list(base_id = "G_C11", status = "exhausted", base_artifacts = "", engine_path = "", attempts = list(
      list(n = 1L, grade = "B", essence = list(cell_code = "B5_19", port_t = 3.7), artifacts = GC,
           vintage_flags = list(list(flag = "pit_c11", verdict = "consumed", evidence = "test"))))),
    list(base_id = "G_FDB", status = "exhausted", base_artifacts = "", engine_path = "", attempts = list(
      list(n = 1L, grade = "B", essence = list(cell_code = "B1_3", port_t = 3.7), artifacts = GF,
           vintage_flags = list(list(flag = "fdb_202608_v1", verdict = "consumed", evidence = "test")))))))
  LPG <- file.path(TMP, "ledger_g.json"); write_json(LG, LPG, auto_unbox = TRUE, null = "null")
  scr <- rfh_pit_screen(c(GC, GF, GOLD), root, ledger = LPG)
  gs <- function(d) scr[tolower(artifact) == tolower(d)]
  chk(isTRUE(gs(GC)$c11) && isTRUE(gs(GC)$skip) && grepl("pit_c11", gs(GC)$skip_reason) &&
        !isTRUE(gs(GF)$skip) && identical(gs(GF)$flags, "fdb_202608_v1") && identical(gs(GOLD)$n_refs, 0L),
      "G1 rfh_pit_screen — pit_c11 칸 skip · fdb 표식 칸 통과(표식 승계) · 원장 밖 산출물 참조 0")
  OG <- file.path(TMP, "og")
  CLG <- file.path(TMP, "c", "gclaim"); dir.create(CLG, recursive = TRUE)
  writeLines(toJSON(list(pid = Sys.getpid(), started_at = "x"), auto_unbox = TRUE), file.path(CLG, "owner.json"))  # 점유 — 판정까지만 보고 멈춘다
  rG2 <- qd(rfh_batch(c(GC, GF), exec_prices = "close_t1", out_dir = OG, root = root, claim = CLG, stale_hours = 6,
                      barrier = FALSE, n_workers = 1L, ledger = LPG))
  chk(identical(rG2$status, "claimed") && nrow(rG2$skipped) == 1L && identical(tolower(rG2$skipped$artifact), tolower(GC)) &&
        grepl("pit_c11", rG2$skipped$reason) && !length(list.files(OG, pattern = "^remeasure_", recursive = TRUE, include.dirs = TRUE)),
      "G2 ★문자 벡터 입력 배치(구판 skip=FALSE 로 시작) — C11 칸이 skipped(pit_c11) · fdb 칸은 과제 · 재측정 쓰기 0",
      sprintf("G2 %s · skipped %d", rG2$status, nrow(rG2$skipped)))
  # 호출자가 data.frame 으로 skip=FALSE 를 명시해도 판정이 해제되지 않는다
  rG2b <- qd(rfh_batch(data.table(artifact = GC, skip = FALSE, skip_reason = ""), exec_prices = "close_t1", out_dir = OG, root = root,
                       claim = CLG, stale_hours = 6, barrier = FALSE, n_workers = 1L, ledger = LPG))
  chk(nrow(rG2b$skipped) == 1L && grepl("pit_c11", rG2b$skipped$reason), "G2b data.frame skip=FALSE 명시 → 여전히 C11 skip(호출자가 판정을 끄지 못한다)")
  unlink(CLG, recursive = TRUE)
  eG3 <- errmsg(rfh_remeasure(GC, "close_t1", raw = mk, out_dir = OG, root = root, pit = rfh_pit_screen(GC, root, ledger = LPG)))
  chk(grepl("PIT 비편입", eG3) && !dir.exists(file.path(OG, basename(GC))), "G3 rfh_remeasure 직접 호출도 C11 칸 → stop · 쓰기 0", paste("G3", eG3))
  RF <- qd(rfh_remeasure(GF, "close_t1", raw = mk, out_dir = OG, root = root, pit = rfh_pit_screen(GF, root, ledger = LPG)))
  jf <- fromJSON(file.path(RF$out, "authoritative_remeasure.json"), simplifyVector = TRUE)
  chk(identical(unlist(jf$remeasure$vintage_flags), "fdb_202608_v1") && identical(jf$remeasure$pit_screen$n_ledger_refs, 1L) &&
        !isTRUE(jf$remeasure$pit_screen$c11),
      "G4 격리 밖 표식(fdb_202608_v1)은 재측정 JSON remeasure$vintage_flags 로 승계(선정 결함은 재측정이 못 고친다)")
  # 돌연변이 M5 — 자기 판정 제거(구판: 문자 벡터 입력은 skip=FALSE 로 시작) → C11 칸이 skip 에서 빠진다 = G2 가 잡는다
  .scr_new <- rfh_pit_screen
  assign("rfh_pit_screen", function(artifacts, root = NULL, ledger = NULL, layers = c(1L, 2L), check_text = TRUE)
    data.table(artifact = unique(.rfh_norm(artifacts)), n_refs = 0L, c11 = FALSE, flags = "", quarantine_flags = "", text_hit = "",
               skip = FALSE, skip_reason = ""), envir = environment(rfh_batch))
  dir.create(CLG, recursive = TRUE)
  writeLines(toJSON(list(pid = Sys.getpid(), started_at = "x"), auto_unbox = TRUE), file.path(CLG, "owner.json"))
  rM5 <- tryCatch(qd(rfh_batch(c(GC, GF), exec_prices = "close_t1", out_dir = OG, root = root, claim = CLG, stale_hours = 6,
                               barrier = FALSE, n_workers = 1L, ledger = LPG)), error = function(e) NULL)
  assign("rfh_pit_screen", .scr_new, envir = environment(rfh_batch)); unlink(CLG, recursive = TRUE)
  chk(!is.null(rM5) && nrow(rM5$skipped) == 0L,
      "M5 돌연변이(자기 판정 제거 = 구판) → C11 칸이 skip 에서 빠져 과제가 된다 = G2 가 이 결함을 잡는다(red 실증)",
      "M5 돌연변이에도 C11 skip — 가드 소재 오판")
}
finish()
