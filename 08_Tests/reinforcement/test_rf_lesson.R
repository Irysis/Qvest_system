#==============================================================================
# test_rf_lesson.R — 무인 교훈 기전 서술 계약 (v10.2 2026-09-03 · Phase 4)
# 대상: 02_Infrastructure/reinforcement/rf_lesson.R + 러너 배선
#==============================================================================
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
suppressMessages(source("02_Infrastructure/reinforcement/rf_lesson.R"))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(paste("  OK   ", m), fill = TRUE) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L
  cat(paste("  FAIL ", m, if (nzchar(d)) paste("—", d) else ""), fill = TRUE) }

ES  <- list(port_t = 1.2, calmar = 0.22, net_sharpe = 0.62, cagr = 0.14, oos_retention = 0.24, mdd = 0.65)
CAR <- list(port_t = 1.5, calmar = 0.26, net_sharpe = 0.67, cagr = 0.161, oos_retention = -0.09, mdd = 0.61)

# ① 문턱을 정본에서 읽는가 (하드코딩이면 재보정이 안 따라온다)
th <- rf_lesson_text("X", "C", list(calmar = 0.22))
if (grepl("0.64", th, fixed = TRUE)) ok("① Calmar 문턱 0.64 를 정본에서 읽는다") else
  ng("① 문턱이 안 보인다 — constraint_defaults 를 못 읽었다", th)

# ② 구속 조건을 값/문턱 쌍으로 특정하는가
b <- rfl_binding(ES)
if (b$n_met == 0L && grepl("port_t(", b$text, fixed = TRUE) && grepl("calmar(", b$text, fixed = TRUE))
  ok(sprintf("② 구속 축 특정 — %s", b$text)) else ng("② 구속 축 미특정", b$text)

# ②b sweep 칸은 DSR 이 여섯째 A 조건 — 5조건을 넘고 DSR 로만 B 인 칸을 '전부 충족' 으로 적으면 구속 축이 숨는다(2026-09-23)
ES_A5 <- list(port_t = 3.5, calmar = 0.7, net_sharpe = 1.2, cagr = 0.25, oos_retention = 0.9)
b_ch <- rfl_binding(ES_A5)
b_sw <- rfl_binding(c(ES_A5, list(selection_type = "sweep", dsr = 0.41)))
b_sw_ok <- rfl_binding(c(ES_A5, list(selection_type = "sweep", dsr = 0.88)))
if (grepl("전부 충족", b_ch$text) && grepl("dsr(0.410/0.50)", b_sw$text, fixed = TRUE) && grepl("6개 전부 충족", b_sw_ok$text))
  ok(sprintf("②b sweep 칸 DSR 구속 표기 — chain: %s · sweep 탈락: %s · sweep 통과: %s", b_ch$text, b_sw$text, b_sw_ok$text)) else
  ng("②b DSR 구속 축 미표기", paste(b_ch$text, "|", b_sw$text, "|", b_sw_ok$text))

# ③ 대칭/비대칭 판정 — 이 저장소의 실측 구속축이 여기서 갈린다
s_sym  <- rfl_shift(list(mdd = 0.53, cagr = 0.082), list(mdd = 0.586, cagr = 0.106))  # 위험↓ 수익 더↓
s_asym <- rfl_shift(list(mdd = 0.50, cagr = 0.110), list(mdd = 0.586, cagr = 0.106))  # 위험↓ 수익↑
if (grepl("대칭 축소의 전형", s_sym) && grepl("비대칭 성공", s_asym))
  ok("③ 대칭 축소 vs 비대칭 성공을 구분한다") else
  ng("③ 이동 판정 오작동", paste(substr(s_sym, 1, 60), "|", substr(s_asym, 1, 60)))

# ④ 지표 되풀이가 아니어야 한다 — 구판 템플릿과 구별되는가
# ★정규식 대신 고정 문자열로 판정한다 — 이 저장소에서 heredoc/이스케이프가 반복해서 접혔다.
new_txt <- rf_lesson_text("B1_3", "C", ES, CAR)
if (!startsWith(new_txt, "[무인") && !grepl("· PORT_t ", new_txt, fixed = TRUE) && grepl("구속", new_txt, fixed = TRUE))
  ok("④ 구판 지표-되풀이 템플릿과 구별된다") else ng("④ 여전히 지표 되풀이", new_txt)

# ⑤ next_probe — C/F 는 2건 이상이 계약(lcode_schema)
np <- rf_next_probes(ES, CAR, block = "B2")
if (length(np) >= 2L) ok(sprintf("⑤ next_probe %d건 (계약 하한 2)", length(np))) else
  ng("⑤ next_probe 부족", as.character(length(np)))

# ⑥ CAGR 이 문턱을 넘었으면 '수익 축을 더 밀지 말라'가 나와야 한다 — 방향 지시가 핵심이다
np2 <- rf_next_probes(list(port_t = 1.5, calmar = 0.26, net_sharpe = 0.67,
                           cagr = 0.20, oos_retention = 0.2, mdd = 0.62), CAR)
if (any(grepl("MDD 다", np2, fixed = TRUE))) ok("⑥ CAGR 충족 시 남은 격차를 MDD 로 지목") else
  ng("⑥ 방향 지시 없음", paste(np2, collapse = " / "))

# ⑦ 러너 배선 — 함수가 있어도 안 불리면 소용없다
rp <- tryCatch(paste(readLines("02_Infrastructure/ops/reinforce_auto_parallel.R", warn = FALSE),
                     collapse = "\n"), error = function(e) "")
if (grepl("rf_lesson_text(", rp, fixed = TRUE)) ok("⑦ 병렬 러너가 기전 서술을 호출한다") else
  ng("⑦ 러너 미배선 — 함수만 있고 안 돈다")

# ⑧ 폴백 — essence 가 결측이어도 죽지 않는다(무인 레인은 멈추면 안 된다)
r <- tryCatch(rf_lesson_text("X", "F", list()), error = function(e) NULL)
if (!is.null(r) && nzchar(r)) ok("⑧ essence 결측에도 서술 생성") else ng("⑧ 결측에서 죽는다")

cat("", fill = TRUE)
cat(sprintf("합계: 통과 %d · 실패 %d", PASS, FAIL), fill = TRUE)
cat(sprintf('{"test":"rf_lesson","pass":%d,"fail":%d,"total":%d}', PASS, FAIL, PASS + FAIL), fill = TRUE)
if (FAIL > 0L) quit(status = 1L)
