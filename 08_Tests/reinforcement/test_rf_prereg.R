## rf_prereg.R — 사전등록 레버 실험 계약 검사 (P2-01 · 2026-09-25 · 플랜 qvest-1-drifting-eclipse §P2)
## 재는 것(양방향 — 양성 대조 · 위반 주입 · 돌연변이):
##   A. 설정 fail-closed(파일·키·라벨)                     B. 스키마 — 양성 + 위반 주입 17종 + 등록 차단 사유 13종
##   C. writer — 원자 쓰기·sha 색인·덮어쓰기 거부·rev·등록·가족·묘비·변조 검출
##   D. 검정력 3종 — measurement-graduation 표 항등 · required_effect 단일 출처 · 처분 경계
##   E. SE 원천 — 짝지은 블록 부트스트랩(항등·주입·결정론·짝지음·defensive_score 동일식·NA) · null 희석 · 결합 · 위상쌍 거부
##   F. 판정 — 라벨 4종 · 우선순위 · 멈춤 집행(skip/halt) · 손계산·sha·규약·미선언·중복·계약 부재 거부 · must_report · 1회만 · AX-008
##   G. 드라이런 — dry_run=FALSE 거부 · 쓰기 0 · formals 재도출(P1-08 양성 대조)
##   H. N 회계 — rf_runner_gates 정의 재사용(상속 제외) · RF_DECISION_KINDS 에 prereg_verdict
##   N. 적대 검증 수리분(2026-09-25) — 손 수치·verify 해제·멈춤 우회(생략/NA/뒤 arm 참조)·반대편 powered_null·등록 뒤 설정 변경·
##      등록 전 측정·seed 쇼핑·halt 시 must_report·대상 귀속 위조·함의 효과 부호·floor v2 키=id 형태
##   P. PREREGFIX(2026-10-03 · 결정 09-26 [위임]) — 기전 한정 바닥 수락(scope) · 1차 판정 교정(bootstrap_p·null_t_quantile) ·
##      결정 파라미터(from·derive·rhs{param}) · 처치 전달 타당성(treatment_dilution) · 실행 전제(run_blockers)
##   M. 돌연변이 52종 — 각 가드를 끈 사본이 해당 검사에서 red(생존 = NG)
##   Z. 루트 색인의 초안(있으면) — 무결성·초안 검증(읽기만 · 차단 사유 개수는 단정하지 않는다: 살아 있는 상태를 빌리지 않음)
## 쓰기 = tempdir() 안 합성 루트뿐(ROOT 는 읽기만). ROOT = QM_ROOT(샌드박스·배포 미러) — 운영 트리에서 직접 돌리지 말 것.
suppressMessages(library(jsonlite))
ROOT <- normalizePath(Sys.getenv("QM_ROOT", getwd()), winslash = "/", mustWork = TRUE)
P <- 0L; F <- 0L
ok <- function(m) { P <<- P + 1L; cat(sprintf("  ok   %s\n", m)) }
ng <- function(m, d = "") { F <<- F + 1L; cat(sprintf("  NG   %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }
chk <- function(cond, m, d = "") if (isTRUE(cond)) ok(m) else ng(m, d)
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
err_of <- function(expr) tryCatch({ force(expr); NA_character_ }, error = function(e) conditionMessage(e))
TMPB <- normalizePath(tempfile("rfprereg_"), winslash = "/", mustWork = FALSE); dir.create(TMPB, recursive = TRUE)
if (startsWith(tolower(TMPB), tolower(paste0(ROOT, "/")))) stop("tempdir 가 ROOT 안이다 — 합성 루트가 운영 트리에 생긴다. TMPDIR 을 루트 밖으로")
LIB <- file.path(ROOT, "02_Infrastructure/reinforcement/rf_prereg.R")
CFG <- file.path(ROOT, "06_Registry/prereg/prereg_config.json")
if (!file.exists(LIB) || !file.exists(CFG)) stop("rf_prereg.R 또는 prereg_config.json 부재 — ROOT 확인: ", ROOT)

## ── 합성 루트 ──────────────────────────────────────────────────────────────────
COPY <- c("02_Infrastructure/reinforcement/rf_prereg.R", "02_Infrastructure/reinforcement/reinforce_ledger.R",
          "02_Infrastructure/reinforcement/rf_overlay_adversary.R", "02_Infrastructure/reinforcement/rf_runner_gates.R",
          "02_Infrastructure/contracts/required_effect_size.R", "02_Infrastructure/contracts/defensive_score.R",
          "02_Infrastructure/contracts/essence_score.R", "02_Infrastructure/contracts/beta_controlled_alpha.R",
          "02_Infrastructure/contracts/no_signal_control.R", "02_Infrastructure/tools/hypothesis_index.R",
          "02_Infrastructure/reinforcement/rf_sleeve.R",   # sleeve_delivery 계약 파일(PREREGFIX)
          "06_Registry/prereg/prereg_config.json")
.nroot <- 0L
new_root <- function(tag = "r", floors = TRUE, lib = NULL) {
  .nroot <<- .nroot + 1L
  r <- file.path(TMPB, sprintf("%s_%02d", tag, .nroot)); dir.create(file.path(r, "02_Infrastructure"), recursive = TRUE)
  file.create(file.path(r, "02_Infrastructure/config.R"))
  for (f in COPY) { dir.create(dirname(file.path(r, f)), recursive = TRUE, showWarnings = FALSE); file.copy(file.path(ROOT, f), file.path(r, f)) }
  if (!is.null(lib)) file.copy(lib, file.path(r, "02_Infrastructure/reinforcement/rf_prereg.R"), overwrite = TRUE)
  dir.create(file.path(r, "stage_artifacts"), showWarnings = FALSE)
  writeLines(toJSON(list(entries = list(
    list(strategy_id = "SYN_DEF_1", hypothesis_signature = "defense|low_volatility|k200_kq150|equal25", title = "defensive sleeve synthetic",
         verdict = "FAIL", grade = "F", date = "2026-01-01", source_types = list("lcode"), research_mode = "reinforcement_cell"))),
    auto_unbox = TRUE), file.path(r, "06_Registry/hypothesis_index.json"))
  m <- function(pt, inh = FALSE) { e <- list(port_t = pt); if (inh) e$inherited_from <- "X"; list(essence = e) }
  writeLines(toJSON(list(schema_version = "reinforce_ledger_v2", current_axis = "exec_v2_close_t1", entries = list(
    list(base_id = "R", attempts = list(m(1.1), m(2.2), m(3.3, TRUE), list(grade = "NA"))),
    list(base_id = "R_p1", parent = list(base_id = "R"), attempts = list(m(1.0), m(NULL)))
  )), auto_unbox = TRUE, null = "null"), file.path(r, "06_Registry/reinforce_ledger_l1.json"))
  file.create(file.path(r, "06_Registry/rf_decisions.jsonl"))
  if (floors) writeLines(toJSON(list(floors = list(list(id = "F", status = "confirmed", determinism_ok = TRUE, selection_basis = "as_of",
                                                        measurement_regime = list(exec_price = "close_t1"), vintage_flags = list()))),
                                auto_unbox = TRUE), file.path(r, "06_Registry/prereg/reference_floors_v2.json"))
  dir.create(dirname(file.path(r, CAL_REL)), recursive = TRUE, showWarnings = FALSE)   # 1차 판정 교정 산출물(합성 · α=0.05 · t 분위 ±2.6)
  writeLines(toJSON(list(rule = list(alpha_cal = 0.05), threshold = list(t_lo = -2.6, t_hi = 2.6)), auto_unbox = TRUE, digits = NA), file.path(r, CAL_REL))
  normalizePath(r, winslash = "/")
}
CAL_REL <- "stage_artifacts/prereg/_calibration/TEST/calibration.json"
cal_from <- function(L, root, field) list(artifact = CAL_REL, artifact_sha256 = unname(L$.rfp_sha_file(file.path(root, CAL_REL))), field = field)
load_lib <- function(path) { e <- new.env(parent = globalenv()); invisible(capture.output(sys.source(path, envir = e, keep.source = FALSE))); e }

## 합성 사전등록(등록 가능한 완전형)
at <- function(m, t, s, op, rhs) list(metric = m, target = t, stat = s, op = op, rhs = rhs)
rf <- function(m, t, s = "value") list(ref = list(metric = m, target = t, stat = s))
syn_pr <- function(L, root, id = "PR-T-SYN", fam = "FAM-T-SYN-01", rev = 1L, halt = FALSE, implied = -0.05, se = 0.02) {
  cfg <- L$rf_prereg_config(root); pw <- L$rf_prereg_power(implied, se = se, root = root, cfg = cfg)
  list(schema = "rf_prereg_v1", prereg_id = id, family_id = fam, status = "draft", draft_rev = rev, revision_of = NULL, layer = 1L,
    lever = "TEST", title = "합성", framing = "falsification_attempt", hypothesis = list(statement = "s", mechanism = "m"),
    floors = list(list(id = "F", ref = "06_Registry/prereg/reference_floors_v2.json#F", status = "confirmed")),
    arms_frozen = TRUE,
    arms = list(list(id = "T1", order = 1L, role = "treatment", on_floor = "F", selection_basis = "as_of", spec = list(k = 5)),
                list(id = "C1", order = 2L, role = "control", on_floor = "F", selection_basis = "none", spec = list(k = 5, random = TRUE)),
                list(id = "T2", order = 3L, role = "treatment", on_floor = "F", selection_basis = "as_of", spec = list(k = 8))),
    deleted_arms = list(),
    contrasts = list(list(id = "T1-F", a = "T1", b = "F"), list(id = "T1-C1", a = "T1", b = "C1"), list(id = "T2-F", a = "T2", b = "F")),
    se_cells = list(list(id = "F.NULL", on_floor = "F", kind = "null_dilution", counts_in_n = FALSE)),
    metrics = list(list(id = "prim", tier = "primary", contract = "rf_prereg_paired_boot", direction = "decrease", targets = list("T1-F", "T1-C1", "T2-F")),
                   list(id = "cal", tier = "secondary", contract = "essence_score", direction = "increase", targets = list("T1", "F", "T2")),
                   list(id = "rep", tier = "safety", contract = "beta_controlled_alpha", direction = "report", must_report = TRUE, targets = list("T1")),
                   list(id = "tilt", tier = "safety", contract = "tilt_attribution", direction = "report", targets = list("T1"))),
    criteria = list(success = list(at("prim", "T1-F", "ci_hi", "<", 0), at("cal", "T1", "value", ">", rf("cal", "F"))),
                    failure = list(list(all = list(at("prim", "T1-F", "ci_hi", "<", 0), at("prim", "T1-C1", "ci_hi", ">=", 0)))),
                    stop = list(list(id = "STOP1", after_arms = list("T1", "C1"), when = at("prim", "T1-F", "ci_hi", ">=", 0),
                                     action = if (halt) list(halt = TRUE) else list(skip_arms = list("T2"))))),
    labels = cfg$labels,
    power = list(primary = list(metric = "prim", target = "T1-F"), ci_level = cfg$bootstrap$ci_level,
                 implied_effect = list(value = implied, formula = "합성"), se = list(value = se, source = list("block_bootstrap")),
                 computed = pw[c("ratio", "expected_t", "power", "disposition")], modal_outcome = "undetermined", leaves_behind = list("계기")),
    se_source = list(methods = list("null_dilution", "block_bootstrap")), budget = list(max_cells = 3L),
    priors = list(mechanism = 0.3, success = list(lo = 0.1, hi = 0.2), grade_a = 0.01, basis = "합성"),
    hypothesis_index_lookup = L$rf_prereg_lookup(list(c("defensive")), root = root, max_rows = 3L),
    pit = list(as_of_selection = TRUE, statements = list("합성")),
    measurement_regime = list(exec_price = "close_t1", pin_tag = "pin_test"),
    selection_accounting = list(selection_type = "sweep", n_family = 4L, n_source = "합성"),
    dependencies = list(), open_questions = list(),
    decision_params = list(list(id = "alpha_cal", value = 0.05, from = cal_from(L, root, "rule/alpha_cal")),
                           list(id = "alpha_cal_upper", value = 0.95, derive = list(op = "one_minus", of = "alpha_cal"))))
}
## syn_pr 에 1차 판정 교정을 싣는다(교정 없는 등록 = 차단 · PREREG-POWERED-NULL-CALIBRATION)
.syn_pr0 <- syn_pr
syn_pr <- function(L, root, ...) { p <- .syn_pr0(L, root, ...); p$power$calibration <- list(kind = "bootstrap_p", params = list(alpha = "alpha_cal")); p }
reg <- function(L, root, ...) { pr <- syn_pr(L, root, ...); L$rf_prereg_write(pr, "draft", root); L$rf_prereg_register(pr$prereg_id, root = root)
  L$rf_prereg_load(pr$prereg_id, "registered", root = root) }
reg_pr <- function(L, root, pr) { L$rf_prereg_write(pr, "draft", root); L$rf_prereg_register(pr$prereg_id, root = root)
  L$rf_prereg_load(pr$prereg_id, "registered", root = root) }
meas <- function(L, root, pid, metric, target, contract, ..., regime = "close_t1", name = NULL) {
  obj <- c(list(contract = contract, metric = metric, target = target), list(...))
  if (identical(contract, "rf_prereg_paired_boot")) {   # 정직 경로 = 설정값(B·seed·ci_level)으로 낸 산출물(판정이 pinned 로 대조)
    cb <- L$rf_prereg_config(root)
    obj <- c(obj, list(B = cb$bootstrap$B, seed = cb$bootstrap$seed, config_sha256 = attr(cb, "sha256")))
    if (is.null(obj$ci_level)) obj$ci_level <- cb$bootstrap$ci_level
  }
  src <- L$rf_prereg_artifact(obj, pid, name %||% gsub("[^A-Za-z0-9_.-]", "_", paste(metric, target, sep = "_")), list(exec_price = regime), root)
  c(list(metric = metric, target = target), list(...), list(source = src))
}
## 1차(prim|T1-F) 측정 — 교정 통계 동봉(산출물 cal_alpha = 등록 α 0.05)
pmeas <- function(L, root, pid, v, lo, hi, p, qlo, qhi, name = NULL, alpha = 0.05, target = "T1-F")
  meas(L, root, pid, "prim", target, "rf_prereg_paired_boot", value = v, ci_lo = lo, ci_hi = hi, ci_level = 0.9, p_gt0 = p,
       cal_alpha = alpha, cal_q_lo = qlo, cal_q_hi = qhi, name = name)
## 측정 묶음 — kind: confirmed | failed | pnull | undet
mset <- function(L, root, pid, kind, with_rep = TRUE) {
  ci <- switch(kind, confirmed = c(-0.05, -0.09, -0.02), failed = c(-0.05, -0.09, -0.02), pnull = c(-0.005, -0.02, 0.01), undet = c(-0.03, -0.08, 0.01))
  cq <- switch(kind, confirmed = c(0.01, -0.10, -0.015), failed = c(0.01, -0.10, -0.015), pnull = c(0.30, -0.025, 0.015), undet = c(0.10, -0.085, 0.02))
  tc <- if (kind == "failed") c(-0.02, -0.05, 0.01) else c(-0.03, -0.06, -0.01)
  x <- list(pmeas(L, root, pid, ci[1], ci[2], ci[3], cq[1], cq[2], cq[3]),
            meas(L, root, pid, "prim", "T1-C1", "rf_prereg_paired_boot", value = tc[1], ci_lo = tc[2], ci_hi = tc[3], ci_level = 0.9),
            meas(L, root, pid, "cal", "T1", "essence_score", value = 0.5), meas(L, root, pid, "cal", "F", "essence_score", value = 0.4))
  if (with_rep) x <- c(x, list(meas(L, root, pid, "rep", "T1", "beta_controlled_alpha", value = 0.8)))
  x
}
dec_lines <- function(root) { p <- file.path(root, "06_Registry/rf_decisions.jsonl"); if (!file.exists(p)) 0L else length(Filter(nzchar, readLines(p, warn = FALSE))) }

## 합성 루트의 원장 writer rf_open_entry formals 에 priority·experiment 를 놓거나 뺀다(P1-08 — HUMAN 판·주입 꼴 모두) · TRUE = 결과가 원하는 꼴
set_p108 <- function(r, present) {
  lg <- file.path(r, "02_Infrastructure/reinforcement/reinforce_ledger.R")
  tx <- paste(readLines(lg, encoding = "UTF-8", warn = FALSE), collapse = "\n")
  tx <- gsub(",\\s*priority = \"normal\", experiment = NULL\\)", ")", tx)
  tx <- gsub("base_grade, priority = \"normal\", experiment = NULL,", "base_grade,", tx, fixed = TRUE)
  if (present) tx <- sub("rf_open_entry <- function(layer, base_id, base_grade,", "rf_open_entry <- function(layer, base_id, base_grade, priority = \"normal\", experiment = NULL,", tx, fixed = TRUE)
  writeLines(tx, lg, useBytes = TRUE)
  ex <- parse(lg, encoding = "UTF-8", keep.source = FALSE)
  oe <- Filter(function(e) is.call(e) && identical(as.character(e[[1]]), "<-") && identical(as.character(e[[2]]), "rf_open_entry"), as.list(ex))
  fm <- if (length(oe)) names(as.list(oe[[1]][[3]][[2]])) else character(0)
  identical(all(c("priority", "experiment") %in% fm), isTRUE(present))
}
## ── PREREGFIX 픽스처(2026-10-03) ─────────────────────────────────────────────────────
reg_view <- function(p) modifyList(p, list(status = "registered", draft_rev = NULL))
## 기전 한정 바닥(rf_floor_v2 의 confirmed_mechanism_only 꼴) — permitted_use · a_eligible · use_restriction 을 바꿔 위반 주입
mo_floor <- function(r, permitted_use = "mechanism_only", a_eligible = FALSE, decision_id = "FLOOR-BASE-ENGINE-Q4")
  writeLines(toJSON(list(floors = list(F = list(id = "F", status = "confirmed_mechanism_only", determinism_ok = TRUE, selection_basis = "as_of",
    measurement_regime = list(exec_price = "close_t1"), a_eligible = a_eligible, permitted_use = permitted_use,
    use_restriction = list(kind = "mechanism_only", decision_id = decision_id, a_eligible = FALSE)))), auto_unbox = TRUE),
    file.path(r, "06_Registry/prereg/reference_floors_v2.json"))
mo_pr <- function(L, r, ...) { p <- syn_pr(L, r, ...); p$scope <- list(label = "mechanism_only", a_eligible = FALSE, decision_ref = "FLOOR-BASE-ENGINE-Q4"); p }
## 처치 전달 타당성 픽스처 — 전달량 지표(sleeve_delivery) + 하한 = derive disposition_floor_over_ratio(설정 power_gate · 재계산 ratio)
val_pr <- function(L, r, halt = FALSE, write = TRUE) {
  p <- syn_pr(L, r, id = if (halt) "PR-T-VH" else "PR-T-VL", fam = if (halt) "FAM-T-VH-01" else "FAM-T-VL-01", halt = halt)
  p$metrics <- c(p$metrics, list(list(id = "deliv", tier = "safety", contract = "sleeve_delivery", direction = "report", targets = list("T1"))))
  dp <- list(id = "delivery_floor", value = NULL, derive = list(op = "disposition_floor_over_ratio"))
  dp$value <- L$.rfp_derive_param(dp, list(), p, r, L$rf_prereg_config(r))
  p$decision_params <- c(p$decision_params, list(dp))
  p$criteria$validity <- list(list(id = "V_DELIV_T1", metric = "deliv", target = "T1", stat = "value", op = ">=", rhs = list(param = "delivery_floor"),
                                   outcome = "treatment_dilution"))
  if (!write) return(p)
  reg_pr(L, r, p)
}

## ── 가드 검사 함수(돌연변이 재사용 — TRUE = 가드가 제대로 작동) ─────────────────────
G <- list(
  forbidden_se = function(L) { r <- new_root("fse"); pr <- syn_pr(L, r); pr$power$se$source <- list("phase_pair")
    v <- L$rf_prereg_validate(pr, "draft", r); !v$ok && any(grepl("금지 SE", v$errors)) },
  overwrite = function(L) { r <- new_root("ow"); pr <- syn_pr(L, r); w <- L$rf_prereg_write(pr, "draft", r); s0 <- w$sha256
    pr$title <- "바뀐 제목"; e <- err_of(L$rf_prereg_write(pr, "draft", r))
    !is.na(e) && identical(unname(L$.rfp_sha_file(w$path)), s0) },
  tamper = function(L) { r <- new_root("tp"); pr <- syn_pr(L, r); w <- L$rf_prereg_write(pr, "draft", r)
    tx <- readLines(w$path, encoding = "UTF-8", warn = FALSE); hit <- any(grepl('"title": "합성"', tx, fixed = TRUE))
    tx <- sub('"title": "합성"', '"title": "변조"', tx, fixed = TRUE); writeLines(tx, w$path, useBytes = TRUE)   # JSON 유효성 유지 · 값만 변조
    hit && !is.null(tryCatch(jsonlite::fromJSON(w$path), error = function(e) NULL)) && !is.na(err_of(L$rf_prereg_load(pr$prereg_id, "draft", root = r))) },
  failed_precedence = function(L) { r <- new_root("fp"); pr <- reg(L, r); v <- L$rf_prereg_verdict(pr, mset(L, r, pr$prereg_id, "failed"), root = r, record = FALSE)
    identical(v$label, "failed") },
  regime = function(L) { r <- new_root("rg"); pr <- reg(L, r); M <- mset(L, r, pr$prereg_id, "confirmed")
    M[[3]]$source$measurement_regime <- list(exec_price = "close_d_legacy")   # 산출물 안은 close_t1 · 주장만 legacy — 주장 대조를 따로 잰다
    e <- err_of(L$rf_prereg_verdict(pr, M, root = r, record = FALSE)); !is.na(e) && grepl("규약", e) },
  artifact_regime = function(L) { r <- new_root("ar"); pr <- reg(L, r); M <- mset(L, r, pr$prereg_id, "confirmed")
    src <- L$rf_prereg_artifact(list(contract = "essence_score", value = 0.5), pr$prereg_id, "cal_T1_legacy_inside", list(exec_price = "close_d_legacy"), r)
    src$measurement_regime <- list(exec_price = "close_t1"); M[[3]]$source <- src
    e <- err_of(L$rf_prereg_verdict(pr, M, root = r, record = FALSE)); !is.na(e) && grepl("산출물 안 규약", e) },
  stop_enforced = function(L) { r <- new_root("st"); pr <- reg(L, r); M <- c(mset(L, r, pr$prereg_id, "pnull"),
      list(meas(L, r, pr$prereg_id, "prim", "T2-F", "rf_prereg_paired_boot", value = -0.01, ci_lo = -0.03, ci_hi = 0.01, ci_level = 0.9)))
    e <- err_of(L$rf_prereg_verdict(pr, M, root = r, record = FALSE)); !is.na(e) && grepl("멈춤 위반", e) },
  artifact_sha = function(L) { r <- new_root("as"); pr <- reg(L, r); M <- mset(L, r, pr$prereg_id, "confirmed")
    p <- file.path(r, M[[3]]$source$artifact); cat(" ", file = p, append = TRUE)
    e <- err_of(L$rf_prereg_verdict(pr, M, root = r, record = FALSE)); !is.na(e) && grepl("sha256", e) },
  reverdict = function(L) { r <- new_root("rv"); pr <- reg(L, r); M <- mset(L, r, pr$prereg_id, "confirmed")
    v1 <- L$rf_prereg_verdict(pr, M, root = r, record = TRUE); e <- err_of(L$rf_prereg_verdict(pr, M, root = r, record = TRUE))
    isTRUE(v1$recorded) && !is.na(e) && grepl("이미 판정", e) && dec_lines(r) == 1L },
  selbasis = function(L) { r <- new_root("sb"); pr <- syn_pr(L, r); pr$arms[[1]]$selection_basis <- "full_sample"
    v <- L$rf_prereg_validate(pr, "draft", r); !v$ok && any(grepl("selection_basis", v$errors)) },
  power_t80 = function(L) { r <- new_root("pw"); cfg <- L$rf_prereg_config(r)
    t80 <- qnorm(0.8) + qnorm(0.975); tab <- rbind(c(0.10, 0.280, 0.046), c(0.30, 0.840, 0.131), c(0.50, 1.401, 0.288),
                                                   c(0.70, 1.961, 0.500), c(0.85, 2.381, 0.663), c(1.00, 2.802, 0.800))
    all(apply(tab, 1, function(z) { q <- L$rf_prereg_power(z[1] * t80 * 0.01, se = 0.01, root = r, cfg = cfg)
      abs(q$ratio - z[1]) < 1e-9 && abs(q$expected_t - z[2]) < 0.0015 && abs(q$power - z[3]) < 0.0015 })) },
  paired = function(L) { r <- new_root("pa"); set.seed(7); b <- rnorm(600, 0, 0.02); a <- b + 0.0004 + rnorm(600, 0, 0.001)
    q <- L$rf_prereg_paired_boot(a, b, "mean", root = r, B = 400); unp <- sqrt(var(a) / 600 + var(b) / 600)
    is.finite(q$se) && q$se < 0.25 * unp && q$ci_lo > 0 },
  dryrun_only = function(L) { r <- new_root("dr"); pr <- reg(L, r); e <- err_of(L$rf_prereg_run(pr$prereg_id, root = r, dry_run = FALSE))
    !is.na(e) && grepl("드라이런 전용", e) },
  must_report = function(L) { r <- new_root("mr"); pr <- reg(L, r); n0 <- dec_lines(r)
    v <- L$rf_prereg_verdict(pr, mset(L, r, pr$prereg_id, "confirmed", with_rep = FALSE), root = r, record = TRUE)
    identical(v$status, "incomplete") && is.null(v$label) && dec_lines(r) == n0 },
  power_recompute = function(L) { r <- new_root("pr"); pr <- syn_pr(L, r); pr$status <- "registered"; pr$draft_rev <- NULL
    pr$power$computed$ratio <- pr$power$computed$ratio * 1.5
    v <- L$rf_prereg_validate(pr, "registered", r); any(grepl("재계산과 다르다", v$errors)) },
  undeclared_target = function(L) { r <- new_root("ut"); pr <- reg(L, r)
    M <- c(mset(L, r, pr$prereg_id, "confirmed"), list(meas(L, r, pr$prereg_id, "cal", "T9", "essence_score", value = 0.9)))
    e <- err_of(L$rf_prereg_verdict(pr, M, root = r, record = FALSE)); !is.na(e) && grepl("미선언 대상", e) },
  ## ── 적대 검증(2026-09-25) 수리분 — 각 가드의 위반 주입 + 필요한 곳은 양성 대조 ──
  hand_numbers = function(L) { r <- new_root("hn"); pr <- reg(L, r); M <- mset(L, r, pr$prereg_id, "undet"); M[[1]]$ci_hi <- -0.02
    e <- err_of(L$rf_prereg_verdict(pr, M, root = r, record = FALSE)); !is.na(e) && grepl("≠ 산출물", e) && grepl("AX-008", e) },
  fill_from_artifact = function(L) { r <- new_root("fa"); pr <- reg(L, r)
    M <- lapply(mset(L, r, pr$prereg_id, "confirmed"), function(m) m[c("metric", "target", "source")])
    v <- L$rf_prereg_verdict(pr, M, root = r, record = FALSE); identical(v$label, "confirmed") && isTRUE(abs(v$primary$ci_hi - (-0.02)) < 1e-12) },
  verify_off = function(L) { r <- new_root("vo"); pr <- reg(L, r); n0 <- dec_lines(r)
    e <- err_of(L$rf_prereg_verdict(pr, mset(L, r, pr$prereg_id, "confirmed"), root = r, record = TRUE, verify_artifacts = FALSE))
    !is.na(e) && grepl("verify_artifacts", e) && dec_lines(r) == n0 },
  stop_undecidable = function(L) { r <- new_root("su"); p <- syn_pr(L, r, id = "PR-T-SU", fam = "FAM-T-SU-01")
    p$metrics <- c(p$metrics, list(list(id = "trunc", tier = "secondary", contract = "essence_score", direction = "increase", targets = list("T1", "F"))))
    p$criteria$stop[[1]]$when <- at("trunc", "T1", "value", "<", rf("trunc", "F")); pr <- reg_pr(L, r, p)
    M <- c(mset(L, r, pr$prereg_id, "confirmed"),
           list(meas(L, r, pr$prereg_id, "prim", "T2-F", "rf_prereg_paired_boot", value = -0.01, ci_lo = -0.03, ci_hi = 0.01, ci_level = 0.9)))
    e1 <- err_of(L$rf_prereg_verdict(pr, M, root = r, record = FALSE))                                   # 멈춤 지표 생략
    e2 <- err_of(L$rf_prereg_verdict(pr, c(M, list(meas(L, r, pr$prereg_id, "trunc", "T1", "essence_score", value = NA_real_),
                                                      meas(L, r, pr$prereg_id, "trunc", "F", "essence_score", value = 0.5))), root = r, record = FALSE))  # NA 제출
    v3 <- L$rf_prereg_verdict(pr, c(M, list(meas(L, r, pr$prereg_id, "trunc", "T1", "essence_score", value = 0.6, name = "trunc_T1_ok"),
                                            meas(L, r, pr$prereg_id, "trunc", "F", "essence_score", value = 0.5, name = "trunc_F_ok"))), root = r, record = FALSE)
    grepl("판정 불능", e1) && grepl("판정 불능", e2) && identical(v3$status, "concluded") && "T2" %in% unlist(v3$arms_measured) },
  stop_target = function(L) { r <- new_root("stv"); p <- syn_pr(L, r); p$criteria$stop[[1]]$when <- at("cal", "T2", "value", "<", 0)
    v <- L$rf_prereg_validate(p, "draft", r); !v$ok && any(grepl("체크포인트 뒤 arm", v$errors)) },
  pnull_zero = function(L) { r <- new_root("pz"); pr <- reg(L, r); M <- mset(L, r, pr$prereg_id, "confirmed")
    M[[1]] <- pmeas(L, r, pr$prereg_id, 0.03, 0.01, 0.05, 0.99, 0.005, 0.055, name = "prim_T1F_opp")
    v <- L$rf_prereg_verdict(pr, M, root = r, record = FALSE); identical(v$label, "undetermined") && identical(v$primary$powered_null, FALSE) },
  cfg_pin = function(L) { r <- new_root("cp"); pr <- reg(L, r); M <- mset(L, r, pr$prereg_id, "failed")
    cp <- file.path(r, "06_Registry/prereg/prereg_config.json"); cj <- fromJSON(cp, simplifyVector = FALSE)
    cj$label_precedence <- list("confirmed", "failed", "powered_null", "undetermined")
    writeLines(toJSON(cj, auto_unbox = TRUE, null = "null", pretty = TRUE, digits = NA), cp)
    e <- err_of(L$rf_prereg_verdict(pr, M, root = r, record = FALSE)); !is.na(e) && grepl("설정이 등록 뒤", e) },
  prereg_time = function(L) { r <- new_root("pt"); p <- syn_pr(L, r); M <- mset(L, r, p$prereg_id, "confirmed"); Sys.sleep(1.2)
    pr <- reg_pr(L, r, p); e <- err_of(L$rf_prereg_verdict(pr, M, root = r, record = FALSE))
    M2 <- list(pmeas(L, r, pr$prereg_id, -0.05, -0.09, -0.02, 0.01, -0.10, -0.015, name = "post_T1F"),
               meas(L, r, pr$prereg_id, "prim", "T1-C1", "rf_prereg_paired_boot", value = -0.03, ci_lo = -0.06, ci_hi = -0.01, ci_level = 0.9, name = "post_T1C1"),
               meas(L, r, pr$prereg_id, "cal", "T1", "essence_score", value = 0.5, name = "post_cal_T1"), M[[4]],   # cal|F = 바닥 — 등록 전 산출물 허용(양성 대조)
               meas(L, r, pr$prereg_id, "rep", "T1", "beta_controlled_alpha", value = 0.8, name = "post_rep_T1"))
    v <- L$rf_prereg_verdict(pr, M2, root = r, record = FALSE)
    !is.na(e) && grepl("보다 먼저 쓰였다", e) && identical(v$label, "confirmed") },
  seed_pin = function(L) { r <- new_root("sp"); pr <- reg(L, r); M <- mset(L, r, pr$prereg_id, "confirmed")
    M[[1]]$source <- L$rf_prereg_artifact(list(contract = "rf_prereg_paired_boot", metric = "prim", target = "T1-F", value = -0.05, ci_lo = -0.09,
      ci_hi = -0.02, ci_level = 0.9, B = 200L, seed = 17L, p_gt0 = 0.01, cal_alpha = 0.05, cal_q_lo = -0.10, cal_q_hi = -0.015,   # 교정 통계는 정직(seed·B 만 다르다)
      config_sha256 = attr(L$rf_prereg_config(r), "sha256")), pr$prereg_id, "prim_T1F_seed17", list(exec_price = "close_t1"), r)
    e <- err_of(L$rf_prereg_verdict(pr, M, root = r, record = FALSE)); !is.na(e) && grepl("쇼핑", e) },
  halt_must_report = function(L) { r <- new_root("hm"); pr <- reg(L, r, id = "PR-T-HM", fam = "FAM-T-HM-01", halt = TRUE); n0 <- dec_lines(r)
    v <- L$rf_prereg_verdict(pr, mset(L, r, pr$prereg_id, "pnull", with_rep = FALSE), root = r, record = TRUE)
    identical(v$status, "incomplete") && is.null(v$label) && dec_lines(r) == n0 },
  target_bind = function(L) { r <- new_root("tb"); pr <- reg(L, r); M <- mset(L, r, pr$prereg_id, "confirmed")
    M[[3]]$source <- M[[4]]$source; M[[3]]$value <- NULL                      # 바닥 F 의 산출물을 T1 측정으로
    e <- err_of(L$rf_prereg_verdict(pr, M, root = r, record = FALSE)); !is.na(e) && grepl("다른 대상의 산출물", e) },
  artifact_reuse = function(L) { r <- new_root("au"); pr <- reg(L, r); M <- mset(L, r, pr$prereg_id, "confirmed")
    s2 <- L$rf_prereg_artifact(list(contract = "essence_score", essence = list(calmar = 0.45)), pr$prereg_id, "ess_shared", list(exec_price = "close_t1"), r)
    s2$fields <- list(value = "essence/calmar"); M[[3]]$source <- s2; M[[4]]$source <- s2; M[[3]]$value <- NULL; M[[4]]$value <- NULL
    e <- err_of(L$rf_prereg_verdict(pr, M, root = r, record = FALSE))
    r3 <- new_root("au"); pr3 <- reg(L, r3); M3 <- mset(L, r3, pr3$prereg_id, "confirmed")   # 양성 대조: 중첩 산출물(fields) 1대상
    s3 <- L$rf_prereg_artifact(list(contract = "essence_score", essence = list(calmar = 0.55)), pr3$prereg_id, "ess_T1", list(exec_price = "close_t1"), r3)
    s3$fields <- list(value = "essence/calmar"); M3[[3]]$source <- s3; M3[[3]]$value <- NULL
    v3 <- L$rf_prereg_verdict(pr3, M3, root = r3, record = FALSE)
    !is.na(e) && grepl("서로 다른 대상", e) && identical(v3$label, "confirmed") },
  sign = function(L) { r <- new_root("sg"); p <- syn_pr(L, r, implied = 0.05); p$status <- "registered"; p$draft_rev <- NULL
    v <- L$rf_prereg_validate(p, "registered", r); !v$ok && any(grepl("부호", v$errors)) },
  ## ── PREREGFIX(2026-10-03) — 기전 한정 바닥 · 1차 판정 교정 · 결정 파라미터 · 처치 전달 타당성 ──
  mo_scope = function(L) { r <- new_root("mo"); mo_floor(r)                         # A 경로(scope 없음) + 기전 한정 바닥 → 차단
    v <- L$rf_prereg_validate(reg_view(syn_pr(L, r)), "registered", r)
    vm <- L$rf_prereg_validate(reg_view(mo_pr(L, r)), "registered", r)              # 양성 대조: scope=mechanism_only ∧ a_eligible=false → 통과
    !v$ok && any(grepl("기전 한정 바닥은", v$errors)) && vm$ok },
  mo_scope_aelig = function(L) { r <- new_root("ma"); mo_floor(r)
    p1 <- mo_pr(L, r); p1$scope$a_eligible <- TRUE; p2 <- mo_pr(L, r); p2$scope$a_eligible <- "false"
    v1 <- L$rf_prereg_validate(reg_view(p1), "registered", r); v2 <- L$rf_prereg_validate(reg_view(p2), "registered", r)
    any(grepl("기전 한정 바닥은", v1$errors)) && !v2$ok },
  mo_floor = function(L) { r <- new_root("mf"); mo_floor(r, permitted_use = "none")
    v <- L$rf_prereg_validate(reg_view(mo_pr(L, r)), "registered", r); !v$ok && any(grepl("permitted_use", v$errors)) },
  mo_floor_aelig = function(L) { r <- new_root("mg"); mo_floor(r, a_eligible = TRUE)
    v <- L$rf_prereg_validate(reg_view(mo_pr(L, r)), "registered", r); !v$ok && any(grepl("a_eligible=", v$errors, fixed = TRUE)) },
  mo_restriction = function(L) { r <- new_root("mr2"); mo_floor(r, decision_id = "OTHER-DECISION")
    v <- L$rf_prereg_validate(reg_view(mo_pr(L, r)), "registered", r); !v$ok && any(grepl("use_restriction", v$errors)) },
  cfg_mo = function(L) { r <- new_root("cm"); cp <- file.path(r, "06_Registry/prereg/prereg_config.json"); cj <- fromJSON(cp, simplifyVector = FALSE)
    cj$registration$mechanism_only_scope$a_eligible <- TRUE; writeLines(toJSON(cj, auto_unbox = TRUE, null = "null", pretty = TRUE, digits = NA), cp)
    grepl("a_eligible 은 false", err_of(L$rf_prereg_config(r))) },
  cal_required = function(L) { r <- new_root("cr"); p <- reg_view(syn_pr(L, r)); p$power$calibration <- NULL
    v <- L$rf_prereg_validate(p, "registered", r); !v$ok && any(grepl("교정 미선언", v$errors)) },
  cal_verdict_refuse = function(L) { r <- new_root("cv"); pr <- reg(L, r); M <- mset(L, r, pr$prereg_id, "confirmed")
    p2 <- pr; p2$power$calibration <- NULL; attr(p2, "integrity") <- attr(pr, "integrity")   # 메모리에서 교정을 지운 등록본(파일·색인 무결성은 그대로)
    e <- err_of(L$rf_prereg_verdict(p2, M, root = r, record = FALSE)); !is.na(e) && grepl("power.calibration)이 없다", e, fixed = TRUE) },
  cal_mech = function(L) { r <- new_root("cmh"); pr <- reg(L, r); M <- mset(L, r, pr$prereg_id, "confirmed")
    M[[1]] <- pmeas(L, r, pr$prereg_id, -0.04, -0.08, -0.004, 0.08, -0.09, 0.006, name = "prim_T1F_nomonly")   # 명목 CI 상한<0 · 교정 p ≥ α
    v <- L$rf_prereg_verdict(pr, M, root = r, record = FALSE)
    r2 <- new_root("cmh"); pr2 <- reg(L, r2)                                                                    # 양성 대조: p < α → 탐지
    v2 <- L$rf_prereg_verdict(pr2, mset(L, r2, pr2$prereg_id, "confirmed"), root = r2, record = FALSE)
    identical(v$primary$mechanism_detected, FALSE) && identical(v2$primary$mechanism_detected, TRUE) },
  cal_pnull = function(L) { r <- new_root("cpn"); pr <- reg(L, r); M <- mset(L, r, pr$prereg_id, "pnull")
    M[[1]] <- pmeas(L, r, pr$prereg_id, -0.005, -0.02, 0.01, 0.30, -0.06, 0.03, name = "prim_T1F_wide")   # 명목은 함의(−0.05) 배제 · 교정 α 분위는 못 배제
    v <- L$rf_prereg_verdict(pr, M, root = r, record = FALSE)
    identical(v$label, "undetermined") && identical(v$primary$powered_null, FALSE) && identical(v$primary$implied_excluded_calibrated, FALSE) },
  cal_alpha_pin = function(L) { r <- new_root("cap"); pr <- reg(L, r); M <- mset(L, r, pr$prereg_id, "confirmed")
    M[[1]] <- pmeas(L, r, pr$prereg_id, -0.05, -0.09, -0.02, 0.01, -0.12, -0.01, name = "prim_T1F_a10", alpha = 0.10)
    e <- err_of(L$rf_prereg_verdict(pr, M, root = r, record = FALSE)); !is.na(e) && grepl("등록 교정값", e) },
  cal_t = function(L) { r <- new_root("ct"); p <- syn_pr(L, r, id = "PR-T-CT", fam = "FAM-T-CT-01")
    p$decision_params <- c(p$decision_params, list(list(id = "t_lo", value = -2.6, from = cal_from(L, r, "threshold/t_lo")),
                                                   list(id = "t_hi", value = 2.6, from = cal_from(L, r, "threshold/t_hi"))))
    p$power$calibration <- list(kind = "null_t_quantile", params = list(t_lo = "t_lo", t_hi = "t_hi")); pr <- reg_pr(L, r, p)
    tm <- function(nm, v, tt, se) { cb <- L$rf_prereg_config(r)   # meas(...) 는 t= 가 target 에 부분 일치하므로 산출물을 직접 쓴다
      obj <- list(contract = "rf_prereg_paired_boot", metric = "prim", target = "T1-F", value = v, ci_lo = v - 0.02, ci_hi = v + 0.02, ci_level = 0.9,
                  t = tt, se = se, B = cb$bootstrap$B, seed = cb$bootstrap$seed, config_sha256 = attr(cb, "sha256"))
      list(metric = "prim", target = "T1-F", source = L$rf_prereg_artifact(obj, pr$prereg_id, nm, list(exec_price = "close_t1"), r)) }
    base <- mset(L, r, pr$prereg_id, "pnull")[-1]
    v1 <- L$rf_prereg_verdict(pr, c(list(tm("t_pn", -0.005, -0.5, 0.01)), base), root = r, record = FALSE)   # (−0.005+0.05)/0.01 = 4.5 ≥ 2.6 · 0 포함
    v2 <- L$rf_prereg_verdict(pr, c(list(tm("t_opp", 0.03, 3, 0.01)), base), root = r, record = FALSE)       # 반대 방향 유의 → 부재 아님
    v3 <- L$rf_prereg_verdict(pr, c(list(tm("t_mech", -0.04, -3.1, 0.013)), base), root = r, record = FALSE) # t ≤ t_lo → 탐지
    isTRUE(v1$primary$powered_null) && identical(v2$primary$powered_null, FALSE) && isTRUE(v3$primary$mechanism_detected) &&
      identical(v1$primary$mechanism_detected, FALSE) },
  param_source = function(L) { r <- new_root("ps"); p <- reg_view(syn_pr(L, r)); p$decision_params[[1]]$value <- 0.04
    v <- L$rf_prereg_validate(p, "registered", r); !v$ok && any(grepl("≠ 산출물", v$errors)) },
  param_hand = function(L) { r <- new_root("ph"); p <- reg_view(syn_pr(L, r)); p$decision_params[[1]]$from <- NULL
    v <- L$rf_prereg_validate(p, "registered", r); !v$ok && any(grepl("출처 없음", v$errors)) },
  param_missing = function(L) { r <- new_root("pm"); p <- reg_view(syn_pr(L, r)); p$decision_params[[1]]["value"] <- list(NULL)
    vd <- L$rf_prereg_validate(modifyList(p, list(status = "draft", draft_rev = 1L)), "draft", r)   # 초안은 비어도 된다(규칙·절차만)
    v <- L$rf_prereg_validate(p, "registered", r); vd$ok && !v$ok && any(grepl("미산출: alpha_cal", v$errors, fixed = TRUE)) },
  param_derive = function(L) { r <- new_root("pd"); p <- reg_view(syn_pr(L, r)); p$criteria$failure[[2]] <- at("prim", "T1-F", "p_gt0", ">", list(param = "alpha_cal_upper"))
    p$decision_params[[2]]$value <- 0.9
    v <- L$rf_prereg_validate(p, "registered", r); !v$ok && any(grepl("규칙 one_minus", v$errors)) },
  param_rhs = function(L) { r <- new_root("pr2"); p <- syn_pr(L, r, id = "PR-T-PR", fam = "FAM-T-PR-01")
    p$criteria$success[[1]] <- at("prim", "T1-F", "p_gt0", "<", list(param = "alpha_cal")); pr <- reg_pr(L, r, p)
    v <- L$rf_prereg_verdict(pr, mset(L, r, pr$prereg_id, "confirmed"), root = r, record = FALSE)
    identical(v$label, "confirmed") && isTRUE(v$success[[1]]) },
  param_grammar = function(L) { r <- new_root("pg"); p <- syn_pr(L, r)
    p1 <- p; p1$criteria$success[[1]] <- at("prim", "T1-F", "p_gt0", "<", list(param = "nope"))
    p2 <- p; p2$power$calibration$params$alpha <- "nope"
    p3 <- p; p3$power$calibration$kind <- "normal_ci"
    p4 <- p; p4$criteria$success[[1]] <- at("prim", "T1-F", "p_gt0", "<", list(param = "alpha_cal", offset = 0.01))
    e <- lapply(list(p1, p2, p3, p4), function(x) L$rf_prereg_validate(x, "draft", r)$errors)
    any(grepl("미선언 결정 파라미터", e[[1]])) && any(grepl("선언된 decision_params 가 아니다", e[[2]])) && any(grepl("calibration.kind", e[[3]])) &&
      any(grepl("단독", e[[4]])) },
  validity = function(L) { r <- new_root("vl"); pr <- val_pr(L, r); n0 <- dec_lines(r)
    M <- c(mset(L, r, pr$prereg_id, "confirmed"), list(meas(L, r, pr$prereg_id, "deliv", "T1", "sleeve_delivery", value = 0.30)))
    v <- L$rf_prereg_verdict(pr, M, root = r, record = TRUE); e <- err_of(L$rf_prereg_verdict(pr, M, root = r, record = TRUE))
    d <- fromJSON(readLines(file.path(r, "06_Registry/rf_decisions.jsonl"), warn = FALSE)[n0 + 1L], simplifyVector = FALSE)
    r2 <- new_root("vl"); pr2 <- val_pr(L, r2)                                                                        # 양성 대조: 전달량 ≥ 하한
    v2 <- L$rf_prereg_verdict(pr2, c(mset(L, r2, pr2$prereg_id, "confirmed"), list(meas(L, r2, pr2$prereg_id, "deliv", "T1", "sleeve_delivery", value = 0.90))), root = r2, record = FALSE)
    identical(v$status, "invalid") && is.null(v$label) && identical(unlist(v$invalid$outcome), "treatment_dilution") && isTRUE(v$recorded) &&
      dec_lines(r) == n0 + 1L && identical(unlist(d$chosen$ids), "none") && identical(d$scope$status, "invalid") && isTRUE(grepl("이미 판정", e)) &&
      identical(v2$label, "confirmed") },
  validity_missing = function(L) { r <- new_root("vm"); pr <- val_pr(L, r, halt = TRUE); n0 <- dec_lines(r)
    v <- L$rf_prereg_verdict(pr, mset(L, r, pr$prereg_id, "pnull"), root = r, record = TRUE)   # halt 여도 전달량 미제출 = incomplete
    identical(v$status, "incomplete") && "deliv|T1" %in% unlist(v$missing) && dec_lines(r) == n0 },
  validity_na = function(L) { r <- new_root("vn"); pr <- val_pr(L, r)
    M <- c(mset(L, r, pr$prereg_id, "confirmed"), list(meas(L, r, pr$prereg_id, "deliv", "T1", "sleeve_delivery", value = NA_real_)))
    v <- L$rf_prereg_verdict(pr, M, root = r, record = FALSE); identical(v$status, "invalid") },
  validity_vocab = function(L) { r <- new_root("vv"); p <- val_pr(L, r, write = FALSE); p$criteria$validity[[1]]$outcome <- "whatever"
    v <- L$rf_prereg_validate(p, "draft", r); !v$ok && any(grepl("validity_outcomes", v$errors)) },
  boot_cal = function(L) { r <- new_root("bc"); set.seed(9); b <- rnorm(400, 0, 0.01); a <- b + 0.0003 + rnorm(400, 0, 0.004)
    q1 <- L$rf_prereg_paired_boot(a, b, "mean", root = r, B = 300, cal_alpha = 0.05); q2 <- L$rf_prereg_paired_boot(a, b, "mean", root = r, B = 300, cal_alpha = 0.024)
    q0 <- L$rf_prereg_paired_boot(a, b, "mean", root = r, B = 300)
    isTRUE(all.equal(c(q1$cal_q_lo, q1$cal_q_hi), c(q1$ci_lo, q1$ci_hi), tolerance = 1e-10)) && q2$cal_q_lo < q2$ci_lo && q2$cal_q_hi > q2$ci_hi &&
      identical(q2$cal_alpha, 0.024) && is.null(q0$cal_alpha) && identical(q0$se, q1$se) },
  run_blockers = function(L) { r <- new_root("rb"); set_p108(r, FALSE); p <- syn_pr(L, r, id = "PR-T-RB", fam = "FAM-T-RB-01")
    p$run_prerequisites <- list(list(id = "P1-08", status = "pending"), list(id = "X", status = "available")); pr <- reg_pr(L, r, p)
    dq <- L$rf_prereg_run(pr$prereg_id, root = r); rb <- unlist(dq$run_blockers)
    isTRUE(dq$ready_to_register) && any(grepl("^P1-08: rf_open_entry formals", rb)) && any(grepl("실행 전제 P1-08 미충족", rb, fixed = TRUE)) &&
      !any(grepl("실행 전제 X", rb, fixed = TRUE)) && dq$writes == 0L }
)

## ══════════════════════════════════════════════════════════════════════════════
L <- load_lib(LIB)
cat("=== A. 설정 fail-closed ===\n")
r <- new_root("cfg"); file.remove(file.path(r, "06_Registry/prereg/prereg_config.json"))
chk(grepl("설정 부재", err_of(L$rf_prereg_config(r))), "A1 설정 파일 없음 → 멈춤(코드 기본값 없음)")
r <- new_root("cfg"); cj <- fromJSON(CFG, simplifyVector = FALSE); cj$bootstrap$B <- NULL
writeLines(toJSON(cj, auto_unbox = TRUE, null = "null"), file.path(r, "06_Registry/prereg/prereg_config.json"))
chk(grepl("bootstrap.B", err_of(L$rf_prereg_config(r))), "A2 키 누락(bootstrap.B) → 멈춤")
r <- new_root("cfg"); cj <- fromJSON(CFG, simplifyVector = FALSE); cj$labels <- list("confirmed", "failed", "undetermined")
writeLines(toJSON(cj, auto_unbox = TRUE, null = "null"), file.path(r, "06_Registry/prereg/prereg_config.json"))
chk(grepl("4종", err_of(L$rf_prereg_config(r))), "A3 라벨 3종으로 축소 → 멈춤")
r <- new_root("cfg"); cfg <- L$rf_prereg_config(r)
chk(identical(unlist(cfg$se_sources$allowed), c("null_dilution", "block_bootstrap")) && "phase_pair" %in% names(cfg$se_sources$forbidden),
    "A4 SE 원천 = null 희석·블록 부트스트랩 · 위상쌍 금지 등재")
links <- unlist(lapply(c(cfg$bootstrap$links, cfg$power_gate$links, cfg$label_links, cfg$se_sources$links, cfg$selection_accounting$links), `[[`, "url"))
chk(length(links) >= 10 && all(grepl("^https://doi.org/", links)), sprintf("A5 수치 근거 문헌 원문 링크 %d건(doi)", length(links)))

cat("=== B. 스키마 — 양성 대조 + 위반 주입 ===\n")
r <- new_root("sch"); pr0 <- syn_pr(L, r)
v <- L$rf_prereg_validate(pr0, "draft", r); chk(v$ok, "B0 합성 완전형 = 초안 검증 통과", paste(v$errors, collapse = " | "))
v <- L$rf_prereg_validate(modifyList(pr0, list(status = "registered", draft_rev = NULL)), "registered", r)
chk(v$ok, "B0' 합성 완전형 = 등록 검증 통과(차단 0)", paste(v$errors, collapse = " | "))
inj <- list(
  list("B1 se_source.methods 에 위상쌍", function(p) { p$se_source$methods <- list("phase_pair"); p }, "금지 SE"),
  list("B2 power.se.source 에 위상쌍", function(p) { p$power$se$source <- list("phase_pair"); p }, "금지 SE"),
  list("B3 arms 비움", function(p) { p$arms <- list(); p }, "arms 가 비었다"),
  list("B4 arm id 중복", function(p) { p$arms[[2]]$id <- "T1"; p }, "id 중복"),
  list("B5 selection_basis=full_sample(C1)", function(p) { p$arms[[1]]$selection_basis <- "full_sample"; p }, "selection_basis"),
  list("B6 라벨 3종", function(p) { p$labels <- p$labels[1:3]; p }, "labels"),
  list("B7 1차 지표 없음", function(p) { p$metrics[[1]]$tier <- "secondary"; p }, "1차"),
  list("B8 실패 조건 비움", function(p) { p$criteria$failure <- list(); p }, "failure"),
  list("B9 미선언 지표 참조", function(p) { p$criteria$success[[2]]$metric <- "nope"; p }, "미선언 지표"),
  list("B10 미등재 계약(manual)", function(p) { p$metrics[[2]]$contract <- "manual"; p }, "미등재"),
  list("B11 사전확률 범위 밖", function(p) { p$priors$mechanism <- 1.4; p }, "priors"),
  list("B12 예산 < arm 수", function(p) { p$budget$max_cells <- 2L; p }, "max_cells"),
  list("B13 framing ≠ 반증 시도", function(p) { p$framing <- "confirmation"; p }, "framing"),
  list("B14 삭제 arm 을 N 에 계상", function(p) { p$deleted_arms <- list(list(id = "A4", reason = "x", counted_in_n = TRUE)); p }, "counted_in_n"),
  list("B15 멈춤이 측정한 arm 을 건너뜀", function(p) { p$criteria$stop[[1]]$action$skip_arms <- list("T1"); p }, "이미 측정"),
  list("B16 예비 arm activation 부재", function(p) { p$arms[[3]]$role <- "spare"; p }, "activation"),
  list("B17 prereg_id 경로 문자", function(p) { p$prereg_id <- "PR-../../x"; p }, "prereg_id"))
for (x in inj) { vv <- L$rf_prereg_validate(x[[2]](pr0), "draft", r)
  chk(!vv$ok && any(grepl(x[[3]], vv$errors, fixed = TRUE)), paste0(x[[1]], " → 거부"), paste(vv$errors, collapse = " | ")) }
regp <- modifyList(pr0, list(status = "registered", draft_rev = NULL))
binj <- list(
  list("R1 바닥 정본 부재", function(p, rr) { file.remove(file.path(rr, "06_Registry/prereg/reference_floors_v2.json")); p }, "바닥 정본 부재"),
  list("R2 바닥 표식 selection_basis_full_sample_ic_inherited", function(p, rr) {
    writeLines(toJSON(list(floors = list(list(id = "F", status = "confirmed", determinism_ok = TRUE, selection_basis = "as_of",
      measurement_regime = list(exec_price = "close_t1"), vintage_flags = list(list(flag = "selection_basis_full_sample_ic_inherited"))))), auto_unbox = TRUE),
      file.path(rr, "06_Registry/prereg/reference_floors_v2.json")); p }, "금지 표식"),
  list("R3 바닥 selection_basis=full_sample", function(p, rr) {
    writeLines(toJSON(list(floors = list(list(id = "F", status = "confirmed", determinism_ok = TRUE, selection_basis = "full_sample",
      measurement_regime = list(exec_price = "close_t1")))), auto_unbox = TRUE), file.path(rr, "06_Registry/prereg/reference_floors_v2.json")); p }, "as-of 재선정"),
  list("R4 바닥 결정론 미확인", function(p, rr) {
    writeLines(toJSON(list(floors = list(list(id = "F", status = "confirmed", determinism_ok = FALSE, selection_basis = "as_of",
      measurement_regime = list(exec_price = "close_t1")))), auto_unbox = TRUE), file.path(rr, "06_Registry/prereg/reference_floors_v2.json")); p }, "결정론"),
  list("R5 바닥 규약 legacy", function(p, rr) {
    writeLines(toJSON(list(floors = list(list(id = "F", status = "confirmed", determinism_ok = TRUE, selection_basis = "as_of",
      measurement_regime = list(exec_price = "close_d_legacy")))), auto_unbox = TRUE), file.path(rr, "06_Registry/prereg/reference_floors_v2.json")); p }, "규약"),
  list("R6 착수 금지(ratio<0.15)", function(p, rr) { q <- L$rf_prereg_power(-0.001, se = 0.02, root = rr)
    p$power$implied_effect$value <- -0.001; p$power$computed <- q[c("ratio", "expected_t", "power", "disposition")]; p }, "착수 금지"),
  list("R7 조건부 착수에 남는 것 없음", function(p, rr) { q <- L$rf_prereg_power(-0.02, se = 0.02, root = rr)
    p$power$implied_effect$value <- -0.02; p$power$computed <- q[c("ratio", "expected_t", "power", "disposition")]; p$power$leaves_behind <- list(); p }, "조건부 착수"),
  list("R8 lookup 미첨부(pending)", function(p, rr) { p$hypothesis_index_lookup <- list(status = "pending"); p }, "lookup 미첨부"),
  list("R9 stale 인덱스 조회", function(p, rr) { p$hypothesis_index_lookup$index_stale_sources <- list("06_Registry/module_catalog.json"); p }, "stale"),
  list("R10 미결 질문 잔존", function(p, rr) { p$open_questions <- list(list(id = "Q1", question = "?")); p }, "미결 질문"),
  list("R11 조건부 arm 미해소", function(p, rr) { p$arms[[3]]$conditional_on <- list(floor = "F", require = "x", resolved = FALSE); p }, "조건부 arm"),
  list("R12 power.computed 손편집", function(p, rr) { p$power$computed$expected_t <- 9; p }, "재계산과 다르다"),
  list("R13 pin 태그 부재", function(p, rr) { p$measurement_regime$pin_tag <- NULL; p }, "pin_tag"))
for (x in binj) { rr <- new_root("blk"); vv <- L$rf_prereg_validate(x[[2]](regp, rr), "registered", rr)
  chk(!vv$ok && any(grepl(x[[3]], vv$errors, fixed = TRUE)), paste0(x[[1]], " → 등록 차단"), paste(vv$errors, collapse = " | ")) }
chk(isTRUE(G$forbidden_se(L)), "B-G 위상쌍 SE 는 초안 단계에서도 거부")
chk(isTRUE(G$selbasis(L)), "B-G full_sample 선정 기저 거부(C1 · D-E)")
chk(isTRUE(G$power_recompute(L)), "B-G 손편집 power.computed 등록 차단")

cat("=== C. writer ===\n")
r <- new_root("wr"); pr <- syn_pr(L, r); w <- L$rf_prereg_write(pr, "draft", r)
idx <- L$rf_prereg_index(r)
chk(file.exists(w$path) && length(idx) == 1L && identical(idx[[1]]$sha256, unname(L$.rfp_sha_file(w$path))) && identical(idx[[1]]$kind, "draft"),
    "C1 초안 rev1 원자 쓰기 + 색인 sha256 = 파일 바이트")
chk(isTRUE(G$overwrite(L)), "C2 같은 rev 재쓰기 → 거부 · 파일 불변")
pr3 <- pr; pr3$draft_rev <- 3L
chk(grepl("다음 rev 는 2", err_of(L$rf_prereg_write(pr3, "draft", r))), "C3 rev 건너뛰기(1→3) 거부")
s1 <- unname(L$.rfp_sha_file(w$path)); pr2 <- pr; pr2$draft_rev <- 2L; pr2$title <- "rev2"; w2 <- L$rf_prereg_write(pr2, "draft", r)
chk(identical(unname(L$.rfp_sha_file(w$path)), s1) && identical(L$rf_prereg_load(pr$prereg_id, "draft", root = r)$title, "rev2"),
    "C4 초안 개정 = 새 rev 파일(rev1 불변) · 최신 로드 = rev2")
chk(isTRUE(G$tamper(L)), "C5 파일 1바이트 변조 → 로드 거부(무결성)")
reg1 <- L$rf_prereg_register(pr$prereg_id, root = r)
chk(file.exists(reg1$path) && file.exists(w2$path) && identical(L$rf_prereg_load(pr$prereg_id, "registered", root = r)$status, "registered"),
    "C6 등록 = 새 파일 · 초안 파일 남음")
chk(grepl("이미 등록", err_of(L$rf_prereg_register(pr$prereg_id, root = r))), "C7 재등록 거부")
pr4 <- pr; pr4$draft_rev <- 3L
chk(grepl("이미 등록됐다", err_of(L$rf_prereg_write(pr4, "draft", r))), "C8 등록 뒤 초안 쓰기 거부")
prB <- syn_pr(L, r, id = "PR-T-OTHER", fam = "FAM-T-SYN-01"); L$rf_prereg_write(prB, "draft", r)
chk(grepl("가족", err_of(L$rf_prereg_register("PR-T-OTHER", root = r))), "C9 같은 가족 두 번째 등록 거부(개정 = 새 가족)")
prR <- syn_pr(L, r, id = "PR-T-REV", fam = "FAM-T-SYN-01"); prR$revision_of <- pr$prereg_id
vv <- L$rf_prereg_validate(prR, "draft", r)
chk(!vv$ok && any(grepl("새 가족", vv$errors)), "C10 revision_of 가 같은 가족 → 거부")
prR$family_id <- "FAM-T-SYN-02"; chk(L$rf_prereg_validate(prR, "draft", r)$ok, "C11 revision_of + 새 가족 → 허용(양성 대조)")
file.remove(reg1$path)
chk(grepl("이미 등록", err_of(L$rf_prereg_register(pr$prereg_id, root = r))), "C12 등록 파일을 지워도 색인 묘비가 재등록을 막는다")
chk(grepl("색인에 없다", err_of(L$rf_prereg_load("PR-NOT-INDEXED", "registered", root = r))), "C13 색인 밖 파일(선례 포함)은 로드 거부")
chk(!length(list.files(r, recursive = TRUE, all.files = TRUE, pattern = "[.]tmp[.]")) &&
    !length(grep(".lock_", list.files(r, recursive = TRUE, all.files = TRUE, include.dirs = TRUE), fixed = TRUE)), "C14 임시 파일·잠금 잔재 0")

cat("=== D. 검정력 3종 ===\n")
chk(isTRUE(G$power_t80(L)), "D1 measurement-graduation 표(ratio→기대 t·검정력 6점) 항등 재현")
r <- new_root("pw"); cfg <- L$rf_prereg_config(r); res <- L$.rfp_src(r, "02_Infrastructure/contracts/required_effect_size.R", "res")
t80 <- qnorm(0.8) + qnorm(0.975); q <- L$rf_prereg_power(-0.03, se = 0.015, root = r, cfg = cfg)
chk(abs(q$mde80 - res$required_effect(n = 1, t_threshold = t80, sd_monthly = 0.015, nw_inflation = 1)$required_monthly) < 1e-15 &&
    identical(q$mde_source, "required_effect_size.R::required_effect"), "D2 MDE = required_effect 단일 출처(se 경로)")
q2 <- L$rf_prereg_power(0.004, sd = 0.0394, n = 120, nw_inflation = 1.1, root = r, cfg = cfg)
chk(abs(q2$mde80 - res$required_effect(n = 120, t_threshold = t80, sd_monthly = 0.0394, nw_inflation = 1.1)$required_monthly) < 1e-15 &&
    identical(q2$mde_path, "sd_n"), "D3 (sd, n) 경로도 required_effect 그대로")
disp <- function(rt) L$rf_prereg_power(rt * t80 * 0.01, se = 0.01, root = r, cfg = cfg)$disposition
chk(identical(c(disp(0.15 - 1e-9), disp(0.15 + 1e-9), disp(0.70 - 1e-9), disp(0.70 + 1e-9), disp(1 + 1e-9)),
              c("forbidden", "conditional", "conditional", "normal", "design80")), "D4 처분 경계 0.15·0.70·1.00(설정값)")
chk(!is.na(err_of(L$rf_prereg_power(0.01, root = r))) && !is.na(err_of(L$rf_prereg_power(NA_real_, se = 0.1, root = r))), "D5 SE 없음·효과 NA → 멈춤")

cat("=== E. SE 원천 ===\n")
r <- new_root("bt"); set.seed(3); x <- rnorm(300, 0, 0.01)
q <- L$rf_prereg_paired_boot(x, x, "mean", root = r, B = 200)
chk(q$value == 0 && q$ci_lo == 0 && q$ci_hi == 0 && q$se == 0, "E1 동일 계열 → Δ=0 · CI [0,0] · se 0(항등)")
y <- x + 0.0008; q <- L$rf_prereg_paired_boot(y, x, "mean", root = r, B = 200)
chk(abs(q$value - 0.0008) < 1e-12 && q$ci_lo > 0 && q$p_gt0 == 1, "E2 상수 이동 주입 → Δ 정확 · CI 0 배제 · P(Δ>0)=1")
qa <- L$rf_prereg_paired_boot(y, x, "calmar", root = r, B = 150, seed = 11L); qb <- L$rf_prereg_paired_boot(y, x, "calmar", root = r, B = 150, seed = 11L)
qc <- L$rf_prereg_paired_boot(y, x, "calmar", root = r, B = 150, seed = 12L)
chk(identical(qa[c("se", "ci_lo", "ci_hi")], qb[c("se", "ci_lo", "ci_hi")]) && !identical(qa$se, qc$se), "E3 seed 고정 = 결정론 · seed 변경 = 다른 재표본")
chk(isTRUE(G$paired(L)), "E4 짝지은 인덱스 — SE 가 비짝지음 근사의 1/4 미만")
ds <- L$.rfp_src(r, "02_Infrastructure/contracts/defensive_score.R", "ds")
set.seed(5); k <- c(rnorm(240, 0.008, 0.05), rep(-0.13, 6)); s1 <- 0.6 * k + rnorm(246, 0.004, 0.02); s0 <- 0.95 * k + rnorm(246, 0, 0.02)
dts <- seq(as.Date("2005-01-01"), by = "month", length.out = 246)   # 월초 — 말일 시작 seq 는 2월을 3월로 넘겨 같은 달 2행을 만든다(ds_score 는 달로 복리 합산)
cap <- function(s) ds$ds_score(data.frame(date = dts, ret_net = s), data.frame(date = dts, benchmark_ret = k), ds$ds_params(r))$deep$capture
q <- L$rf_prereg_paired_boot(s1, s0, "deep_capture", bench = k, root = r, B = 300)
chk(abs(q$value - (cap(s1) - cap(s0))) < 1e-12 && q$ci_hi < 0, "E5 deep_capture Δ = defensive_score 심층 capture 차(같은 식 · 문턱 ds_params) · 주입 효과 검출")
dd <- seq(as.Date("2010-01-04"), by = "day", length.out = 2400); dd <- dd[!weekdays(dd) %in% c("Saturday", "Sunday", "토요일", "일요일")]
set.seed(8); kd <- rnorm(length(dd), 0.0003, 0.012); kd[format(dd, "%Y-%m") %in% c("2011-08", "2014-03", "2016-01")] <- -0.012
s1d <- 0.6 * kd + rnorm(length(dd), 0.0002, 0.004); s0d <- 0.95 * kd + rnorm(length(dd), 0, 0.004)
capd <- function(s) ds$ds_score(data.frame(date = dd, ret_net = s), data.frame(date = dd, benchmark_ret = kd), ds$ds_params(r))$deep$capture
qd <- L$rf_prereg_paired_boot(s1d, s0d, "deep_capture", bench = kd, dates = dd, root = r, B = 200)
chk(abs(qd$value - (capd(s1d) - capd(s0d))) < 1e-12 && qd$n < 120, "E5b 일간 입력 + dates → 달력월 복리 합산 후 defensive_score 와 같은 값")
kk <- abs(rnorm(246, 0.01, 0.01)); q <- L$rf_prereg_paired_boot(s1, s0, "deep_capture", bench = kk, root = r, B = 50)
chk(is.na(q$value) && nzchar(q$invalid_reason %||% ""), "E6 심층 월 0개 → 무효(NA + 사유) · 조용한 축소 없음")
q <- L$rf_prereg_paired_boot(y, x, "mean", root = r, B = 20); adv <- L$.rfp_src(r, "02_Infrastructure/reinforcement/rf_overlay_adversary.R", "adv")
chk(identical(q$block_rule, adv$adv_block_len(y - x, cfg$bootstrap$block_rule)$rule) && identical(q$block_len, adv$adv_block_len(y - x, "auto")$b),
    "E7 블록 길이 = adv_block_len 재사용(규칙 기록)")
cb <- L$rf_prereg_combine_se(0.02, 0.03, root = r)
chk(cb$se == 0.03 && identical(cb$used, "block_bootstrap") && grepl("금지 SE", err_of(L$rf_prereg_combine_se(0.02, 0.03, sources = "phase_pair", root = r))),
    "E8 결합 = max · 위상쌍 이름 거부")
sn <- L$rf_prereg_se_null(c(0.1, 0.2, 0.4), root = r)
chk(abs(sn$se - sd(c(0.1, 0.2, 0.4))) < 1e-15 && sn$df == 2L && !is.na(err_of(L$rf_prereg_se_null(0.1, root = r))), "E9 null 희석 SE = 칸 값 표준편차 · n<2 멈춤")
chk(!is.na(err_of(L$rf_prereg_paired_boot(c(x, NA), c(x, 0), "mean", root = r))), "E10 결측 수익 → 멈춤(0 채움 금지)")

cat("=== F. 판정 ===\n")
r <- new_root("vd"); pr <- reg(L, r); n0 <- dec_lines(r)
v <- L$rf_prereg_verdict(pr, mset(L, r, pr$prereg_id, "confirmed"), root = r, record = TRUE)
chk(identical(v$label, "confirmed") && identical(v$status, "concluded") && isTRUE(v$recorded) && dec_lines(r) == n0 + 1L, "F1 성공 전부 TRUE → confirmed · 결정 기록 1줄")
d <- fromJSON(readLines(file.path(r, "06_Registry/rf_decisions.jsonl"), warn = FALSE)[n0 + 1L], simplifyVector = FALSE)
chk(identical(d$kind, "prereg_verdict") && identical(unlist(d$chosen$ids), "confirmed") && length(d$candidates) == 4L &&
    identical(d$scope$prereg_id, pr$prereg_id) && identical(d$rule$sha, attr(pr, "integrity")$sha256) && isTRUE(d$scope$not_a_grade),
    "F2 기록 = kind prereg_verdict · 후보 라벨 4 · 선택 · 사전등록 sha")
txt <- readLines(file.path(r, "06_Registry/rf_decisions.jsonl"), warn = FALSE)[n0 + 1L]
chk(!grepl('"essence"\\s*:|"essence_grade"\\s*:|"authoritative_remeasure"\\s*:', txt), "F3 AX-008 — 기록에 등급 객체 키 0")
chk(isTRUE(G$reverdict(L)), "F4 재판정 거부(1회) — 재판정 = 새 사전등록")
chk(isTRUE(G$failed_precedence(L)), "F5 성공·실패 동시 TRUE → failed(우선순위)")
r <- new_root("vd"); pr <- reg(L, r); v <- L$rf_prereg_verdict(pr, mset(L, r, pr$prereg_id, "pnull"), root = r, record = FALSE)
chk(identical(v$label, "powered_null") && identical(unlist(v$arms_skipped), "T2") && identical(v$status, "concluded"),
    "F6 CI 가 함의 효과 배제·0 포함 → powered_null · 멈춤이 T2 건너뜀(skip)")
r <- new_root("vd"); pr <- reg(L, r); v <- L$rf_prereg_verdict(pr, mset(L, r, pr$prereg_id, "undet"), root = r, record = FALSE)
chk(identical(v$label, "undetermined") && !isTRUE(v$primary$powered_null), "F7 CI 가 0·함의 효과 모두 포함 → undetermined(벽 아님)")
chk(isTRUE(G$stop_enforced(L)), "F8 멈춤 뒤 건너뛸 arm 측정 → 거부(멈춤 기계 집행)")
r <- new_root("vd"); pr <- reg(L, r, id = "PR-T-HALT", fam = "FAM-T-HALT-01", halt = TRUE)
v <- L$rf_prereg_verdict(pr, mset(L, r, pr$prereg_id, "pnull"), root = r, record = FALSE)
chk(identical(v$status, "halted") && "T2" %in% unlist(v$arms_skipped) && identical(v$label, "powered_null"), "F9 halt → 이후 order arm 전부 건너뜀 · status halted")
r <- new_root("vd"); pr <- reg(L, r); M <- mset(L, r, pr$prereg_id, "confirmed")
bad <- function(f) err_of(L$rf_prereg_verdict(pr, f(M), root = r, record = FALSE))
e1 <- bad(function(M) { M[[3]]$source$contract <- "manual"; M }); e2 <- bad(function(M) { M[[3]]$source$contract <- "python"; M })
e3 <- bad(function(M) { M[[3]]$source <- NULL; M })
chk(grepl("AX-008", e1) && grepl("AX-008", e2) && grepl("source", e3), "F10 손계산·python·출처 없는 입력 거부")
chk(isTRUE(G$artifact_sha(L)), "F11 산출물 sha256 불일치 거부")
ext <- tempfile(fileext = ".json", tmpdir = TMPB); writeLines("{}", ext)
e <- bad(function(M) { M[[3]]$source$artifact <- ext; M[[3]]$source$artifact_sha256 <- unname(L$.rfp_sha_file(ext)); M })
chk(grepl("루트 밖", e), "F12 루트 밖 산출물 거부")
e <- bad(function(M) { M[[3]]$source$artifact <- "stage_artifacts/prereg/nope.json"; M }); chk(grepl("산출물 부재", e), "F13 산출물 부재 거부")
chk(isTRUE(G$regime(L)), "F14 주장 규약 불일치(close_d_legacy) 거부")
chk(isTRUE(G$artifact_regime(L)), "F14b 주장은 close_t1 · 산출물 안 실현 규약은 legacy → 거부(실현값 재도출)")
nor <- file.path(r, "stage_artifacts/prereg", pr$prereg_id, "cal_T1_noregime.json"); writeLines('{"contract":"essence_score","value":0.5}', nor)
e <- bad(function(M) { M[[3]]$source$artifact <- sub(paste0(r, "/"), "", nor, fixed = TRUE); M[[3]]$source$artifact_sha256 <- unname(L$.rfp_sha_file(nor)); M })
chk(grepl("measurement_regime", e), "F14c 규약 표식 없는 essence 산출물 → 거부(fail-closed)")
chk(isTRUE(G$undeclared_target(L)), "F15 미선언 arm 측정 거부(사후 추가 금지)")
e <- bad(function(M) { M[[3]]$metric <- "zzz"; M }); chk(grepl("미선언 지표", e), "F16 미선언 지표 거부")
e <- bad(function(M) c(M, list(meas(L, r, pr$prereg_id, "tilt", "T1", "tilt_attribution", value = 1))))
chk(grepl("계약 파일 부재", e), "F17 배포 안 된 계약(tilt_attribution)의 산출물 거부(fail-closed)")
e <- bad(function(M) { M[[3]] <- meas(L, r, pr$prereg_id, "cal", "T1", "beta_controlled_alpha", value = 0.5, name = "cal_T1_wrongc"); M })
chk(grepl("선언 계약", e), "F18 선언 계약 ≠ 산출 계약 거부")
e <- bad(function(M) c(M, list(M[[4]]))); chk(grepl("둘 이상", e), "F19 같은 (지표|대상) 중복 측정 거부(사후 선택 차단)")
e <- bad(function(M) { M[[1]]$ci_level <- 0.95; M }); chk(grepl("ci_level", e), "F20 1차 지표 ci_level ≠ 사전등록 거부")
chk(isTRUE(G$must_report(L)), "F21 must_report 누락 → incomplete · 라벨·기록 없음")
r <- new_root("vd"); prd <- syn_pr(L, r); L$rf_prereg_write(prd, "draft", r); dl <- L$rf_prereg_load(prd$prereg_id, "draft", root = r)
chk(grepl("등록본에만", err_of(L$rf_prereg_verdict(dl, list(), root = r))) &&
    grepl("등록본에만", err_of(L$rf_prereg_verdict(modifyList(prd, list(status = "registered")), list(), root = r))), "F22 초안·무결성 없는 객체 판정 거부")
r <- new_root("vd"); pr <- reg(L, r); n0 <- dec_lines(r); v <- L$rf_prereg_verdict(pr, mset(L, r, pr$prereg_id, "confirmed"), root = r, record = FALSE)
chk(!isTRUE(v$recorded) && dec_lines(r) == n0, "F23 record=FALSE → 기록 0")

cat("=== G. 드라이런 ===\n")
chk(isTRUE(G$dryrun_only(L)), "G1 dry_run=FALSE 거부(P1-08 전)")
r <- new_root("dr"); pr <- reg(L, r); lp <- file.path(r, "06_Registry/reinforce_ledger_l1.json"); m0 <- unname(tools::md5sum(lp))
fl0 <- list.files(r, recursive = TRUE, all.files = TRUE); dq <- L$rf_prereg_run(pr$prereg_id, root = r)
chk(isTRUE(dq$dry_run) && dq$writes == 0L && identical(unname(tools::md5sum(lp)), m0) && setequal(fl0, list.files(r, recursive = TRUE, all.files = TRUE)),
    "G2 드라이런 = 원장 md5 불변 · 새 파일 0")
chk(identical(vapply(dq$steps, function(s) s$arm, ""), c("T1", "C1", "T2")) && identical(unlist(dq$steps[[2]]$stop_checkpoints_after), "STOP1") &&
    identical(dq$steps[[1]]$would_call$priority, "prereg"), "G3 계획 = order 순 · 멈춤 체크포인트는 after_arms 최대 order 뒤 · priority=prereg")
fm_root <- (function() { ex <- parse(file.path(ROOT, "02_Infrastructure/reinforcement/reinforce_ledger.R"), encoding = "UTF-8", keep.source = FALSE)
  oe <- Filter(function(e) is.call(e) && identical(as.character(e[[1]]), "<-") && identical(as.character(e[[2]]), "rf_open_entry"), as.list(ex))
  if (length(oe)) names(as.list(oe[[1]][[3]][[2]])) else character(0) })()
chk(identical(dq$p108_ready, all(c("priority", "experiment") %in% fm_root)),
    sprintf("G4 p108_ready = 루트 원장 writer formals 재도출과 일치(현재 %s — P1-08 배포 순서 무관)", if (all(c("priority", "experiment") %in% fm_root)) "있음" else "없음"))
r3 <- new_root("dr"); ok3 <- set_p108(r3, FALSE); pr3 <- reg(L, r3); dq3 <- L$rf_prereg_run(pr3$prereg_id, root = r3)
chk(ok3 && identical(dq3$p108_ready, FALSE), "G4b 음성 대조: formals 에 priority·experiment 가 없으면 p108_ready=FALSE")
r2 <- new_root("dr"); ok2 <- set_p108(r2, TRUE); pr2 <- reg(L, r2); dq2 <- L$rf_prereg_run(pr2$prereg_id, root = r2)
chk(ok2 && isTRUE(dq2$p108_ready) && isTRUE(dq2$dry_run) && !is.na(err_of(L$rf_prereg_run(pr2$prereg_id, root = r2, dry_run = FALSE))),
    "G5 양성 대조: formals 에 priority·experiment 가 생기면 p108_ready=TRUE — 그래도 live 경로는 없다")

cat("=== H. N 회계 · 결정 종류 ===\n")
r <- new_root("n"); nn <- L$rf_prereg_lineage_n("R_p1", 3L, root = r)
chk(identical(nn$lineage, c("R_p1", "R")) && nn$n_lineage_measured == 3 && nn$n_family_at_registration == 7L && identical(nn$selection_type, "sweep"),
    "H1 N = 1 + 계보 측정 칸(상속·NA 제외 = 3) + arm 3 = 7 (rf_runner_gates 정의 재사용)")
le <- new.env(); for (e in as.list(parse(file.path(ROOT, "02_Infrastructure/reinforcement/reinforce_ledger.R"), encoding = "UTF-8", keep.source = FALSE)))
  if (is.call(e) && identical(as.character(e[[1]]), "<-") && identical(as.character(e[[2]]), "RF_DECISION_KINDS")) eval(e, envir = le)
chk("prereg_verdict" %in% le$RF_DECISION_KINDS, "H2 RF_DECISION_KINDS 에 prereg_verdict 등재(기록 경로 존재)")
r <- new_root("lk"); ip <- file.path(r, "06_Registry/hypothesis_index.json"); Sys.setFileTime(ip, as.POSIXct("2020-01-01"))
dir.create(file.path(r, "06_Registry"), showWarnings = FALSE); writeLines("{}", file.path(r, "06_Registry/module_catalog.json"))
s0 <- unname(L$.rfp_sha_file(ip)); t0 <- file.info(ip)$mtime; lk <- L$rf_prereg_lookup(list(c("defensive"), c("nothing_matches_zz")), root = r)
chk(identical(unname(L$.rfp_sha_file(ip)), s0) && identical(file.info(ip)$mtime, t0) && "06_Registry/module_catalog.json" %in% unlist(lk$index_stale_sources) &&
    lk$queries[[1]]$n_hits == 1L && lk$queries[[2]]$n_hits == 0L, "H3 lookup = 재빌드 없이 읽기만 · stale 원천 기록 · 0건도 기록")

cat("=== N. 적대 검증 수리분(2026-09-25) — 우회 경로 차단 ===\n")
chk(isTRUE(G$hand_numbers(L)), "N1 측정 객체의 손 수치 ≠ 산출물 → 거부(수치는 산출물에서만 · AX-008)")
chk(isTRUE(G$fill_from_artifact(L)), "N1b 양성 대조: 측정 객체에 수치 없이 source 만 → 산출물에서 채워 판정")
chk(isTRUE(G$verify_off(L)), "N2 verify_artifacts=FALSE → 거부 · 기록 0")
chk(isTRUE(G$stop_undecidable(L)), "N3 멈춤 조건 지표 생략·NA 로 뒤 arm 측정 → 거부 · 판정 가능하면 허용(양성 대조)")
chk(isTRUE(G$stop_target(L)), "N3b 멈춤 조건이 체크포인트 뒤 arm 참조 → 초안 거부")
chk(isTRUE(G$pnull_zero(L)), "N4 1차 CI 가 반대 방향으로 0 배제 → powered_null 아님(undetermined)")
chk(isTRUE(G$cfg_pin(L)), "N5 등록 뒤 설정(label_precedence) 변경 → 판정 거부")
chk(isTRUE(G$prereg_time(L)), "N6 arm 산출물이 등록보다 먼저 → 거부 · 바닥 산출물은 등록 전이어도 허용(양성 대조)")
chk(isTRUE(G$seed_pin(L)), "N7 부트스트랩 seed·B 가 설정과 다른 산출물 → 거부(쇼핑 차단)")
chk(isTRUE(G$halt_must_report(L)), "N8 halt 여도 must_report 누락이면 incomplete · 기록 0")
chk(isTRUE(G$target_bind(L)), "N9 바닥 산출물을 arm 측정으로 제출 → 거부(산출물 target 대조)")
chk(isTRUE(G$artifact_reuse(L)), "N9b 같은 산출물·필드를 두 대상에 → 거부 · 중첩 fields 1대상은 허용(양성 대조)")
chk(isTRUE(G$sign(L)), "N10 기전-함의 효과 부호가 1차 방향과 반대 → 등록 차단")
r <- new_root("fd"); writeLines(toJSON(list(floors = list(F = list(status = "confirmed", determinism_ok = TRUE, selection_basis = "as_of",
  measurement_regime = list(exec_price = "close_t1"), vintage_flags = list()))), auto_unbox = TRUE), file.path(r, "06_Registry/prereg/reference_floors_v2.json"))
v1 <- L$rf_prereg_validate(modifyList(syn_pr(L, r), list(status = "registered", draft_rev = NULL)), "registered", r)
writeLines(toJSON(list(floors = list(F = list(status = "defined_unmeasured", selection_path = list(rule = "x")))), auto_unbox = TRUE),
           file.path(r, "06_Registry/prereg/reference_floors_v2.json"))
v2 <- L$rf_prereg_validate(modifyList(syn_pr(L, r), list(status = "registered", draft_rev = NULL)), "registered", r)
chk(v1$ok && !v2$ok && any(grepl("필드 부재", v2$errors)) && !any(grepl("에 없다", v2$errors)),
    "N11 floor v2 {floors:{F:{...}}}(키=id) 형태도 읽는다 · 필드 미충족은 '없다'가 아니라 필드 사유로 차단")

cat("=== P. PREREGFIX(2026-10-03 · 결정 09-26 [위임]) — 기전 한정 바닥 · 1차 판정 교정 · 결정 파라미터 · 처치 전달 타당성 ===\n")
r <- new_root("p0"); cfg <- L$rf_prereg_config(r)
chk(identical(unlist(cfg$registration$floor_status_mechanism_only), "confirmed_mechanism_only") && identical(cfg$registration$mechanism_only_scope$a_eligible, FALSE) &&
    setequal(names(cfg$verdict$calibration$kinds), c("bootstrap_p", "null_t_quantile")) && "treatment_dilution" %in% names(cfg$verdict$validity_outcomes) &&
    all(c("cal_q_lo", "cal_q_hi") %in% unlist(cfg$verdict$stats)) && "sleeve_delivery" %in% names(cfg$verdict$contracts),
    "P0 설정 — 기전 한정 상태·scope · 교정 종류 2 · 전달 타당성 어휘 · cal 통계 · sleeve_delivery 계약")
chk(all(grepl("^https://doi.org/", unlist(lapply(c(cfg$verdict$calibration$links, cfg$verdict$param_derivations_links), `[[`, "url")))),
    "P0b 새 수치 규칙 근거 문헌 원문 링크(doi)")
chk(isTRUE(G$cfg_mo(L)), "P1 설정 mechanism_only_scope.a_eligible=true → 멈춤(기전 한정 바닥이 A 경로를 열지 않게)")
chk(isTRUE(G$mo_scope(L)), "P2 A 경로(scope 없음) + confirmed_mechanism_only 바닥 → 등록 차단 · scope=mechanism_only ∧ a_eligible=false → 통과(양성 대조)")
chk(isTRUE(G$mo_scope_aelig(L)), "P3 scope.a_eligible=true · 문자열 'false' → 거부(identical FALSE 만)")
chk(isTRUE(G$mo_floor(L)), "P4 바닥 permitted_use ≠ mechanism_only → 등록 차단")
chk(isTRUE(G$mo_floor_aelig(L)), "P5 바닥 a_eligible=true(기전 한정 상태와 모순) → 등록 차단")
chk(isTRUE(G$mo_restriction(L)), "P6 바닥 use_restriction.decision_id ≠ 초안 scope.decision_ref → 등록 차단")
r <- new_root("p7"); vA <- L$rf_prereg_validate(reg_view(mo_pr(L, r)), "registered", r)
chk(vA$ok, "P7 scope=mechanism_only 사전등록도 confirmed(A 경로) 바닥은 그대로 받는다", paste(vA$errors, collapse = " | "))
chk(isTRUE(G$cal_required(L)), "P8 교정(power.calibration) 없는 등록 → 차단(명목 CI 판정 금지 · 설정 스위치 없음)")
chk(isTRUE(G$cal_verdict_refuse(L)), "P9 교정 없는 등록본(메모리 변조)으로 판정 → 거부(대체 경로 없음)")
chk(isTRUE(G$cal_mech(L)), "P10 명목 CI 상한<0 이어도 교정 p ≥ α 면 mechanism_detected=FALSE · p<α 는 TRUE(양성 대조)")
chk(isTRUE(G$cal_pnull(L)), "P11 명목 CI 는 함의 효과 배제 · 교정 α 분위는 못 배제 → powered_null 아님(undetermined)")
chk(isTRUE(G$pnull_zero(L)), "P11b 교정 판정에서도 반대 방향 유의(p > 1−α)는 powered_null 아님")
chk(isTRUE(G$cal_alpha_pin(L)), "P12 1차 산출물 cal_alpha ≠ 등록 α → 판정 거부(수준 쇼핑 차단)")
chk(isTRUE(G$cal_t(L)), "P13 null_t_quantile — t ≤ t_lo 탐지 · (v−ie)/se ≥ t_hi ∧ 0 포함 = powered_null · 반대 방향 유의는 부재 아님")
chk(isTRUE(G$boot_cal(L)), "P14 rf_prereg_paired_boot(cal_alpha) — α=0.05 분위 = 명목 90% CI 와 비트 동일 · α=0.024 는 더 넓다 · 미지정 = 미기재")
chk(isTRUE(G$param_source(L)), "P15 결정 파라미터 값 ≠ 산출물(from) → 등록 차단")
chk(isTRUE(G$param_hand(L)), "P16 출처(from·derive) 없는 결정 파라미터 → 등록 차단(손 입력)")
chk(isTRUE(G$param_missing(L)), "P17 결정 파라미터 값 비움 → 초안 통과 · 등록 차단(측정 전 항목)")
chk(isTRUE(G$param_derive(L)), "P18 derive one_minus 불일치 → 등록 차단")
chk(isTRUE(G$param_rhs(L)), "P19 조건 rhs {param} 이 등록본 값으로 풀린다(p_gt0 < α_cal → confirmed)")
chk(isTRUE(G$param_grammar(L)), "P20 문법 — 미선언 파라미터 · 교정 파라미터 미선언 · 미지 교정 종류 · {param}+offset 혼합 → 초안 거부")
r <- new_root("p21"); p <- syn_pr(L, r); q <- L$rf_prereg_power(-0.05, se = 0.02, root = r); g <- L$rf_prereg_config(r)$power_gate
want <- switch(q$disposition, conditional = g$ratio_forbidden_below, normal = g$ratio_conditional_below, design80 = g$ratio_design80_at) / q$ratio
got <- L$.rfp_derive_param(list(derive = list(op = "disposition_floor_over_ratio")), list(), p, r, L$rf_prereg_config(r))
chk(isTRUE(abs(got - want) < 1e-12) && identical(q$disposition, "normal") && got > 0 && got < 1,
    sprintf("P21 전달량 하한 규칙 = 처분 등급 하한 ratio / 재계산 ratio (합성: %s · %.4f)", q$disposition, got))
chk(isTRUE(G$validity(L)), "P22 전달량 < 하한 → status invalid · 라벨 없음 · 기록 1줄(chosen none) · 재판정 거부 · ≥ 하한이면 정상 라벨(양성 대조)")
chk(isTRUE(G$validity_missing(L)), "P23 halt 여도 전달량 미제출 → incomplete · 기록 0")
chk(isTRUE(G$validity_na(L)), "P24 전달량 NA → invalid(판정 불가 · 조용한 통과 없음)")
chk(isTRUE(G$validity_vocab(L)), "P25 설정 어휘 밖 validity outcome → 초안 거부")
chk(isTRUE(G$run_blockers(L)), "P26 rf_prereg_run — 실행 전제(run_prerequisites · P1-08 formals)는 등록 차단이 아니라 run_blockers")

cat("=== M. 돌연변이 (가드를 끈 사본은 red 여야 한다) ===\n")
orig <- readLines(LIB, encoding = "UTF-8", warn = FALSE); orig_txt <- paste(orig, collapse = "\n")
MUT <- list(
  list("M1 금지 SE 스캔 제거", "  fse <- .rfp_scan_forbidden_se(pr, cfg)", "  fse <- character(0)", "forbidden_se"),
  list("M2 덮어쓰기 허용(거부 2곳 + rev 순서 제거 + rename→copy)",
       c("  if (file.exists(path)) stop(sprintf(\"[rf_prereg] 덮어쓰기 거부: %s\", path))",
         "  if (file.exists(path)) { unlink(tmp); stop(sprintf(\"[rf_prereg] 덮어쓰기 거부(경합): %s\", path)) }",
         "  ok <- suppressWarnings(file.rename(tmp, path))", "    want <- if (length(revs)) max(revs) + 1L else 1L"),
       c("  if (FALSE) NULL", "  NULL", "  ok <- file.copy(tmp, path, overwrite = TRUE); unlink(tmp)", "    want <- as.integer(pr$draft_rev)"), "overwrite"),
  list("M3 로드 sha 대조 제거", "  if (!identical(sha, r$sha256)) stop(", "  if (FALSE) stop(", "tamper"),
  list("M4 failed 우선 제거", "flags <- list(failed = any(fail %in% TRUE),", "flags <- list(failed = FALSE,", "failed_precedence"),
  list("M5 규약 대조 제거", "  if (!identical(as.character(s$measurement_regime[[rk]] %||% \"\"), as.character(pr$measurement_regime[[rk]])))", "  if (FALSE)", "regime"),
  list("M6 멈춤 위반 검사 제거", "  viol <- intersect(measured, skipped)", "  viol <- character(0)", "stop_enforced"),
  list("M7 산출물 sha 대조 제거", "    if (!identical(tolower(.rfp_sha_file(ap)), tolower(s$artifact_sha256)))", "    if (FALSE)", "artifact_sha"),
  list("M8 재판정 거부 제거", "  if (length(prior)) stop(", "  if (FALSE) stop(", "reverdict"),
  list("M9 full_sample 선정 허용", "RF_PREREG_SELBASIS <- c(\"as_of\", \"none\")", "RF_PREREG_SELBASIS <- c(\"as_of\", \"none\", \"full_sample\")", "selbasis"),
  list("M10 MDE 에 z(.975) 만(임계값을 MDE 로 오칭)", "t80 <- stats::qnorm(g$power_target) + z", "t80 <- z", "power_t80"),
  list("M11 비짝지음 재표본", "ix <- .rfp_cb_idx(n, bl$b); f(a[ix], bench[ix]) - f(b[ix], bench[ix])",
       "ix <- .rfp_cb_idx(n, bl$b); jx <- .rfp_cb_idx(n, bl$b); f(a[ix], bench[ix]) - f(b[jx], bench[jx])", "paired"),
  list("M12 드라이런 전용 해제", "  if (!isTRUE(dry_run)) stop(", "  if (FALSE) stop(", "dryrun_only"),
  list("M13 must_report 누락 무시", "  if (length(missing))\n", "  if (FALSE)\n", "must_report"),
  list("M14 검정력 재계산 대조 제거", ".rfp_num1(cp[[k]]) && abs(cp[[k]] - re[[k]]) < 1e-9", ".rfp_num1(cp[[k]])", "power_recompute"),
  list("M15 미선언 대상 허용", "  if (!(as.character(m$target %||% \"\") %in% tg)) stop(", "  if (FALSE) stop(", "undeclared_target"),
  list("M16 산출물 안 규약 재도출 제거", "    if (nzchar(ar) && !identical(ar, as.character(pr$measurement_regime[[rk0]])))", "    if (FALSE)", "artifact_regime"),
  ## 적대 검증 수리분(2026-09-25)
  list("M17 손 수치 ≠ 산출물 대조 제거", "      if (!same) stop(", "      if (FALSE) stop(", "hand_numbers"),
  list("M18 산출물 수치 채움 제거(측정 객체 수치 사용)", "    for (st in names(der)) m[[st]] <- der[[st]]", "    NULL", "fill_from_artifact"),
  list("M19 verify_artifacts=FALSE 허용", "  if (!isTRUE(verify_artifacts) && (isTRUE(record) || isTRUE(cfg$verdict$require_artifact_sha)))", "  if (FALSE)", "verify_off"),
  list("M20 판정 불능 멈춤 통과 허용", "    if (length(beyond) && is.na(ev))", "    if (FALSE)", "stop_undecidable"),
  list("M21 멈춤 조건 대상 검증 제거", "      if (!(t %in% c(fids, sids)) && (t %in% c(aids, cids)) && !all(ar %in% aa))", "      if (FALSE)", "stop_target"),
  list("M22 powered_null 의 0 포함 조건 제거(교정 판정 · bootstrap_p)", "    zero_in <- p0 >= a && p0 <= 1 - a", "    zero_in <- TRUE", "pnull_zero"),
  list("M23 등록 시점 설정 고정 제거", "  if (isTRUE(cfg$verdict$pin_to_registration_config) && !identical(", "  if (FALSE && !identical(", "cfg_pin"),
  list("M24 등록-측정 시간 순서 제거", "      if (is.na(mt) || mt < reg_time)", "      if (FALSE)", "prereg_time"),
  list("M25 부트스트랩 설정 고정 제거", "      if (is.null(got) || is.null(want) || !isTRUE(all.equal(as.numeric(got), as.numeric(want))))", "      if (FALSE)", "seed_pin"),
  list("M26 halt 시 핵심 요구 면제", "  req <- if (halted) core else unique(", "  req <- if (halted) character(0) else unique(", "halt_must_report"),
  list("M27 산출물 target 대조 제거", "      if (!is.null(aj[[k]]) && !identical(as.character(aj[[k]]), as.character(m[[k]] %||% \"\")))", "      if (FALSE)", "target_bind"),
  list("M28 산출물 재사용 검사 제거", "    if (length(multi)) stop(", "    if (FALSE) stop(", "artifact_reuse"),
  list("M29 함의 효과 부호 검사 제거", "      if ((identical(pdir, \"decrease\") && !(ie < 0)) || (identical(pdir, \"increase\") && !(ie > 0)))", "      if (FALSE)", "sign"),
  ## PREREGFIX(2026-10-03)
  list("M30 기전 한정 바닥 — scope 대조 제거", "      else if (!.rfp_scope_mech_only(pr, cfg))", "      else if (FALSE)", "mo_scope"),
  list("M31 기전 한정 바닥 — permitted_use 대조 제거", "        if (!(as.character(x$permitted_use %||% \"\") %in% unlist(R$floor_permitted_use_mechanism_only)))", "        if (FALSE)", "mo_floor"),
  list("M32 기전 한정 바닥 — 바닥 a_eligible 대조 제거", "        if (!identical(x$a_eligible, FALSE)) e <- c(e,", "        if (FALSE) e <- c(e,", "mo_floor_aelig"),
  list("M33 기전 한정 바닥 — use_restriction 결정 대조 제거", "        if (nzchar(ur) && !identical(ur, as.character(pr$scope$decision_ref %||% \"\")))", "        if (FALSE)", "mo_restriction"),
  list("M34 scope.a_eligible 아무 값이나 수락", "&& identical(pr$scope$a_eligible, FALSE)\n}", "&& TRUE\n}", "mo_scope_aelig"),
  list("M35 교정 미선언 등록 허용", "  if (!is.list(pc))   #", "  if (FALSE)   #", "cal_required"),
  list("M36 기전 탐지를 명목 CI 로", "    mech <- if (dirn == \"decrease\") p0 < a else p0 > 1 - a", "    mech <- if (dirn == \"decrease\") hi < 0 else lo > 0", "cal_mech"),
  list("M37 함의 효과 배제를 명목 CI 로", "    excl_ie <- if (dirn == \"decrease\") qlo > ie else qhi < ie", "    excl_ie <- if (dirn == \"decrease\") lo > ie else hi < ie", "cal_pnull"),
  list("M38 교정 수준(cal_alpha) 고정 제거", "      if (!(is.numeric(got) && length(got) == 1L && is.finite(got) && isTRUE(abs(as.numeric(got) - as.numeric(cal$value)) <= 1e-12)))", "      if (FALSE)", "cal_alpha_pin"),
  list("M39 결정 파라미터 산출물 재도출 제거", "      if (!is.finite(av) || abs(av - v) > 1e-12 * max(1, abs(av)))", "      if (FALSE)", "param_source"),
  list("M40 출처 없는 결정 파라미터 허용", "    } else addb(\"결정 파라미터 %s 출처 없음(from·derive)", "    } else if (FALSE) addb(\"결정 파라미터 %s 출처 없음(from·derive)", "param_hand"),
  list("M41 derive 재계산 대조 제거", "      if (!is.finite(dv) || abs(dv - v) > 1e-12 * max(1, abs(dv)))", "      if (FALSE)", "param_derive"),
  list("M42 미산출 결정 파라미터 허용", "  if (length(miss)) addb(\"결정 파라미터 미산출", "  if (FALSE) addb(\"결정 파라미터 미산출", "param_missing"),
  list("M43 rhs {param} 미해결(NA)", "    if (.rfp_num1(x)) as.numeric(x) else NA_real_\n  } else if (is.list(r)) {", "    NA_real_\n  } else if (is.list(r)) {", "param_rhs"),
  list("M44 처치 전달 타당성 미집행", "  if (length(vbad)) {", "  if (FALSE) {", "validity"),
  list("M45 전달량을 핵심 요구에서 제외", "                   unlist(lapply(cr$validity %||% list(), .rfp_cond_pairs))))   #", "                   character(0)))   #", "validity_missing"),
  list("M46 전달량 NA 를 통과로", "  vbad <- Filter(function(z) !isTRUE(z$ok), vres)", "  vbad <- Filter(function(z) isFALSE(z$ok), vres)", "validity_na"),
  list("M47 t 교정 — 0 포함 조건 제거", "    zero_in <- tt > tl && tt < th", "    zero_in <- TRUE", "cal_t"),
  list("M48 t 교정 — 함의 효과 배제 방향 반전", "    excl_ie <- if (dirn == \"decrease\") te >= th else te <= tl", "    excl_ie <- if (dirn == \"decrease\") te <= tl else te >= th", "cal_t"),
  list("M49 교정 분위를 명목 수준으로", "qc <- stats::quantile(d[ok], c(cal_alpha, 1 - cal_alpha), names = FALSE, type = 7)",
       "qc <- stats::quantile(d[ok], c((1 - lev) / 2, 1 - (1 - lev) / 2), names = FALSE, type = 7)", "boot_cal"),
  list("M50 판정의 교정 부재 거부 제거", "  if (is.null(kd)) stop(\"[rf_prereg] 등록본에 1차 판정 교정", "  if (FALSE) stop(\"[rf_prereg] 등록본에 1차 판정 교정", "cal_verdict_refuse"),
  list("M51 설정 a_eligible 가드 제거", "  if (!identical(cfg$registration$mechanism_only_scope$a_eligible, FALSE))", "  if (FALSE)", "cfg_mo"),
  list("M52 실행 전제를 run_blockers 에서 누락", "                    vapply(rq, function(d) sprintf(\"실행 전제 %s 미충족(%s)\", d$id %||% \"?\", d$status %||% \"?\"), character(1)))",
       "                    character(0))", "run_blockers"))
for (mu in MUT) {
  txt <- orig_txt; anch_ok <- TRUE
  for (i in seq_along(mu[[2]])) {
    n_hit <- lengths(regmatches(txt, gregexpr(mu[[2]][i], txt, fixed = TRUE)))
    if (n_hit != 1L) { anch_ok <- FALSE; break }
    txt <- sub(mu[[2]][i], mu[[3]][i], txt, fixed = TRUE)
  }
  if (!anch_ok) { ng(paste0(mu[[1]], " — 돌연변이 앵커가 정확히 1회가 아니다(리팩터로 좌표 이동 — 검사 갱신 필요)")); next }
  mp <- file.path(TMPB, paste0("mut_", gsub("[^A-Za-z0-9]", "_", mu[[4]]), ".R")); writeLines(txt, mp, useBytes = TRUE)
  Lm <- tryCatch(load_lib(mp), error = function(e) NULL)
  if (is.null(Lm)) { ng(paste0(mu[[1]], " — 사본 적재 실패")); next }
  res <- tryCatch(G[[mu[[4]]]](Lm), error = function(e) FALSE)
  chk(!isTRUE(res), paste0(mu[[1]], " → 검사 '", mu[[4]], "' red(돌연변이 사살)"), "생존 — 가드를 꺼도 검사가 못 잡는다")
}

cat("=== Z. 루트 색인의 초안(읽기만) ===\n")
cfgR <- tryCatch(L$rf_prereg_config(ROOT), error = function(e) NULL)
idxR <- if (is.null(cfgR)) list() else tryCatch(L$rf_prereg_index(ROOT, cfgR), error = function(e) { ng("Z0 루트 색인 파싱 실패", conditionMessage(e)); list() })
drs <- Filter(function(x) identical(x$kind, "draft"), idxR)
if (!length(drs)) ok("Z0 루트 색인에 초안 없음 — 건너뜀") else for (x in drs) {
  d <- tryCatch(L$rf_prereg_load(x$prereg_id, "draft", x$rev, ROOT, cfgR), error = function(e) conditionMessage(e))
  if (is.character(d)) { ng(sprintf("Z1 %s rev%s 로드", x$prereg_id, x$rev), d); next }
  vv <- L$rf_prereg_validate(d, "draft", ROOT, cfgR)
  chk(vv$ok && identical(d$framing, "falsification_attempt") && identical(unlist(d$labels), unlist(cfgR$labels)) &&
      !length(L$.rfp_scan_forbidden_se(d, cfgR)),
      sprintf("Z1 %s rev%s — sha 무결성 · 초안 검증 · 라벨 4종 · 금지 SE 0 (등록 차단 %d건은 보고만)", x$prereg_id, x$rev, length(vv$registration_blockers)),
      paste(vv$errors, collapse = " | "))
}

unlink(TMPB, recursive = TRUE)
cat(sprintf("\nTOTAL: %d pass / %d fail\n", P, F))
cat(sprintf('{"test":"rf_prereg","pass":%d,"fail":%d,"total":%d}\n', P, F, P + F))
quit(save = "no", status = if (F > 0L) 1L else 0L)
