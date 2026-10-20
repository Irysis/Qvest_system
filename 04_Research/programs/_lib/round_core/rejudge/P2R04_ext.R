## P2R04 고유 규칙(round_ext) — 코어 P2 템플릿 위에서 P2R04 판정을 재현한다(재판정 · 픽스처 대조).
##   이 라운드가 코어에 더하는 것 = 장치 표 · 진단 표 · 용량 읽기 표 · 판정어 이름('방어만 · 복리 없음' = '저변동 기계') · 진단 읽기 묶음 · 파일 이름.
##   출처: P2R04 evaluate.R L19-82(등록 a32201675 판 그대로 — 표 · 문구 무수정). 판정 단계 · 도우미 · 라운드 판정 = round_core v1(pair.R · p2.R).
P2R04_ROUND_ID <- "P2R04_defensive_holdings"
P2R04_DEVICES <- list(
  H1 = list(kind = "db", id = "D04_Downside_Beta", name = "하방β", raw = "−(시장 하락일만으로 추정한 β)",
            basis = "Ang, Chen & Xing (2006) Downside Risk, RFS 19(4)"),
  H2 = list(kind = "db", id = "D03_RealVol", name = "저변동", raw = "−(252일 실현 변동성)",
            basis = "Blitz & van Vliet (2007) The Volatility Effect, JPM 34(1) · Frazzini & Pedersen (2014) JFE 111(1) — P2R02 C4 재시험"),
  H3 = list(kind = "db", id = "D07_Beta_Asymmetry", name = "β 비대칭", raw = "상승β − 하락β(클수록 오를 때 더 오르고 내릴 때 덜 내림)",
            basis = "Ang, Chen & Xing (2006) 비대칭 β — 철학 '비대칭'의 종목 수준 대응"),
  H4 = list(kind = "db", id = "Q08_Composite_Quality", name = "퀄리티", raw = "복합 퀄리티(GPA · ROE · ROA · 발생액)",
            basis = "Asness, Frazzini & Pedersen (2019) Quality minus junk, RAS 24 — P2R02 C5 재시험"))
P2R04_DIAG_ENGINE <- "E2"
P2R04_DIAGNOSTICS <- c(
  setNames(lapply(names(P2R04_DEVICES), function(h) list(reading = "missing", pair = h, engines = P2R04_DIAG_ENGINE, weight = 0,
                                                          note = "결측 짝(C-016) — DNN 100% + 장치 팩터 · 혼합 가중 0 · 팩터 결측 종목 제외 효과만")), sub("^H", "C", names(P2R04_DEVICES))),
  setNames(lapply(names(P2R04_DEVICES), function(h) list(reading = "capacity", pair = h, engines = c("E2", "E3"), weight_toolbox_on = "E3",
                                                          note = "용량 짝(C-018 · R-20261018-004) — 장치 팩터 몫 = 도구 상자 기본(E3 RX0 base_weight 위 장치 팩터 1회)")), sub("^H", "W", names(P2R04_DEVICES))),
  list(N0 = list(reading = "dilution", pair = NA_character_, engines = P2R04_DIAG_ENGINE, kind = "null_perm", weight_like = list(engine = P2R04_DIAG_ENGINE, component = names(P2R04_DEVICES)[1]),
                 note = "희석 짝(C-021) — 무작위 순열 팩터(null_perm) 몫 = E2 장치 칸의 몫")))
P2R04_CAPACITY_TABLE <- data.table(
  e2_50 = c(TRUE,  TRUE,  TRUE, TRUE,  FALSE, FALSE, FALSE),
  e3_50 = c(TRUE,  TRUE,  TRUE, FALSE, TRUE,  FALSE, FALSE),
  e2_12 = c(TRUE,  FALSE, NA,   NA,    NA,    FALSE, NA),
  e3_12 = c(TRUE,  FALSE, NA,   NA,    NA,    FALSE, NA),
  label = c("같은 처치 두 구성 통과 · 용량 무관(12.5% 도 통과)", "같은 처치 두 구성 통과 · 용량 의존(12.5% 들만 미달)",
            "같은 처치 두 구성 통과(12.5% 엇갈림)", "구성 의존(E2 50% 만 통과 · E3 50% 미달)", "구성 의존(E3 50% 만 통과 · E2 50% 미달)",
            "이 형태 미달(네 칸 모두 미달)", "과용량 의심(희석 과다 — 50% 미달 ∧ 12.5% 통과)"))
P2R04_VERDICT_NAMES <- c(pass = "통과", not_decisive = "결정 미달", exposure_only = "노출 방어(β 짝 미통과)",
                         selection_unmeasured = "선택 귀속 미측정 — 방어 이름 보류",
                         size_or_exposure_defense = "크기 · 노출 방어(⑭ 미통과)", fast_unmeasured = "빠른 급락 미측정", beta_unmeasured = "β 대조 미측정",
                         defense_but_strength_or_path = "저변동 기계(방어만 · 복리 없음)", untested = "미시험")
P2R04_VERDICT_SHORT <- c(pass = "통과", not_decisive = "결정 미달", exposure_only = "노출 방어", selection_unmeasured = "⑭ 미측정",
                         size_or_exposure_defense = "크기 · 노출 방어", fast_unmeasured = "빠른 급락 미측정", beta_unmeasured = "β 짝 미측정",
                         defense_but_strength_or_path = "저변동 기계", untested = "미시험")
P2R04_P2R03_RX0 <- "04_Research/programs/P2_DEFENSE/P2R03_conditional_overlay/results/P2R03_%s_RX0.json"

## 템플릿 = 코어 P2 기본(P2R04 판) + 이 라운드 표
P2R04_T <- rc_p2_template(cfg = list(devices = P2R04_DEVICES, diagnostics = P2R04_DIAGNOSTICS, diag_engine = P2R04_DIAG_ENGINE, capacity_table = P2R04_CAPACITY_TABLE,
                                     verdict_names = P2R04_VERDICT_NAMES, verdict_short = P2R04_VERDICT_SHORT))
p2r04_readings <- function(OUT, DOUT, tol, DEVS, T) rc_p2_readings(OUT, DOUT, tol, DEVS, T$cfg$diagnostics, T$cfg$diag_engine, T$cfg$capacity_table)

## 라운드 R — rd = 라운드 디렉터리(저장소 상대) · src = 사전등록 · 사양 · 평가 파일을 읽는 저장소(재현 루트) · res = 저장된 칸 산출 · out = 재판정 출력
p2r04_R <- function(root, res, out, perf_env = NULL, ...) {
  rd <- file.path(root, "04_Research/programs/P2_DEFENSE", P2R04_ROUND_ID)
  pp <- file.path(root, "stage_artifacts/programs/P2_DEFENSE", P2R04_ROUND_ID, "prereg.json")
  utils::modifyList(list(round_id = P2R04_ROUND_ID, program = "P2_DEFENSE", tag = "P2R04", prefix = "P2R04", pre = fromJSON(pp, simplifyVector = FALSE), prereg_path = pp,
                         root = root, res = res, out = out, precheck = file.path(res, "precheck.json"),
                         fingerprint = list(script = file.path(rd, "fingerprint.sh"), args = character(0), record_args = character(0)),
                         evaluate_md5 = rc_md5(file.path(rd, "evaluate.R")), rx0_identity = P2R04_P2R03_RX0, rx0_identity_names = c("p2r04", "p2r03"),
                         schema_visible = "p2r04_evaluation_visible_v1", schema_full = "p2r04_evaluation_full_v1",
                         cell_cache = "legacy", cell_write = FALSE, check_pins = TRUE, readings = p2r04_readings, perf_env = perf_env), list(...))
}
## 선언 규칙(같은 판정의 rules.R 선언판 — 선언 판정 = 단계 판정 대조용 · 값 = 사전등록 final_selection_rule 그대로)
p2r04_rules <- function(FS) {
  b <- "P2R04 사전등록 final_selection_rule(등록 a32201675)"
  list(
    list(id = "crisis", type = "crisis_majority", label = "① 위기 과반(RX0)", vs = "rx0", crises = "all", majority = as.numeric(FS[["majority_share"]]), basis = b),
    list(id = "deep", type = "crisis_majority", label = "② 깊은 위기 과반(RX0)", vs = "rx0", crises = "deep", majority = as.numeric(FS[["majority_share"]]), basis = b),
    list(id = "beta_deep", type = "beta_pair_win", label = "③ β 짝 깊은 위기", crises = "deep", majority = as.numeric(FS[["majority_share"]]), basis = b),
    list(id = "fast", type = "beta_pair_win", label = "④ β 짝 빠른 급락", crises = "fast", majority = as.numeric(FS[["majority_share"]]), basis = b),
    list(id = "bull", type = "up_capture", label = "⑥ 강세 참여", segments = TRUE, floor = as.numeric(FS[["uc_floor"]]), majority = as.numeric(FS[["majority_share"]]), basis = b),
    list(id = "alpha", type = "alpha_noninferior", label = "⑦ 알파 비열등", t_floor = as.numeric(FS[["alpha_t_floor"]]), margin_frac = as.numeric(FS[["alpha_margin_frac"]]), basis = b),
    list(id = "axis", type = "axis_audit", label = "축 감사"))
}
p2r04_rules_map <- list(crisis = function(x) x$rules$crisis$ok, deep = function(x) x$rules$deep$ok,
                        beta_deep = function(x) if (identical(x$rules$beta_deep$status, "ok")) x$rules$beta_deep$ok else NA,
                        fast = function(x) if (identical(x$rules$fast$status, "ok")) x$rules$fast$ok else NA,
                        bull = function(x) x$rules$bull$ok, alpha = function(x) x$alpha_non_loss$ok,
                        axis = function(x) if (isTRUE(x$tested)) TRUE else NA)   # 판정된 짝 = 두 칸 모두 축 감사 통과(rc_st_status — 아니면 미시험)
