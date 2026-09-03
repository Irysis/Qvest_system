# test_reinforce_ledger.R — v10 강화 원장의 양방향 검증 (임시 루트에서 실행 — 실원장 불변)
#
# 계약: ①root_papers 없는 attempt 거부 ②L1 20회 상한 stop + exhausted 전이
#       ③L2 무한(21회째 허용) ④Grade A → graduated ⑤논문 3편 → 결합 검토 플래그·기록
#       ⑥PIT FAIL → 재활성화 ⑦원자 쓰기 왕복 (재로드 파싱)
# 실행: Rscript 08_Tests/worktask/test_reinforce_ledger.R

# 앵커 = self-first (r-portability 금칙 ④-b: 테스트 러너는 자기 위치 1순위 — env 는 폴백)
.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else "."
}, error = function(e) ".")
root <- normalizePath(file.path(.self, "..", ".."), winslash = "/", mustWork = FALSE)
if (!file.exists(file.path(root, "02_Infrastructure", "config.R")))
  root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(root)
suppressPackageStartupMessages(library(jsonlite))

pass <- 0L; fail <- 0L
ok <- function(m) { cat(sprintf("  [PASS] %s\n", m)); pass <<- pass + 1L }
ng <- function(m) { cat(sprintf("  [FAIL] %s\n", m)); fail <<- fail + 1L }

# 임시 루트 (02_Infrastructure/config.R 마커 + 06_Registry 흉내 — 실원장 보호)
TMP <- file.path(tempdir(), sprintf("rf_test_%d", Sys.getpid()))
dir.create(file.path(TMP, "02_Infrastructure"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(TMP, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
file.create(file.path(TMP, "02_Infrastructure", "config.R"))
source("02_Infrastructure/reinforcement/reinforce_ledger.R")
R <- TMP  # 명시 root 인자 사용 (env 오염 없이)

pp <- list(list(url = "https://arxiv.org/abs/1234.5678", claim = "논문 §4 후속연구"))

# ① 근거 논문 — ★2026-09-03 의무 해제(도훈 "강화에는 근거논문 필요없게 배선해").
#   구 계약은 root_papers 가 없으면 원장이 거부하는 것이었다. 이제 거부하지 않고
#   시도 레코드에 evidence = paper/method/none 을 남긴다. 통과 여부가 아니라 **적립된 필드**를 본다.
#   ★근거 시험은 별도 entry 에서 한다 — 구판은 '거부라서 카운트가 안 는다'는 데 기대고 있었고,
#     거부가 사라진 채 같은 entry 를 쓰면 ②의 상한 시험이 밀린다(부작용도 계약의 일부다).
e0 <- rf_open_entry(1L, "RP_T0", "C", root = R)
.ev_of <- function(bid, k) tryCatch({
  .e <- Filter(function(x) identical(x$base_id, bid), rf_load(1L, root = R)$entries)
  .e[[1]]$attempts[[k]]$evidence
}, error = function(e) NA_character_)

invisible(rf_append_attempt(1L, "RP_T0", "근거 없음", "weighting", list(), root = R))
if (identical(.ev_of("RP_T0", 1L), "none"))
  ok("① root_papers 없어도 통과 · evidence=\"none\" 적립(의무 해제)") else
  ng(sprintf("① evidence 불일치: %s", .ev_of("RP_T0", 1L)))

invisible(rf_append_attempt(1L, "RP_T0", "url 없는 항목", "weighting",
                            list(list(claim = "url 없음")), root = R))
if (identical(.ev_of("RP_T0", 2L), "none"))
  ok("① url 빈 root_papers 도 evidence=\"none\"") else
  ng(sprintf("① url 빈 항목 evidence=%s", .ev_of("RP_T0", 2L)))

# 양성 대조 — evidence 가 상수로 굳지 않았음을 보인다(url 있으면 paper, method 있으면 method)
invisible(rf_append_attempt(1L, "RP_T0", "근거 있음", "weighting", pp, root = R))
invisible(rf_append_attempt(1L, "RP_T0", "방법 명시", "risk_overlay",
                            list(list(method = "vol-target 20%")), root = R))
if (identical(.ev_of("RP_T0", 3L), "paper") && identical(.ev_of("RP_T0", 4L), "method"))
  ok("① 양성 대조 — url→paper · method→method (필드가 실제로 구별한다)") else
  ng(sprintf("① evidence 미구별: 3=%s 4=%s", .ev_of("RP_T0", 3L), .ev_of("RP_T0", 4L)))

e <- rf_open_entry(1L, "RP_T1", "C", root = R)

# 정상 attempt + 잘못된 축 거부
a1 <- rf_append_attempt(1L, "RP_T1", "비중방법 교체", "weighting", pp, root = R)
if (identical(a1$n, 1L)) ok("정상 attempt n=1 등록") else ng("attempt 등록 실패")
rax <- tryCatch({ rf_append_attempt(1L, "RP_T1", "x", "regime_identification", pp, root = R); "no_stop" },
                error = function(e) conditionMessage(e))
if (grepl("축이 아님", rax)) ok("L1 에 L2 축(regime_identification) 거부") else ng("축 검증 실패")

# ② 상한 — ★칸 수는 **원장**에서 센다(하드코딩 금지).
#   2026-09-01 격자 재편(B5 오버레이 블록 신설 · 5블록×5)으로 max_attempts 20→25 가 됐는데
#   구판 검사기는 20 을 박아두고 "21번째" 를 기대해 상시 FAIL 이었다 — 검사기가 정본보다 낡은 자리.
CAP <- rf_load(1L, root = R)$max_attempts   # 원장 최상위 필드(entry 아님)
if (is.numeric(CAP) && CAP >= 2L) ok(sprintf("② 상한 원장에서 파생 (max_attempts=%d)", as.integer(CAP))) else
  ng(sprintf("② max_attempts 미발행 — 상한 검사 불가(값=%s)", paste(CAP, collapse = ",")))
for (k in 2:as.integer(CAP)) invisible(rf_append_attempt(1L, "RP_T1", sprintf("시도 %d", k), "multifactor", pp, root = R))
r2 <- tryCatch({ rf_append_attempt(1L, "RP_T1", sprintf("%d번째", as.integer(CAP) + 1L), "multifactor", pp, root = R); "no_stop" },
               error = function(e) conditionMessage(e))
obj <- rf_load(1L, root = R)
# ★위치가 아니라 base_id 로 찾는다 — entries 순서는 앞에 entry 하나만 늘어도 바뀐다.
st <- tryCatch(Filter(function(x) identical(x$base_id, "RP_T1"), obj$entries)[[1]]$status,
               error = function(e) NA_character_)
if (grepl("소진", r2) && identical(st, "exhausted")) ok(sprintf("② %d번째 시도 stop + exhausted 전이", as.integer(CAP) + 1L)) else
  ng(sprintf("② 상한 미작동(cap=%s): msg=%s status=%s", CAP, substr(r2, 1, 40), st))

# ③ L2 무한
invisible(rf_open_entry(2L, "FR_T1", "C", root = R))
for (k in 1:21) invisible(rf_append_attempt(2L, "FR_T1", sprintf("국면 %d", k), "regime_identification", pp, root = R))
o2 <- rf_load(2L, root = R)
if (o2$entries[[1]]$attempts_used == 21L && identical(o2$entries[[1]]$status, "active"))
  ok("③ L2 21회째도 active (무한 모드)") else ng("③ L2 상한이 걸림 — 무한 모드 위반")

# ④ Grade A → graduated
invisible(rf_open_entry(1L, "RP_T2", "B", root = R))
invisible(rf_append_attempt(1L, "RP_T2", "오버레이", "risk_overlay", pp, root = R))
invisible(rf_record_result(1L, "RP_T2", 1L, "A", essence = list(port_t = 3.1), root = R))
o1 <- rf_load(1L, root = R)
i2 <- which(vapply(o1$entries, function(e) identical(e$base_id, "RP_T2"), logical(1)))
if (identical(o1$entries[[i2]]$status, "graduated")) ok("④ Grade A → graduated") else ng("④ graduated 전이 실패")

# ⑤ 결합 검토 — RP_T1/RP_T2 + 1건 더 open → 카운터 3
invisible(rf_open_entry(1L, "RP_T3", "F", root = R))
o1 <- rf_load(1L, root = R)
if (o1$combination_review$papers_since_last_review >= 3L) ok("⑤ 논문 3편 → 결합 검토 카운터 도래") else
  ng(sprintf("⑤ 카운터=%s (3 기대)", o1$combination_review$papers_since_last_review))
invisible(rf_record_combination_review(c("RP_T1", "RP_T2", "RP_T3"), "no_combination",
                                       note = "축 이질 — 결합 이득 없음", root = R))
o1 <- rf_load(1L, root = R)
if (o1$combination_review$papers_since_last_review == 0L &&
    length(o1$combination_review$history) == 1L) ok("⑤ 검토 기록 + 카운터 리셋") else ng("⑤ 검토 기록 실패")

# ⑥ PIT FAIL → 재활성화
invisible(rf_record_judge(1L, "RP_T2", "stage_artifacts/judge/x.json", pit_pass = FALSE, root = R))
o1 <- rf_load(1L, root = R)
if (identical(o1$entries[[i2]]$status, "active")) ok("⑥ PIT FAIL → active 재전이 (등급 무효)") else
  ng("⑥ PIT FAIL 재활성화 실패")

# ⑦ 왕복 파싱
p1 <- file.path(R, "06_Registry", "reinforce_ledger_l1.json")
chk <- tryCatch(fromJSON(p1, simplifyVector = FALSE), error = function(e) NULL)
if (!is.null(chk) && identical(chk$schema_version, "reinforce_ledger_v2")) ok("⑦ 원장 왕복 파싱 OK") else
  ng("⑦ 원장 파싱 실패")

# ⑧ 서술 의무 — idea 공백 거부 (2026-09-03 신설)
#   실사고: 원장 305 시도 중 184건(60%)이 idea=[] 였다. 등급은 있는데 무엇을 한 시도인지 없다.
#   원인은 sprintf 영길이 붕괴 — 조각 하나가 NULL 이면 결과 전체가 character(0) 이 된다.
i3 <- rf_open_entry(1L, "RP_T3", "논문3", "STR_x", "B", root = R)
.rej <- function(v) tryCatch({ rf_append_attempt(1L, "RP_T3", v, "multifactor", pp, root = R); "no_stop" },
                             error = function(e) conditionMessage(e))
.hits <- vapply(list(character(0), "", "   ", NULL), function(v) grepl("idea 가 비었다", .rej(v)), logical(1))
if (all(.hits)) ok("⑧ 위반 주입 4방향(character(0)/\"\"/공백/NULL) 전부 거부") else
  ng(sprintf("⑧ 공백 idea 가 통과했다 — 발화 %d/4", sum(.hits)))

# 정상 idea 는 통과하고 **길이 1 문자열**로 저장된다
.att <- tryCatch(rf_append_attempt(1L, "RP_T3", "정상 서술 한 줄", "multifactor", pp, root = R),
                 error = function(e) NULL)
.e3 <- Filter(function(e) identical(e$base_id, "RP_T3"), rf_load(1L, root = R)$entries)
.stored <- tryCatch(.e3[[1L]]$attempts[[1L]]$idea, error = function(e) NULL)
if (!is.null(.att) && is.character(.stored) && length(.stored) == 1L && nzchar(.stored))
  ok("⑧ 정상 idea 통과 + 길이 1 문자열로 적립") else
  ng(sprintf("⑧ 정상 idea 적립 실패 (len=%s)", length(.stored %||% character(0))))

# 함정의 실재 — 이 런타임에서 sprintf 가 정말 무너지는가(규칙이 아니라 현상을 잰다)
if (length(sprintf("a=%s b=%s", "A", NULL)) == 0L)
  ok("⑧ 함정 재현 — sprintf 는 인자 하나가 NULL 이면 character(0) 을 낸다") else
  ng("⑧ sprintf 영길이 붕괴가 재현되지 않는다 — 이 계약의 전제가 바뀌었다(검사기 갱신 필요)")

# 무인 러너 2종이 조립 전에 조각을 길이 1로 강제하는가 (정적 — 원장 가드에 도달하기 전 단계)
for (.f in c("02_Infrastructure/ops/reinforce_auto_parallel.R", "02_Infrastructure/ops/reinforce_auto_run.R")) {
  .repo <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  .s <- tryCatch(paste(readLines(file.path(.repo, .f), warn = FALSE), collapse = "\n"), error = function(e) "")
  if (grepl(".s1(CELL$code)", .s, fixed = TRUE))
    ok(sprintf("⑧ %s — idea 조각을 .s1() 로 강제", basename(.f))) else
    ng(sprintf("⑧ %s — idea 조립이 무방비(영길이 붕괴 재발 경로)", basename(.f)))
}

unlink(TMP, recursive = TRUE, force = TRUE)
cat(sprintf("결과: PASS=%d FAIL=%d\n", pass, fail))
## ★러너 요약 계약 (v10 2026-09-03) — 없으면 run_all_hooks.sh 가 UNMEASURED 로 계상해 이 스위트의 단언이 총계에 0 으로 들어간다.
cat(sprintf('{"test":"reinforce_ledger","pass":%d,"fail":%d,"total":%d,"skipped":0}\n', pass, fail, pass + fail))
if (fail > 0L) quit(status = 1L)
