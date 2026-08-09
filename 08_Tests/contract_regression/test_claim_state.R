## test_claim_state.R — 위반 주입 테스트
## ★검사기가 진짜 위반을 잡는지 확인. 특히 **2026-08-09 실사고 재현**:
##   owner="완료 — Q-Lead session cee0bdd0" 에 "CLAIMED" 가 없어 구판 가드가 통과시킨 케이스.
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
source("02_Infrastructure/ops/claim_state.R")
PASS <- 0L; FAIL <- 0L
chk <- function(l, cond, d = "") { if (isTRUE(cond)) { PASS <<- PASS+1L; cat(sprintf("  [PASS] %s\n", l)) }
  else { FAIL <<- FAIL+1L; cat(sprintf("  [FAIL] %s  %s\n", l, d)) } }
can <- function(e) isTRUE(claim_state(e)$safe_to_start)

cat("=== 1. 선언 필드 — 정본 경로 ===\n")
chk("unclaimed -> 착수 가능", can(list(id="X", claim=list(state="unclaimed"))))
chk("claimed -> 차단",      !can(list(id="X", claim=list(state="claimed", session="s1"))))
chk("complete -> 차단",     !can(list(id="X", claim=list(state="complete"))))
chk("blocked -> 차단",      !can(list(id="X", claim=list(state="blocked"))))
chk("dohoon -> 차단",       !can(list(id="X", claim=list(state="dohoon"))))
chk("source=declared 표기", claim_state(list(claim=list(state="unclaimed")))$source == "declared")

cat("=== 2. ★위반 주입 — 2026-08-09 실사고 재현 (구판이 놓친 케이스) ===\n")
fq165 <- list(id="FQ-165", status="measured_config_scoped_negative",
              owner="완료 — Q-Lead session cee0bdd0 (2026-08-09)")
old_guard <- grepl("CLAIMED", fq165$owner) && !grepl("UNCLAIMED", fq165$owner)
chk("구판 가드는 이 케이스를 **놓친다**(사고 재현)", old_guard == FALSE,
    "구판이 안 놓쳤다면 실사고 재현이 틀린 것")
chk("★신판은 차단한다", !can(fq165), paste("state =", claim_state(fq165)$state))
chk("추론 표기가 붙는다", grepl("inferred", claim_state(fq165)$source))

cat("=== 3. ★위반 주입 — 다른 자유 문자열 완료 표기 ===\n")
for (o in c("COMPLETE — session abc", "done 2026-08-09", "resolved_pending_dohoon_decision",
            "Q-Lead session 2026-08-09 (수행)", "in_flight_20260809")) {
  e <- list(id="Y", owner=o, status="")
  chk(sprintf("owner='%s' -> 차단", substr(o,1,34)), !can(e), paste("state =", claim_state(e)$state))
}

cat("=== 4. 양성 대조 — 진짜 미배정은 통과해야 한다 ===\n")
chk("UNCLAIMED 문자열 -> 통과", can(list(id="Z", owner="UNCLAIMED — FQ-182 가 발행", status="frontier_open")))
chk("미배정 문자열 -> 통과",   can(list(id="Z", owner="미배정 (WT-005 NP-2)", status="frontier_open")))

cat("=== 5. ★알 수 없는 상태는 **안전측으로 차단** ===\n")
chk("빈 owner -> 차단(unknown)", !can(list(id="W", owner="", status="")))
chk("정체불명 문자열 -> 차단",  !can(list(id="W", owner="아무말", status="아무값")))

cat("=== 6. assert_can_start 는 예외를 던진다 ===\n")
er <- tryCatch({ assert_can_start(fq165, "FQ-165"); "no-error" }, error = function(e) "error")
chk("차단 대상에 stop() 발생", er == "error")
ok <- tryCatch({ assert_can_start(list(id="Z", claim=list(state="unclaimed")), "Z"); "ok" }, error=function(e) "error")
chk("통과 대상은 예외 없음", ok == "ok")

cat("=== 7. make_claim 왕복 ===\n")
e2 <- make_claim(list(id="A"), "claimed", "sess-1", "테스트 착수")
chk("make_claim 후 claimed", claim_state(e2)$state == "claimed")
chk("owner 사람용 메모 갱신", grepl("CLAIMED", e2$owner))
chk("잘못된 state 는 거부", tryCatch({ make_claim(list(id="A"), "bogus", "s"); FALSE },
                                     error = function(e) TRUE))

cat(sprintf("\n=== 결과: PASS %d · FAIL %d ===\n", PASS, FAIL))
if (FAIL > 0) quit(status = 1)
