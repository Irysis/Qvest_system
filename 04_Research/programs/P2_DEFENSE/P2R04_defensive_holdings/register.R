## P2R04 방어적 보유(비대칭 원천 ③) × β 짝 — 엔진 자체 구성(E2 EW · E3 엔트로피 비중) 위에 방어 팩터 틸트 4종(H1 하방β · H2 저변동 · H3 β 비대칭 ·
##   H4 퀄리티)을 도구 상자 혼합식(Score = w × 순위z(DNN) + (1 − w) × 평균 순위z(팩터))으로 얹으면, 같은 β 의 정적 현금 사본(β 짝)보다 깊은 위기 · 빠른 급락에서
##   덜 빠지고(헌장 빈칸 6 · 8 · 10) 크기 · 노출 짝을 넘는 선택 방어(⑭)이며 강세 참여 · 알파 · 복리를 지키는가
##   설계 = DESIGN.md v3 · Q 자율 판단 J-20261018-003(라운드 선택) · 앞 라운드 P2R03 = falsified(β 짝 깊은 위기 과반 0/14 — 노출(β) 방어) ·
##   철학 Superfan P1 R-20261018-003 수용(E2 진단 9 — 결측 짝 C1~C4 · 용량 짝 W1~W4 · 희석 짝 N0) ·
##   판단 Superfan T1 R-20261018-004 C-027 수용(E3 장치 방어 몫 50% = E2 와 같은 처치 · 도구 상자 12.5% = E3 진단 W1~W4)
## 칸 = 23: E2 묶음 14(RX0 + 장치 H1~H4 + 진단 9) · E3 묶음 9(RX0 + 장치 H1~H4 + 진단 W1~W4). 판정 표 = 장치 8칸(엔진 2 × 장치 4)뿐.
## 실행:
##   Rscript register.R --draft      초안 — 싼 기계 점검(사양 23 · 평가 경로 파일 · 리허설 요약 · 규칙 상수 계약 · 판정 구현과의 정합 · 판단 원장)을 먼저 하고,
##                                   검사 4종을 실제로 돌려 통과 수를 싣는다 · 하나라도 실패면 초안을 쓰지 않는다
##   Rscript register.R --register   등록 — 검토판 보존 · 사양 · 운영 경로 · 팩터 레지스트리 엔트리 · 평가 경로 md5 · 패키지 · R 판 · 리허설 · 행동 카드 사본 ·
##                                   철학 Superfan P1 수령 · 커밋 상태(고정 대상 전부)를 확인한 뒤에만 사전등록 두 사본(stage_artifacts 정본 + 라운드 디렉터리 prereg.json) ·
##                                   등록부 pr_record_round
##   ★R2: 이 라운드의 측정 결과(results/P2R04_*.json)가 하나라도 있거나 사전등록이 이미 있으면 사전등록을 바꾸지 않는다.
##   ★사양(specs/)은 이 파일이 쓰지 않는다 — 구현 계약(DESIGN §10 + 조정자 지시)대로 만든 23개를 P2R04_CONST$spec_checks 로 검사만 한다
##     (RX0 = P2R03 RX0 와 code · label 밖 동일 · 장치 · 진단 = 혼합 몫 유도식(mix_plan)이 정한 팩터 나열 · base_weight 밖 RX0 와 동일 ·
##      시행 회계 = 장치만 앞선 사전등록 계보 최댓값 + 8 · 축 파서 rx_validate(null_perm 은 엔진 null_perm 분기의 seed 규칙)).
##   ★판정 규칙 상수(final_selection_rule)는 round_rules.R::p2r04_final_selection_rule 이 정본이다(구현 계약 §10 키 · 값을 여기서 단정만 한다).
##     판정 규칙 문장(rules)은 round_rules.R 에 p2r04_rules() 가 있으면 그것, 없으면 아래 RULES_DEFAULT(DESIGN v3 §5 · P2R03 사전등록 문장 승계).
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

## ── 상수 · 검사 함수(순수 · 자기완결 — 바깥 변수를 참조하지 않는다) ─────────────────────────────────────────
##   precheck.R --dry 가 이 대입문 하나만 골라 평가한다(핀 목록 · 칸 계획 · 혼합 몫 유도 · 사양 검사의 단일 정본). 바꾸면 precheck · 등록이 같이 바뀐다.
P2R04_CONST <- local({
  PROGRAM <- "P2_DEFENSE"; ROUND <- "P2R04_defensive_holdings"
  RD_REL <- "04_Research/programs/P2_DEFENSE/P2R04_defensive_holdings"
  P2R03_SPECS <- "04_Research/programs/P2_DEFENSE/P2R03_conditional_overlay/specs"
  P2R03_PREREG <- "stage_artifacts/programs/P2_DEFENSE/P2R03_conditional_overlay/prereg.json"
  ## 운영 경로 핀 = P2R03 목록 그대로(팩터 DB 커넥터 · 등급 계약 v3.2 grade_v3.R · 06_Registry/grade_v3.json 포함) − 오버레이 arm 코드 4개
  ##   (dbeta_tilt · gen_20260903_133452 의 .R · .arm.json — 이 라운드에 오버레이 없음). overlay_pit_guard.R 는 backtest_harness 의 C11 경로가 읽으므로 남긴다.
  ##   팩터 레지스트리는 파일 md5 가 아니라 쓰는 팩터 엔트리 내용으로 핀한다(operational_pins$factor_registry_entries · evaluate.R P2R04_PIN_KINDS) —
  ##   IC 이력이 모자란 신호일의 방향 대체 원천이라 처치 팩터의 방향에 닿는다 · 경로 = 커넥터가 먼저 읽는 판(factor_db_connector.R .load_registry 후보 1)
  ##   ★워커가 읽는 설정(06_Registry/reinforce_program.json fixed_axes — rf_cell_worker.R 가 칸 사양 대신 읽는 수수료 commission_bps · 종목 수 n_max)은
  ##   파일 핀이 아니라 precheck.R 의 키 값 대조(= 사양 fixed_axes 값)로 막는다 — 자주 바뀌는 파일이라 md5 핀은 무관한 편집으로 측정을 막는다(교차 점검 v1 필수 5)
  OPS <- c("02_Infrastructure/reinforcement/rf_cell_engine.R", "02_Infrastructure/reinforcement/rf_base_cache.R", "02_Infrastructure/reinforcement/rf_axes.R",
           "02_Infrastructure/reinforcement/rf_rebalance.R", "02_Infrastructure/reinforcement/rf_sleeve.R", "02_Infrastructure/ops/rf_cell_worker.R",
           "02_Infrastructure/validation/overlay_pit_guard.R",
           "02_Infrastructure/portfolio/weight_catalog.R", "02_Infrastructure/methods/method_registry.R", "02_Infrastructure/portfolio/strategy_tilt_weights.R",
           "02_Infrastructure/portfolio/advanced_weights.R",
           "02_Infrastructure/alpha_search/run_paper_replication.R", "02_Infrastructure/replication/replication_harness.R", "02_Infrastructure/backtest_harness.R",
           "02_Infrastructure/config.R", "02_Infrastructure/contracts/measurement_axis.R", "02_Infrastructure/contracts/behavior_card.R",
           "02_Infrastructure/contracts/diagnosis_packet.R", "02_Infrastructure/contracts/matched_controls.R", "02_Infrastructure/contracts/grade_v3.R",
           "02_Infrastructure/contracts/tilt_attribution.R", "02_Infrastructure/contracts/beta_controlled_alpha.R", "06_Registry/matched_controls.json",
           "02_Infrastructure/worktask/constraint_defaults.json", "04_Research/strategies/RP_AUTO_2002_06975/engine.R",
           "02_Infrastructure/factor_db/factor_db_connector.R", "04_Research/programs/_lib/round_kit.R", "04_Research/programs/_lib/measure_round_cell.R",
           "04_Research/programs/_lib/eval_parallel.sh", "02_Infrastructure/ops/refresh_barrier.sh",
           "02_Infrastructure/contracts/backtest_result_contract.R", "02_Infrastructure/contracts/save_bt_result.R", "02_Infrastructure/contracts/essence_score.R",
           "02_Infrastructure/contracts/tilt_attribution_config.json", "02_Infrastructure/contracts/rolling_grade.R", "06_Registry/rolling_grade.json",
           "02_Infrastructure/factor_db/factor_z_standard.R", "06_Registry/grade_v3.json")
  FACTOR_REGISTRY <- "02_Infrastructure/factor_db/factor_registry.json"
  ## 평가 경로(결과 전에 고정 · evaluate.R 시작부가 재대조) — evaluate.R · evaluate_fixture.R · round_rules.R 은 판정 구현 쪽이 만든다(이름만 맞춘다)
  EVALF <- c("evaluate.R", "evaluate_fixture.R", "precheck.R", "measure.sh", "measure_now.sh", "measure_now_vram.sh", "fingerprint.sh", "round_rules.R")
  PIN_CATS <- "lean:entropy"                                                     # E3 RX0 비중(엔진 정의)
  PKGS <- c("bbdetection", "PerformanceAnalytics", "data.table", "arrow")        # arrow = 처치 팩터 적재(load_month_factors 의 Arrow 읽기)
  ## 검사 — 증분 알파(⑦) · 셀 엔진 실행(팩터 결합 · 혼합 경로) · 팩터 적재 결과 동일성(처치 원천) · 판정 픽스처
  TESTF <- c("08_Tests/programs/test_round_kit_pair_alpha.R", "08_Tests/reinforcement/test_rf_cell_engine_smoke.R",
             "08_Tests/factor_db/test_fdc_read_fastpath.R", paste0(RD_REL, "/evaluate_fixture.R"))
  ## 장치 표(DESIGN §3) — 사양 · 등록 · 알림이 같은 이름을 쓴다(판정은 사전등록 variants · cells 를 읽는다)
  DEV <- list(
    H1 = list(factor = "D04_Downside_Beta", name = "하방β 틸트",
              basis = "Ang, Chen & Xing (2006) Downside Risk, RFS 19(4) — 하방β: 원값 = −(시장 하락일만으로 추정한 β)"),
    H2 = list(factor = "D03_RealVol", name = "저변동 틸트",
              basis = "Blitz & van Vliet (2007) The Volatility Effect, JPM 34(1) · Frazzini & Pedersen (2014) Betting Against Beta, JFE 111(1) — 저변동: 원값 = −(252일 실현 변동성) · P2R02 C4 재시험(이 축 · β 짝)"),
    H3 = list(factor = "D07_Beta_Asymmetry", name = "β 비대칭 틸트",
              basis = "Ang, Chen & Xing (2006) Downside Risk, RFS 19(4)(상승 · 하락 β 비대칭) — β 비대칭: 원값 = 상승β − 하락β(클수록 오를 때 더 오르고 내릴 때 덜 내림) · 철학 '비대칭'의 종목 수준 대응"),
    H4 = list(factor = "Q08_Composite_Quality", name = "퀄리티 틸트",
              basis = "Asness, Frazzini & Pedersen (2019) Quality minus junk, RAS 24 — 퀄리티: 원값 = 복합 퀄리티(GPA · ROE · ROA · 발생액) · P2R02 C5 재시험(이 축 · β 짝)"))
  ENG <- list(E2 = list(src = "P2R03_E2_RX0", base_weighting = "EW(동일 비중 · 25종)"),
              E3 = list(src = "P2R03_E3_RX0", base_weighting = "lean:entropy(엔진 자체 엔트로피 비중 · 순위 버퍼 2배 · B6_36 정의)"))
  N_ROUND <- length(ENG) * length(DEV)                                           # 시행 수 가산 칸 = 장치 칸(RX0 · 진단 무가산)
  ## 진단 칸(시행 수 무가산 · 판정 표 밖 · 선택 대상 아님 · 2계층 모듈 풀 미등재) — 접두 + 장치 번호(C1 = H1 의 팩터 …) · N0 = 장치 무관 1칸
  DIAG <- list(
    C = list(control = "missing_pair", engines = "E2", tag = "결측 짝(커버리지 필터만)", per_device = TRUE, weight = "dnn_only",
             challenge = c(E2 = "C-20261018-016"),
             purpose = "셀 엔진의 팩터 내부 병합(rf_cell_engine.R §3 merge · inner join)이 만드는 '팩터 결측 종목 제외' 효과만 분리 — 점수는 DNN 100%"),
    W = list(control = "capacity_pair", engines = c("E2", "E3"), tag = "용량 짝(12.5%)", per_device = TRUE, weight = "toolbox",
             challenge = c(E2 = "C-20261018-018", E3 = "C-20261018-027"),
             purpose = "도구 상자 기본 방어 몫(E3 RX0 + 장치 팩터 1 · w0 0.5 → 12.5%)을 두 구성에 줘 세기 의존(장치 50% 대비)을 가른다"),
    N = list(control = "dilution_pair", engines = "E2", tag = "희석 짝(무작위 순열 50%)", per_device = FALSE, weight = "device_e2",
             challenge = c(E2 = "C-20261018-021"), factor = list(kind = "null_perm", id = "null_perm_s20261018", seed = 20261018L),
             purpose = "방어 내용 없는 50% 혼합(셀 엔진 null_perm · 월별 시드 · 패널 멤버십 그대로라 결측 필터 없음) — ① 개선 중 희석 몫을 읽는다"))
  ENGINE_NULL_PERM_MARK <- 'identical(fs$kind, "null_perm")'                     # 엔진 null_perm 분기 존재 확인용(rf_cell_engine.R §3)
  .or <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
  md5f <- function(f) unname(as.character(tools::md5sum(f)))
  cj <- function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA))
  read_spec <- function(f) tryCatch(jsonlite::fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)
  ## 혼합 몫 유도(새 숫자 없음) — rf_cell_engine §4: Score = w·z(DNN) + (1 − w)·평균 z(팩터 열 n + r) · 장치 팩터 r 회 나열이면 방어 몫 = (1 − w)·r/(n + r)
  ##   s = 장치 방어 몫 = E2 장치(E2 RX0 + 장치 팩터 1 · w0_E2)의 몫 · t = 도구 상자 기본 몫 = E3 RX0 + 장치 팩터 1(w0_E3)의 몫 (1 − w0_E3)/(n_E3 + 1)
  ##   장치(H): 기존 팩터 없는 엔진 = w 1 − s · r 1 / 있는 엔진 = DNN : 기존 = w0 : (1 − w0) 를 지키며 w = (1 − s)·w0 · r = n·s / ((1 − s)(1 − w0))(정수여야 한다)
  ##   용량 짝(W): r 1 · w = 1 − t·(n + 1) · 결측 짝(C): r 1 · w 1 · 희석 짝(N): null_perm 1열 · w = E2 장치 w
  mix_plan <- function(SRC) {
    e2 <- SRC[["E2"]]; e3 <- SRC[["E3"]]
    w0_2 <- as.numeric(e2$base_weight); n_2 <- length(e2$factors); w0_3 <- as.numeric(e3$base_weight); n_3 <- length(e3$factors)
    s <- (1 - w0_2) * 1 / (n_2 + 1); t <- (1 - w0_3) * 1 / (n_3 + 1)
    out <- list(s = s, t = t, engines = list())
    for (e in names(SRC)) {
      w0 <- as.numeric(SRC[[e]]$base_weight); n <- length(SRC[[e]]$factors)
      if (n == 0L) { hw <- 1 - s; hr <- 1 } else { hw <- (1 - s) * w0; hr <- n * s / ((1 - s) * (1 - w0)) }
      if (!is.finite(hr) || abs(hr - round(hr)) > 1e-9 || round(hr) < 1) stop(sprintf("[P2R04 mix_plan] %s 장치 반복 수 %s 가 양의 정수가 아니다", e, format(hr)))
      out$engines[[e]] <- list(n_base = n, w0 = w0, H = list(w = hw, r = as.integer(round(hr))), C = list(w = 1, r = 1L),
                               W = list(w = 1 - t * (n + 1), r = 1L), N = list(w = 1 - s, r = 1L))
    }
    out
  }
  ## 칸 계획 — 엔진마다 RX0 → 장치 → 진단(DIAG 순). 반환 = 칸 목록(code · engine · component · role · device · diag)
  plan <- function() {
    out <- list()
    for (e in names(ENG)) {
      out[[length(out) + 1L]] <- list(code = sprintf("P2R04_%s_RX0", e), engine = e, component = "RX0", role = "reference")
      for (k in names(DEV)) out[[length(out) + 1L]] <- list(code = sprintf("P2R04_%s_%s", e, k), engine = e, component = k, role = "variant", device = k)
      for (g in names(DIAG)) if (e %in% DIAG[[g]]$engines) {
        if (isTRUE(DIAG[[g]]$per_device)) for (i in seq_along(DEV)) {
          comp <- sprintf("%s%d", g, i)
          out[[length(out) + 1L]] <- list(code = sprintf("P2R04_%s_%s", e, comp), engine = e, component = comp, role = "diagnostic", diag = g, device = names(DEV)[i])
        } else out[[length(out) + 1L]] <- list(code = sprintf("P2R04_%s_%s0", e, g), engine = e, component = paste0(g, "0"), role = "diagnostic", diag = g)
      }
    }
    out
  }
  ## 시행 회계 — 계보(family_root)마다 앞선 모든 사전등록 칸의 n_family 최댓값(이 라운드 사전등록은 뺀다 · P2R03 nf_prior 와 같은 규칙)
  nf_prior <- function(root, fam) {
    pp <- Sys.glob(file.path(root, "stage_artifacts/programs/*/*/prereg.json"))
    pp <- pp[basename(dirname(pp)) != ROUND]
    v <- unlist(lapply(pp, function(p) {
      d <- tryCatch(jsonlite::fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
      ok <- Filter(function(z) is.numeric(z$n_family) && !is.null(z$path) &&
                     identical(.or(read_spec(file.path(root, z$path))$selection_accounting$family_root, NA_character_), fam), .or(d$cells, list()))
      vapply(ok, function(z) as.integer(z$n_family), integer(1))
    }))
    if (length(v)) max(v) else 0L
  }
  ## 사양 기계 검사(칸 계획 전부) — 반환 = list(ok, errors, cells(칸 기록 · 사전등록 cells 의 원천), n_round, n_cells, mix).
  ##   rx_validate(엔진 파서 · 등록부)는 처방 레인 검증 경로 그대로 — 같은 팩터 id 중복을 막지 않는다(id 어휘 · kind 만 본다) ·
  ##   null_perm 팩터는 rx_validate 어휘(db 만) 밖이라 엔진 분기의 seed 규칙으로 따로 본다
  spec_checks <- function(root, epoch_id) {
    if (!exists("rx_validate", mode = "function")) source(file.path(root, "02_Infrastructure/programs/rx_round.R"))
    err <- character(0); add <- function(...) err <<- c(err, paste0(...))
    strip <- function(s, drop) s[setdiff(names(s), drop)]
    SRC <- lapply(ENG, function(g) read_spec(file.path(root, P2R03_SPECS, paste0(g$src, ".json"))))
    for (e in names(SRC)) if (is.null(SRC[[e]])) add(e, ": 원형 사양 판독 실패 — ", ENG[[e]]$src)
    if (length(err)) return(list(ok = FALSE, errors = err, cells = list(), n_round = N_ROUND, n_cells = 0L))
    MX <- tryCatch(mix_plan(SRC), error = function(z) { add(conditionMessage(z)); NULL })
    if (is.null(MX)) return(list(ok = FALSE, errors = err, cells = list(), n_round = N_ROUND, n_cells = 0L))
    eng_src <- paste(readLines(file.path(root, "02_Infrastructure/reinforcement/rf_cell_engine.R"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
    cells <- list(); pl <- plan(); NFP <- list()                                # NFP = 계보별 앞선 최댓값(한 번만 센다)
    for (p in pl) {
      src <- SRC[[p$engine]]; code <- p$code; mx <- MX$engines[[p$engine]]
      fam <- as.character(.or(src$selection_accounting$family_root, NA_character_))
      rp <- sprintf("%s/specs/%s.json", RD_REL, code); f <- file.path(root, rp)
      s <- if (file.exists(f)) read_spec(f) else NULL
      if (is.null(s)) { add(code, ": 사양 없음 또는 JSON 판독 실패"); next }
      if (!identical(s$code, code)) add(code, ": code 불일치(", .or(s$code, "NULL"), ")")
      if (!identical(s$fixed_axes$measurement_axis, epoch_id)) add(code, ": 측정 축 ", .or(s$fixed_axes$measurement_axis, "NULL"), " ≠ 활성 epoch ", epoch_id)
      if (!is.null(s$overlay) || !is.null(s$overlay_shift)) add(code, ": 오버레이 키가 있다(이 라운드는 오버레이 없음)")
      fk <- vapply(.or(s$factors, list()), function(z) as.character(.or(z$kind, "")), character(1))
      axn <- intersect(c("factors", "weighting", "universe", "rebalance", "defense_sleeve", "cap_core"), names(s))
      if (any(fk == "null_perm")) axn <- setdiff(axn, "factors")              # null_perm 은 아래 엔진 규칙으로
      ax <- Filter(Negate(is.null), s[axn])
      v <- tryCatch(rx_validate(ax, root), error = function(z) list(ok = FALSE, errors = conditionMessage(z)))
      if (!isTRUE(v$ok)) add(code, ": 축 검증(rx_validate) 실패 — ", paste(v$errors, collapse = " | "))
      dv <- if (!is.null(p$device)) DEV[[p$device]] else NULL
      dg <- if (!is.null(p$diag)) DIAG[[p$diag]] else NULL
      ## 기대값 — 팩터 나열 · base_weight(mix_plan) · 시행 회계
      rule <- if (identical(p$role, "reference")) list(w = as.numeric(src$base_weight), r = 0L) else if (identical(p$role, "variant")) mx$H else mx[[p$diag]]
      dfac <- if (!is.null(dv)) list(kind = "db", id = dv$factor) else if (!is.null(dg$factor)) dg$factor else NULL
      want_f <- c(src$factors, if (!is.null(dfac) && rule$r > 0L) rep(list(dfac), rule$r))
      if (!identical(cj(s$factors), cj(want_f))) add(code, sprintf(": factors ≠ 기대(RX0 factors + %s × %d)", .or(dfac$id, "-"), as.integer(rule$r)))
      w_top <- suppressWarnings(as.numeric(s$base_weight)); w_ax <- suppressWarnings(as.numeric(s$fixed_axes$base_weight))
      if (!isTRUE(all.equal(w_top, rule$w)) || !isTRUE(all.equal(w_ax, rule$w))) add(code, sprintf(": base_weight(최상위 %s · fixed_axes %s) ≠ 기대 %s", format(w_top), format(w_ax), format(rule$w)))
      if (any(fk == "null_perm")) {                                           # 엔진 null_perm 분기 규칙(seed = 정수 1개) · 분기 존재
        np <- s$factors[[which(fk == "null_perm")[1]]]
        sd <- suppressWarnings(as.integer(.or(np$seed, NA)))
        if (length(sd) != 1L || is.na(sd)) add(code, ": null_perm seed 가 정수 1개가 아니다")
        if (!grepl(ENGINE_NULL_PERM_MARK, eng_src, fixed = TRUE)) add(code, ": 셀 엔진에 null_perm 분기가 없다")
        if (any(fk != "null_perm" & fk != "db")) add(code, ": 팩터 kind 는 db · null_perm 만")
      }
      ## RX0 와 같아야 하는 나머지 — 비교에서 빼는 키: 이름 · 서술 · 회계 · 팩터 · base_weight 두 곳(값은 위에서 단정)
      s2 <- s; s2$base_weight <- src$base_weight; s2$fixed_axes$base_weight <- src$fixed_axes$base_weight
      if (identical(p$role, "reference")) {
        if (!identical(cj(strip(s, c("code", "label"))), cj(strip(src, c("code", "label"))))) add(code, ": ", ENG[[p$engine]]$src, " 사양과 code · label 밖이 다르다")
      } else {
        keep <- c("code", "label", "idea", "selection_accounting", "factors")
        if (!identical(cj(strip(s2, keep)), cj(strip(src, keep)))) add(code, ": RX0 사양과 factors · base_weight · 이름 · 서술 · 회계 밖이 다르다")
      }
      sa <- s$selection_accounting; n0 <- NA_integer_; nf <- NULL
      if (identical(p$role, "variant")) {
        if (is.null(NFP[[fam]])) NFP[[fam]] <- nf_prior(root, fam)
        n0 <- NFP[[fam]]
        if (!identical(sa$selection_type, "sweep") || !identical(sa$family_root, fam)) add(code, ": 시행 회계 selection_type · family_root 불일치")
        if (!identical(as.character(unlist(sa$lineage)), c(paste0("RX_", ROUND), as.character(unlist(src$selection_accounting$lineage)))))
          add(code, ": 시행 회계 lineage ≠ RX_", ROUND, " + RX0 계보")
        if (!identical(suppressWarnings(as.integer(sa$n_family_at_registration)), as.integer(n0 + N_ROUND)))
          add(code, sprintf(": 시행 회계 n_family %s ≠ 앞선 사전등록 계보 최댓값 %d + 이 라운드 장치 칸 %d", format(.or(sa$n_family_at_registration, "NULL")), n0, N_ROUND))
        if (!grepl(dv$factor, .or(s$label, ""), fixed = TRUE) || !grepl(dv$factor, .or(s$idea, ""), fixed = TRUE)) add(code, ": label · idea 에 팩터 id 없음")
        if (rule$r > 1L && !grepl(sprintf("장치 팩터 %d회 나열", rule$r), .or(s$label, ""), fixed = TRUE)) add(code, sprintf(": label 에 '장치 팩터 %d회 나열' 없음", rule$r))
        nf <- as.integer(n0 + N_ROUND)
      } else if (identical(p$role, "diagnostic")) {
        sa0 <- src$selection_accounting; sa0$remeasure_of <- NULL; sa0$n_trials_note <- NULL
        want_sa <- c(sa0, if (!is.null(dv)) list(diagnostic_of = sprintf("P2R04_%s_%s", p$engine, p$device)),
                     list(control = dg$control, challenge = unname(dg$challenge[[p$engine]])))
        got_sa <- sa[intersect(names(sa), names(want_sa))]
        if (!identical(cj(got_sa[names(want_sa)]), cj(want_sa)) || !nzchar(.or(sa$n_trials_note, "")) ||
            length(setdiff(names(sa), c(names(want_sa), "n_trials_note"))))
          add(code, ": 진단 시행 회계 ≠ RX0 회계(무가산 · remeasure_of 제외) + diagnostic_of · control · challenge · n_trials_note")
        if (!grepl(dg$tag, .or(s$label, ""), fixed = TRUE)) add(code, ": label 에 '", dg$tag, "' 없음")
        if (!is.null(dv) && !grepl(dv$factor, .or(s$label, ""), fixed = TRUE)) add(code, ": label 에 팩터 id 없음")
      }
      w0 <- suppressWarnings(as.numeric(s$base_weight)); nfac <- length(s$factors)
      r_dev <- if (!is.null(dfac)) sum(vapply(.or(s$factors, list()), function(z) identical(cj(z), cj(dfac)), logical(1))) else 0L
      cells[[code]] <- list(code = code, engine = p$engine, component = p$component, role = p$role, path = rp, md5 = md5f(f),
                            device = p$device, factor = if (!is.null(dv)) dv$factor else NULL, control = if (!is.null(dg)) dg$control else NULL,
                            diagnostic_of = if (!is.null(dg) && !is.null(dv)) sprintf("P2R04_%s_%s", p$engine, p$device) else NULL,
                            challenge = if (!is.null(dg)) unname(dg$challenge[[p$engine]]) else NULL,
                            n_family = nf, n_prior = n0, n_factors = nfac, base_weight = w0, device_repeat = r_dev,
                            device_share = if (r_dev > 0L && !is.null(dv)) (1 - w0) * r_dev / nfac else if (!is.null(dv)) 0 else NULL,
                            dilution_share = if (!is.null(dg) && identical(dg$control, "dilution_pair")) (1 - w0) * r_dev / nfac else NULL,
                            spec_copy_of = if (identical(p$role, "reference")) ENG[[p$engine]]$src else NULL,
                            remeasure_of = if (identical(p$role, "reference")) src$selection_accounting$remeasure_of else NULL)
    }
    list(ok = !length(err), errors = err, cells = cells, n_round = N_ROUND, n_cells = length(pl), mix = MX)
  }
  list(PROGRAM = PROGRAM, ROUND = ROUND, RD_REL = RD_REL, P2R03_SPECS = P2R03_SPECS, P2R03_PREREG = P2R03_PREREG, OPS = OPS, FACTOR_REGISTRY = FACTOR_REGISTRY,
       EVALF = EVALF, PIN_CATS = PIN_CATS, PKGS = PKGS, TESTF = TESTF, DEV = DEV, ENG = ENG, N_ROUND = N_ROUND, DIAG = DIAG,
       mix_plan = mix_plan, plan = plan, nf_prior = nf_prior, spec_checks = spec_checks)
})
K <- P2R04_CONST

source("02_Infrastructure/programs/rx_round.R")
source("02_Infrastructure/programs/program_registry.R")
source("02_Infrastructure/contracts/measurement_axis.R")
source(file.path(ROOT, "04_Research/programs/_lib/round_kit.R"))
args <- commandArgs(trailingOnly = TRUE)
MODE <- if ("--register" %in% args) "register" else if ("--draft" %in% args) "draft" else stop("usage: register.R --draft | --register")
PROGRAM <- K$PROGRAM; ROUND <- K$ROUND
DRAFT_VERSION <- 3L                                                             # 초안을 고쳐 다시 쓸 때 올린다(검토판 보존본과 짝) · v2 = 격리 교차 점검 v1 반영 · v3 = 점검 v2 반영(R7 판정 장치 정의 · 판독 불가 문장 · 등록 관문)
rel <- function(p) sub(paste0("^", ROOT, "/"), "", p)
P <- rx_paths(PROGRAM, ROUND, ROOT); RD <- P$round_dir
if (!identical(rel(RD), K$RD_REL)) stop("[P2R04] 라운드 디렉터리 해석 불일치: ", RD)
PR <- file.path(P$prereg_dir, "prereg.json"); DR <- file.path(RD, "prereg_draft.json")
.measured_any <- function() length(Sys.glob(file.path(RD, "results", "P2R04_*.json"))) > 0L
if (.measured_any()) stop("[P2R04] 측정 결과가 생긴 뒤에는 사전등록을 바꿀 수 없다(R2)")
if (file.exists(PR)) stop("[P2R04] 사전등록이 이미 있다(R2) — 대체는 측정 전 · 별도 절차로만")
source(file.path(RD, "round_rules.R"))                                          # p2r04_final_selection_rule(+ 있으면 p2r04_rules)
if (!exists("p2r04_final_selection_rule", mode = "function")) stop("[P2R04] round_rules.R 에 p2r04_final_selection_rule() 이 없다")
## 격리 교차 점검을 받은 초안 보존본(있으면 등록판에 연결 — 없으면 --register 거부)
REVIEWED <- Filter(function(z) file.exists(z$path), list(
  list(version = 1L, path = file.path(RD, "prereg_draft_reviewed_v1.json"), review = "격리 교차 점검 v1(결과 미열람 · 설계 · 구현 비참여 서브에이전트) — revise(필수 6 · 권고 11 · 선택 7 · prereg_draft_review_v1.md)"),
  list(version = 2L, path = file.path(RD, "prereg_draft_reviewed_v2.json"), review = "격리 변경분 점검(v1 → v2 · 결과 미열람)"),
  list(version = 3L, path = file.path(RD, "prereg_draft_reviewed_v3.json"), review = "격리 변경분 점검(v2 → v3 · 좁은 범위)")))
## 초안 v(n) 을 쓰기 전에 점검받은 v(n − 1) 보존본이 있어야 한다 — 없으면 새 초안이 점검받은 초안을 덮어 --register 가 연결할 보존본을 잃는다
if (MODE == "draft" && DRAFT_VERSION > 1L && !file.exists(file.path(RD, sprintf("prereg_draft_reviewed_v%d.json", DRAFT_VERSION - 1L))))
  stop(sprintf("[P2R04] 초안 v%d 을 쓰기 전에 점검받은 v%d 초안을 prereg_draft_reviewed_v%d.json 으로 보존해야 한다(현 prereg_draft.json 을 그대로 복사)",
               DRAFT_VERSION, DRAFT_VERSION - 1L, DRAFT_VERSION - 1L))
cj <- function(x) as.character(toJSON(x, auto_unbox = TRUE, null = "null", digits = NA))
LEDGER <- file.path(ROOT, "06_Registry/q_judgment_ledger.json")
J_ROUND_SELECTION <- "J-20261018-003"                                           # 라운드 선택(판단 원장 · 아래에서 존재 · 종류를 단정)
P1_FILE_RX <- "^04_Research/programs/_supervision/superfan/philosophy/[^/]+_P1_P2R04\\.md$"
BCP <- file.path(RD, "behavior_card_cfg_at_prereg.json")
FS_KEYS <- c("calmar_norm", "port_t_norm", "w_calmar", "w_port_t", "tie_eps", "uc_floor", "majority_share", "crisis_improve_min", "alpha_t_floor",
             "alpha_margin_frac", "single_name_loss_floor", "bull_ratio", "fast_window_days", "fast_drop")   # 구현 계약 §10 — P2R03 과 같은 이름 · 같은 값
FS_RECORD_KEYS <- c("state_unturned_max_drop_crises", "from_top_crises")       # 기록용 위기 목록(round_rules.R 현행 이름 · 구 이름) — 하나는 있어야 한다

.factor_ids <- function(sc) sort(unique(unlist(lapply(sc$cells, function(z) {
  s <- fromJSON(file.path(ROOT, z$path), simplifyVector = FALSE)
  vapply(Filter(function(f) identical(f$kind, "db"), s$factors %||% list()), function(f) as.character(f$id), character(1)) }))))
.ops_pins <- function(sc) {
  miss <- K$OPS[!file.exists(file.path(ROOT, K$OPS))]
  if (length(miss)) stop("[P2R04] 운영 경로 파일 없음: ", paste(miss, collapse = ", "))
  wc <- fromJSON(file.path(ROOT, "06_Registry/weight_catalog.json"), simplifyVector = FALSE)$entries
  ents <- lapply(K$PIN_CATS, function(cid) { e <- Filter(function(z) identical(z$catalog_id, cid), wc)
    if (!length(e)) stop("[P2R04] 비중 카탈로그 엔트리 없음: ", cid)
    if (!identical(e[[1]]$status, "active")) stop("[P2R04] 비중 카탈로그 엔트리 status ≠ active: ", cid)
    list(catalog_id = cid, status = e[[1]]$status, resolver = e[[1]]$resolver) })
  FR <- fromJSON(file.path(ROOT, K$FACTOR_REGISTRY), simplifyVector = FALSE)
  fre <- lapply(.factor_ids(sc), function(id) { if (is.null(FR[[id]])) stop("[P2R04] 팩터 레지스트리에 없는 팩터: ", id)
    list(id = id, path = K$FACTOR_REGISTRY, entry = FR[[id]]) })
  list(files = lapply(K$OPS, function(f) list(path = f, md5 = rk_md5(file.path(ROOT, f)))), catalog_entries = ents, factor_registry_entries = fre,
       packages = setNames(lapply(K$PKGS, function(p) as.character(utils::packageVersion(p))), K$PKGS),
       r_version = R.version.string)
}
.eval_pins <- function() lapply(K$EVALF, function(f) { p <- file.path(RD, f)
  if (!file.exists(p)) stop("[P2R04] 평가 경로 파일 없음(판정 구현 · 측정 절차를 결과 전에 고정해야 한다): ", rel(p))
  list(path = rel(p), md5 = rk_md5(p)) })
REH <- file.path(RD, "rehearsal", "summary.json")
.rehearsal <- function() {
  if (!file.exists(REH)) stop("[P2R04] 리허설 요약이 없다 — Rscript rehearse.R 먼저")
  s <- fromJSON(REH, simplifyVector = FALSE)
  if (!isTRUE(s$pass)) stop("[P2R04] 리허설 실패 — 등록하지 않는다")
  if (!identical(s$evaluate_md5, rk_md5(file.path(RD, "evaluate.R")))) stop("[P2R04] 리허설 뒤 evaluate.R 이 바뀌었다 — 다시 리허설")
  list(script = list(path = rel(file.path(RD, "rehearse.R")), md5 = rk_md5(file.path(RD, "rehearse.R"))), summary = list(path = rel(REH), md5 = rk_md5(REH)),
       evaluate_md5 = s$evaluate_md5, pass = TRUE, inputs = s$inputs, seconds = s$seconds)
}
## 판정 구현(evaluate.R)과의 정합 — 격리 환경에 도우미만 적재해(본 실행 블록은 sys.nframe 가드) 사전등록이 평가 시작부 단정을 통과하는지 결과 전에 확인한다:
##   final_selection_rule 키(P2R04_FS_KEYS) · 칸 목록(p2_cells_check) · 운영 핀(p2_pin_mismatches — 대조 함수 없는 핀 종류 포함). 함수가 없으면 그 항목은 '미확인'으로 싣는다
.eval_consistency <- function(pre_like) {
  E <- new.env(parent = globalenv())
  e <- tryCatch({ source(file.path(RD, "evaluate.R"), local = E); NULL }, error = function(z) conditionMessage(z))
  if (!is.null(e)) stop("[P2R04] evaluate.R 적재 실패 — 정합 확인 불가: ", e)
  has <- function(n) exists(n, envir = E, inherits = FALSE)
  out <- list(evaluate_md5 = rk_md5(file.path(RD, "evaluate.R")))
  out$fs_keys <- if (has("P2R04_FS_KEYS")) { m <- setdiff(get("P2R04_FS_KEYS", envir = E), names(pre_like$final_selection_rule)); if (length(m)) paste("결손:", paste(m, collapse = ",")) else "ok" } else "미확인(P2R04_FS_KEYS 없음)"
  out$cells_check <- if (has("p2_cells_check")) { m <- get("p2_cells_check", envir = E)(pre_like$cells); if (length(m)) paste(m, collapse = " / ") else "ok" } else "미확인(p2_cells_check 없음)"
  out$pins <- if (has("p2_pin_mismatches")) { m <- get("p2_pin_mismatches", envir = E)(pre_like, ROOT); if (length(m)) paste(m, collapse = " / ") else "ok" } else "미확인(p2_pin_mismatches 없음)"
  out$ok <- all(vapply(out[c("fs_keys", "cells_check", "pins")], function(x) identical(x, "ok"), logical(1)))
  out
}
## 철학 Superfan P1 수령 확인(P2R03 과 같은 방식 · 등록 전 기계 확인) — 판단 원장에 이 라운드의 P1 리뷰(role philosophy · trigger P1 · round = ROUND)가 있고,
##   그 리뷰 파일이 04_Research/programs/_supervision/superfan/philosophy/<시각>_P1_P2R04.md 로 실재하며, 리뷰의 도전 · 정지 항목이 모두 Q 응답을 받았고
##   (status ≠ open) 열린 보류 요청이 없어야 한다. 거부권이 아니라 '건너뛸 수 없음'이다(응답은 수용 · 반박 모두 가능 · superfan_protocol §11).
.p1_check <- function() {
  L <- tryCatch(fromJSON(LEDGER, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(L)) return(list(ok = FALSE, why = "판단 원장 판독 실패"))
  rv <- Filter(function(r) identical(r$role, "philosophy") && identical(r$trigger, "P1") && identical(r$round, ROUND), L$reviews %||% list())
  if (!length(rv)) return(list(ok = FALSE, why = sprintf("이 라운드(%s)의 철학 P1 리뷰가 원장에 없다", ROUND)))
  fl <- vapply(rv, function(r) as.character(r$file %||% NA_character_), character(1))
  bad_f <- fl[is.na(fl) | !grepl(P1_FILE_RX, fl, perl = TRUE) | !file.exists(file.path(ROOT, fl))]
  if (length(bad_f)) return(list(ok = FALSE, why = paste("P1 리뷰 파일이 없거나 이름 형식(…/philosophy/<시각>_P1_P2R04.md)이 아니다:", paste(bad_f, collapse = ","))))
  ids <- unique(unlist(lapply(rv, function(r) unlist(r$challenges))))
  ch <- Filter(function(c) c$id %in% ids && (c$grade %||% "") %in% c("challenge", "stop"), L$challenges %||% list())
  open <- vapply(Filter(function(c) identical(c$status, "open") || !length(c$responses), ch), function(c) c$id, character(1))
  hold <- vapply(Filter(function(c) isTRUE(c$hold_request) && !(c$status %in% c("accepted", "withdrawn", "escalated", "settled")), ch), function(c) c$id, character(1))
  if (length(open)) return(list(ok = FALSE, why = paste("응답 없는 도전:", paste(open, collapse = ","))))
  if (length(hold)) return(list(ok = FALSE, why = paste("열린 보류 요청:", paste(hold, collapse = ","))))
  list(ok = TRUE, reviews = vapply(rv, function(r) r$id, character(1)), files = fl, n_challenges = length(ch),
       statuses = setNames(vapply(ch, function(c) c$status %||% NA_character_, character(1)), vapply(ch, function(c) c$id, character(1))),
       checked_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
}
## 판단 · 리뷰 연결 — 라운드 선택 판단은 고정 id 를 원장에서 단정하고, 이 라운드의 리뷰(round = ROUND · 그리고 라운드 선택 판단을 대상으로 한 리뷰)는 원장에서 읽는다
.judgments <- function() {
  L <- fromJSON(LEDGER, simplifyVector = FALSE)
  j <- Filter(function(x) identical(x$id, J_ROUND_SELECTION), L$judgments %||% list())
  if (!length(j) || !identical(j[[1]]$kind, "round_selection")) stop("[P2R04] 판단 원장에 라운드 선택 판단 ", J_ROUND_SELECTION, "(kind round_selection)이 없다")
  tgt <- function(r) J_ROUND_SELECTION %in% unlist(r$scope %||% list())
  rv <- Filter(function(r) identical(r$round, ROUND) || tgt(r), L$reviews %||% list())
  list(round_selection = J_ROUND_SELECTION, ledger = rel(LEDGER), design = paste0(K$RD_REL, "/DESIGN.md"),
       reviews = lapply(rv, function(r) list(id = r$id, role = r$role, trigger = r$trigger, file = r$file %||% NA_character_)))
}
## 커밋 확인 대상 — 비중 카탈로그 · 팩터 레지스트리 파일은 빼고 쓰이는 엔트리를 내용으로 핀한다(operational_pins) — 무인 작업이 다른 엔트리를 쓰면
##   파일 전체가 '미커밋'이 되어 등록을 막지만 판정에 닿는 것은 그 엔트리뿐이다(P2R03 승계)
COMMIT_PATHS <- unique(c(K$TESTF, K$RD_REL, K$OPS))
.uncommitted <- function() {
  s <- suppressWarnings(system2("git", c("-C", ROOT, "status", "--porcelain", "--", COMMIT_PATHS), stdout = TRUE, stderr = FALSE))
  st <- attr(s, "status")
  if (!is.null(st) && !identical(as.integer(st), 0L)) stop("[P2R04] git status 실패(rc ", st, ") — 커밋 상태를 확인할 수 없다")
  s <- s[nzchar(s)]; s[!grepl("prereg_draft|results/|rehearsal/out", s)]
}
.git_head <- function() {
  h <- suppressWarnings(system2("git", c("-C", ROOT, "rev-parse", "HEAD"), stdout = TRUE, stderr = FALSE))
  st <- attr(h, "status"); if ((!is.null(st) && !identical(as.integer(st), 0L)) || !length(h)) NA_character_ else h[1]
}
.run_test <- function(path) {
  o <- suppressWarnings(system2("Rscript", c("--no-environ", shQuote(path)), stdout = TRUE, stderr = TRUE))   # QM_ROOT = 위 Sys.setenv 상속(Windows 에서 system2(env=) 는 Rscript 에 안 먹는다)
  j <- grep('^\\{"test"', o, value = TRUE)
  if (length(j)) { r <- fromJSON(j[length(j)]); return(list(path = rel(path), md5 = rk_md5(path), pass = r$pass, fail = r$fail)) }
  list(path = rel(path), md5 = rk_md5(path), pass = NA, fail = NA)
}
## 사전등록 cells — 칸 기록(spec_checks)에서. reference = RX0 · diagnostic = 진단 13(판정 표 밖) · n_family = 장치만(RX0 · 진단 = NA → 앞으로의 시행 회계에 안 든다)
.cells_of <- function(sc) unname(lapply(sc$cells, function(z) {
  c(list(code = z$code, engine = z$engine, component = z$component, path = z$path, md5 = z$md5,
         n_family = if (identical(z$role, "variant")) z$n_family else NA, reference = identical(z$role, "reference"), diagnostic = identical(z$role, "diagnostic")),
    if (identical(z$role, "variant")) list(device = z$device, factor = z$factor, base_weight = z$base_weight, device_repeat = z$device_repeat, defense_share = z$device_share),
    if (identical(z$role, "diagnostic")) c(list(control = z$control, challenge = z$challenge),
                                           if (!is.null(z$diagnostic_of)) list(diagnostic_of = z$diagnostic_of, device = z$device, factor = z$factor, defense_share = z$device_share),
                                           if (!is.null(z$dilution_share)) list(dilution_share = z$dilution_share),
                                           list(base_weight = z$base_weight)),
    if (identical(z$role, "reference")) list(spec_copy_of = z$spec_copy_of, remeasure_of = z$remeasure_of))
}))

if (MODE == "register") {
  if (!file.exists(DR)) stop("[P2R04] 초안이 없다 — --draft 먼저")
  if (!length(REVIEWED)) stop("[P2R04] 격리 교차 점검 보존본이 없다 — 점검 뒤 등록")
  .last_rev <- file.path(RD, sprintf("prereg_draft_reviewed_v%d.json", DRAFT_VERSION))   # 격리 점검 v2 권고 3 — 등록할 초안 = 마지막으로 점검받은 판
  if (!file.exists(.last_rev)) stop(sprintf("[P2R04] 등록할 초안 v%d 의 점검받은 보존본(prereg_draft_reviewed_v%d.json)이 없다 — 점검 뒤 보존하고 등록", DRAFT_VERSION, DRAFT_VERSION))
  if (!identical(rk_md5(DR), rk_md5(.last_rev))) stop("[P2R04] 등록할 초안 md5 ≠ 마지막으로 점검받은 보존본 md5 — 점검받지 않은 초안은 등록하지 않는다")
  pre <- fromJSON(DR, simplifyVector = FALSE)
  if (!length(pre$changes_after_review)) stop("[P2R04] 교차 점검 반영 기록(changes_after_review)이 비었다")
  sc <- K$spec_checks(ROOT, ma_epoch(root = ROOT)$id)
  if (!isTRUE(sc$ok)) stop("[P2R04] 사양 검사 실패:\n", paste(sc$errors, collapse = "\n"))
  if (length(pre$cells) != sc$n_cells) stop("[P2R04] 초안 칸 수 ", length(pre$cells), " ≠ 칸 계획 ", sc$n_cells)
  for (c in pre$cells) if (!identical(rk_md5(file.path(ROOT, c$path)), c$md5)) stop("[P2R04] 사양 md5 ≠ 초안: ", c$code)
  now <- .ops_pins(sc)
  for (f in pre$operational_pins$files) {
    m <- Filter(function(z) identical(z$path, f$path), now$files)
    if (!length(m) || !identical(m[[1]]$md5, f$md5)) stop("[P2R04] 운영 경로 md5 ≠ 초안(초안 뒤 구현이 바뀌었다): ", f$path)
  }
  if (length(now$files) != length(pre$operational_pins$files)) stop("[P2R04] 운영 경로 목록 ≠ 초안(핀 목록이 바뀌었다 — 초안을 다시 쓴다)")
  if (!identical(now$packages, pre$operational_pins$packages) || !identical(now$r_version, pre$operational_pins$r_version)) stop("[P2R04] 패키지 · R 판 ≠ 초안")
  if (!identical(cj(now$catalog_entries), cj(pre$operational_pins$catalog_entries))) stop("[P2R04] 비중 카탈로그 엔트리 ≠ 초안")
  if (!identical(cj(now$factor_registry_entries), cj(pre$operational_pins$factor_registry_entries))) stop("[P2R04] 팩터 레지스트리 엔트리 ≠ 초안")
  for (f in pre$evaluation$files) if (!identical(rk_md5(file.path(ROOT, f$path)), f$md5)) stop("[P2R04] 평가 경로 md5 ≠ 초안: ", f$path)
  for (t in pre$tests) if (!identical(rk_md5(file.path(ROOT, t$path)), t$md5) || !identical(as.integer(t$fail), 0L)) stop("[P2R04] 검사 파일 변경 또는 실패: ", t$path)
  rh <- .rehearsal()
  if (!identical(rh$evaluate_md5, pre$rehearsal$evaluate_md5) || !identical(rh$summary$md5, pre$rehearsal$summary$md5) ||
      !identical(rh$script$md5, pre$rehearsal$script$md5)) stop("[P2R04] 리허설 기록(evaluate · 요약 · 리허설 스크립트 md5) ≠ 초안")
  if (!identical(rk_md5(file.path(ROOT, pre$behavior_card_cfg$path)), pre$behavior_card_cfg$md5)) stop("[P2R04] 행동 카드 설정 사본 md5 ≠ 초안")
  cc <- .eval_consistency(pre)
  if (!isTRUE(cc$ok)) stop("[P2R04] 판정 구현(evaluate.R)과 사전등록이 맞지 않는다 — 등록하지 않는다: FS ", cc$fs_keys, " · 칸 ", cc$cells_check, " · 핀 ", cc$pins)
  p1 <- .p1_check()                                                              # 철학 P1 수령 · 도전 응답 — 건너뛸 수 없게(도훈 10-17 '철학 Superfan 역할이 검토에서 끝이냐')
  if (!isTRUE(p1$ok)) stop("[P2R04] 철학 Superfan P1 조건 미충족 — 등록하지 않는다: ", p1$why)
  unc <- .uncommitted()
  if (length(unc)) stop("[P2R04] 커밋되지 않은 고정 대상이 있다 — 커밋 뒤 등록:\n", paste(unc, collapse = "\n"))
  pre$status <- "registered"; pre$registered_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"); pre$draft_md5 <- rk_md5(DR)
  pre$philosophy_p1 <- p1                                                        # 등록 시점 재확인 값(초안 때는 P1 전일 수 있다)
  pre$evaluate_consistency <- cc
  pre$reviewed_drafts <- lapply(REVIEWED, function(rv) list(version = rv$version, path = rel(rv$path), md5 = rk_md5(rv$path), review = rv$review))
  pre$git_head_at_register <- .git_head()
  dir.create(P$prereg_dir, recursive = TRUE, showWarnings = FALSE)
  RCOPY <- file.path(RD, "prereg.json")
  tryCatch({
    writeLines(toJSON(pre, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA), PR, useBytes = TRUE)
    if (!isTRUE(file.copy(PR, RCOPY, overwrite = TRUE)) || !identical(rk_md5(RCOPY), rk_md5(PR))) stop("라운드 디렉터리 사본 쓰기 실패 · md5 불일치")
    pr_record_round(PROGRAM, list(round_id = ROUND, prereg = rel(PR), prereg_md5 = rk_md5(PR), status = "registered",
                                  n_variants = length(Filter(function(z) !isTRUE(z$reference) && !isTRUE(z$diagnostic), pre$cells)),
                                  n_diagnostic = length(Filter(function(z) isTRUE(z$diagnostic), pre$cells)),
                                  variants = unname(vapply(pre$cells, function(z) z$code, character(1)))), root = ROOT)
  }, error = function(e) { unlink(c(PR, RCOPY)); stop("[P2R04] 등록 중단 — 사전등록 두 사본을 되돌렸다(등록부 미기록): ", conditionMessage(e)) })
  cat(sprintf("[P2R04] 사전등록 %s (md5 %s) · 사본 %s · 칸 %d(장치 %d · 기준 %d · 진단 %d) · HEAD %s\n", rel(PR), rk_md5(PR), rel(RCOPY), length(pre$cells),
              length(Filter(function(z) !isTRUE(z$reference) && !isTRUE(z$diagnostic), pre$cells)), length(Filter(function(z) isTRUE(z$reference), pre$cells)),
              length(Filter(function(z) isTRUE(z$diagnostic), pre$cells)), pre$git_head_at_register))
  quit(status = 0)
}

## ── 초안 ─────────────────────────────────────────────────────────────────────
##   순서 = 싼 결정론 점검 먼저(사양 · 평가 경로 파일 · 리허설 요약 · 규칙 상수 계약 · 판단 원장 · 판정 구현 정합) → 비싼 검사 실행(약 5분) 나중
EP <- ma_epoch(root = ROOT)
sc <- K$spec_checks(ROOT, EP$id)
if (!isTRUE(sc$ok)) stop("[P2R04] 사양 검사 실패 — 초안을 쓰지 않는다:\n", paste(sc$errors, collapse = "\n"))
EVP <- .eval_pins(); REHS <- .rehearsal(); JD <- .judgments(); OPP <- .ops_pins(sc)
if (!file.exists(BCP)) file.copy(file.path(ROOT, "06_Registry/behavior_card.json"), BCP, overwrite = FALSE)   # 리허설이 먼저 만들었으면 그 사본(같은 원본)
P3PRE <- fromJSON(file.path(ROOT, K$P2R03_PREREG), simplifyVector = FALSE)
FS <- p2r04_final_selection_rule(ROOT, BCP)
miss <- setdiff(c(FS_KEYS, "mc8_label_required"), names(FS))
if (length(miss)) stop("[P2R04] final_selection_rule 키 결손(구현 계약 §10): ", paste(miss, collapse = ", "))
FS_REC <- intersect(FS_RECORD_KEYS, names(FS))
if (!length(FS_REC) || !length(FS[[FS_REC[1]]])) stop("[P2R04] final_selection_rule 에 기록용 위기 목록(", paste(FS_RECORD_KEYS, collapse = " | "), ")이 없거나 비었다(DESIGN §5)")
dif <- FS_KEYS[!vapply(FS_KEYS, function(k) isTRUE(all.equal(as.numeric(FS[[k]]), as.numeric(P3PRE$final_selection_rule[[k]]))), logical(1))]
if (length(dif)) stop("[P2R04] final_selection_rule 값 ≠ P2R03(구현 계약 §10 '같은 값'): ", paste(dif, collapse = ", "))
if (!identical(FS$mc8_label_required, "selection_defense")) stop("[P2R04] final_selection_rule.mc8_label_required ≠ selection_defense(DESIGN §5 ⑭)")
MCJ <- fromJSON(file.path(ROOT, "06_Registry/matched_controls.json"), simplifyVector = FALSE)
CELLS <- .cells_of(sc)
CC <- .eval_consistency(list(cells = CELLS, final_selection_rule = FS, operational_pins = OPP, evaluation = list(files = EVP),
                             behavior_card_cfg = list(path = rel(BCP), md5 = rk_md5(BCP))))
if (!isTRUE(CC$ok)) stop("[P2R04] 판정 구현(evaluate.R)과 초안이 맞지 않는다 — 초안을 쓰지 않는다:\n  FS 키: ", CC$fs_keys, "\n  칸 목록: ", CC$cells_check, "\n  핀: ", CC$pins)
TESTS <- lapply(file.path(ROOT, K$TESTF), .run_test)
for (t in TESTS) if (!identical(as.integer(t$fail), 0L) || !is.finite(as.numeric(t$pass))) stop("[P2R04] 검사 실패 — 초안을 쓰지 않는다: ", t$path, " (", t$pass, "/", t$fail, ")")

MX <- sc$mix
ROLE_N <- table(factor(vapply(sc$cells, function(z) z$role, ""), levels = c("reference", "variant", "diagnostic")))
N_DIAG <- as.integer(ROLE_N[["diagnostic"]])
GROUP_N <- table(vapply(sc$cells, function(z) z$engine, ""))                  # 엔진 묶음 칸 수(E2 14 · E3 9)
SHARE <- lapply(K$DEV, function(d) { s <- Filter(function(z) identical(z$role, "variant") && identical(z$factor, d$factor), sc$cells)
  setNames(lapply(s, function(z) z$device_share), vapply(s, function(z) z$engine, character(1))) })
N0 <- unique(vapply(Filter(function(z) identical(z$role, "variant"), sc$cells), function(z) as.integer(z$n_prior), integer(1)))
DCODES <- function(ctrl, eng = NULL) unname(vapply(Filter(function(z) identical(z$control, ctrl) && (is.null(eng) || identical(z$engine, eng)), sc$cells), function(z) z$code, character(1)))
DPAIRS <- function(ctrl) { s <- Filter(function(z) identical(z$control, ctrl) && !is.null(z$diagnostic_of), sc$cells)
  setNames(lapply(s, function(z) z$diagnostic_of), vapply(s, function(z) z$code, character(1))) }
pct <- function(x) paste0(format(round(100 * x, 4)), "%")
E3H <- MX$engines$E3$H
REC_KEY <- FS_REC[1]
## PIT 경계 기록(교차 점검 v1 권고 11) — 쓰는 팩터 중 재무 원값이 정정 공시로 과거 값을 덮는 것(팩터 레지스트리 엔트리 restatement_prone ∧ vintage_available false · 핀한 엔트리에서 읽는다)
REST <- Filter(function(z) isTRUE(z$entry$restatement_prone) && identical(z$entry$vintage_available, FALSE), OPP$factor_registry_entries)
REST_ID <- vapply(REST, function(z) as.character(z$id), character(1))
REST_DEV <- intersect(REST_ID, vapply(K$DEV, function(d) d$factor, character(1))); REST_BASE <- setdiff(REST_ID, REST_DEV)
DEV_OF <- function(f) names(K$DEV)[vapply(K$DEV, function(d) identical(d$factor, f), logical(1))]
PIT_TXT <- if (length(REST)) sprintf(paste0("PIT 경계(기록): %s 는 재무 원값이 정정 공시로 과거 값을 덮는다(팩터 레지스트리 restatement_prone · vintage_available false — 정정 전 판본 없음 · ",
                                            "가용 시차 %s · C4 준수) — 처치 자체가 그 경계 위에 있는 장치 = %s · 기존 팩터 %s 는 같은 경계지만 짝(RX0 · 변형) 양쪽 공통"),
                                     paste(REST_ID, collapse = " · "),
                                     paste(unique(vapply(REST, function(z) as.character(z$entry$availability$rule %||% "?"), character(1))), collapse = " | "),
                                     if (length(REST_DEV)) paste(sprintf("%s %s", vapply(REST_DEV, DEV_OF, character(1)), REST_DEV), collapse = " · ") else "없음",
                                     if (length(REST_BASE)) paste(REST_BASE, collapse = " · ") else "없음") else NA_character_
RULES_DEFAULT <- list(
  tested = paste0("장치 × 엔진 판정은 다음을 모두 만족할 때만 — 아니면 미시험(반증 아님): ① 변형 · RX0 둘 다 평가됨(측정 ok ∧ 축 감사 ok) ",
                  "② 구성 증거(⑩) ③ 실효 시작 status = ok(두 칸) ④ 공통 창 사본 · 보는 창 패킷이 만들어짐 ",
                  "⑤ 위기 짝 — 두 칸의 위기가 모두 짝지어짐(짝 없는 위기 0) ∧ ① 의 짝 ≥ 2 ∧ ② 의 깊은 위기 짝 ≥ 2 ",
                  "⑥ 판정 입력(①②⑤⑥⑨⑫⑬ · 알파 · 엔진 알파)이 모두 유한 — ⑭ 결손은 미시험이 아니다: ⑭ 미측정(판정됨 · 통과 불가 · 판정어 selection_unmeasured · ",
                  "rules.selection_attribution · failure_semantics). 측정 연기(워커 ok=FALSE · deferred)는 판정 전 같은 사양 재측정(rules.remeasure). ",
                  "P2R03 의 '같은 선정 집합(변형 보유 ⊆ RX0 보유)' 조건은 두지 않는다 — 이 라운드의 처치는 선택 자체를 바꾼다(⑩ 이 보유 차이를 요구한다)"),
  remeasure = paste0("인프라 실패(측정 결과 ok ≠ true) 칸은 measure.sh 가 같은 사양으로 1회 기계 재측정(엔진 묶음마다 RX0 먼저 단독 → 나머지 칸 병렬) · ",
                     "재측정 전 그 칸의 옛 칸 평가 캐시 · 지문 삭제 · 평가는 칸 평가 캐시의 산출물 = 현 측정 산출물을 단정"),
  vintage_group = paste0("같은 엔진의 칸은 함께 잰다(measure.sh — E2 묶음 ", GROUP_N[["E2"]], "칸 → E3 묶음 ", GROUP_N[["E3"]], "칸 · 진단 칸 포함) · 칸마다 측정 시작 · 종료 데이터 지문",
                         "(fingerprint.sh equality — RAWDATA · 벤치 · 재무 원값 · 컨센서스 · 팩터 DB 월 스냅샷 · 팩터 레지스트리 · 빌드 해시 · IC 월간 이력 factor_ic_monthly.parquet) — ",
                         "측정: 묶음 칸(진단 포함) 지문이 갈리면 measure.sh 가 배리어 대기 뒤 그 묶음 전체를 1회 재측정 / ",
                         "평가: 판정 칸(장치 + RX0) 지문이 모두 같아야 판정 · 다르거나 없으면 evaluate.R 이 평가 전체를 멈춘다 · ",
                         "진단 칸 지문이 그 엔진 판정 칸 지문과 다르거나 없으면 그 진단 칸만 미시험(판정 계속 — 칸 하나의 문제는 그 칸만). 평가 시점 지문을 함께 기록한다(이름 없는 문자열 비교)"),
  common_window = P3PRE$rules$common_window,
  pins_at_evaluation = paste0("evaluate.R 은 시작부(셀 평가 샤드 포함)에서 precheck.R 과 같은 함수로 사양 · 운영 경로(팩터 DB 커넥터 · 등급 계약 v3.2 포함) · 팩터 레지스트리 엔트리 · ",
                              "비중 카탈로그 엔트리 · 패키지 · R 판 · 평가 경로 · 행동 카드 설정 사본을 재대조 — 다르면 평가하지 않는다 · 오버레이 arm 핀 없음(오버레이 없음)"),
  decisive = paste0(P3PRE$rules$decisive, " · 헌장 빈칸 10(현금 층 · 보유 방어 모두 ④ 로 판정) · 기록: 일화 단위 판(2008-11 제외)"),
  strength = sub("변화량만이 시변 층이 만든 비대칭", "변화량만이 보유 기울기가 만든 비대칭", P3PRE$rules$strength, fixed = TRUE),
  non_inferiority = P3PRE$rules$non_inferiority,
  construction = paste0("⑩ 구성 증거(통과 조건) — 변형 셀 로그에 방어 팩터 적재 줄('[rf_cell_engine] cell=<code> | … | factors=<…> | …' 의 factors 가 사양 factors 와 같고 ",
                        "RX0 줄엔 방어 팩터 없음) ∧ 사양 = RX0 factors + 장치 팩터 r 회(E2 r 1 · E3 r ", E3H$r, ") · base_weight = 혼합 몫 유도값(E2 ", format(MX$engines$E2$H$w), " · E3 ",
                        format(E3H$w), " — 두 구성 방어 몫 ", pct(MX$s), ") ∧ 보는 창 리밸일 중 변형 보유가 RX0 보유와 다른 리밸 비율 > 0(무처치 = 미시험) · ",
                        "PIT = load_month_factors(Usable_Date ≤ 신호일 · C14 · C15 — 측정 경로의 엔진 코드가 강제) · lag-1 스트레스판 없음(시점 신호 없음)"),
  concentration = P3PRE$rules$concentration,
  recovery = P3PRE$rules$recovery,
  selection_attribution = paste0("⑭ 선택 귀속(신설 · v3 강화 · 통과 조건) — MC8 귀속(보는 창 · 진단 패킷 controls.attribution.label) = final_selection_rule.mc8_label_required(selection_defense) — ",
                                 "크기 · 평균 노출 짝 플라시보(", MCJ$placebo_n %||% "?", "개 · 06_Registry/matched_controls.json)를 위기 과반에서 넘음 ",
                                 "AND 위기 분해 selection_sum(β · 크기 동시 통제 · 수익 단위 — 위기 (고점, 저점] 일간 선택 기여의 산술합 · diagnosis_packet)이 깊은 위기마다 ",
                                 "변형 − RX0 > 0(엄격 · 문턱 없음 — crisis_improve_min 0.03 은 낙폭 포착 비율 단위라 쓰지 않는다)인 위기가 과반(비율 > majority_share · 깊은 위기 짝 ≥ 2 · 판단 T1 C-20261018-028) · ",
                                 "분해 필드 부재 · 짝 < 2 · MC8 라벨 insufficient · 오류 = ⑭ 미측정(판정됨 · 통과 불가 · 판정어 selection_unmeasured · 방어 이름 보류) · ",
                                 "size_defense(크기 방어) · exposure_defense(노출 방어) · no_defense = 통과 불가(판정어 size_or_exposure_defense) · ",
                                 "해석 범위(판단 T1 자기 점검 2): 분해 선택 항은 3요인(시장 β · EW−CW · 무신호 틸트) 밖 노출(가치 · 모멘텀 · 유동성 · 퀄리티)도 선택으로 센다 — 순수 실력이 아니라 MC8 보다 β 에 강한 귀속일 뿐이고, ",
                                 "t−1 적재라 위기 중 조건부 β 하락(H1 · H3 의 기전)도 선택 항으로 잡힌다(의도에 맞음 · 결론 범위 8)"),
  pass = "장치 칸 통과 = ① ∧ ② ∧ ③ ∧ ④ ∧ ⑤ ∧ ⑥ ∧ ⑦ ∧ ⑨ ∧ ⑩ ∧ ⑫ ∧ ⑬ ∧ ⑭ · 장치 검증 = 두 엔진(같은 DNN 기저의 두 구성) 통과 ∧ ⑧ 제외 아님 · ⑪ = 꼬리표",
  selection = paste0("검증 장치(두 엔진 통과 ∧ 집중 제외 아님) 중 보는 창 S(v3)의 RX0 대비 증분(두 엔진 평균)이 가장 큰 1개 · 동률(차 < 1e-12)이면 ③ · ④ 비율 합(두 엔진 평균) · ",
                     "검증 0 = 선택 없음 · 진단 칸은 선택 대상 아님 · 꼬리표: 회복 · ⑤ 수준 · 귀속(MC8 라벨 + 분해 선택 항 + β 짝)"),
  round_verdict = sprintf("supported = 검증 장치 ≥ 1 · partial = 한 엔진 통과 또는 두 엔진 통과지만 집중 제외 · falsified = 판정된 장치 칸 중 통과 0 · untested = 판정된 장치 칸 0 — '판정(판정 칸/전체 장치 칸 %d · 판정어별 칸 수)'으로 적는다(예: falsified(판정 8/8 · β 짝 미측정 8) · 진단 %d칸은 분모 밖)", K$N_ROUND, N_DIAG),
  r7_reading = paste0("R7 판독(기계 · 사전 고정 · 판정 아님 · 판단 T1 C-20261018-029 · 격리 점검 v2 필수 1 · 권고 1): 판정된 장치 = 두 구성(E2 · E3) 모두에서 tested 이고 ③(β 짝 깊은 위기)이 측정된(status ok · 짝 ≥ 2 · 비율 유한) 장치 중 S 증분(두 구성 평균)도 유한한 장치 · ",
                      "판정된 장치 < 2 = 판독 불가(NA — 부분 판정 · 측정 실패로 예산을 소모하지 않는다) · ≥ 2 = 라운드 '잡음 이내' = 검증 0 ∧ 판정된 장치 중 두 구성에서 ③ 비율 > majority_share 인 장치 0 ∧ 판정된 장치의 S 증분(두 구성 평균) 최대 < tie_eps · ",
                      "판정된 장치 수와 빠진 장치 · 이유를 함께 싣는다 — 프로그램 예산 R7 의 입력 · P2R03 은 이 정의로 다시 읽어 기록한다"),
  diagnostics = paste0("진단 칸 ", N_DIAG, "(시행 수 무가산 · DSR 표본 아님 · 선택 대상 아님 · 판정 표 밖 · 2계층 모듈 풀 미등재(QVEST_RP_REGISTER=0 — RX0 와 같다)) — ",
                       "E2 결측 짝 ", paste(DCODES("missing_pair", "E2"), collapse = " · "), "(철학 P1 C-016) · E2 용량 짝 ", paste(DCODES("capacity_pair", "E2"), collapse = " · "),
                       "(C-018) · E2 희석 짝 ", paste(DCODES("dilution_pair", "E2"), collapse = " · "), "(C-021) · E3 용량 짝 ", paste(DCODES("capacity_pair", "E3"), collapse = " · "),
                       "(판단 T1 C-027). 같은 엔진 묶음으로 재고 묶음 지문과 대조한다 — 진단 칸 지문이 그 엔진 판정 칸 지문과 다르거나 없으면 그 진단 칸만 미시험(판정 계속 · rules.vintage_group) · ",
                       "칸 평가는 장치 칸과 같은 계약(보는 창 패킷 · 행동 카드) · 읽기 = rules.diagnostics_reading"),
  diagnostics_reading = paste0("진단 읽기(사전 고정 · 판정 아님 · DESIGN v3 §5): 결측 짝 — Hk 가 β 짝을 이긴 깊은 위기에서 Ck 도 이겼으면 그 승리 = '결측 패턴 방어'(Hk 의 방어로 세지 않는 서술) / ",
                               "용량 짝(네 칸 E2 · E3 × 50% · 12.5%) — 두 50% 통과 = '같은 처치 두 구성 통과' · E2 50% 통과 ∧ E3 50% 미달 = '구성 의존' · 50% 미달 ∧ 12.5% 통과 = '과용량 의심(희석 과다)' · ",
                               "50% 통과 ∧ 12.5% 미달 = '용량 의존' · 넷 다 미달 = '이 형태 미달' · 한 구성 단독 실패로 원천 ③ 을 닫지 않는다 / 희석 짝 — Hk 의 ① 개선 위기 중 N0 도 개선한 위기 = '희석 몫'"),
  failure_semantics = paste0("사전 고정: 평가 상태 · 구성 증거 · 실효 시작 · 공통 창 · 패킷 · 위기 짝 · 판정 입력 실패 = 그 칸 미시험(반증 아님) / ",
                             "칸 평가 오류(진단 패킷 · 행동 카드 · 축 감사의 stop) = 그 칸 status eval_error → 짝 판정 미시험 · 평가는 계속 / ",
                             "그 밖의 예기치 않은 평가 오류 = 그 칸 미시험(오류 문구 기록 · 라운드 평가는 계속) / β 사본 실패 · ③ 짝 < 2 = 'β 대조 미측정'(통과 불가) / ",
                             "④ 짝 < 2 = '빠른 급락 미측정'(통과 불가) / ⑭ 분해 필드 부재 · 깊은 위기 짝 < 2 · MC8 라벨 insufficient · 오류 = '⑭ 미측정'(판정됨 · 통과 불가 · ",
                             "판정어 selection_unmeasured · 방어 이름 보류 — 크기 · 노출 방어로 접지 않는다) / 집중 손실 표 결손 = '집중 손실 미측정'(제외) / ",
                             "진단 칸 지문 불일치 · 부재 = 그 진단 칸만 미시험(판정 계속) / 핀 · 행동 카드 사본 · 판정 칸 지문 · 칸 평가 캐시 불일치 = 평가 중단"),
  files = paste0("칸 평가 = results/<code>/visible/{diagnosis_packet.json, eval_visible.json} · results/<code>/full/{behavior_card.json, eval_full.json, NO_VISIBLE_REVIEW.txt} · ",
                  "전기간 산출이 들어가는 짝 평가 사본(results/<code>/original · common_* · rx0_beta_scaled · artifacts · rx0_artifacts)에도 NO_VISIBLE_REVIEW.txt 표식(보는 창 = visible* 하위 폴더만 · 격리 점검 v1 권고) · ",
                 "종합 = results/evaluation_visible.json(schema p2r04_evaluation_visible_v1 · 보는 창 리뷰어 열람 가능) · results/evaluation_full.json(사람 쪽 전용 · C-031)"),
  test_window = P3PRE$rules$test_window,
  record = paste0("판정 입력 아님(DESIGN v3 §5 기록): 회전 · 비용 · 평균 노출 · 위기별 표(①~④) · 강세 국면별 표 · 사이클 표 · 롤링 · 귀속(MC8) · 집중 · 알파 표준오차 · 엔진 알파(자격) · 지문 · ",
                  "보유 겹침률(RX0 대비 월별) · 위기 중 보유의 크기 분위 · 유동성 분위 · 무거래일 비율(불가 = '미측정' 꼬리표) · 국면별(위기 · 강세 · 그 밖) 월 차이 · ",
                  "기준점 둘(엔진 대비 · 시장 대비) · 크기 × β 짝 승패 · RX0 와 P2R03 RX0 동일성 · 칸마다 보는 창 A 조건별 값 · 문턱 거리(grade_v3 계약 · C-031) · ④ 일화 단위 판(2008-11 제외) · ",
                  "팩터 방향 원천(셀 로그 '[align_factor_direction] loaded-factor direction' 줄의 registry-fallback · default-fallback 합 — 방향 = as-of IC 부호면 0)"),
  state_unturned = paste0("기록(판정 아님) — 상태 미전환 최대 하락 위기(최대 21거래일 하락 구간 직전 월말에 r252 ≥ 0 ∧ 낙폭 ≤ 확장창 중앙값 — 벤치만 · _design_notes/state_turn_classify.md · ",
                          "철학 P1 C-019 이름) = final_selection_rule.", REC_KEY, " 의 β 짝 승패 · 보유 겹침률 · 위기 중 보유의 크기 분위. 판정 조건이 아닌 이유: 깊은 위기로는 1건뿐이다",
                          "(2021-06~ 위기의 최대 하락 구간 2022-05~07 은 상태가 꺾인 뒤) — 한 위기로 통과를 정하지 않는다(원칙 2 · DESIGN §5)"),
  leave_behind = paste0("검증 0 일 때 남길 것(DESIGN v3 §8.5): 장치 × 위기 실패 지도(β 짝 여유 · 크기 × β 짝 · 결측 · 희석 · 용량 읽기 · 크기 · 유동성 귀속 · 보유 겹침 · 국면별 월 차이) — ",
                        "'선택 기울기도 노출 방어'면 다음 = 원천 ① 분포 표적(종목 수준 꼬리 학습)의 입력 · P2R05 설계 초안 병렬 착수(판단 T1 C-029)"))
RULES <- if (exists("p2r04_rules", mode = "function")) p2r04_rules(ROOT, BCP) else RULES_DEFAULT
RULES_SRC <- if (exists("p2r04_rules", mode = "function")) paste0("round_rules.R::p2r04_rules (md5 ", rk_md5(file.path(RD, "round_rules.R")), ")") else
  "register.R RULES_DEFAULT — DESIGN v3 §5 · P2R03 사전등록 rules 문장 승계(①~⑨ · ⑪~⑬) + ⑩ 구성 증거 · ⑭ 선택 귀속(v3) · 진단 칸 · R7 판독"
ch <- function(item, change, reason) list(item = item, change = change, reason = reason)
pre <- list(
  schema = "rx_prereg_v1", program = PROGRAM, round_id = ROUND, status = "draft", draft_version = DRAFT_VERSION,
  drafted_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  judgments = JD,
  exposures = list(   # DESIGN §7 + 구현 쪽 열람
    list(what = paste0("1차 라운드 · P3R03 · P2R03 의 시험 창 정보 — P2R03 평가 샤드 로그 꼬리(칸별 전기간 UC · DC · CAGR · CDaR 12줄 · 10-18 07:00) · ",
                       "P2R03 전기간 누적 차트(보고 생성 · 10-18)"), when = "2026-10-15 ~ 10-18", who = "Q(세션)"),
    list(what = paste0("설계 입력(보는 창 · 성과 무관) — 벤치만으로 낸 위기 상태 분류 2건(_design_notes/state_turn_classify.md · onset_state_classify.md) · ",
                       "방어 팩터 IC 부호 정렬(defense_direction_agreement.md — 부호만) · P2R03 evaluation_visible.json · 실패 지도(보는 창)"), when = "2026-10-18", who = "Q"),
    list(what = "P2R02 C4 · C5 의 구 축 판정(MC8 V2 비율 · 보는 창)을 후보 근거로 썼다 — 시험 창 수치 아님", when = "2026-10-18", who = "Q"),
    list(what = paste0("판단 Superfan T2 C-20261018-003 함정 셋 — L7(D7 lag-1 진단) 결과를 후보로 올리지 않음 · 위기별 승패 지도로 결합 규칙을 짜지 않음(이 라운드는 결합 없음) · ",
                       "전기간 차트 열람 기록(위)"), when = "2026-10-18", who = "Q"),
    list(what = paste0("측정 기계 구현 에이전트(사양 · precheck · measure · register 작성) — 판단 원장 구조 확인 중 도전 C-20261018-015 본문(P2R03 L7 칸 보는 창 지표) · ",
                       "철학 P1 R-20261018-003 도전 C-20261018-016 ~ 026 본문(실패 지도 보는 창 수치 포함) · 판단 T1 C-20261018-027 본문(RX0 보는 창 S · CAGR · Sharpe · PORT_t)을 열람 · ",
                       "판정 규칙 · 후보 · 기대 문장 미작성(DESIGN · P1 · T1 옮김) · results/ 미열람"), when = "2026-10-18", who = "구현 에이전트"),
    list(assessment = paste0("Q 는 시험 창 수치를 본 상태다(τ_D 노출). 판정 · 선택 규칙은 보는 창(≤ 2022-12-31) 지표로만 쓰고 시험 창은 사람 쪽 보고 전용이다. ",
                             "장치 4종은 원리(하방β · 저변동 · β 비대칭 · 퀄리티 — 비대칭 원천 ③) · IC 부호 정렬(부호만) · P2R02 기록(보는 창)으로 골랐고 시험 창 성과로 고르지 않았다."))),
  purpose = paste0("현금 비중(얼마나 드느냐)이 아니라 무엇을 드느냐(방어적 보유 · 비대칭 원천 ③)로 위기에서 덜 잃는가 — 같은 β 로 비중만 낮춘 현금 사본(β 짝)보다 ",
                   "깊은 위기 · 빠른 급락에서 덜 잃고 크기 · 노출 짝을 넘는 선택 방어(⑭)이면서 강세 참여 · 알파 · 복리를 지키는가. 방어적 보유는 늘 켜진 선택 기울기라 ",
                   "시점 신호가 없다 — 시장 상태가 꺾이기 전 위기 초입에도 작동할 수 있다(P2R03 타이밍 층의 구조적 사각). 등록부 P2_DEFENSE · 병목 = 급락기 낙폭(엔진 = 시장 동행)"),
  conclusion_scope = c(   # DESIGN v3 §8(정본 = 이 사전등록)
    paste0("1 이 결과는 '방어 팩터 틸트(순위 z 혼합 · 방어 몫 ", pct(MX$s), ") × 같은 DNN 기저의 두 구성(E2 · E3) · 이 축'의 효과다(두 구성 통과는 독립 엔진 강건성이 아니다 — 헌장 빈칸 상신). ",
           "두 구성 모두 방어 몫 ", pct(MX$s), "(v3) — 용량 짝(W · ", pct(MX$t), ")이 세기 의존을 가른다(rules.diagnostics_reading)."),
    paste0("2 '방어'는 ③ ∧ ④ ∧ ⑤(수준) ∧ ⑭ 일 때만 쓴다. ⑭ 를 못 넘으면 '크기 방어' 또는 '노출 방어'다. '선택(특성) 방어' 이름은 크기 × β 짝까지 넘을 때만 · ",
           "결측 짝이 같은 위기를 이겼으면 그 승리는 '결측 패턴 방어'. ⑭ 미측정(판정어 selection_unmeasured — 분해 필드 부재 · 깊은 위기 짝 < 2 · MC8 insufficient · 오류)이면 ",
           "방어 이름을 보류한다(크기 · 노출 방어로 접지 않는다 — 결측이 다음 라운드의 동기가 되지 않게)."),
    "3 ③ · ④ · ⑭ 를 넘었으나 ⑥ · ⑦ · ⑨ · ⑫ · ⑬ 중 하나라도 못 넘으면 '저변동 기계'(방어만 · 복리 없음 — C-024).",
    paste0("4 이 라운드 결과는 이 축에서 P2R02 C4 · C5 의 '검증 · 기각'(구 축 · β 짝 없음)을 대체한다. P2R02 C6(추세 현금 + 저변동) 판정은 전액 현금 결함 위의 측정이라 무효다",
           "(10-17 결함 b234afb11 — 등록부 'validated' 를 인용하지 않는다)."),
    paste0("5 검증 0 일 때 남길 것: 장치 × 위기 실패 지도(β 짝 여유 · 크기 × β 짝 · 결측 · 희석 · 용량 읽기 · 크기 · 유동성 귀속 · 보유 겹침 · 국면별 월 차이) — ",
           "'선택 기울기도 노출 방어'면 다음 = 원천 ① 분포 표적(종목 수준 꼬리 학습)."),
    paste0("6 결합 금지(이 라운드 안): 이 라운드의 장치를 P2R03 장치(D5 · D7 등)와 묶는 결합은 새 사전등록과 결합 칸 자체의 판정으로만 한다 — ",
           "위기별 승패 지도의 합집합으로 결합을 고르지 않는다(T2 C-003 · 철학 P1 C-019)."),
    paste0("7 기준점: 위기 방어를 엔진 대비(①)와 시장 대비(벤치 dd_capture < 1 − tol) 둘 다 적는다 — E2 RX0 는 보는 창 위기 일부에서 시장보다 더 빠졌다",
           "(엔진 대비 방어 ≠ 시장 대비 방어)."),
    paste0("8 ⑭ 해석 범위(판단 T1 자기 점검 2): '선택 방어'는 위기 분해 선택 항 기준이다 — 3요인(시장 β · EW−CW · 무신호 틸트) 밖 노출(가치 · 모멘텀 · 유동성 · 퀄리티)도 ",
           "선택으로 세므로 순수 종목 선택 실력이 아니라 MC8 보다 β 에 강한 귀속이고, t−1 적재라 위기 중 조건부 β 하락(H1 · H3 의 기전)도 선택 항으로 잡힌다 — 결론 문장에 이 범위를 함께 적는다."),
    if (!is.na(PIT_TXT)) paste0("9 ", PIT_TXT, " — 그 장치 결론에 'PIT 경계 기록(정정 공시 판본 없음)'을 붙인다.")),
  candidates = list(   # DESIGN v3 §3
    selected = unname(lapply(names(K$DEV), function(k) list(code = k, factor = K$DEV[[k]]$factor, name = K$DEV[[k]]$name, basis = K$DEV[[k]]$basis,
                                                            direction = "원값 방향 = 방어 쪽 틸트(보는 창 월말 216개월 ic_sign +1 · 정렬이 공격 쪽으로 뒤집힌 달 0 — _design_notes/defense_direction_agreement.md)"))),
    excluded = list(
      list(item = "D08 꼬리β", reason = "IC 이력 0 → 레지스트리 대체 경로 → 레지스트리 표기(lower_better)가 음수화된 원값과 어긋나 공격 쪽 틸트가 된다(별도 수리 칩 task_7ee1c9a2)"),
      list(item = "D25 왼꼬리β", reason = "방어 정렬 78.7%(7번 뒤집힘) — 21% 달은 공격 틸트"),
      list(item = "D16 공왜도", reason = "+1 정렬 = 음의 공왜도(위험 프리미엄 쪽) — 위기 방어 틸트가 아님"),
      list(item = "D01 특이변동 · D02 β · D15 약세β", reason = "D01 = D03 와 순위 상관 0.99(보는 창 반기 월말 36개 측정 — 같은 신호) · D02 = D04 와 0.715 · D15 = D04 와 같은 하방 축 · 시행 수 예산(판단 T1 C-032)"),
      list(item = "원천 ① 분포 표적(종목 수준 꼬리 확률 학습)", reason = "모델 신축이 필요 — 다음 라운드 후보(이번 결과가 '선택 기울기도 노출 방어'면 그 근거)"),
      list(item = "추세 현금 · 재진입 변형", reason = "철학 P2 C-008 — D5 · D7 이웃 라운드 금지(비교 기준으로만)")),
    p2r02_tags = list(
      list(item = "P2R02 C4(저변동 틸트) '검증'", tag = "구 축 · 빈칸 8(β 짝) 이전 판정 — H2 가 이 축 · β 짝 · ⑭ 로 재시험하고 결과가 대체한다(결론 범위 4)"),
      list(item = "P2R02 C5(퀄리티 틸트)", tag = "구 축 · β 짝 이전 판정 — H4 가 이 축 · β 짝 · ⑭ 로 재시험하고 결과가 대체한다(결론 범위 4)"),
      list(item = "P2R02 C6(추세 현금 + 저변동) '검증'", tag = "무효 — 전액 현금 결함(b234afb11) 위 측정(결론 범위 4 · 등록부 'validated' 인용 금지)"))),
  measurement_axis = list(epoch = EP$id), tau_d = "2022-12-31",
  reference = list(
    baseline = "같은 엔진 RX0(이 배치에서 P2R03_E?_RX0 사양 = P0R01_E?_C0 사양 그대로 재측정) — 반증 · 비열등 · β 짝 원천 · 시행 수 무가산 · 카탈로그 미등재(QVEST_RP_REGISTER=0)",
    e3_note = sprintf(paste0("E3(B6_36) 의 RX0 = lean:entropy 비중 · 순위 버퍼 2배 · 기존 팩터 3(M01 · V10 · M08) — 장치 칸은 base_weight %s + 기존 3 + 방어 팩터 %d회 나열(DNN %s · 기존 %s · 방어 %s = E2 장치와 같은 방어 몫 · ",
                             "엔진 알파 구성 DNN : 기존 = RX0 비율 유지 · 판단 T1 C-027) · 도구 상자 기본(RX0 + 방어 1 · w0 %s → 방어 %s)은 진단 W1~W4"),
                      format(E3H$w), E3H$r, pct(E3H$w), pct((1 - E3H$w) * MX$engines$E3$n_base / (MX$engines$E3$n_base + E3H$r)), pct(MX$s),
                      format(MX$engines$E3$w0), pct(MX$t)),
    beta_copy = "β 짝 사본 = RX0 를 k = β(변형)/β(RX0) 배 노출로 낮추고 나머지를 현금으로 둔 사본(P2R03 기계 그대로) · k ≥ 1 이면 사본 = RX0 · 판정 ③ · ④ 에 쓴다",
    matched_controls = sprintf("크기 · 노출 짝(MC8) — 같은 크기 분포 · 같은 평균 노출의 무작위 포트폴리오 %s개 분위(06_Registry/matched_controls.json) · 방어 틸트는 대형주 쪽으로 기울 수 있으므로 크기 방어를 선택 방어로 세지 않는다(⑭)",
                               MCJ$placebo_n %||% "?"),
    size_beta_copy = "크기 × β 짝(평가 기록 · 칸 아님 · 철학 P1 C-017): MC8 크기 바스켓을 변형 β / 바스켓 β 로 낮추고 나머지를 현금으로 둔 사본",
    no_lag1 = "lag-1 스트레스판 없음 — 시점 신호(오버레이)가 없다 · 팩터 값의 시점은 load_month_factors(Usable_Date ≤ 신호일 · C14 · C15)가 지킨다"),
  variants = lapply(K$DEV, function(d) list(name = d$name, factor = d$factor,
                                            delta = list(E2 = list(factors_append = list(list(kind = "db", id = d$factor)), repeat_n = MX$engines$E2$H$r, base_weight = MX$engines$E2$H$w),
                                                         E3 = list(factors_append = list(list(kind = "db", id = d$factor)), repeat_n = E3H$r, base_weight = E3H$w)),
                                            mix_share = SHARE[[match(d$factor, vapply(K$DEV, function(z) z$factor, ""))]])),
  diagnostics = list(   # 철학 P1 R-20261018-003(C-016 · 018 · 021) · 판단 T1 R-20261018-004(C-027) 수용 — 판정 표 밖 · 시행 수 무가산 · 선택 대상 아님
    n = N_DIAG, engines = unname(sort(unique(vapply(Filter(function(z) identical(z$role, "diagnostic"), sc$cells), function(z) z$engine, "")))),
    accounting = "시행 수 무가산(n_family = NA · 사양 회계 = RX0 회계 + control · challenge · diagnostic_of) · DSR 표본 아님 · 선택 대상 아님 · 판정 표 밖 · 2계층 모듈 풀 미등재(QVEST_RP_REGISTER=0)",
    mix_derivation = list(device_share = MX$s, toolbox_share = MX$t,
                          rule = "rf_cell_engine §4 Score = w·z(DNN) + (1 − w)·평균 z(팩터 열) · 장치 팩터 r 회면 방어 몫 = (1 − w)·r/(n + r) — s = E2 장치 몫 · t = E3 도구 상자 기본 몫 · register.R P2R04_CONST$mix_plan"),
    missing_pair = list(codes = DCODES("missing_pair"), pairs = DPAIRS("missing_pair"), challenge = "C-20261018-016", purpose = K$DIAG$C$purpose,
                        construction = "E2 RX0 사양 + 짝 장치와 같은 팩터 1 · base_weight 1(최상위 · fixed_axes 둘 다) — 점수 = 순위z(DNN) 100% · 팩터 내부 병합의 '결측 종목 제외'만 남는다"),
    capacity_pair = list(codes = DCODES("capacity_pair"), pairs = DPAIRS("capacity_pair"), challenge = list(E2 = "C-20261018-018", E3 = "C-20261018-027"), purpose = K$DIAG$W$purpose,
                         share = MX$t, base_weight = list(E2 = MX$engines$E2$W$w, E3 = MX$engines$E3$W$w),
                         construction = "RX0 사양 + 짝 장치와 같은 팩터 1 · base_weight = 1 − t·(n + 1)(E2 = 1 − t · E3 = 도구 상자 기본 0.5 그대로) — 방어 몫 t"),
    dilution_pair = list(codes = DCODES("dilution_pair"), challenge = "C-20261018-021", purpose = K$DIAG$N$purpose, factor = K$DIAG$N$factor, base_weight = MX$engines$E2$N$w,
                         construction = "E2 RX0 사양 + factors [null_perm · id · seed](기존 통제 칸 형식) · base_weight = E2 장치와 같은 혼합 — 셀 엔진 null_perm 분기(월별 시드 · 그 신호일 패널 종목 순열)"),
    reading = "rules.diagnostics_reading(사전 고정 · 판정 아님)"),
  adaptations = c(
    paste0("장치 = 셀 사양 factors 끝에 팩터 DB 팩터(kind db) r 회 — 엔진 혼합식 Score = w × 순위z(DNN) + (1 − w) × 평균 순위z(팩터 열)(rf_cell_engine.R §4) · E2 = w ",
           format(MX$engines$E2$H$w), " · r ", MX$engines$E2$H$r, " · E3 = w ", format(E3H$w), " · r ", E3H$r, "(두 구성 방어 몫 ", pct(MX$s), " · 판단 T1 C-027)"),
    paste0("같은 팩터 id 의 r 회 나열은 셀 엔진이 허용한다 — 팩터 결합 루프가 항목마다 태그(.fv1 …)를 따로 달아 같은 팩터를 r 번 내부 병합(같은 결측 필터 · 멱등)하고 ",
           "순위 z 열 r 개를 rowMeans 에 넣는다(가중 r/(n + r)) · rx_validate 는 id 어휘 · kind 만 본다(중복 검사 없음) · 측정 경로에 팩터 중복 제거(.dedup_factors) 없음(rf_spec_sig.R 은 셀 엔진이 읽지 않는다)"),
    paste0("팩터 값 = load_month_factors(신호일, factor_names = id) 의 Z_Score_Aligned(C13 · C15) — 방향 = as-of IC 부호(Usable_Date ≤ 신호일 · 36행 이상 · C14) · ",
           "IC 이력이 모자란 신호일은 레지스트리 direction 으로 대체된다(원값이 방어 쪽 저장인 D03 · D04 · D07 은 레지스트리 lower_better 라 그 신호일엔 공격 쪽으로 뒤집힌다 — 셀 로그 방향 원천 줄로 기록)"),
    "팩터 결합 = 신호일 × 종목 내부 결합(rf_cell_engine.R §3 merge) — 그 신호일에 팩터 값이 없는 종목은 후보에서 빠진다(커버리지 축소가 처치에 함께 든다 · ⑩ 보유 차이의 한 원천 · E2 결측 짝 C1~C4 가 그 몫을 따로 잰다)",
    "E3 의 비중(lean:entropy) · 순위 버퍼 2배 · 기존 팩터 3 은 RX0 그대로 — 점수만 바뀐다"),
  cells = CELLS,
  fast_crash_prior = c(P3PRE$fast_crash_prior, list(inherited_from = list(prereg = K$P2R03_PREREG, md5 = rk_md5(file.path(ROOT, K$P2R03_PREREG)),
                                                                          note = "DESIGN §5 — 빠른 급락 정의 = Mishkin & White 2002 · 21거래일 · −20% · P2R03 표 그대로"))),
  rules = RULES, rules_source = RULES_SRC,
  expectations = list(   # Q 사전 기대(측정 전 고정 · 판단 T1 C-20261018-033 — 보는 창 선행 기록으로 정량화 · 구 축 수치는 참고 사전분포일 뿐 판정 근거 아님)
    note = paste0("선행 기록(구 축 all_hyg_2000_v1 · 보는 창 · P2R02 ROUND_REPORT): 저변동 틸트 C4 = 엔진 단독보다 덜 빠진 (엔진×위기) 쌍 85.2% · MC8 크기 + 노출 짝 플라시보 넘음 55.6% · 상승 포착 ≥ 0.55 엔진 3/3 = '검증' / ",
                  "퀄리티 틸트 C5 = 74.1% · 37.0% · 3/3 = 기각(V2) · 둘 다 β 짝 판정 없음(빈칸 8 미적용) · 판단 T1 실례: P0R01 E2_C4 는 MC8 0.86 '선택'인데 위기 분해 선택 항은 깊은 위기 4/4 악화 · 개선은 시장 β 항. ",
                  "최빈 결말 = H1 · H2 노출(β) 방어(③ β 짝 ≤ 2/4 또는 ⑭ 분해 미달) · 검증 0 확률 높음(Q 확신 0.55 — 판단 원장 J-20261018-003)"),
    H1 = paste0("하방β 낮은 쪽 기울기: β ↓(k < 1) · ① · ② 통과 가능 · ③ β 짝 ≤ 2/4 예상(개선이 β 항에서 옴) · ⑤ Δ < 0 가능 · ⑭ 분해 선택 항 미달 예상 · ⑥ 강세 참여 위험 — ",
                "근거 방향 주의: Ang · Chen · Xing (2006) 은 하방β 가 높은 종목의 프리미엄을 보였고 이 데이터의 as-of IC 는 저위험 쪽(철학 P1 C-023) — 이 장치는 프리미엄 수확이 아니라 방어 기울기다"),
    H2 = "저변동 기울기(P2R02 C4 재시험): H1 과 다른 축(순위 상관 0.26)이나 같은 저위험 계열 · ① · ② 통과 예상(선행 85%) · ③ 은 P0R01 실례대로 β 항 몫이면 미달 · ⑭ 분해 미달 예상 · ⑥ 강한 강세(대형 성장주 주도)에서 미달 위험",
    H3 = "β 비대칭(상승β − 하락β 큰 쪽) 기울기: ⑤ Δ < 0 가장 유력(구성상 비대칭) · ③ · ⑭ 불확실(하방β 와 상관 0.61 — H1 과 일부 겹침) · ⑥ 은 상승β 쪽이라 H1 · H2 보다 덜 위험",
    H4 = "퀄리티 기울기(P2R02 C5 재시험): 저위험 축과 독립(상관 0.08) · 선행 MC8 37% 로 ⑭ 미달 예상 · 2008 · 2011 '질로의 도피' 위기에서 ③ 승리 가능 · 재무 결측(금융업 등)이 결측 짝(C4) 읽기에 영향",
    falsification = "기대 반증 = H1 · H2 가 두 구성에서 ③(β 짝 깊은 위기 과반) ∧ ⑭(분해 선택 항) 를 통과하면 'β 항 몫' 기대가 틀린 것 · H4 가 ⑭ 를 통과하면 선행 C5 기각이 이 축 · β 짝 판정에서 뒤집힌 것 — 결과 뒤 기대를 고쳐 쓰지 않는다",
    engines = paste0("두 구성(같은 DNN 기저 · 독립 엔진 아님) 모두 방어 몫 ", pct(MX$s), "(v3 · T1 C-027) — 같은 처치의 두 구성 반복 · 용량 짝(", pct(MX$t), ")이 세기 의존을 가른다(§0a · §5 진단 읽기)"),
    overall = paste0("검증 0 이면 '선택 기울기도 노출 방어'를 남기고 다음 = 원천 ① 분포 표적(§8.5 · P2R05 설계 초안 병렬 착수 · T1 C-029) · 상태 미전환 최대 하락 위기(final_selection_rule.", REC_KEY,
                     ")의 β 짝 승패는 기록만(§5 — 한 위기로 통과를 정하지 않는다)")),
  final_selection_rule = FS,
  axis_audit = P3PRE$axis_audit,
  behavior_card_cfg = list(path = rel(BCP), md5 = rk_md5(BCP), same_as_p2r03 = identical(rk_md5(BCP), P3PRE$behavior_card_cfg$md5)),
  operational_pins = OPP,
  evaluation = list(files = EVP, note = "판정 구현(evaluate.R) · 픽스처 · precheck · 측정 절차(measure.sh · measure_now.sh · measure_now_vram.sh) · 데이터 지문(fingerprint.sh) · 규칙 상수(round_rules.R)를 결과 전에 고정 — evaluate.R 은 시작부(샤드 포함)에서 이 md5 와 운영 핀 전체를 재대조한다"),
  evaluate_consistency = CC,                                                    # 초안 시점 판정 구현 정합(등록 때 다시 확인해 덮는다)
  rehearsal = REHS,
  philosophy_p1 = .p1_check(),                                                  # 초안 시점 값 — 등록 때 다시 확인해 덮는다(--register)
  tests = TESTS,
  precheck = sprintf(paste0("측정 직전 precheck.R 가 (1) evaluate.R 의 핀 대조 함수 ∪ precheck.R 의 같은 정의로 사양 %d · 운영 경로 · 팩터 레지스트리 엔트리 · 비중 카탈로그 1 · 패키지 · R 판 · ",
                            "평가 경로 · 행동 카드 설정 사본과 등록부 사전등록 md5 를 다시 대조하고 (2) 러너 축 — 06_Registry/reinforce_program.json fixed_axes.n_max · commission_bps(rf_cell_worker.R 가 칸 사양 대신 ",
                            "읽는 종목 수 · 수수료) = 사양 fixed_axes 값(%s · %s bps)을 키 값으로 단정하고(파일 md5 핀 아님 — 자주 바뀌는 파일) (3) 사전등록 두 사본(stage_artifacts 정본 · 라운드 prereg.json)이 ",
                            "git 에 커밋돼 있고 작업 트리 변경이 없으며 두 md5 가 같은지 본다(등록 → 커밋 → 측정) — 하나라도 어긋나면 측정하지 않는다 · 데이터 지문 · 러너 축 값 기록(results/precheck.json)"),
                     length(CELLS), paste(unique(vapply(sc$cells, function(z) format(fromJSON(file.path(ROOT, z$path), simplifyVector = FALSE)$fixed_axes$n_max), "")), collapse = "/"),
                     paste(unique(vapply(sc$cells, function(z) format(fromJSON(file.path(ROOT, z$path), simplifyVector = FALSE)$fixed_axes$commission_bps), "")), collapse = "/")),
  data_note = paste0("데이터 판본: RAWDATA · 벤치 퀀티 단일 · 측정 축 ", EP$id, "(동전주 바닥) · DNN 예측 = P2R03 이 새 epoch 로 학습한 내용 주소 캐시를 그대로 쓴다(재학습 없음 · DESIGN §2 — ",
                     "측정 묶음 지문 record 에 남긴다) · 팩터 DB 월 스냅샷 · IC 월간 이력 = equality 지문 대상(처치 원천 · 방향 원천) · 팩터 레지스트리 = 쓰는 엔트리 내용 핀",
                     if (!is.na(PIT_TXT)) paste0(" · ", PIT_TXT) else ""),
  design_inputs = paste0("DESIGN.md v3 · _design_notes 3건(defense_direction_agreement · state_turn_classify · onset_state_classify — 벤치 · IC 부호만) · ",
                         "P2R03 사전등록(빠른 급락 표 · 규칙 ①~⑬ 문장 · final_selection_rule 값) · 판단 원장 ", J_ROUND_SELECTION, " · 철학 P1 R-20261018-003 · 판단 T1 R-20261018-004 · ",
                         "측정 · 평가 계약 코드 — 시험 창 성과 미사용"),
  budget = list(variants = K$N_ROUND, reference_remeasure = as.integer(ROLE_N[["reference"]]), diagnostic = N_DIAG, diagnostic_lag1 = 0L, cells = length(CELLS), rounds = 1L,
                note = sprintf("변형 %d 만 시행 수 가산(계보 2002.06975 · %s → %s) · RX0 %d · 진단 %d = 무가산 · lag-1 진단 없음 · DSR 표본 = 변형 칸", K$N_ROUND,
                               paste(N0, collapse = "/"), paste(N0 + K$N_ROUND, collapse = "/"), as.integer(ROLE_N[["reference"]]), N_DIAG)),
  changes_after_superfan = list(   # 설계 단계 반영(앞 라운드 P2R03 의 판단 T2 · 철학 P2) + 이 라운드 철학 P1 · 판단 T1 중 측정 기계에 든 것(나머지 항목 = 조정자가 잇는다)
    ch("판단 Superfan T2 C-20261018-001 · 철학 P2 C-008(R-20261018-002) — P2R03 판정 해석",
       "질문을 '현금 비중'에서 '무엇을 드느냐(방어적 보유 · 원천 ③)'로 옮김 · 추세 현금 · 재진입 변형을 이웃 라운드로 두지 않음(비교 기준으로만 · candidates.excluded)",
       "P2R03 의 방어는 노출(β) 방어였고 이긴 빠른 급락은 추세 · 낙폭 상태가 꺾인 뒤의 2차 급락 2건뿐 · 꼭대기에서 시작한 2011-08 급락은 노출 1.00 그대로(DESIGN 머리말)"),
    ch("판단 Superfan T2 C-20261018-003 함정 셋", "L7(D7 lag-1 진단) 결과를 후보로 올리지 않음 · 위기별 승패 지도로 결합 규칙을 짜지 않음(결합 없음) · 전기간 차트 열람을 exposures 에 기록", "수용(DESIGN §7)"),
    ch("'상태 미전환 최대 하락 위기'의 판정 조건화 — 불채택", paste0("기록만(rules.state_unturned · final_selection_rule.", REC_KEY, ")"),
       "깊은 위기로는 1건뿐(2022-05~07 은 상태가 꺾인 뒤) — 한 위기로 통과를 정하지 않는다(원칙 2 · DESIGN §5)"),
    ch("철학 P1 C-20261018-016 결측 짝", paste0("E2 진단 칸 ", paste(DCODES("missing_pair"), collapse = " · "), " — 장치 팩터 + base_weight 1(점수 = DNN 100%) · 판정 표 밖 · 무가산"),
       "셀 엔진의 팩터 내부 병합이 '방어 팩터 결측 종목 제외'라는 둘째 처치를 얹는다 — β 짝(RX0 사본) · MC8 이 그 경로를 못 거른다"),
    ch("철학 P1 C-20261018-018 용량 짝(E2)", paste0("E2 진단 칸 ", paste(DCODES("capacity_pair", "E2"), collapse = " · "), " — 장치 팩터 + base_weight ", format(MX$engines$E2$W$w), "(방어 몫 ", pct(MX$t), ") · 판정 표 밖 · 무가산"),
       "방어 몫 차이가 '엔진 의존'과 '용량 부족'을 교락한다"),
    ch("철학 P1 C-20261018-021 희석 짝", paste0("E2 진단 칸 ", paste(DCODES("dilution_pair"), collapse = " · "), " — factors [null_perm · seed 20261018] + base_weight ", format(MX$engines$E2$N$w), " · 판정 표 밖 · 무가산"),
       "DNN 상위 25종은 극단 선택이라 신호 절반을 무정보로 섞기만 해도 ① · ② 가 좋아질 수 있다 — 희석 몫을 따로 읽는다"),
    ch("판단 T1 C-20261018-027 처치 용량", paste0("E3 장치 칸 = base_weight ", format(E3H$w), " + 기존 3 + 장치 팩터 ", E3H$r, "회 나열(방어 몫 ", pct(MX$s), " = E2 와 같은 처치) · ",
                                              "도구 상자 12.5% 판 = E3 진단 칸 ", paste(DCODES("capacity_pair", "E3"), collapse = " · "), "(P0R01 E3 C4/C5 와 같은 지정 · 무가산)"),
       "E2 50% · E3 12.5% 면 '두 엔진 공통 통과'가 같은 처치의 반복 검증이 아니라 다른 처치 둘의 동시 통과다"),
    ## ── 조정자(Q)가 잇는 수용 항목(판정 · 기록 · 문언 — evaluate.R · DESIGN v3 · fingerprint.sh 에 반영) ──
    ch("철학 P1 C-20261018-017 크기 × β 동시 짝", "평가 기록 = MC8 크기 바스켓을 변형 β / 바스켓 β 로 낮춘 현금 사본의 깊은 위기 승패 · 결론 이름 '선택(특성) 방어'는 이것까지 넘을 때만(통과 조건 아님) · 불가 = '크기 × β 짝 미측정'",
       "③ 은 β 만 · ⑭(MC8) 는 크기 · 평균 노출만 맞춘다 — 대형 · 저β 쪽 이동이 특성 선택 없이 둘 다 넘을 수 있다"),
    ch("판단 T1 C-20261018-028 ⑭ 강화", "⑭ = MC8 selection_defense AND 위기 분해 선택 항(β · 크기 동시 통제)이 깊은 위기 과반에서 RX0 보다 개선 · 필드 부재 = 미측정(통과 불가)",
       "P0R01 E2_C4 실례 — MC8 0.86 '선택'인데 분해 선택 항은 깊은 위기 4/4 악화 · 개선은 시장 β 항"),
    ch("철학 P1 C-20261018-019 결론 범위 · 기록 이름", "결론 범위 6(결합은 새 사전등록 · 결합 칸 자체 판정으로만) · 4 확장(P2R02 C6 판정 무효 — 전액 현금 결함 위 측정) · 기록 이름 '상태 미전환 최대 하락 위기'",
       "'꼭대기 시작' 기록이 P2R03 D5 · D7 승패 지도와 상보라 합치면 4/4 가 기계적으로 나온다"),
    ch("철학 P1 C-20261018-020 · 024 기록 · 문언", "평가 기록 = 위기 보유 유동성 분위 · 무거래일 비율(불가 = '유동성 귀속 미측정') · 국면별(위기 · 강세 · 그 밖) 월 차이 · 보유 겹침률 · 기준점 둘(엔진 대비 · 시장 대비) · '방어만 · 복리 없음' = '저변동 기계'",
       "얇은 거래 종목은 측정 β 가 낮고 MC8 플라시보 모집단엔 유동성 하한이 없다 · 늘 켜진 틸트의 횡보 세금 · 엔진이 시장보다 더 빠지는 위기가 있다"),
    ch("철학 P1 C-20261018-022 · 023 방향 · 근거 · 선택 회계", "방향 = as-of IC 부호(보는 창 216개월 방어 정렬 100% · IC 방향 확정 신호일 2003-05-30 < DNN 첫 신호) · 시험 창 정렬은 P3 에서 기록 · 기대에 ACX(2006) 방향 차이 명시 · 후보 12 중 4 선택(candidates)",
       "방어 장치가 정렬 뒤집힘으로 공격 장치가 되는 달 · 근거 논문 방향과 데이터 방향 차이 · 선택 회계"),
    ch("철학 P1 C-20261018-025 기록", "RX0 와 P2R03 RX0 동일성(보는 창 보유 · 순수익) · H1 대 P2R03 D1 대조 읽기(같은 하방β 정보 · 처치 = 늘 켜진 선택 vs 낙폭 국면 축소)", "동기 자체를 재는 기록"),
    ch("판단 T1 C-20261018-029 실패 뒤 경로", "R7 판독 기계 고정(검증 0 ∧ 두 구성 ③ 과반 장치 0 ∧ S 증분 최대 < tie_eps = 잡음 이내) · 원천 ① 분포 표적 P2R05 설계 초안 병렬 착수",
       "최빈 기대가 실패인데 실패 뒤 경로가 없었다"),
    ch("판단 T1 C-20261018-031 · 032 기록 · 제외 근거", "칸마다 보는 창 A 조건별 값 · 문턱 거리(grade_v3 계약) · D01 제외 근거 측정 = D03 와 순위 상관 0.99(보는 창 반기 월말 36개)",
       "선택 규칙이 CAGR · Sharpe 하한을 보지 않는다 · '원리 중복'은 진술이었다"),
    ch("판단 T1 C-20261018-034 데이터 판본", "fingerprint.sh equality 에 factor_ic_monthly.parquet 추가(방어 틸트 방향의 원천 · 방향 캐시는 이 파일로 키가 바뀐다)",
       "IC 이력이 묶음 지문 밖이면 측정 중 재생성이 방향을 바꿔도 같은 판본으로 읽힌다"),
    ch("판단 T1 C-20261018-035 · 철학 P1 헌장 빈칸", "decision_register CHARTER-GAPS-4-20261018 상신(선택 방어 정의 · 방어 특성 방향 원리 · 방어 기준점 · 독립 엔진 정의) · 기본값 = 현행 헌장 · 이 라운드 판정 불변",
       "v3.2 등급 노치의 '선택' 분기도 완전 투자 β 틸트를 선택으로 셀 수 있다 · 사람 판정 필요")),
  changes_after_review = list(   # 격리 교차 점검 v1(prereg_draft_review_v1.md · revise · 필수 6 · 권고 11 · 선택 7 · 점검 초안 md5 79f3ff1d) 반영 — 무엇을 · 왜 · 리뷰 위치
    ch("필수 1 ⑭ 분해 문턱(리뷰 §1 필수 1 · 초안 rules.selection_attribution · evaluate.R:461 · T1 20261018_1227_T1.md:52)",
       paste0("rules.selection_attribution = MC8 selection_defense AND 위기 분해 selection_sum(β · 크기 동시 통제 · 수익 단위)이 깊은 위기마다 변형 − RX0 > 0(엄격 · 문턱 없음)인 위기가 과반(짝 ≥ 2) · ",
              "crisis_improve_min 0.03 은 쓰지 않는다 · 구현 = evaluate.R(판정 구현 쪽 — `sv - sr >= tol` → 문턱 없는 엄격 부등호) · 조정자 결정(리뷰 권장 '> tol' 대신 '> 0')"),
       "문장(개선 = 차 > 0) · 코드(≥ 0.03 · 등호 포함) · T1 원 요구(> tol)가 셋 다 달랐다 · 0.03 의 근거 문장은 낙폭 포착 비율(dd_capture) 단위라 수익 단위 selection_sum 에 빌려 쓸 근거가 없다(재현 R1 — 같은 패킷에서 ⑭ 가 뒤집힘)"),
    ch("필수 2 rules.tested ⑥(리뷰 §1 필수 2 · 초안 rules.tested · evaluate.R:1103-1108)",
       "⑥ '유한해야 하는 판정 입력' 목록에서 ⑭ 를 뺐다 · '⑭ 결손은 미시험이 아니다 — ⑭ 미측정(판정됨 · 통과 불가 · selection_unmeasured)' 한 줄",
       "코드는 ⑭ 를 유한 검사에 넣지 않고 결손을 통과 불가로 센다(판정 칸) · 같은 사전등록 selection_attribution · failure_semantics 와 반대 의미였다"),
    ch("필수 3 ⑭ 미측정 판정어(리뷰 §1 필수 3 · evaluate.R:546-559 · matched_controls.R:437 · 재현 R2 · R3)",
       paste0("판정어 selection_unmeasured('선택 귀속 미측정 — 방어 이름 보류') 신설 · rules.selection_attribution · failure_semantics · conclusion_scope 2 에 '⑭ 미측정이면 방어 이름 보류(크기 · 노출 방어로 접지 않음)' · ",
              "MC8 라벨 insufficient = 미측정 · notify.R 판정어 사전 · 구현 = evaluate.R(판정 구현 쪽 · 픽스처 · 리허설 재실행 뒤 초안 재작성)"),
       "⑭ 결손(분해 필드 부재 · MC8 insufficient)이 판정어 size_or_exposure_defense · 결론 이름 '크기 · 노출 방어'로 접혀 결론 범위 2 · 5(다음 라운드 동기)의 입력이 결측에서 만들어질 수 있었다"),
    ch("필수 4 진단 칸 지문 불일치(리뷰 §1 필수 4 · 초안 rules.vintage_group · rules.diagnostics · evaluate.R 진단 칸 블록)",
       paste0("rules.vintage_group · diagnostics · failure_semantics — 판정 칸(장치 + RX0) 지문 불일치 · 부재 = 평가 전체 중단 / 진단 칸 지문이 그 엔진 판정 칸 지문과 다르거나 없으면 ",
              "그 진단 칸만 미시험(판정 계속) · 측정(measure.sh same_fp)은 진단 칸까지 묶어 재측정 — 문장을 코드에 맞춤"),
       "문장은 진단 칸 지문 불일치도 '평가 전체 중단'이었고 코드는 그 칸만 미시험이다 — 칸 하나의 문제는 그 칸만(failure_semantics 원칙)"),
    ch("필수 5 러너 축(리뷰 §1 필수 5 · rf_cell_worker.R:31-32 · 96-101)",
       paste0("precheck.R 본 대조 · 건식이 06_Registry/reinforce_program.json fixed_axes.n_max · commission_bps(워커가 칸 사양 대신 읽는 종목 수 · 수수료) = 사양 fixed_axes 값을 키 값으로 단정 · ",
              "다르면 측정하지 않음(precheck_fail) · precheck.json 에 러너 축 값 기록 · register.R OPS 주석 · rules.precheck 문장"),
       "칸 사양의 commission_bps · n_max 는 러너에 가지 않고 워커는 그 파일을 읽는데 핀 · 지문 · precheck 어디에도 없었다 · 9~10월 8회 바뀐 파일이라 md5 핀은 무관한 편집으로 측정을 막는다 → 읽는 키 내용 대조"),
    ch("필수 6 설계 정본 낡은 문장 셋(리뷰 §1 필수 6 · DESIGN.md §2 · §4 · §10)", "DESIGN v3 문장 정정(조정자) — §2 'E3 틸트 약함' · §4 '진단 칸 9' · §10 '장치 팩터 하나'(+ 혼합 몫 식 · 진단 칸 사양 규칙)",
       "설계 정본(judgments.design · rules_source)의 세 문장이 v3 구현과 어긋나 §10 으로 재도출하면 E3 장치 칸이 계약 위반으로 보였다"),
    ch("권고 5 등록 → 커밋 → 측정 기계 확인(리뷰 §2 권고 5 · precheck.R git_head 기록만)",
       "precheck.R 본 대조가 사전등록 두 사본(stage_artifacts 정본 · 라운드 prereg.json)의 git 추적 · 작업 트리 변경 없음 · 두 사본 md5 같음을 단정 — 아니면 측정하지 않음",
       "커밋 순서를 기계가 보지 않았다(register.R 은 고정 대상 커밋을 확인한 뒤 사전등록을 쓰지만 그 사전등록의 커밋은 아무도 확인하지 않았다)"),
    ch("권고 8 ⑭ 해석 범위(리뷰 §2 권고 8 · T1 20261018_1227_T1.md 자기 점검 2)",
       "conclusion_scope 8 · rules.selection_attribution — 분해 선택 항 = 3요인(시장 β · EW−CW · 무신호 틸트) 밖 노출 포함 · t−1 적재라 위기 중 조건부 β 하락(H1 · H3 기전)도 선택 항으로 잡힘",
       "T1 이 스스로 적은 해석 범위가 사전등록에 없었다(사전등록 grep 0건)"),
    ch("권고 11 Q08 정정 공시 PIT 경계(리뷰 §2 권고 11 · 초안 operational_pins.factor_registry_entries Q08 · parse_fundamental_xlsx.R:205)",
       "data_note · conclusion_scope 9 — 핀한 팩터 레지스트리 엔트리에서 restatement_prone ∧ vintage_available false 인 팩터를 읽어 'PIT 경계(기록)' 문장(처치 = H4 Q08 · 기존 팩터 V10 은 짝 양쪽 공통) · H4 결론에 'PIT 경계 기록'",
       "정정 공시가 과거 재무 값을 덮는 판본 없음 경계 위에 처치 자체(H4)가 있다(C4 시차는 맞다 — Q4 = 익년 3/31)"),
    ch("선택 3 vintage_group 문장의 IC 월간 이력(리뷰 §3 선택 3)", "rules.vintage_group 지문 원천 목록에 IC 월간 이력(factor_ic_monthly.parquet) 명시", "판단 T1 C-034 반영이 fingerprint.sh 에만 있고 문장에 없었다"),
    ## ── 격리 교차 점검 v2(prereg_draft_review_v2.md · revise(좁은 범위) · 점검 초안 md5 211b62d0) 반영 ──
    ch("v2 필수 1 R7 판독 불가 문장(리뷰 v2 §남은 필수 · evaluate.R R7 블록 · register.R r7_reading)", "r7_reading 문장에 판정된 장치 정의 · 판정된 장치 < 2 = 판독 불가 · 빠진 장치와 이유 기록을 넣음 · DESIGN §5 같은 문장",
       "v2 코드의 판독 불가 규칙이 문장에 없어 장치 1개 판정 시 코드(NA) ≠ 문장(잡음 이내)으로 갈렸다 — R7 은 프로그램 예산 입력"),
    ch("v2 권고 1 R7 판정 장치 = ③ 측정 장치(리뷰 v2 §(b))", "evaluate.R — 두 구성 모두 ③ 이 측정된 장치만 판정된 장치로 센다(β 대조 미측정 장치는 분모에서 빠짐) · 픽스처 · 뮤테이션 · 리허설 갱신",
       "8칸 모두 β 대조 미측정이어도 '잡음 이내(판정 4/4)'가 나왔다 — 측정 실패가 예산을 소모하면 안 된다"),
    ch("v2 권고 3 등록 관문(리뷰 v2 §(c) · register.R:374)", "--register 가 '등록할 초안 md5 = 마지막으로 점검받은 보존본(prereg_draft_reviewed_v<현판>.json) md5'를 단정",
       "보존본이 하나라도 있으면 통과해 점검받지 않은 초안이 등록될 수 있었다"),
    ch("v2 비차단 문장-코드 정합(리뷰 v2 §(b))", "round_verdict 문장에 판정어별 칸 수 라벨 · files 문장에 짝 평가 사본 폴더 NO_VISIBLE_REVIEW 표식 · 변경 기록에 v1 권고 2(판정어별 칸 수 라벨) · 6(전기간 사본 표식) · 7(E3 W 구성 비 1:1 → 4:3 주석 — evaluate.R · DESIGN §4) 반영 명시",
       "같은 재작성에서 맞춘다 — 코드에는 v2 에서 들어갔으나 문장 · 기록에 빠져 있었다"))) # 비어 있으면 --register 거부
writeLines(toJSON(pre, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA), DR, useBytes = TRUE)
cat(sprintf("[P2R04] 초안 v%d %s (md5 %s) · 칸 %d(장치 %d + 기준 %d + 진단 %d) · 검사 %s · 시행 회계 %s · 규칙 문장 = %s · 판정 구현 정합 %s · 철학 P1 %s\n", pre$draft_version, rel(DR), rk_md5(DR),
            length(CELLS), K$N_ROUND, as.integer(ROLE_N[["reference"]]), N_DIAG,
            paste(vapply(TESTS, function(t) sprintf("%s %s/%s", basename(t$path), t$pass, t$fail), ""), collapse = " · "),
            paste(N0 + K$N_ROUND, collapse = "/"), if (exists("p2r04_rules", mode = "function")) "round_rules.R" else "RULES_DEFAULT",
            if (isTRUE(CC$ok)) "ok" else "불일치", if (isTRUE(pre$philosophy_p1$ok)) "수령" else paste0("미수령(", pre$philosophy_p1$why, ")")))
