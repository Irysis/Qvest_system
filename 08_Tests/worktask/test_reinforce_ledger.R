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

# ① root_papers 거부
e <- rf_open_entry(1L, "RP_T1", "C", root = R)
r1 <- tryCatch({ rf_append_attempt(1L, "RP_T1", "아이디어", "weighting", list(), root = R); "no_stop" },
               error = function(e) conditionMessage(e))
if (grepl("논문 근거", r1)) ok("① root_papers 없는 attempt 거부") else ng(sprintf("① 거부 실패: %s", r1))
r1b <- tryCatch({ rf_append_attempt(1L, "RP_T1", "아이디어", "weighting",
                                    list(list(claim = "url 없음")), root = R); "no_stop" },
                error = function(e) conditionMessage(e))
if (grepl("논문 근거", r1b)) ok("① url 빈 root_papers 도 거부") else ng("① url 빈 항목 통과됨")

# 정상 attempt + 잘못된 축 거부
a1 <- rf_append_attempt(1L, "RP_T1", "비중방법 교체", "weighting", pp, root = R)
if (identical(a1$n, 1L)) ok("정상 attempt n=1 등록") else ng("attempt 등록 실패")
rax <- tryCatch({ rf_append_attempt(1L, "RP_T1", "x", "regime_identification", pp, root = R); "no_stop" },
                error = function(e) conditionMessage(e))
if (grepl("축이 아님", rax)) ok("L1 에 L2 축(regime_identification) 거부") else ng("축 검증 실패")

# ② 20회 상한
for (k in 2:20) invisible(rf_append_attempt(1L, "RP_T1", sprintf("시도 %d", k), "multifactor", pp, root = R))
r2 <- tryCatch({ rf_append_attempt(1L, "RP_T1", "21번째", "multifactor", pp, root = R); "no_stop" },
               error = function(e) conditionMessage(e))
obj <- rf_load(1L, root = R)
st <- obj$entries[[1]]$status
if (grepl("소진", r2) && identical(st, "exhausted")) ok("② 21번째 시도 stop + exhausted 전이") else
  ng(sprintf("② 상한 미작동: msg=%s status=%s", substr(r2, 1, 40), st))

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

unlink(TMP, recursive = TRUE, force = TRUE)
cat(sprintf("결과: PASS=%d FAIL=%d\n", pass, fail))
if (fail > 0L) quit(status = 1L)
