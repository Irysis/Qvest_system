## test_round_core_v1.R — 공통 판정 코어 v1(2026-10-20 · 1계층 속도 계획 WP1) 검사
##   A 공용 도구(과반 · τ_D 가림 · 누출 검사 · 참조 해석) B 규칙 단일 출처(검사 · Kleene NA 의미 · 적격 행 · 문장 · 뮤테이션 양성 대조)
##   C 사양 검사(P1R01 '이름 없는 배열' 결함 부류를 측정 전에 잡는지) D P1R01 결과 동일 — 원래 evaluate.R 을 격리 사본(출력 경로만 치환)으로
##   다시 돌린 결과와 코어 판정 표가 바이트 동일한지(같은 입력 · 같은 계약). 저장본(10-15)과의 대조는 입력 · 계약 변화 탐지용으로 함께 본다.
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
PASS <- 0L; FAIL <- 0L
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [ok]   %s\n", name)) } else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s %s\n", name, detail)) }
}
throws <- function(expr) inherits(tryCatch({ force(expr); NULL }, error = function(e) e), "error")
source("04_Research/programs/_lib/round_core/v1/load.R")
TAU <- as.Date("2022-12-31")

cat("A 공용 도구\n")
chk("A1 과반 = 엄격 초과 · 비유한 거짓", rc_maj(0.6, 0.5) && !rc_maj(0.5, 0.5) && !rc_maj(NA, 0.5) && !rc_maj(0.9, NA))
red <- rc_redact_after_tau(list(a = "2022-12-30 · 2023-01-02", b = c("2023-01", "2022-12"), n = 3), TAU)
chk("A2 τ_D 가림 — 이후 일 · 월만 가리고 이전 · 수치 보존", identical(red$a, paste0("2022-12-30 · ", RC_REDACT)) &&
      identical(red$b, c(RC_REDACT, "2022-12")) && identical(red$n, 3))
chk("A3 누출 검사 — 가림 뒤 0 · 가림 전 탐지", !length(rc_after_tau_leaks(red, TAU)) &&
      setequal(rc_after_tau_leaks(list("2023-01-02", "2024-05"), TAU), c("2023-01-02", "2024-05")))
chk("A4 참조 해석 — 정본 설정 tier_graduation.grade_b_min_portfolio_alpha_t",
    identical(as.numeric(rc_ref_value("02_Infrastructure/worktask/constraint_defaults.json::tier_graduation.grade_b_min_portfolio_alpha_t")), 2))
chk("A5 참조 키 없음 = 멈춤", throws(rc_ref_value("02_Infrastructure/worktask/constraint_defaults.json::tier_graduation.없는_키")))
chk("A6 상대 경로", identical(rc_rel(file.path(ROOT, "06_Registry/x.json")), "06_Registry/x.json"))

cat("E 처방 입력 정보 경계 검사(rc_input_issues · 11-10(2) 감사 U11 — fail-closed · 양방향)\n")
## [E-begin] — 이 구간은 돌연변이 대조 스크립트가 그대로 떼어 다시 돌린다(수리 전 검사기로는 실패해야 한다)
## 막아야 할 문장 — 감사 시나리오 원문 + 등급 표기 어순 · τ_D 뒤 연도 표기 · 시험 창 수치
E_BLOCK <- c(
  "전기간 A등급 후보 · 2023~2025 시험 창 Calmar 0.41 · 23년 급락에서 방어",       # 감사 시나리오 원문(U11)
  "기저는 C등급에 머물렀다", "A 등급 후보로 올랐다", "Grade B 판정", "B→A 상향", "C -> B 로 올라감", "A급 전략이다", "등급: A",
  "{\"essence_grade\": \"B\"}", "A 자격 통과", "등급은 B 였다", "graded A", "A grade 전략", "B 띠에 들었다", "A 후보로 BOOK 상신",
  "Mar 2023 급락", "20230315 리밸에서", "2023H1 성과", "FY2024 실적", "2024-03 위기", "24.3Q 반등", "23H2 반등", "202403 리밸",
  "’23 하락장", "1Q24 반등", "2024년 3분기", "2023년 이후 급락", "2023~2025 구간",
  "시험 창 Calmar 0.41", "OOS Sharpe 1.2", "강건성 구간에서 CAGR 18%", "τ_D 이후 하락 포착 0.62", "시험 창 위기 3건 모두 방어", "holdout CAGR 0.15",
  "전기간 Sharpe 0.9",
  ## 11-10(3) 재수리(독립 검증 미흡 4종) — 하이픈 어순 · 한국어 서술형 이동 · 판정 · 전기간 다른 표기 · 줄바꿈 · 긴 간격 우회
  "Grade-A 전략", "grade–B 후보", "B에서 A로 올라갔다", "A로 승급", "A 로 올라섰다", "B 로 상향", "C에서 B로", "A 판정을 받았다", "최종 판정 A", "F 판정",
  "판정은 B", "전체 기간 Calmar 0.41", "전 구간 Sharpe 0.9", "전체 표본 CAGR 17%", "검증 구간 Calmar 0.41",
  "시험 창\n Calmar 0.41", "시험 창에서 위기 방어가 유지됐고 상승 포착도 기대보다 높은 0.62였다",
  "OOS 에서는\n위기 하락 포착이 보는 창보다 훨씬 낮아 0.48 수준", "| 시험 창 | 0.41 |")
## 통과해야 할 문장 — 실제 교훈 · 원장 · 설계 입력에 쓰이는 표현(τ_D 이전 연도 · 칸 · 블록 라벨 · 문턱 이름 · 규범 문장)
E_PASS <- c(
  "2015~2016 위기에서 방어가 약했다", "칸 A 와 칸 B 를 비교", "B1 블록 채택", "2008-10-24 바닥 · arXiv 2002.06975 · 2022-12",
  "등급 산식 S 는 Calmar 와 PORT_t 의 가중 기하평균", "보는 창 Calmar 0.81 · 상승 포착 0.58", "τ_D 이전 위기 하락 포착 0.71",
  "A 하한 중 PORT_t 가 병목", "RP_AUTO_2002_06975 엔진 · P1R02_1801_long_leg", "36개월 롤링 IC 로 고른다(전기간 IC 를 쓰지 않는다)",
  "dS_vis 0.12 개선 · 위기 비악화", "2022년 급락 · 2020년 3월 코로나", "1Q22 하락 · 2022Q4 반등", "시험 창 판정은 사람 쪽만 본다",
  "교훈: P2R04 방어 틸트 β 짝 0/8 — 희석", "15bps · ≤ 25종 · LIQ 2e8", "MC8 짝 대조 · CR 노치", "B 블록 → A 블록 순서",
  "12년 표본 · 10년 보유", "F-Score 팩터 · C1~C15 체크리스트", "교훈: 정적 노출 축소는 비대칭을 못 만든다",
  "교훈: tail_overlay 연속 기각 — 보는 창 위기 수 부족", "PBO 0.3 · DSR 0.97 은 진단", "생성기 gen_20260918_235445 의 기각 걸음",
  "2022년 12월까지의 위기만 본다",
  ## 11-10(3) 재수리 — 라벨 이동 · A/B 비교 · 보는 창 전 구간 · 문단이 다른 시험 창 언급(오탐 방지)
  "칸 A 로 옮겨 측정", "칸 B 에서 칸 C 로 바꿨다", "칸 B에서 A로 옮겼다", "strict-PIT A/B 판정에서 인플레 없음", "블록 A 판정 규칙은 사전등록에 고정",
  "보는 창 전체 기간 Calmar 0.81", "보는 창 전 구간 Sharpe 0.9", "τ_D 이전 구간 위기 하락 포착 0.71", "판정 대기 · dS_vis 0.04",
  "- 보는 창 Calmar 0.81\n- 시험 창 값은 싣지 않는다", "보는 창 Sharpe 0.9\n\n시험 창 판정은 사람 쪽만 본다",
  "Grade 산식 메모 · 등급 하한 점검", "B1 블록에서 B2 블록으로 옮겼다",
  RC_P4_REASONS[["not_qualified"]],                                                     # 설계 입력 기저 풀 사유 문장(실제)
  "> 보는 창(τ_D = 2022-12-31 까지)의 R 계약 산출만 싣는다. 시험 창 값 · 등급 · 그 뒤 날짜는 없다. 수치를 새로 계산하지 마라.")   # 설계 입력 머리말(실제)
e_ok <- function(s, ...) isTRUE(tryCatch(rc_input_issues(s, TAU, ...)$ok, error = function(e) NA))
eb <- vapply(E_BLOCK, function(s) !e_ok(s), logical(1)); ep <- vapply(E_PASS, function(s) e_ok(s), logical(1))
chk(sprintf("E1 막아야 할 문장 %d개 전부 거부(등급 어순 · τ_D 뒤 연도 표기 · 시험 창 수치)", length(E_BLOCK)), all(eb), paste("통과해 버린 것:", paste(E_BLOCK[!eb], collapse = " | ")))
chk(sprintf("E2 통과해야 할 문장 %d개 전부 통과(τ_D 이전 연도 · 칸 · 블록 라벨 · 실제 원장 · 설계 입력 표현)", length(E_PASS)), all(ep), paste("막힌 것:", paste(E_PASS[!ep], collapse = " | ")))
chk("E3 사례 수 — 양쪽 각 15개 이상", length(E_BLOCK) >= 15L && length(E_PASS) >= 15L)
AL <- "2023년 이후의 시장 사건 · 성과는 사전학습으로 알고 있더라도 **근거로 쓰지 마라**"
chk("E4 allow — 코드가 준 지시문 그 문장만 지운다(같은 글의 다른 τ_D 뒤 표기는 그대로 막는다)",
    e_ok(paste("- ", AL, "(처방이 시험 창에 맞춰지면 시험이 무효가 된다)."), allow = AL) && !e_ok(paste(AL, "· 2023년 급락에서 방어"), allow = AL) && !e_ok(AL))
chk("E5 τ_D 판독 불가 = 막는다(fail-closed)", !isTRUE(tryCatch(rc_input_issues("평범한 교훈", NA)$ok, error = function(e) FALSE)) &&
      !isTRUE(tryCatch(rc_input_issues("평범한 교훈", "not-a-date")$ok, error = function(e) FALSE)))
ci5 <- rc_input_issues("A등급 · 2024년 · 시험 창 Calmar 0.4", TAU)
chk("E6 사유에 세 범주(연도 · 등급 · 시험 창 수치)가 함께 실린다", grepl("연도", ci5$why) && grepl("등급 표기", ci5$why) && grepl("시험 창", ci5$why) && length(ci5$windows) >= 1L)
## [E-end]

cat("B 규칙 단일 출처\n")
thr <- function(id, metric, op, value, na = "untested", basis = "검사용 근거") list(id = id, type = "threshold", label = id, metric = metric, op = op, value = value, basis = basis, na = na)
chk("B1 수치 문턱에 근거 없음 = 거부(하드코딩 금지)", throws(rc_rules_validate(list(list(id = "x", type = "threshold", label = "x", metric = "m", op = ">=", value = 1)))))
chk("B2 이름 있는 목록 = 거부", throws(rc_rules_validate(list(a = thr("a", "m", ">=", 1)))))
chk("B3 최상위 id 중복 = 거부", throws(rc_rules_validate(list(thr("a", "m", ">=", 1), thr("a", "n", ">=", 1)))))
chk("B4 모르는 비교 = 거부", throws(rc_rules_validate(list(thr("a", "m", "=>", 1)))))
chk("B5 report 의 when 이 최상위 규칙 아님 = 거부", throws(rc_rules_validate(list(thr("a", "m", ">=", 1),
      list(id = "r", type = "report", label = "r", metric = "m", op = ">", value = 0, basis = "b", when = "zz")))))
T0 <- data.table(m = c(3, 1, NA, 2), n = c(1, 1, 1, NA))
R1 <- rc_rules_resolve(list(list(id = "q", type = "all_of", label = "q", of = list(thr("qa", "m", ">=", 2), thr("qb", "n", ">=", 1)))))
v1 <- rc_rules_apply(R1, T0)$q
chk("B6 all_of Kleene — 참 · 거짓 우선 · 미측정(NA) 보존", identical(v1, c(TRUE, FALSE, NA, NA)), paste(v1, collapse = ","))
R1f <- rc_rules_resolve(list(list(id = "q", type = "all_of", label = "q", na = "fail", of = list(thr("qa", "m", ">=", 2, "fail"), thr("qb", "n", ">=", 1, "fail")))))
v1f <- rc_rules_apply(R1f, T0)$q
chk("B7 na = fail — 미측정 = 미달(통과로 접지 않음)", identical(v1f, c(TRUE, FALSE, FALSE, FALSE)), paste(v1f, collapse = ","))
R2 <- rc_rules_resolve(list(list(id = "o", type = "any_of", label = "o", of = list(thr("oa", "m", ">=", 3), thr("ob", "n", ">", 5)))))
chk("B8 any_of Kleene — 참 우선 · 미측정 보존", identical(rc_rules_apply(R2, T0)$o, c(TRUE, FALSE, NA, NA)))
chk("B9 적격 아닌 행 = 모든 규칙 NA(미시험)", identical(rc_rules_apply(R1f, T0, eligible = c(TRUE, TRUE, FALSE, TRUE))$q, c(TRUE, FALSE, NA, FALSE)))
R3 <- rc_rules_resolve(list(thr("q", "m", ">=", 2), list(id = "h", type = "report", label = "h", metric = "n", op = ">", value = 0, basis = "b", when = "q")))
chk("B10 report — 선행 규칙 참인 칸만 · 그 밖 NA", identical(rc_rules_apply(R3, T0)$h, c(TRUE, NA, NA, NA)))
## 뮤테이션 양성 대조 — 경계값(m = 2)에서 >= 를 > 로 바꾸면 판정이 바뀌어야 검사가 경계 결함을 잡는다
Tb <- data.table(m = 2)
chk("B11 뮤테이션 ① 경계 비교(>= → >) 탐지", rc_rules_apply(rc_rules_resolve(list(thr("q", "m", ">=", 2))), Tb)$q &&
      !rc_rules_apply(rc_rules_resolve(list(thr("q", "m", ">", 2))), Tb)$q)
chk("B12 뮤테이션 ② NA 를 참으로 접는 구현이 있으면 B6 · B7 이 실패한다(미측정 칸의 판정 ≠ TRUE)", !isTRUE(v1[3]) && !isTRUE(v1f[3]))
s1 <- rc_rules_sentences(R1f)
chk("B13 문장 — 선언에서 생성 · 값 · 근거 · 미측정 의미 포함 · 결정론", grepl("m >= 2", s1[["q"]]) && grepl("미측정 = 미달", s1[["q"]]) &&
      identical(s1, rc_rules_sentences(R1f)))
chk("B14 DESIGN 표 — 하위 규칙까지 한 표", length(rc_rules_table_md(R1f)) == 2L + 3L)

cat("C 사양 검사\n")
base_spec <- list(schema = "round_spec_v1", program = "P1_RETURN", round_id = "P1R01_engine_qualification", template = "p1_qualification",
                  core_version = "v1", tau_d = "2022-12-31",
                  cells = list(list(code = "P0R01_E1_C0", engine = "E1", role = "variant", source_results = "04_Research/programs/P0_FRONTIER/P0R01_feasibility_map/results")),
                  rules = list(thr("qa", "m", ">=", 2)), selection = list(rule = "none"), exposures = list())
chk("C1 정상 사양 통과", !throws(rc_spec_validate(base_spec)))
bad <- base_spec; bad$cells <- list(E1 = bad$cells[[1]])
chk("C2 칸이 이름 있는 목록(P1R01 결함 부류) = 거부", throws(rc_spec_validate(bad)))
bad <- base_spec; bad$cells <- list(bad$cells[[1]], bad$cells[[1]])
chk("C3 칸 code 중복 = 거부", throws(rc_spec_validate(bad)))
bad <- base_spec; bad$exposures <- NULL
chk("C4 노출(exposures) 누락 = 거부(τ_D 노출 고지)", throws(rc_spec_validate(bad)))
bad <- base_spec; bad$cells[[1]]$spec <- "x.json"
chk("C5 spec · source_results 둘 다 = 거부", throws(rc_spec_validate(bad)))
bad <- base_spec; bad$round_id <- "p1r01"
chk("C6 round_id 형식 = 거부", throws(rc_spec_validate(bad)))

cat("D P1R01 결과 동일\n")
P1D <- "04_Research/programs/P1_RETURN/P1R01_engine_qualification"
pre <- jsonlite::fromJSON("stage_artifacts/programs/P1_RETURN/P1R01_engine_qualification/prereg.json", simplifyVector = FALSE)
## P1R01 사전등록을 코어 사양으로 옮긴 것(문턱 = 같은 정본 · 같은 값 — 아래에서 사전등록 값과 대조)
spec <- list(schema = "round_spec_v1", program = "P1_RETURN", round_id = "P1R01_engine_qualification", template = "p1_qualification",
             core_version = "v1", tau_d = pre$tau_d,
             cells = lapply(unlist(pre$data$cells), function(code) list(code = code, engine = sub("^P0R01_(E[0-9]+)_C0$", "\\1", code), role = "variant",
                                                                     source_results = "04_Research/programs/P0_FRONTIER/P0R01_feasibility_map/results")),
             rules = list(
               list(id = "qualify", type = "all_of", label = "수익 엔진 자격", na = "fail", of = list(
                 list(id = "q_t_alpha", type = "threshold", label = "보는 창 β-통제 t(α)", metric = "t_alpha_vis", op = ">=",
                      value_ref = "02_Infrastructure/worktask/constraint_defaults.json::tier_graduation.grade_b_min_portfolio_alpha_t", na = "fail"),
                 list(id = "q_uc", type = "threshold", label = "보는 창 상승 포착", metric = "uc_vis", op = ">=", value = 0.55,
                      basis = "P1R01 사전등록 rules.qualify.uc_floor · 투자철학 헌장 강세 참여 ≥ 55%", na = "fail"))),
               list(id = "test_hold", type = "report", label = "시험 창 유지", when = "qualify", metric = "alpha_ann_test", op = ">", value = 0,
                    basis = "P1R01 사전등록 rules.test_window(자격 엔진만 · 사람 쪽 보고)")),
             selection = list(rule = "none"), exposures = list())
chk("D1 옮긴 사양 검사 통과", !throws(rc_spec_validate(spec)))
RR <- rc_rules_resolve(spec$rules)
chk("D2 해석된 문턱 = P1R01 사전등록 값(t 2 · 상승 포착 0.55)", identical(RR[[1]]$of[[1]]$value, as.numeric(pre$rules$qualify$t_alpha_min)) &&
      identical(RR[[1]]$of[[2]]$value, as.numeric(pre$rules$qualify$uc_floor)))
core <- rc_p1_evaluate(spec, RR)
## 원래 evaluate.R 격리 사본 — 출력 경로(RD)만 치환(치환 성사 단정 · 소스 텍스트 치환 — deparse 금지)
sbx <- gsub("\\\\", "/", file.path(tempdir(), "rc_p1r01_sbx")); dir.create(sbx, recursive = TRUE, showWarnings = FALSE)
src <- readLines(file.path(P1D, "evaluate.R"), encoding = "UTF-8", warn = FALSE)
pat <- 'RD <- file.path(ROOT, "04_Research/programs/P1_RETURN/P1R01_engine_qualification")'
hit <- which(src == pat)
chk("D3 격리 사본 치환 성사(정확히 1줄)", length(hit) == 1L, paste("hits", length(hit)))
src[hit] <- sprintf('RD <- "%s"', sbx)
sf <- file.path(sbx, "evaluate_sandbox.R"); writeLines(src, sf, useBytes = TRUE)
o <- suppressWarnings(system2("Rscript", shQuote(sf), stdout = TRUE, stderr = TRUE))
ej <- file.path(sbx, "results", "evaluation.json")
chk("D4 원래 evaluate.R 격리 실행 성공", file.exists(ej), paste(tail(o, 3), collapse = " | "))
js <- function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", na = "null", digits = NA))
if (file.exists(ej)) {
  orig <- jsonlite::fromJSON(ej, simplifyVector = FALSE)
  core_tbl <- jsonlite::fromJSON(js(core$table), simplifyVector = FALSE)
  chk("D5 판정 표 바이트 동일(코어 vs 원래 코드 · 같은 입력)", identical(js(core_tbl), js(orig$table)),
      paste0("\n    core: ", substr(js(core_tbl), 1, 300), "\n    orig: ", substr(js(orig$table), 1, 300)))
  chk("D6 자격 엔진 동일", identical(sort(unlist(core$qualified)), sort(unlist(orig$qualified))),
      paste(paste(core$qualified, collapse = ","), "vs", paste(unlist(orig$qualified), collapse = ",")))
  stored <- jsonlite::fromJSON(file.path(P1D, "results", "evaluation.json"), simplifyVector = FALSE)
  same_stored <- identical(js(stored$table), js(orig$table))
  cat(sprintf("  [정보] 저장본(%s)과 오늘 원래 코드 재실행의 판정 표 %s\n", stored$evaluated_at,
              if (same_stored) "동일 — 입력 · 계약 변화 없음" else "차이 — 10-15 이후 입력(P0R01 eval.json · 산출물) 또는 계약이 바뀌었다"))
  chk("D7 자격 엔진 = 저장본(10-15) 자격 엔진", identical(sort(unlist(core$qualified)), sort(unlist(stored$qualified))))
}
unlink(sbx, recursive = TRUE)
cat(sprintf("\n== round_core_v1: PASS %d · FAIL %d ==\n", PASS, FAIL))
cat(sprintf('{"test":"round_core_v1","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
