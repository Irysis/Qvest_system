#!/usr/bin/env Rscript
#==============================================================================
# test_rf_fidelity_audit.R — 적대적 충실도 감사 (2026-09-04)
#
# 배경: 검증 4관문은 전부 산출물(계약·고정축·PIT·원장)을 본다. "논문대로 구현했는가" 만
#   재도출이 없었고 FIDELITY.json 은 에이전트의 진술이었다 — 2608.23944 는 하지도 않은
#   변경을 스스로 신고했고 원문 대조로만 잡혔다.
#   ★값어치는 A등급 보호가 아니라 **F 판정의 신뢰**다: F 면 ledger_consumed 로 논문이
#   영구 소비되므로, 구현이 틀려서 F 였다면 논문이 잘못된 이유로 버려진다.
#   ⇒ 그래서 이 검사에서 가장 중요한 항목은 **감사가 소비보다 앞에 서는가**(C절)다.
#
# 양방향: 정상 판정은 통과하는가 + 근거 없는 기각·형식 위반을 실제로 잡는가.
#
# (v10.01 2026-10-13) G 절(모델 정본 — 레인이 설정에서 읽는가)의 대상 4종 중 rf_b1_design.sh · rf_overlay_propose.sh 가
#   고정 격자 강화와 함께 퇴역(코드 삭제) — 살아 있는 D12 레인 2종(cleaner_distill_run.sh · paper_atlas_run.sh)으로 바꿔
#   "네 레인" 을 유지했다(paper_router 등 나머지 해석기 배선은 08_Tests/ops/test_llm_lane_wiring.sh C 절이 잰다).
#   롤백 태그 pre-v10.01-prescription-20261013
#==============================================================================
suppressMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
## ★이 검사는 위반 주입(NO_SUCH_FACTOR 등)을 하므로 운영 jlog 에 박히면 기각률 계기가 죽는다 (2026-09-04 실사고).
Sys.setenv(QVEST_RP_JLOG = file.path(tempdir(), sprintf("rf_test_jlog_%d.jsonl", Sys.getpid())))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(sprintf("  OK   %s\n", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }

LIB <- file.path(ROOT, "02_Infrastructure/ops/rf_fidelity_audit_lib.R")
suppressMessages(source(LIB, local = TRUE))
TMP <- file.path(tempdir(), sprintf("fid_audit_%d", Sys.getpid()))
dir.create(TMP, recursive = TRUE, showWarnings = FALSE)
# ★최상위 on.exit 을 쓰지 않는다 — Rscript <file> 로는 조용한 no-op 이고,
#   source() 로 부르면 withVisible 프레임이 닫히며 **즉시 발화해 TMP 를 지운다**.
#   두 호출 방식에서 정반대로 동작하는 정리 코드였다(2026-09-04 실측: 배터리는 초록,
#   source 호출은 "cannot open the connection"). R 이 세션 종료 시 tempdir 을 청소한다.
AP <- file.path(TMP, "fidelity_audit.json")
wr <- function(x) write(toJSON(x, auto_unbox = TRUE, null = "null"), AP)

cat("=== A. 스키마 — 정상 판정은 통과한다 (음성 대조) ===\n")
for (v in c("faithful", "adapted", "unverifiable")) {
  wr(list(verdict = v, note = "n"))
  if (isTRUE(rf_audit_verify(AP))) ok(sprintf("A verdict=%s 통과", v)) else ng(sprintf("A verdict=%s 기각됨", v))
}
wr(list(verdict = "misdeclared",
        undeclared_changes = list("논문 §3.1 식 (2) 는 형성기간 J=6 인데 engine.R:104 는 J=12 — FIDELITY.changed 에 없음"),
        evidence = "§3.1 식 (2) 및 Table 2"))
if (isTRUE(rf_audit_verify(AP))) ok("A 근거 있는 misdeclared 통과") else ng("A 근거 있는 misdeclared 가 기각됨")

cat("\n=== B. 위반 주입 — 형식과 근거 ===\n")
wr(list(verdict = "looks_fine", note = "n"))
if (!isTRUE(rf_audit_verify(AP))) ok("B1 허용값 아닌 verdict 기각") else ng("B1 임의 verdict 통과")
wr(list(verdict = "misdeclared", note = "느낌상 다름"))
if (!isTRUE(rf_audit_verify(AP))) ok("B2 지적 0건 misdeclared 기각(근거 없는 기각은 잡음)") else
  ng("B2 근거 없는 기각이 통과")
wr(list(verdict = "misdeclared", signal_mismatch = list("부호가 반대")))
if (!isTRUE(rf_audit_verify(AP))) ok("B3 evidence 없는 misdeclared 기각") else ng("B3 원문 근거 없이 통과")
writeLines("{not json", AP)
if (!isTRUE(rf_audit_verify(AP))) ok("B4 파손 JSON 기각") else ng("B4 파손 JSON 통과")
unlink(AP, force = TRUE)
if (identical(rf_audit_read(AP)$verdict, "unverifiable"))
  ok("B5 감사 파일 부재 = unverifiable (침묵을 통과로 읽지 않는다)") else ng("B5 부재를 통과로 읽는다")

cat("\n=== B2. 채움 항목 — 비발견을 근거로 세지 않는다 (2026-09-04 실측) ===\n")
# 실측: 감사가 signal_mismatch 배열에 "신호 불일치 없음" 을 넣었다. 근거 게이트가 **배열 길이**로
# 서 있어 그런 비발견 하나가 misdeclared 를 열어준다. 문턱은 휴리스틱이고, 아래 B7 이
# "진짜 지적은 막지 않는다" 를 같이 잰다 — 한쪽만 재면 문턱이 과하게 조여도 안 보인다.
wr(list(verdict = "misdeclared", signal_mismatch = list("신호 불일치 없음"), evidence = "§1"))
if (!isTRUE(rf_audit_verify(AP))) ok("B6 짧은 비발견 채움 항목 기각") else ng("B6 채움 항목이 게이트를 통과")
wr(list(verdict = "misdeclared",
        signal_mismatch = list("논문 정의는 loser 롱인데 engine.R:209 는 winner 를 +비중 롱으로 배정"),
        evidence = "§2 정의절"))
if (isTRUE(rf_audit_verify(AP))) ok("B7 실제 지적은 통과 — 문턱이 진짜 발견을 막지 않는다") else
  ng("B7 진짜 지적이 기각됨")

cat("\n=== B3. 실측 픽스처 — 감사자가 실제로 낸 misdeclared ===\n")
# ★손으로 쓴 payload 로만 재면 스키마가 실제 산출과 갈릴 수 있다. 2026-09-04 부호반전 프로브에서
#   감사자가 낸 **진짜 산출물**을 픽스처로 둔다(LLM 발화 실증의 사료이기도 하다).
FX <- file.path(ROOT, "08_Tests/fixtures/fidelity_audit/misdeclared_signflip_20260904.json")
if (file.exists(FX)) {
  file.copy(FX, AP, overwrite = TRUE)
  if (isTRUE(rf_audit_verify(AP))) ok("B8 실측 misdeclared 산출물이 스키마를 통과") else
    ng("B8 실제 감사 산출물이 스키마에 걸린다", "검증기가 현실과 갈렸다")
  fx <- rf_audit_read(FX)
  if (identical(fx$verdict, "misdeclared")) ok("B9 픽스처 판정 = misdeclared(부호 반전 주입 적발분)") else
    ng("B9 픽스처 판정", fx$verdict)
  if (identical(rf_audit_disposition(fx, 0L)$action, "reimplement"))
    ok("B10 실측 산출물 → 재구현 처분") else ng("B10 실측 산출물 처분")
} else cat("  SKIP 픽스처 부재\n")

cat("\n=== C. 처분 — 도훈 선택(자동 재구현 1회 + 소비 보류) ===\n")
d0 <- rf_audit_disposition(list(verdict = "faithful"), 0L)
if (identical(d0$action, "proceed")) ok("C1 faithful → 진행") else ng("C1 faithful 처분", d0$action)
if (identical(rf_audit_disposition(list(verdict = "unverifiable"), 0L)$action, "proceed"))
  ok("C2 unverifiable → 진행(멈추진 않는다 · 기록은 남는다)") else ng("C2 unverifiable 처분")
d1 <- rf_audit_disposition(list(verdict = "misdeclared",
                                undeclared_changes = list("u1"), signal_mismatch = list("s1"),
                                evidence = "§2"), 0L)
if (identical(d1$action, "reimplement")) ok("C3 misdeclared 초회 → 재구현") else ng("C3 초회 처분", d1$action)
if (grepl("미신고 변경", d1$feedback, fixed = TRUE) && grepl("신호 불일치", d1$feedback, fixed = TRUE))
  ok("C4 지적사항이 재구현 프롬프트로 전달된다(되풀이 차단)") else ng("C4 피드백 조립")
d2 <- rf_audit_disposition(list(verdict = "misdeclared", undeclared_changes = list("u1"), evidence = "§2"), 1L)
if (identical(d2$action, "proceed_suspect"))
  ok("C5 재구현도 기각 → 소비하되 꼬리표(무한 재시도 아님)") else ng("C5 2회차 처분", d2$action)

cat("\n=== C2. 감사 상충 — 재감사가 앞 회차 지적을 번복하면 구현자 몫이 아니다 (2026-10-14 · 1810.08384 실측) ===\n")
# 실측: 1차 감사의 신호 축이 §I 채택 문장을 근거에 싣고도 반대 결론을 냈고, 재구현이 그 지적을 따랐고, 2차 감사가 그 수정을
#   다시 지적했다. 구판 처분은 2회차 misdeclared 를 그대로 proceed_suspect(소비 + 꼬리표)로 냈다 — 감사의 오독이 구현자 몫이 됐다.
.mk <- function(pr) list(verdict = "misdeclared", undeclared_changes = list("u1"), evidence = "§I", prior_review = pr)
.pr <- function(st, ev) list(list(item = "[모멘텀 식 — 일별 평균]", status = st, evidence = ev))
d3 <- rf_audit_disposition(.mk(.pr("overturned", "§I 'we will stick to the classical academic definition'")), 1L)
if (identical(d3$action, "audit_conflict") && identical(as.integer(d3$n_overturned), 1L))
  ok("C6 재감사 번복(근거 있음) → audit_conflict(소비 보류 · 세션 판정) ★양성") else ng("C6 번복 처분", d3$action)
d4 <- rf_audit_disposition(.mk(.pr("overturned", "  ")), 1L)
if (identical(d4$action, "proceed_suspect")) ok("C7 근거 없는 번복은 세지 않는다 → 구판 처분(suspect)") else ng("C7 근거 없는 번복", d4$action)
d5 <- rf_audit_disposition(.mk(.pr("confirmed", "§V")), 1L)
if (identical(d5$action, "proceed_suspect")) ok("C8 앞 회차 지적 확인(confirmed) → 구현자 몫(suspect) 그대로 ★음성") else ng("C8 확인 처분", d5$action)
d6 <- rf_audit_disposition(.mk(.pr("overturned", "§I")), 0L)
if (identical(d6$action, "reimplement")) ok("C9 초회 감사는 번복 칸이 있어도 재구현(상충은 재감사에서만)") else ng("C9 초회 처분", d6$action)
d7 <- rf_audit_disposition(list(verdict = "adapted", prior_review = .pr("overturned", "§I")), 1L)
if (identical(d7$action, "audit_conflict")) ok("C10 adapted + 근거 있는 번복(재감사) → audit_conflict — 틀린 지적을 따르고 신고한 엔진도 꼬리표 없이 소비되지 않는다(리뷰 C7)") else
  ng("C10 adapted 번복 처분", d7$action)
d7b <- rf_audit_disposition(list(verdict = "faithful", prior_review = .pr("overturned", "§I")), 1L)
if (identical(d7b$action, "proceed")) ok("C10b faithful + 번복 → 진행(지금 엔진이 논문과 같다 · 기록만) ★음성") else ng("C10b faithful 번복 처분", d7b$action)
d7c <- rf_audit_disposition(list(verdict = "misdeclared", undeclared_changes = list("u1"), evidence = "§I",
                                 prior_review = list(list(item = "[x]", status = "overturned", evidence = "§I", admissible = FALSE))), 1L)
if (identical(d7c$action, "proceed_suspect")) ok("C10c 병합기가 불채택(admissible=FALSE)으로 표시한 번복은 세지 않는다(리뷰 U8)") else ng("C10c 불채택 번복", d7c$action)
wr(c(.mk(.pr("OVERTURNED ", "§I")), list(note = "n")))   # 파일 왕복 — rf_audit_read 가 prior_review 를 버리면 처분이 번복을 못 본다
d8 <- rf_audit_disposition(rf_audit_read(AP), 1L)
if (identical(d8$action, "audit_conflict")) ok("C11 파일 왕복 — rf_audit_read 가 prior_review 를 싣고 대소문자·공백을 접는다") else
  ng("C11 파일 왕복", d8$action)
## 세션 판정(ruling) — 상충 뒤 세션이 정한 처분은 감사를 다시 사지 않고 관문 한 자리에서 적용된다
.ns <- 0L; .sp <- function() { .ns <<- .ns + 1L; 0L }
GW <- file.path(TMP, "gate_w"); dir.create(GW, showWarnings = FALSE)
writeLines("## 판정 대상 엔진(픽스처)\nFACTORS <- NULL", file.path(GW, "engine.R"))
EMD5 <- unname(tools::md5sum(file.path(GW, "engine.R")))
.wa <- function() write(toJSON(.mk(.pr("overturned", "§I")), auto_unbox = TRUE, null = "null"), file.path(GW, "fidelity_audit.json"))
.wa()
## 판정은 엔진에 묶인다(리뷰 C1) — 지문이 다르거나 감사 파일이 깨졌거나 형식이 틀리면 적용하지 않는다
.ns <- 0L
g0 <- rf_audit_gate(GW, .sp, max_retries = 0L, retries_done = 1L, ruling = list(action = "proceed_suspect", engine_md5 = "deadbeef"))
if (.ns == 1L && !isTRUE(g0$disp$ruled)) ok("C15 엔진 지문 불일치(판정 뒤 엔진이 바뀌었다) → 판정 미적용 · 감사를 다시 산다 ★양성") else
  ng("C15 지문 불일치 판정", sprintf("spawns=%d ruled=%s", .ns, isTRUE(g0$disp$ruled)))
.wa(); .ns <- 0L
g0b <- rf_audit_gate(GW, .sp, max_retries = 0L, retries_done = 1L, ruling = list(action = "proceed_suspect"))
if (.ns == 1L && !isTRUE(g0b$disp$ruled)) ok("C16 엔진 지문 없는 판정 → 미적용") else ng("C16 지문 없는 판정", sprintf("spawns=%d", .ns))
writeLines("{not json", file.path(GW, "fidelity_audit.json")); .ns <- 0L
g0c <- rf_audit_gate(GW, .sp, max_retries = 0L, retries_done = 1L, ruling = list(action = "proceed_suspect", engine_md5 = EMD5))
if (.ns == 1L && !isTRUE(g0c$disp$ruled)) ok("C17 감사 파일 파손 → 지문이 맞아도 판정 미적용(감사를 다시 산다)") else ng("C17 파손 감사 판정", sprintf("spawns=%d", .ns))
.wa(); .ns <- 0L; .lg <- character(0)
g0d <- rf_audit_gate(GW, .sp, max_retries = 0L, retries_done = 1L, ruling = "proceed", log_fn = function(ev, ...) .lg <<- c(.lg, ev))
if (.ns == 1L && "fidelity_audit_ruling_ignored" %in% .lg) ok("C18 객체가 아닌 판정 → 무시 기록을 남기고 정상 관문") else ng("C18 형식 위반 판정", paste(.lg, collapse = ","))
.wa(); .ns <- 0L
g1 <- rf_audit_gate(GW, .sp, retries_done = 1L, ruling = list(action = "proceed_suspect", by = "session", decision = "T-1", engine_md5 = EMD5))
if (identical(g1$disp$action, "proceed_suspect") && .ns == 0L && file.exists(file.path(GW, "fidelity_audit.json")) && isTRUE(g1$disp$ruled))
  ok("C12 판정(proceed_suspect) + 같은 엔진 지문 + 남은 감사 파일 → 재스폰 0 · 판정 처분") else ng("C12 판정 적용", sprintf("%s spawns=%d", g1$disp$action, .ns))
.ns <- 0L
g2 <- rf_audit_gate(GW, .sp, max_retries = 0L, retries_done = 1L, ruling = list(action = "reimplement"))
if (.ns == 1L) ok("C13 허용 밖 판정(reimplement)은 적용하지 않고 정상 관문(스폰 1) ★음성") else ng("C13 허용 밖 판정", sprintf("spawns=%d", .ns))
.ns <- 0L   # 직전 관문이 감사 파일을 지웠다(스폰 전 삭제 규약) — 파일 없는 판정은 감사 없이 개설로 가지 않는다
g3 <- rf_audit_gate(GW, .sp, max_retries = 0L, retries_done = 1L, ruling = list(action = "proceed", engine_md5 = EMD5))
if (.ns == 1L && identical(g3$disp$action, "audit_required"))
  ok("C14 감사 파일 없는 판정은 적용하지 않는다 → 정상 관문 · 미실행이면 audit_required(감사 없이 개설 불가 유지)") else
  ng("C14 파일 없는 판정", sprintf("%s spawns=%d", g3$disp$action, .ns))

cat("\n=== D. 조립 순서 — 감사가 **소비보다 앞**에 서는가 (이 검사의 핵심) ===\n")
vf <- readLines(file.path(ROOT, "02_Infrastructure/ops/rf_replication_verify.R"), warn = FALSE)
code <- sub("#.*$", "", vf)
## ★감사 호출 지점 = rf_audit_gate (2026-09-06 이설 — 스폰·읽기·처분·미실행 재스폰이 lib 함수 하나로 옮겨졌다).
##   구판의 직접 호출(rf_audit_disposition)도 인정한다 — 이름이 아니라 "감사가 소비 앞에 서는가" 를 잰다.
i_aud <- which(grepl("rf_audit_gate(", code, fixed = TRUE) | grepl("rf_audit_disposition(", code, fixed = TRUE))[1]
i_con <- which(grepl("ledger_consumed", code, fixed = TRUE))[1]
i_opn <- which(grepl("rf_open_entry(1L, BID", code, fixed = TRUE))[1]
if (!is.na(i_aud) && !is.na(i_con) && i_aud < i_con)
  ok(sprintf("D1 감사(%d행)가 ledger_consumed(%d행) 앞 — 잘못 구현된 논문이 소비되지 않는다", i_aud, i_con)) else
  ng("D1 감사가 소비 뒤에 있다", sprintf("aud=%s con=%s", i_aud, i_con))
if (!is.na(i_aud) && !is.na(i_opn) && i_aud < i_opn)
  ok("D2 감사가 entry 개설 앞") else ng("D2 감사가 개설 뒤")
if (any(grepl('identical(.disp$action, "reimplement")', code, fixed = TRUE)) &&
    any(grepl("quit(status = 0)", code, fixed = TRUE)))
  ok("D3 재구현이면 조기 종료 — 원장에 아무것도 열지 않는다") else ng("D3 조기 종료 배선")
## 감사 상충 분기(2026-10-14) — 소비 앞 · 분기 안에 소비/재료 등록이 없고 · 보류 표식 + 다음 논문으로 간다
i_cf <- which(grepl('if (identical(.disp$action, "audit_conflict"))', code, fixed = TRUE))[1]   # 분기 머리(번복 기록 줄의 !identical 과 구분)
if (!is.na(i_cf) && !is.na(i_con) && i_cf < i_con) {
  q_cf <- which(grepl("quit(status = 0)", code, fixed = TRUE) & seq_along(code) > i_cf)[1]
  seg <- paste(code[i_cf:q_cf], collapse = "\n")
  if (!grepl("ledger_consumed|v1001_handoff|pr_enqueue|rmm_register|qmirror", seg))
    ok(sprintf("D4 감사 상충 분기(%d행)가 소비 앞이고 분기 안에 소비·재료 등록이 없다", i_cf)) else
    ng("D4 감사 상충 분기가 소비·재료 등록을 부른다")
  if (grepl("held_audit_conflict", seg, fixed = TRUE) && grepl("next_replication.R", seg, fixed = TRUE))
    ok("D5 상충 = 이 논문만 보류(스킵리스트 held_audit_conflict) + 레인은 다음 논문(사람 대기 종점 없음)") else
    ng("D5 보류 표식 또는 다음 논문 발행 누락")
} else ng("D4 감사 상충 분기가 없거나 소비 뒤", sprintf("cf=%s con=%s", i_cf, i_con))
## D7 — 분기 코드를 샌드박스에서 **실행**한다(정적 검사는 분기가 도는지를 못 잰다). 운영 스킵리스트·요청·텔레그램·다음 논문 발행은 전부 대역.
if (!is.na(i_cf)) {
  q_cf <- which(grepl("quit(status = 0)", code, fixed = TRUE) & seq_along(code) > i_cf)[1]
  SB <- file.path(TMP, "cf_sandbox"); dir.create(file.path(SB, "06_Registry"), recursive = TRUE, showWarnings = FALSE)   # 역슬래시 섞인 경로 그대로(분기가 견뎌야 한다)
  dir.create(file.path(SB, "w"), showWarnings = FALSE); dir.create(file.path(SB, "art"), showWarnings = FALSE)
  writeLines('{"schema":"replication_skiplist_v1","entries":[{"paper_key":"9999.00001","status":"revoked"}]}', file.path(SB, "06_Registry/replication_skiplist.json"))
  writeLines('{"status":"in_progress","paper":{"paper_key":"9999.00001"},"audit_ruling":{"action":"proceed","engine_md5":"old"}}', file.path(SB, "06_Registry/replication_request.json"))
  writeLines("## 상충 판정 대상 엔진(픽스처)\nFACTORS <- NULL", file.path(SB, "w/engine.R"))
  ev <- new.env(parent = globalenv()); sent <- list(); called <- character(0)
  ev$ROOT <- SB; ev$REQ <- file.path(SB, "06_Registry/replication_request.json"); ev$WDIR <- file.path(SB, "w")
  ev$eng <- file.path(SB, "w/engine.R"); ev$.CLEAN <- TRUE; ev$.rq0 <- list(lane_mode = "clean")
  ev$PKEY <- "9999.00001"; ev$URL <- "https://arxiv.org/abs/9999.00001"; ev$TITLE <- "샌드박스 논문"
  ev$G <- NA_character_; ev$.aud_p <- file.path(SB, "w/fidelity_audit.json")   # 감사 = 측정 앞(10-17) — 등급 · 산출물 경로(ar) 없음
  i_gx <- which(startsWith(vf, ".v1001_gtxt <- function("))[1]              # 보고 문구 도우미 = 운영 정의 그대로
  if (!is.na(i_gx)) eval(parse(text = vf[i_gx]), envir = ev)
  ev$.aud_tries <- 1L; ev$.prior_fb <- "- 신호 불일치: [signal] [모멘텀 식 — 일별 평균] …"
  ev$.disp <- list(action = "audit_conflict", feedback = "- 미신고 변경: [signal] [12-1 누적 아님] …", n_overturned = 1L)
  ev$.aud <- list(verdict = "misdeclared", prior_review = list(
    list(item = "[모멘텀 식 — 일별 평균]", status = "overturned", evidence = "§I 'we will stick to the classical academic definition'"),
    list(item = "[근거 없음]", status = "overturned", evidence = "")))
  ev$jlog <- function(event, ...) called <<- c(called, event)
  ev$.v1001_report <- function(...) { sent[[length(sent) + 1L]] <<- list(...); invisible(TRUE) }
  ev$.tg_target_label <- function(t, k) t
  ev$.tg_clip <- function(x, cap) substr(as.character(x), 1L, cap)
  ev$system2 <- function(cmd, args, ...) { called <<- c(called, paste("system2", paste(args, collapse = " "))); 0L }
  ev$quit <- function(...) stop(structure(class = c("quit_called", "condition"), list(message = "quit", call = NULL)))
  quitted <- tryCatch({ eval(parse(text = vf[i_cf:(q_cf + 1L)]), envir = ev); FALSE },
                      quit_called = function(e) TRUE, error = function(e) { cat("    eval 오류:", conditionMessage(e), "\n"); NA })
  sk  <- fromJSON(file.path(SB, "06_Registry/replication_skiplist.json"), simplifyVector = FALSE)
  rq  <- fromJSON(file.path(SB, "06_Registry/replication_request.json"), simplifyVector = FALSE)
  cfj <- file.path(SB, "w/audit_conflict.json")
  held <- Filter(function(e) identical(e$status, "held_audit_conflict"), sk$entries)
  if (isTRUE(quitted) && length(held) == 1L && identical(rq$status, "held_audit_conflict") && file.exists(cfj) &&
      identical(fromJSON(cfj, simplifyVector = FALSE)$n_overturned, 1L) && length(sent) == 1L && isTRUE(sent[[1]]$push) &&
      any(grepl("next_replication.R", called, fixed = TRUE)) && "fidelity_audit_conflict" %in% called)
    ok("D7 분기 실행 — 보류 1건(revoked 옛 항목 옆) · 요청 held · audit_conflict.json(근거 있는 번복 1) · 푸시 1통 · 다음 논문 발행") else
    ng("D7 분기 실행", sprintf("quit=%s held=%d req=%s cf=%s sent=%d calls=%s", quitted, length(held), rq$status %||% "?",
                             file.exists(cfj), length(sent), paste(called, collapse = ",")))
  if (length(sent) >= 1L && grepl("측정 전", as.character(sent[[1]]$status$previous %||% ""), fixed = TRUE))
    ok("D7c 보고의 직전 판정 = '측정 전 감사' — 감사가 측정 앞이라 등급이 없다(10-17)") else
    ng("D7c 직전 판정 문구", if (length(sent)) as.character(sent[[1]]$status$previous %||% "-") else "보고 없음")
  ## 리뷰 C1 · C2 · U6 — 판정 재료에 엔진 지문 · 레인 모드가 실리고, 청정 작업 디렉터리 파일에 등급 · 산출물 경로가 없고, 앞 판정은 지워진다
  cfo <- if (file.exists(cfj)) fromJSON(cfj, simplifyVector = FALSE) else list()
  if (identical(cfo$engine_md5, unname(tools::md5sum(file.path(SB, "w/engine.R")))) && identical(cfo$lane_mode, "clean") &&
      is.null(cfo$grade) && is.null(cfo$artifacts) && is.null(rq$audit_ruling))
    ok("D7b audit_conflict.json = 엔진 지문 · lane_mode 실음 · 등급 · 산출물 경로 없음(청정 디렉터리) · 요청의 앞 판정 제거") else
    ng("D7b 판정 재료", sprintf("md5=%s lm=%s grade=%s ruling=%s", cfo$engine_md5 %||% "-", cfo$lane_mode %||% "-",
                               !is.null(cfo$grade), !is.null(rq$audit_ruling)))
  ## D8 — 보류 기록(스킵리스트)이 실패하면 다음 논문으로 넘어가지 않는다(fail-closed · 리뷰 U5) — 스킵리스트 자리에 디렉터리를 둔다
  unlink(file.path(SB, "06_Registry/replication_skiplist.json")); dir.create(file.path(SB, "06_Registry/replication_skiplist.json"))
  writeLines('{"status":"in_progress","paper":{"paper_key":"9999.00001"}}', file.path(SB, "06_Registry/replication_request.json"))
  sent <- list(); called <- character(0)
  q8 <- tryCatch({ eval(parse(text = vf[i_cf:(q_cf + 1L)]), envir = ev); FALSE }, quit_called = function(e) TRUE,
                 error = function(e) { cat("    eval 오류:", conditionMessage(e), "\n"); NA })
  if (isTRUE(q8) && "audit_conflict_skiplist_failed" %in% called && !any(grepl("next_replication.R", called, fixed = TRUE)) &&
      length(sent) == 1L && grepl("멈춘다", as.character(sent[[1]]$next_step %||% ""), fixed = TRUE))
    ok("D8 보류 기록 실패 → 다음 논문 발행 안 함 · 보고가 멈춤을 알린다(같은 논문 즉시 재발행 방지) ★양성") else
    ng("D8 보류 실패 처리", paste(called, collapse = ","))
}
i_pw <- which(grepl(".prior_audit_findings.md", code, fixed = TRUE))[1]
i_gt <- which(grepl("rf_audit_gate(", code, fixed = TRUE))[1]
if (!is.na(i_pw) && !is.na(i_gt) && i_pw < i_gt) ok("D6 앞 회차 지적 파일을 감사 관문 앞에서 쓴다(재감사가 확인/번복할 대상)") else
  ng("D6 앞 회차 지적 전달 배선", sprintf("pw=%s gate=%s", i_pw, i_gt))
## D9 — 감사가 **측정 앞**(2026-10-17 도훈 '실행 전에 오류를 잡아낼 순 없나'): 기각(재구현 · 상충 · 미실행)은 측정 자원을 쓰지 않는다
.order_ok <- function(lines) {
  cd <- sub("#.*$", "", lines)
  at <- function(s) which(grepl(s, cd, fixed = TRUE))[1]
  ix <- c(pre = at("detect_lookahead(eng"), gate = at("rf_audit_gate("), pkg = at(".deps <- .extract_pkgs(eng)"),
          run = at("do.call(run_paper_replication"))
  all(!is.na(ix)) && !is.unsorted(ix, strictly = TRUE)
}
if (.order_ok(vf)) ok("D9 순서 = PIT 사전 점검 → 충실도 감사 → 패키지 설치 → 측정(러너) — 기각은 측정 없이 끝난다") else
  ng("D9 감사가 측정 앞에 있지 않다")
## 양성 대조 — 감사 관문 줄을 러너 호출 뒤로 옮긴 사본(소스 텍스트 이동)을 D9 가 잡는가
i_g9 <- which(grepl("rf_audit_gate(", code, fixed = TRUE))[1]
i_r9 <- which(grepl("do.call(run_paper_replication", code, fixed = TRUE))[1]
if (!is.na(i_g9) && !is.na(i_r9) && i_g9 < i_r9) {
  mut9 <- append(vf[-i_g9], vf[i_g9], after = i_r9 - 1L)   # 관문 줄을 빼면 러너 줄이 한 줄 당겨진다 → 그 바로 뒤에 넣는다
  if (!identical(mut9, vf) && !.order_ok(mut9)) ok("D9b 양성 대조 — 감사를 측정 뒤로 옮긴 사본은 D9 가 빨개진다(검출력)") else
    ng("D9b 양성 대조 실패 — 순서 검사가 뒤바뀐 사본을 통과시킨다")
} else ng("D9b 양성 대조 준비 실패", sprintf("gate=%s run=%s", i_g9, i_r9))

cat("\n=== E. 배선 (주석 제외) ===\n")
code_of <- function(f) paste(sub("#.*$", "", readLines(file.path(ROOT, f), warn = FALSE)), collapse = "\n")
au <- code_of("02_Infrastructure/ops/rf_replication_auto.sh")
sh <- paste(readLines(file.path(ROOT, "02_Infrastructure/ops/rf_fidelity_audit.sh"), warn = FALSE), collapse = "\n")
if (grepl("audit_feedback", au, fixed = TRUE)) ok("E1 재구현 시 지적사항을 프롬프트에 얹는다") else ng("E1 피드백 미전달")
if (grepl("engine.rejected", code_of("02_Infrastructure/ops/rf_replication_verify.R"), fixed = TRUE))
  ok("E2 기각된 엔진을 남긴다(무엇이 틀렸는지 볼 수 있게)") else ng("E2 기각 엔진 폐기")
if (grepl("arxiv.org/html/", sh, fixed = TRUE))
  ok("E3 전문 경로(html 엔드포인트)를 프롬프트에 박는다 — /abs 는 초록뿐") else ng("E3 원문 경로 미지정")
if (grepl("반증하라", sh, fixed = TRUE)) ok("E4 임무가 반증이다(일치 확인이 아니라)") else ng("E4 적대적 프레이밍 부재")
if (grepl('"Bash,Agent,Edit"', sh, fixed = TRUE)) ok("E5 감사자는 엔진을 못 고친다(읽기 전용)") else ng("E5 권한 축소 부재")
if (grepl("fidelity_audit", code_of("06_Registry/reinforce_auto_config.json"), fixed = TRUE))
  ok("E6 kill switch 존재") else ng("E6 kill switch 부재")

cat("\n=== F. 페르소나 — 감정을 배제한 철저한 비평가 (도훈 지시 2026-09-04) ===\n")
if (grepl("감정을 배제한 철저한 비평가", sh, fixed = TRUE)) ok("F1 페르소나 선언") else ng("F1 페르소나 부재")
if (grepl("인상은 판정이 아니다", sh, fixed = TRUE))
  ok("F2 인상 금지 — 모든 진술에 원문 위치·코드 행") else ng("F2 인상 금지 조항 부재")
if (grepl("관대함은 미덕이 아니다", sh, fixed = TRUE) && grepl("가혹함도 미덕이 아니다", sh, fixed = TRUE))
  ok("F3 양쪽 편향을 다 막는다(관대·가혹)") else ng("F3 한쪽 편향만 막는다")
if (grepl("의도를 추측하지 마라", sh, fixed = TRUE))
  ok("F4 의도 추측 금지 — 코드가 하는 일과 문서가 말하는 일의 차이만") else ng("F4 의도 추측 금지 부재")
if (grepl("판정을 먼저 정하고 근거를 모으지 마라", sh, fixed = TRUE))
  ok("F5 결론 선취 금지(사후 근거 수집 차단)") else ng("F5 결론 선취 금지 부재")

cat("\n=== G. 모델 정본 — 네 레인이 설정에서 읽는가 (2026-09-04) ===\n")
# ★구판은 레인마다 `:-opus` / `:-max` 를 들고 있었고 config 의 llm 블록은 **읽는 코드가 0건**이었다.
#   정책을 적어 둔 문서를 아무도 소비하지 않는 상태 — 한 곳을 바꿔도 나머지가 그대로 남는다.
## (v10.01 2026-10-13) 퇴역 2종(rf_b1_design.sh · rf_overlay_propose.sh) → 살아 있는 D12 레인 2종(주간 증류 · 메커니즘 지도)
LANES <- c("rf_fidelity_audit.sh", "rf_replication_auto.sh", "cleaner_distill_run.sh", "paper_atlas_run.sh")
for (f in LANES) {
  b <- code_of(file.path("02_Infrastructure/ops", f))
  if (grepl("rf_llm_resolve", b, fixed = TRUE)) ok(sprintf("G %s — 설정 정본에서 읽는다", f)) else
    ng(sprintf("G %s — 정본 미소비", f))
  if (grepl(":-opus}", b, fixed = TRUE) || grepl(":-max}", b, fixed = TRUE))
    ng(sprintf("G %s — 자기 기본값 잔존(표류 경로)", f)) else
    ok(sprintf("G %s — 자기 기본값 없음", f))
}
cfgj <- tryCatch(fromJSON(file.path(ROOT, "06_Registry/reinforce_auto_config.json"), simplifyVector = FALSE),
                 error = function(e) list())
.ln <- (cfgj$llm %||% list())$lanes %||% list()
if (length(.ln) >= 4L) ok(sprintf("G 설정에 레인 %d종 명시", length(.ln))) else ng("G 레인 명시 부족")
## ★도훈 2026-09-04 레인 배분: fidelity_audit = xhigh (replication 만 max). 모델은 전역 llm.model 을 따른다
##   (fable-5-1 은 CLI 미지원으로 blocked_model 에 기록 — 이름을 검사에 박으면 전환 때 또 낡는다).
.fa <- .ln$fidelity_audit %||% list()
.gm <- as.character((cfgj$llm %||% list())$model %||% "")
if (nzchar(.gm) && identical(as.character(.fa$model %||% ""), .gm) &&
    identical(as.character(.fa$effort %||% ""), "xhigh"))
  ok(sprintf("G 감사 레인 = %s / xhigh (도훈 레인 배분 2026-09-04)", .gm)) else
  ng("G 감사 레인 모델 설정", sprintf("model=%s effort=%s (기대 %s/xhigh)", .fa$model %||% "?", .fa$effort %||% "?", .gm))

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_fidelity_audit","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
