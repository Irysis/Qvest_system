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
LANES <- c("rf_fidelity_audit.sh", "rf_b1_design.sh", "rf_replication_auto.sh", "rf_overlay_propose.sh")
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
