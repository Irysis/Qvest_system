## test_label_gate_wiring.R — FQ-119 라벨 자격 관문 **배선** 위반 주입 테스트
##
## 배경: 계약(`label_eligibility_gate.R`)과 그 자체 검사(17/17)는 이미 있었는데 **호출부가 0**
##   이었다. 그 상태로 "관문 신설 완료"라고 적으면 이 저장소가 반복 수리한 dead code 계통
##   그대로다(WIRE-1 선례: 정의만 있고 소비 없음 → `test_tripwire_reachability.R` 의 배선①/②).
##
## 본 검사가 재는 것 — 세 층:
##   ① **배선 존재**: production 파일이 관문을 *실제로 호출*하는가 (사본 아닌 원본 파싱)
##   ② **배선 검출력**: 그 호출부를 지우면 ①이 실제로 실패하는가 (돌연변이 — 없으면 ①은 장식)
##   ③ **동작 실효**: 자격 라벨은 통과, 무자격은 warn/block 이 실제로 발화하는가 (양방향)
##
## 실행: Rscript 08_Tests/hooks/test_label_gate_wiring.R

## ── 루트 해석: 코드 루트와 데이터 루트를 **분리**한다 ────────────────────────
##   worktree 에서는 코드가 worktree 에, `.cache/` 는 main 에 있다. 한 변수로 합치면
##   worktree 의 배선을 고친 뒤 main 의 파일을 검사하게 된다(옳은 것을 재지만 잘못된 지점).
.pick <- function(cands, probe) {
  cands <- cands[nzchar(cands)]
  hit <- cands[file.exists(file.path(cands, probe))]
  if (length(hit)) hit[1] else ""
}
CODE_ROOT <- .pick(c(getwd(), Sys.getenv("CLAUDE_PROJECT_DIR"), Sys.getenv("QM_ROOT")),
                   "02_Infrastructure/contracts/regime_label_gate.R")
DATA_ROOT <- .pick(c(Sys.getenv("QM_ROOT"), getwd(), Sys.getenv("CLAUDE_PROJECT_DIR")),
                   ".cache/benchmark.parquet")
if (!nzchar(CODE_ROOT)) stop("[wiring] 코드 루트를 찾지 못함 — regime_label_gate.R 부재")
cat(sprintf("[root] CODE=%s\n[root] DATA=%s\n", CODE_ROOT, if (nzchar(DATA_ROOT)) DATA_ROOT else "(없음)"))

pass <- 0L; fail <- 0L
ck <- function(label, cond) {
  if (isTRUE(cond)) { pass <<- pass + 1L; cat(sprintf("  [PASS] %s\n", label)) }
  else { fail <<- fail + 1L; cat(sprintf("  [FAIL] %s\n", label)) }
}
rd <- function(rel) {
  f <- file.path(CODE_ROOT, rel)
  if (!file.exists(f)) return(character(0))
  readLines(f, warn = FALSE)
}
## ★부분문자열 포함만 쓴다 — 한글 혼재 텍스트에서 정규식 단어경계(\b)는 조용히 FALSE 가 된다
##   (2026-08-08 실측: 같은 blob 에서 fixed 25건 vs 경계 0건). 0 을 결론으로 쓰지 않기 위함.
has <- function(src, pat) any(grepl(pat, src, fixed = TRUE))

## ── ① 배선 존재 ─────────────────────────────────────────────────────────────
cat("\n── ① 배선 존재 (production 원본 파싱) ──\n")

SITES <- list(
  list(key = "regime_module_admission",
       file = "02_Infrastructure/portfolio/regime_module_admission.R",
       calls = c("regime_label_gate(asof = asof_date",
                 'rlg_enforce(label_gate, site = "regime_module_admission")'),
       extra = c("label_gate=label_gate")),
  list(key = "auto_regime_overlay_ab",
       file = "02_Infrastructure/ops/auto_regime_overlay_ab.R",
       calls = c('label_basis = "monthly_prev"',
                 'rlg_enforce(.lg, site = "auto_regime_overlay_ab/unified_cat")'),
       extra = c("h2_regime_label_gate.json")),
  list(key = "forward_weights_D3_M4gAE",
       file = "02_Infrastructure/portfolio/forward_weights_D3_M4gAE.R",
       calls = c('label_basis = "alpha_scores_regime_state"',
                 'rlg_enforce(g, site = "forward_weights_D3_M4gAE/beta_R05", mode = "warn")'),
       extra = c("label_gate=LABEL_GATE")),
  list(key = "portfolio_governor",
       file = "02_Infrastructure/portfolio/portfolio_governor.R",
       calls = c(".pg_label_gate_once(date)",
                 'rlg_enforce(gg, site = "portfolio_governor/regime_adj", mode = "warn")'),
       extra = c("label_gate = .PG_LABEL_GATE"))
)
SRC <- list()
for (s in SITES) {
  src <- rd(s$file); SRC[[s$key]] <- src
  ck(sprintf("배선① [%s] 파일 존재", s$key), length(src) > 0L)
  for (p in s$calls)
    ck(sprintf("배선① [%s] 호출부 존재: %s", s$key, substr(p, 1, 52)), has(src, p))
  for (p in s$extra)
    ck(sprintf("배선② [%s] 판정 노출: %s", s$key, substr(p, 1, 40)), has(src, p))
}

## 훅(실행 표면) — 스키마만 고치면 JSON-Schema 엔진이 없어 그것도 dead 계약이 된다
hk <- rd("02_Infrastructure/hooks/worktask_artifact_validator.sh")
ck("배선① [hook] label_consumption 판독", has(hk, 'pkg.get("label_consumption")'))
ck("배선① [hook] 증거 결측 발화", has(hk, "evidence_missing"))
ck("배선① [hook] 무자격 발화", has(hk, "ineligible_label"))
ck("배선① [hook] 미선언 우회 탐지", has(hk, "undeclared_consumption"))

## 스키마 조건부 required
sc_raw <- rd("02_Infrastructure/worktask/schema.json")
ck("배선① [schema] label_eligibility_evidence 정의", has(sc_raw, '"label_eligibility_evidence"'))
ck("배선① [schema] label_consumption 정의", has(sc_raw, '"label_consumption"'))

## 계약 본체 불변 (수정 금지 — 배선만)
cg <- rd("02_Infrastructure/contracts/label_eligibility_gate.R")
ck("계약 본체 LABEL_GATE_ALPHA 단일 정의(문턱 sweep 금지)",
   sum(grepl("^LABEL_GATE_ALPHA <-", cg)) == 1L)
ck("계약 본체 문턱값 0.05 불변", has(cg, "LABEL_GATE_ALPHA <- 0.05"))

## ── ② 배선 검출력 (돌연변이) ────────────────────────────────────────────────
## 호출부를 지운 사본에서 ①의 검사가 **실제로 실패**해야 한다. 아니면 ①은 장식이다.
cat("\n── ② 배선 검출력 (호출부 제거 돌연변이) ──\n")
for (s in SITES) {
  src <- SRC[[s$key]]
  if (!length(src)) next
  probe <- s$calls[length(s$calls)]              # rlg_enforce 호출 라인
  mutant <- src[!grepl(probe, src, fixed = TRUE)]
  ck(sprintf("★돌연변이 [%s]: 호출부 제거 시 배선① 검사가 뒤집힌다", s$key),
     has(src, probe) && !has(mutant, probe))
}
mut_hk <- hk[!grepl("undeclared_consumption", hk, fixed = TRUE)]
ck("★돌연변이 [hook]: 미선언 탐지 제거 시 검사가 뒤집힌다",
   has(hk, "undeclared_consumption") && !has(mut_hk, "undeclared_consumption"))

## ── ③ 동작 실효 (합성 위반 주입) ────────────────────────────────────────────
cat("\n── ③ 동작 실효 (어댑터 위반 주입) ──\n")
owd <- getwd(); setwd(CODE_ROOT)
suppressWarnings(suppressPackageStartupMessages(
  source("02_Infrastructure/contracts/regime_label_gate.R")))
setwd(owd)
ck("어댑터 로드 후 %||% 미오염 (전역 연산자 보호)",
   !exists(".rlg_polluted") && is.function(regime_label_gate))
.rlg_load_contract(CODE_ROOT)          # 계약 본체를 격리 환경에 적재(지연 로드)
le <- get("label_eligibility", envir = .rlg_env)
ck("계약 본체가 격리 환경에만 적재 (전역 오염 없음)",
   !exists("label_eligibility", envir = globalenv(), inherits = FALSE))

set.seed(20260808L)
n <- 300L
evt <- rep(FALSE, n); evt[sample(n, 60)] <- TRUE
lab <- evt; lab[sample(which(evt), 15)] <- FALSE; lab[sample(which(!evt), 10)] <- TRUE
g_ok   <- le(lab, evt)
g_rand <- le(sample(c(TRUE, FALSE), n, TRUE, c(.2, .8)), evt)
ck("자격 라벨 → ELIGIBLE", isTRUE(g_ok$eligible))
ck("무작위 라벨 → 차단", identical(g_rand$eligible, FALSE))
ck("★양방향 실증(판정이 실제로 갈린다)", !identical(g_ok$eligible, g_rand$eligible))

fired <- FALSE
withCallingHandlers(rlg_enforce(g_rand, "unit", mode = "warn"),
  warning = function(w) { fired <<- TRUE; invokeRestart("muffleWarning") })
ck("warn 모드: 무자격에 경고 발화", isTRUE(fired))
quiet <- TRUE
withCallingHandlers(rlg_enforce(g_ok, "unit", mode = "warn"),
  warning = function(w) { quiet <<- FALSE; invokeRestart("muffleWarning") })
ck("warn 모드: 자격 라벨엔 무경고 (항상경고 아님)", isTRUE(quiet))
ck("block 모드: 무자격에 stop 발화",
   isTRUE(tryCatch({ rlg_enforce(g_rand, "unit", mode = "block"); FALSE },
                   error = function(e) grepl("소비 측정 착수 금지", conditionMessage(e)))))
ck("block 모드: 자격 라벨은 통과 (항상차단 아님)",
   isTRUE(tryCatch({ rlg_enforce(g_ok, "unit", mode = "block"); TRUE }, error = function(e) FALSE)))
## '재지 못했다' 를 '통과했다' 로 접지 않는가
g_un <- le(logical(0), logical(0))
ck("빈 입력 → UNMEASURABLE (eligible TRUE 아님)", !isTRUE(g_un$eligible))
ck("UNMEASURABLE 도 block 모드에서 차단",
   isTRUE(tryCatch({ rlg_enforce(g_un, "unit", mode = "block"); FALSE }, error = function(e) TRUE)))

## ── ④ 현장: 사이트별 basis 가 실제 라벨을 재는가 ────────────────────────────
cat("\n── ④ 현장 실측 (basis 별 정본 패널) ──\n")
if (nzchar(DATA_ROOT)) {
  BAS <- c("daily_t1_monthstart", "monthly_prev", "monthly_same", "alpha_scores_regime_state")
  gs <- list()
  for (b in BAS) gs[[b]] <- tryCatch(regime_label_gate(asof = as.Date("2026-08-07"),
                                                       label_basis = b, proj = DATA_ROOT),
                                     error = function(e) NULL)
  for (b in BAS) {
    g <- gs[[b]]
    if (is.null(g) || is.null(g$n) || g$n == 0L) { ck(sprintf("현장 [%s] 패널 로드", b), FALSE); next }
    cat(sprintf("   [현장] %-26s n=%3d on=%3d lift %5.2fx p %s lag1보존 %.2f %s\n",
                b, g$n, g$n_on, g$lift, format(g$fisher_p, scientific = TRUE, digits = 3),
                g$diag_lag1$retention, g$verdict))
    ck(sprintf("현장 [%s] 판정 성립(패널 비어있지 않음)", b), g$n > 100L && !is.na(g$eligible))
  }
  ## 사이트마다 basis 를 나눈 이유가 실재하는가 — 같은 답이면 파라미터가 장식이다
  p1 <- regime_label_monthly_panel(DATA_ROOT, label_basis = "daily_t1_monthstart")
  p2 <- regime_label_monthly_panel(DATA_ROOT, label_basis = "monthly_prev")
  mm <- merge(p1[, .(ym, r1 = regime)], p2[, .(ym, r2 = regime)], by = "ym")
  agree <- mean(mm$r1 == mm$r2)
  cat(sprintf("   [현장] 두 구성 라벨 일치율 %.3f (n=%d)\n", agree, nrow(mm)))
  ck("★basis 파라미터가 장식이 아님 (구성 간 라벨이 실제로 다름)", agree < 0.98 && agree > 0.5)
  ## 어휘 불일치는 조용한 통과가 아니라 UNMEASURABLE 로 떨어져야 한다
  g_wrong <- regime_label_gate(asof = as.Date("2026-08-07"),
                               label_basis = "alpha_scores_regime_state",
                               stress_labels = c("RISK_OFF"), proj = DATA_ROOT)
  ck("어휘 불일치(라벨 상수) → UNMEASURABLE_DEGENERATE (합격 아님)",
     identical(g_wrong$verdict, "UNMEASURABLE_DEGENERATE"))
} else {
  cat("  [skip] 데이터 루트 부재 — 현장 축 미실행(합격으로 세지 않음)\n")
}

## ── ⑤ 배포 경로 안전장치: 경고 고정 (env 로 block 승격 불가) ────────────────
cat("\n── ⑤ 배포 경로 경고 고정 ──\n")
for (k in c("forward_weights_D3_M4gAE", "portfolio_governor")) {
  src <- SRC[[k]]
  ck(sprintf("[%s] rlg_enforce 에 mode=\"warn\" 명시 (env block 승격 차단)", k),
     has(src, 'mode = "warn"'))
}
ck("[forward_weights] 관문 실패가 배포를 멈추지 않음 (tryCatch 로 감쌈)",
   has(SRC[["forward_weights_D3_M4gAE"]], "LABEL_GATE <- tryCatch({"))

cat(sprintf("\n[test_label_gate_wiring] PASS=%d FAIL=%d\n", pass, fail))
cat(sprintf('{"test":"label_gate_wiring","pass":%d,"fail":%d,"total":%d}\n',
            pass, fail, pass + fail))
if (fail > 0L) quit(status = 1L)
