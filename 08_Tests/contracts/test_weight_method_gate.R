# test_weight_method_gate.R — 판별형 비중방법 게이트의 **발화 실증**
#
# 대상: 02_Infrastructure/portfolio/weight_method_gate.R
#       + run_alpha_search.R 의 소비면 배선
#
# 왜 이 시험이 본체인가 (2026-08-24):
#   .normalize 순서 결함으로 lean 6종이 **정확히 EW** 를 냈는데, 그 사실은 이미
#   06_Registry/weight_catalog.json 의 probe.max_abs_dev_from_ew 에 측정돼 커밋돼
#   있었다(당시 22개 항목이 정확히 0). 계기가 없어서가 아니라 **게이트가 없어서**
#   지나갔다. 이 게이트가 그 자리이므로, 게이트가 실제로 발화하는지 실증한다.
#   ★그리고 제약형 게이트로는 구조적으로 못 잡는다 — EW 는 종목수·bounds·Σw 를
#   전부 만족한다. 축 D 가 그 사실을 직접 단언한다.

suppressPackageStartupMessages({ library(jsonlite) })

PASS <- 0L; FAIL <- 0L; SKIP <- 0L; SKIPS <- list()
ok <- function(m) { PASS <<- PASS + 1L; cat("  PASS ", m, "\n") }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat("  FAIL ", m, " :: ", d, "\n") }
sk <- function(a, r, mi) { SKIP <<- SKIP + 1L
  SKIPS[[length(SKIPS) + 1L]] <<- list(axis = a, reason = r, missing = mi)
  cat("  SKIP ", a, " — ", r, "\n") }
emit <- function() {
  cat(sprintf("\nTOTAL: %d pass / %d fail / %d skipped\n", PASS, FAIL, SKIP))
  j <- sprintf('{"test":"weight_method_gate","pass":%d,"fail":%d,"total":%d,"skipped":%d',
               PASS, FAIL, PASS + FAIL, SKIP)
  if (SKIP > 0L) j <- paste0(j, ',"skips":[', paste(vapply(SKIPS, function(s)
    sprintf('{"axis":"%s","reason":"%s","missing":"%s"}', s$axis, s$reason, s$missing),
    character(1)), collapse = ","), "]")
  cat(paste0(j, "}\n")); quit(save = "no", status = if (FAIL > 0L) 1L else 0L)
}

.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else "."
}, error = function(e) ".")
ROOT <- normalizePath(file.path(.self, "..", ".."), winslash = "/", mustWork = FALSE)
GATE <- file.path(ROOT, "02_Infrastructure", "portfolio", "weight_method_gate.R")
RAS  <- file.path(ROOT, "02_Infrastructure", "alpha_search", "run_alpha_search.R")

cat("=== weight method gate ===\n")
if (!file.exists(GATE)) { sk("gate_present", "게이트 모듈 부재", GATE); emit() }

ge <- new.env(parent = globalenv())
sys.source(GATE, envir = ge)
verdict <- ge$weight_method_probe_verdict
assert_alive <- ge$assert_weight_method_alive

# 픽스처 카탈로그를 세운다 — 생산 원장에 의존하면 남의 재생성에 검사가 흔들린다.
mk_root <- function(entries) {
  sb <- normalizePath(tempfile("qv_wmg_"), winslash = "/", mustWork = FALSE)
  dir.create(file.path(sb, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(sb, "02_Infrastructure"), recursive = TRUE, showWarnings = FALSE)
  writeLines(toJSON(list(n_entries = length(entries), entries = entries),
                    auto_unbox = TRUE, null = "null", digits = NA),
             file.path(sb, "06_Registry", "weight_catalog.json"))
  sb
}
ent <- function(id, dev, reason = "픽스처") {
  p <- if (is.null(dev)) NULL else list(ok = dev > 0, max_abs_dev_from_ew = dev, reason = reason)
  list(catalog_id = id, label = sub("^[a-z]+:", "", id), probe = p)
}

# ── A. 양성 대조 — 살아있는 방법은 통과 ────────────────────────────────────
cat("\n── A. 양성 대조 ────────────────────────────────────────────\n")
r1 <- mk_root(list(ent("lean:ivol", 0.0222)))
v <- verdict("lean:ivol", root = r1)
if (identical(v$verdict, "PASS")) ok("dev>0 → PASS") else ng("dev>0 인데 PASS 아님", v$detail)
if (is.null(tryCatch({ assert_alive("lean:ivol", root = r1); NULL },
                     error = function(e) conditionMessage(e))))
  ok("살아있는 방법을 막지 않는다") else ng("★정상 방법을 막는다")

# ── B. 위반 주입 — EW 동치는 막는다 ────────────────────────────────────────
cat("\n── B. 위반 주입 (dev == 0) ─────────────────────────────────\n")
r2 <- mk_root(list(ent("qepm:MaxDiv", 0, "EW 퇴화 — wrapper 폴백")))
v2 <- verdict("qepm:MaxDiv", root = r2)
if (identical(v2$verdict, "VIOLATION")) ok("dev==0 → VIOLATION") else
  ng("★EW 동치를 안 잡는다", v2$detail)
e2 <- tryCatch({ assert_alive("qepm:MaxDiv", root = r2); NULL },
               error = function(e) conditionMessage(e))
if (!is.null(e2) && grepl("정확히 EW", e2, fixed = TRUE))
  ok("strict=TRUE 는 stop 하고 사유가 조치 가능하다") else
  ng("★차단 안 되거나 사유가 조치 불가", substr(paste(e2, collapse = ""), 1, 120))
w2 <- tryCatch({ assert_alive("qepm:MaxDiv", root = r2, strict = FALSE); "warn" },
               warning = function(w) "warn")
if (identical(w2, "warn")) ok("strict=FALSE 는 경보만(경보 표면용 경로 존재)") else
  ng("★strict=FALSE 경로가 없다")

# ── C. 3상태 — 미측정/부재/모호는 **막지 않는다** ──────────────────────────
cat("\n── C. 3상태 (미측정은 위반이 아니다) ───────────────────────\n")
r3 <- mk_root(list(ent("lean:x", NULL)))
if (identical(verdict("lean:x", root = r3)$verdict, "UNKNOWN"))
  ok("probe 미측정 → UNKNOWN (차단 아님)") else ng("★미측정을 위반으로 계상한다")
if (identical(verdict("아무거나_zzz", root = r3)$verdict, "UNKNOWN"))
  ok("카탈로그 부재 이름 → UNKNOWN") else ng("★미등재를 위반으로 계상한다")
# ★모호: 같은 bare 이름이 두 계열에 걸릴 때 첫 일치를 조용히 고르면 퇴화한 쪽을 놓친다
r4 <- mk_root(list(ent("lean:maxdiv", 0.0758), ent("qepm:MaxDiv", 0)))
v4 <- verdict("MaxDiv", root = r4)
if (identical(v4$verdict, "UNKNOWN") && grepl("모호", v4$detail, fixed = TRUE) &&
    grepl("qepm:MaxDiv", v4$detail, fixed = TRUE) && grepl("lean:maxdiv", v4$detail, fixed = TRUE))
  ok("모호한 bare 이름 → UNKNOWN + 후보 전부와 각 dev 를 보고") else
  ng("★모호를 조용히 한쪽으로 해석한다", v4$detail)
if (identical(verdict("qepm:MaxDiv", root = r4)$verdict, "VIOLATION"))
  ok("접두를 붙이면 정확 일치가 이긴다(해석 순서 계약)") else
  ng("★catalog_id 정확 일치가 우선하지 않는다")

# ── D. ★제약형 게이트로는 못 잡는다 (이 게이트의 존재 이유) ────────────────
cat("\n── D. 제약형 게이트의 구조적 한계 실증 ─────────────────────\n")
n <- 25L; ew <- rep(1 / n, n)
if (abs(sum(ew) - 1) < 1e-12 && all(ew >= 0) && all(ew <= 0.20 + 1e-12) && length(ew) <= 25L)
  ok("EW 는 고정 축(≤25종·w≥0·w≤0.20·Σw=1)을 **전부** 만족 — 제약형은 영원히 통과시킨다") else
  ng("★EW 가 고정 축을 위반한다(전제 오류)")
r5 <- mk_root(list(ent("lean:dead", 0)))
if (identical(verdict("lean:dead", root = r5)$verdict, "VIOLATION"))
  ok("판별형 게이트는 같은 EW 를 잡는다 — 제약형과 대비") else
  ng("★판별형도 못 잡는다")

# ── E. 소비면 배선 (run_alpha_search) ──────────────────────────────────────
cat("\n── E. 소비면 배선 ──────────────────────────────────────────\n")
if (!file.exists(RAS)) sk("wiring", "run_alpha_search.R 부재", RAS) else {
  rs <- readLines(RAS, warn = FALSE)
  j <- paste(rs, collapse = "\n")
  if (grepl("weight_method_gate.R", j, fixed = TRUE))
    ok("run_alpha_search 가 게이트 모듈을 참조한다") else
    ng("★배선 부재 — 게이트가 소비면에 없다")
  if (grepl("assert_weight_method_alive(weight_method", j, fixed = TRUE))
    ok("인자 weight_method 를 그대로 게이트에 넘긴다") else
    ng("★게이트에 다른 값을 넘긴다")
  # ★돌연변이 통제: 호출부를 지우면 위 검출이 실제로 뒤집히는가
  mj <- paste(rs[!grepl("assert_weight_method_alive", rs)], collapse = "\n")
  if (!grepl("assert_weight_method_alive(weight_method", mj, fixed = TRUE))
    ok("돌연변이 통제: 호출부를 지우면 배선 검출이 뒤집힌다") else
    ng("★돌연변이 통제 실패 — 배선 검사가 아무것도 재고 있지 않다")
}

emit()
