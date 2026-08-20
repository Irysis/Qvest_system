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

cat("=== 4b. ★거울상 결함 재현 — 초판이 만든 false positive (FQ-164 실사고) ===\n")
## 초판은 bare `도훈` 패턴 때문에 UNCLAIMED 항목을 'dohoon' 으로 오분류해 **착수를 막았다**.
## ★양성 대조가 너무 쉬웠던 것이 원인 — "도훈" 이 안 들어간 문자열만 시험했다.
fq164 <- list(id="FQ-164", status="frontier_open",
  owner=paste0("UNCLAIMED — WT-D20260809_001 이 발행한 next_probe. 착수 세션은 이 필드를 ",
               "'CLAIMED <session> <ts>' 로 먼저 갱신하고 시작할 것(세션 간 중복 착수 방지, 도훈 지시 2026-08-09)."))
chk("★UNCLAIMED ∧ '도훈 지시' 부수언급 -> **통과**해야 한다", can(fq164),
    paste("state =", claim_state(fq164)$state))
chk("  (분류가 unclaimed 인가)", claim_state(fq164)$state == "unclaimed")
## 출처 표기로서의 도훈 언급 여러 형태
for (o in c("미배정 (도훈 mandate 2026-06-05 파생)",
            "UNCLAIMED — 도훈 confirm 으로 신설된 축",
            "미배정 — 도훈 지시 2026-07-13 소비면 전개")) {
  e <- list(id="Z2", owner=o, status="frontier_open")
  chk(sprintf("출처표기 도훈 '%s' -> 통과", substr(o,1,30)), can(e), paste("state =", claim_state(e)$state))
}
## 반대로 진짜 도훈 결정 대기는 여전히 차단
for (o in c("dohoon_decision", "도훈 결정 대기 — 자본 게이트", "dohoon_confirm 대기")) {
  e <- list(id="Z3", owner="", status=o)
  chk(sprintf("진짜 도훈대기 '%s' -> 차단", substr(o,1,24)), !can(e), paste("state =", claim_state(e)$state))
}

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

cat("=== 8. ★재진입 — 내 claim 은 통과, 남의 claim 은 차단 (2026-08-09 실전 적발) ===\n")
mine <- list(id="R1", claim=list(state="claimed", session="Q-Lead 2026-08-09", note="측정 중"))
r <- tryCatch({ assert_can_start(mine, "R1", my_session="Q-Lead 2026-08-09"); "ok" }, error=function(e) "error")
chk("내 세션 재진입 -> 통과", r == "ok")
r2 <- tryCatch({ assert_can_start(mine, "R1", my_session="other-session"); "ok" }, error=function(e) "error")
chk("남의 claim -> 차단", r2 == "error")
r3 <- tryCatch({ assert_can_start(mine, "R1"); "ok" }, error=function(e) "error")
chk("my_session 미지정 -> 차단(보수)", r3 == "error")
done <- list(id="R2", claim=list(state="complete", session="Q-Lead 2026-08-09"))
r4 <- tryCatch({ assert_can_start(done, "R2", my_session="Q-Lead 2026-08-09"); "ok" }, error=function(e) "error")
chk("★complete 는 내 것이어도 차단(재착수 금지)", r4 == "error")
doh <- list(id="R3", claim=list(state="dohoon", session="Q-Lead 2026-08-09"))
r5 <- tryCatch({ assert_can_start(doh, "R3", my_session="Q-Lead 2026-08-09"); "ok" }, error=function(e) "error")
chk("★dohoon 은 내 것이어도 차단", r5 == "error")
cat("=== 9. ★상태 충돌 검출 (FQ-139 census 적발) ===\n")
conf <- list(id="FQ-139", owner="미배정", status="done")
chk("owner=미배정 ∧ status=done -> 차단", !can(conf), paste("state =", claim_state(conf)$state))
chk("  충돌 플래그 표시", isTRUE(claim_state(conf)$conflict))
chk("  사유가 note 에 실림", grepl("상태 충돌", claim_state(conf)$note))
conf2 <- list(id="X", owner="UNCLAIMED — 발행", status="measured_config_scoped_negative")
chk("UNCLAIMED ∧ negative status -> 차단", !can(conf2))
## 충돌 아닌 정상 케이스는 여전히 통과
chk("미배정 ∧ frontier_open -> 통과", can(list(id="Y", owner="미배정 (NP-2)", status="frontier_open")))
chk("UNCLAIMED ∧ 빈 status -> 통과", can(list(id="Y", owner="UNCLAIMED — 발행", status="")))
cat(sprintf("\n=== 최종: PASS %d · FAIL %d ===\n", PASS, FAIL))
# 2026-08-20: 배터리는 마지막 줄의 JSON 요약만 읽는다. 이 줄이 없어 이 파일은
#   등재조차 되지 못했다(측정 권위 계약이 회귀 보호 밖에 있었음).
cat(sprintf("{\"test\":\"test_claim_state\",\"pass\":%d,\"fail\":%d,\"total\":%d}
", PASS, FAIL, PASS + FAIL))
if (FAIL > 0) quit(status = 1)
