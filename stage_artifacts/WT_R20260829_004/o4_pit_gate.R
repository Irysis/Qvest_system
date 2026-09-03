# O4 — detect_lookahead 하드 게이트: 의사결정 경로 vs 사후 평가기 분리 스캔 + 양방향 대조
#  ★코드를 패턴 회피 목적으로 고치지 않는다. 발화한 플래그는 그대로 보고하고 **재도출**한다.
suppressWarnings(suppressMessages({library(data.table); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
source(file.path(ROOT,"02_Infrastructure/validation/lookahead_detector.R"))
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_004")
DEC  <- c("o1_inputs.R","o2_methods.R")
POST <- c("o3_overlay_pit.R","o4_pit_gate.R","o5_diag.R","o6_emit.R")
scan <- function(f){ p <- file.path(OUT,f)
  z <- tryCatch(detect_lookahead(p, verbose=FALSE), error=function(e) list(clean=NA, violations=list()))
  list(file=f, clean=z$clean, n_violations=length(z$violations),
       viol=lapply(z$violations, function(v) list(check=v$check, line=v$line, code=trimws(v$code)))) }
rd <- lapply(DEC, scan)
rp <- lapply(Filter(function(f) file.exists(file.path(OUT,f)), POST), scan)
pr <- function(tag,L) for(z in L){ cat(sprintf("[%s] %-20s clean=%-5s n=%d\n", tag, z$file, as.character(z$clean), z$n_violations))
  for(v in z$viol) cat(sprintf("        %s@%d : %s\n", v$check, v$line, substr(v$code,1,90))) }
pr("DECISION", rd); pr("POSTHOC", rp)

## 동일 idiom 의 코호트 맥락 — alpha 산출 스크립트도 같은 줄에서 발화하는가
cohort <- lapply(c("s4_candidate.R","s5_diag.R","s2_mech.R"), scan)
pr("ALPHA-COHORT", cohort)

## 양성 대조 (A): 검출기가 **선언한** idiom 주입 → 발화해야 한다
src2 <- readLines(file.path(OUT,"o2_methods.R"), warn=FALSE)
mk <- function(extra,nm){ p <- file.path(OUT,nm); writeLines(c(src2, extra), p)
  z <- detect_lookahead(p, verbose=FALSE); unlink(p); z }
z0 <- scan("o2_methods.R")
zA <- mk(c('vol_ann <- sd(port_ret) * sqrt(252)',
           'after_vt <- ret_series * vt_scale',
           'window_ret <- nav[(i-19):i]   # drawdown window'), "_o4_probeA.R")
## 음성 축 대조 (B): optimizer 레인 고유 위반 주입 → 발화하지 않으면 그 축은 검출기 밖
zB <- mk(c('Sig_full <- cov(as.matrix(RET_ALL))          # 전 표본 공분산으로 비중 산출',
           'lab[, panic_future := shift(panic, -1L)]      # 국면 라벨 1개월 앞당김',
           'best <- names(which.max(sapply(METHODS, function(m) full_sample_sharpe(m))))'), "_o4_probeB.R")
ck <- function(z) if(length(z$violations)) sapply(z$violations, function(v) v$check) else character(0)
firedA <- length(zA$violations) > z0$n_violations; firedB <- length(zB$violations) > z0$n_violations
cat(sprintf("\n[대조] baseline(o2)=%d | A(선언 idiom)=%d fired=%s (%s) | B(optimizer 고유)=%d fired=%s\n",
   z0$n_violations, length(zA$violations), firedA, paste(unique(ck(zA)),collapse=","),
   length(zB$violations), firedB))

## 발화 플래그 재도출 — 날짜 t 의사결정에 실제로 들어간 입력의 전수
rederivation <- list(
  flagged_construct = "mean(r)/sd(r)*sqrt(12) — 실현 net 수익 시계열의 SR/Calmar 산출",
  where = "measure()/met() 사후 평가 함수 내부 (o1:31 · o2:73 · o3:60)",
  cohort_context = "alpha 의 s4_candidate.R 도 동일 idiom 4건 · s5_diag.R 2건 발화 — 본 라운드가 만든 결함이 아니라 측정 스크립트 전반의 검출기 특성",
  decision_inputs_at_date_t = c(
    "score_final(t) = alpha 발행 alpha_scores.parquet 의 score (신호월말 t-1 데이터)",
    "score_base_momentum(t) = 동 parquet (t-1)",
    "vol126_ann(t) = alpha 발행 종목 실현변동성 126d (strict t-1)",
    "panic(signal_ym t) = alpha 발행 regime_signal_timeseries (used_cutoff <= holding_month_start)",
    "Sector(t) = 월말 시변 섹터 패널 (risk_inputs SECM, <= sig_date)"),
  future_inputs_at_date_t = "없음 — Ret_1m(전방 실현수익)은 비중 산출식 어디에도 들어가지 않는다(weighted_screen_bt 가 비중을 받아 사후 결합)",
  honest_exposure = paste0("★단 method **선택**은 전 표본 성과로 했다(IS-selection). 이는 PIT 위반이 아니라 ",
    "선택편향 노출이며 방어선은 DSR(sweep, n_trials=5) + oos_retention + 아래 anchored 선택 안정성이다."),
  verdict = "DECISION_PATH_CLEAN_AFTER_REDERIVATION (플래그는 사후 평가기 소재 · 미은폐)")
res <- list(gate="detect_lookahead", split_scan=TRUE,
  decision_path=list(files=DEC, raw_all_clean=all(sapply(rd,function(z) isTRUE(z$clean))), per_file=rd),
  posthoc_evaluator=list(files=sapply(rp,`[[`,"file"), raw_all_clean=all(sapply(rp,function(z) isTRUE(z$clean))), per_file=rp),
  alpha_cohort=cohort, rederivation=rederivation,
  positive_control_A=list(purpose="검출기 선언 idiom(C1 full-sample vol / C5_VT / C5_DDshort)",
    n=length(zA$violations), checks=as.list(unique(ck(zA))), fired=firedA,
    note="양성 대조 없는 계기는 방어선으로 세지 않는다"),
  negative_axis_control_B=list(purpose="optimizer 레인 고유 위반(전 표본 cov 기반 비중 · 국면라벨 shift(-1) · 전 표본 SR argmax)",
    n=length(zB$violations), fired=firedB,
    reading="B 미발화 = R 경로에 그 축의 일반 검사가 없다(risk 가 이미 실증). 그 축의 PIT 담보는 검출기가 아니라 설계·산출물 기록이다 — detect_lookahead PASS 를 그 축의 통과 근거로 인용 금지."),
  pattern_evasion_declaration="의사결정 경로 코드를 검출 패턴 회피 목적으로 수정한 바 없음(발화 줄 원문 그대로 기록).")
write_json(res, file.path(OUT,"pit_gate_optimizer.json"), pretty=TRUE, auto_unbox=TRUE, na="null")
cat(sprintf("[O4] 기록 완료 — decision raw_clean=%s / A fired=%s / B fired=%s\n",
    res$decision_path$raw_all_clean, firedA, firedB))
