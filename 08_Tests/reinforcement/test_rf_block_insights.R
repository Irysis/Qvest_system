## '이번 배치에서 알게 된 것' 규칙 생성기 — rf_block_insights (2026-09-04)
## 실사고: 구판 rf_insights 는 entry 전체 고정 규칙이라 블록이 바뀌어도 같은 세 문장(21:41·22:04·22:33 동일).
##   새 생성기는 **이 블록**을 직전 최고와 대조하고 증거 있는 절만 낸다. 합성 표로 재도출한다.
suppressMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(QVEST_TG_DRY_RUN = "1", QVEST_RP_JLOG = file.path(tempdir(), sprintf("bi_jlog_%d.jsonl", Sys.getpid())))
P <- 0L; F <- 0L
ok <- function(m) { P <<- P + 1L; cat(sprintf("  ok   %s\n", m)) }
ng <- function(m, d = "") { F <<- F + 1L; cat(sprintf("  NG   %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_auto_notify.R"), local = TRUE))
suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_block_insights.R"), local = TRUE))
## 처치 서술은 실제 spec 파일에서 오므로 여기선 rf_cell_desc 를 합성 사전으로 덮는다
DESC <- list(B1_1 = "S01_Size+V14_EBIT_EV | 동일가중 1/25 | K200 합집합 KQ150",
             B1_2 = "S01_Size+V14_EBIT_EV+L27_Price_Level | 동일가중 1/25 | K200 합집합 KQ150",
             B1_3 = "S01_Size+V14_EBIT_EV+L27_Price_Level+R14_DUVOL | 동일가중 1/25 | K200 합집합 KQ150",
             B1_4 = "S01_Size+V14_EBIT_EV+L27_Price_Level+R14_DUVOL+TR01_ADX | 동일가중 1/25 | K200 합집합 KQ150",
             B2_6 = "S01_Size+V14_EBIT_EV | 비중 cvar | K200 합집합 KQ150",
             B2_7 = "S01_Size+V14_EBIT_EV | 비중 entropy | K200 합집합 KQ150",
             B2_8 = "S01_Size+V14_EBIT_EV | 비중 factor_rp | K200 합집합 KQ150",
             B2_9 = "S01_Size+V14_EBIT_EV | 비중 ivol | K200 합집합 KQ150",
             B2_10 = "S01_Size+V14_EBIT_EV | 비중 SchurDamping | K200 합집합 KQ150",
             B5_16 = "S01_Size+V14_EBIT_EV | 비중 cvar | K200 합집합 KQ150 | 오버레이 총노출/낙폭 (dd_brake_q)")
rf_cell_desc <- function(base_id = NULL) DESC
tab <- data.table(
  n = 1:10,
  code = c("B1_1","B1_2","B1_3","B1_4","B2_6","B2_7","B2_8","B2_9","B2_10","B5_16"),
  grade = c("B","B","C","C","B","C","C","C","F","C"),
  port_t = c(2.155, 2.171, 2.065, 1.011, 2.109, 1.998, 2.007, 2.058, 0.316, 1.137),
  inherited = FALSE,
  sr = 0.8, cagr = c(.204,.207,.20,.15,.216,.21,.21,.212,.124,.15),
  mdd = c(.600,.589,.58,.548,.557,.578,.57,.56,.612,.459),
  calmar = c(.34,.351,.345,.27,.388,.363,.368,.379,.203,.327),
  oos = -0.2)
S <- list(entry = list(base_id = "TEST_BI", attempts = list(), parent = NULL), tab = tab, used = 10L, maxa = 25L)

cat("=== A. B1 — 판정·갈린 처치·단조 희석 ===\n")
p1 <- rf_block_insights(S, "B1", ROOT)
if (all(c("판정", "무엇이 갈랐나", "군집·단조", "경계까지") %in% names(p1))) ok("A B1 절 4종 존재") else ng("A B1 절", paste(names(p1), collapse = ","))
if (any(grepl("대조할 기저 없음", p1[["판정"]]))) ok("A 첫 블록 · 부모 없음 → 기저 없음 명시") else ng("A 기저 서술")
if (any(grepl("초과수익을 움직이고 낙폭은 못 움직였다", p1[["판정"]]))) ok("A 축 판정 = 초과수익 축 (PORT_t 폭 1.16 · MDD 폭 5.2%p)") else ng("A 축 판정", paste(p1[["판정"]], collapse = " / "))
if (any(grepl("단조 역상관", p1[["군집·단조"]]))) ok("A 팩터 수 ↑ → PORT_t ↓ 단조 희석 검출") else ng("A 단조 희석 미검출", paste(p1[["군집·단조"]], collapse = " / "))
if (any(grepl("팩터 .*→ S01_Size\\+V14_EBIT_EV\\+L27_Price_Level$", p1[["무엇이 갈랐나"]]))) ok("A 갈린 처치 = 팩터 집합 차이") else ng("A 갈린 처치", paste(p1[["무엇이 갈랐나"]], collapse = " / "))
if (!any(grepl("표본외 유지율|A등급 0건|등급은 계약|자본에 접근", unlist(p1)))) ok("A 구판 채움말·전체 규칙 없음") else ng("A 채움말 잔존")

cat("\n=== B. B2 — 직전 최고 대조 · 한 점 군집 · 위험·수익 교환 ===\n")
p2 <- rf_block_insights(S, "B2", ROOT)
if (any(grepl("직전 최고 B1_2\\(PORT_t 2.171\\) 대비 ΔPORT_t -0.062", p2[["판정"]]))) ok("B 기저 = 직전 최고 B1_2 · Δ 부호 정확") else ng("B 기저 대조", paste(p2[["판정"]], collapse = " / "))
if (any(grepl("한 점", p2[["군집·단조"]])) && any(grepl("비중 cvar", p2[["군집·단조"]]))) ok("B 4칸 한 점 군집 + 처치 라벨") else ng("B 군집", paste(p2[["군집·단조"]] %||% "", collapse = " / "))
if (any(grepl("낙폭을 줄이면서 Calmar 를 올린 칸", p2[["위험·수익 교환"]]))) ok("B 진짜 위험 통제 칸 검출 (B2_6 MDD −3.2%p · ΔCalmar +0.037)") else ng("B 위험·수익", paste(p2[["위험·수익 교환"]], collapse = " / "))
if (!any(grepl("비중 비중", unlist(p2)))) ok("B 축 접두 중복 없음") else ng("B '비중 비중' 중복")

cat("\n=== C. B5 — 노출 축소 서명 ===\n")
p5 <- rf_block_insights(S, "B5", ROOT)
if (any(grepl("노출 축소 서명", p5[["위험·수익 교환"]]))) ok("C 낙폭·수익 동반 축소 → 노출 축소 서명") else ng("C 서명", paste(p5[["위험·수익 교환"]] %||% "", collapse = " / "))

cat("\n=== D. 승격 사슬 — 부모 표 대조 ===\n")
ptab <- data.table(n = 1:5, code = c("B1_1","B4_21","B4_22","B4_23","B4_24"), grade = "C",
                   port_t = c(2.0, 1.5, 1.4, 1.7, 1.2), inherited = FALSE, sr = .7, cagr = .18,
                   mdd = c(.58,.56,.57,.55,.60), calmar = c(.31,.32,.31,.33,.30), oos = 0)
S2 <- S; S2$entry$parent <- list(base_id = "PARENT", depth = 1L, cell = "B1_1", best_port_t = 2.0)
pS <- list(entry = list(base_id = "PARENT"), tab = ptab, used = 5L, maxa = 25L)
p1p <- rf_block_insights(S2, "B1", ROOT, pS)
if (any(grepl("부모 승자 B1_1\\(PORT_t 2.000\\) 대비 ΔPORT_t \\+0.171", p1p[["판정"]]))) ok("D 첫 블록 기저 = 부모 승자") else ng("D 부모 기저", paste(p1p[["판정"]], collapse = " / "))
if (any(grepl("승격 조건 충족 중", p1p[["승격 사슬"]]))) ok("D 승격 조건 판정") else ng("D 승격 사슬", paste(p1p[["승격 사슬"]] %||% "", collapse = " / "))
if (any(grepl("순손실 축: .*비중 -0.200", p1p[["승격 사슬"]]))) ok("D 부모 LOO 순손실 축 (비중 Δ −0.200) 인용") else ng("D 부모 LOO", paste(p1p[["승격 사슬"]] %||% "", collapse = " / "))

cat("\n=== E. 렌더 예산 · 요약/전체 분리 ===\n")
full <- rf_block_insights_render(p1); sh <- rf_block_insights_split(p1)
if (nchar(gsub("</?b>", "", sh$short)) <= 520L && grepl("▸ 판정", sh$short) && !grepl("▸ 경계까지", sh$short)) ok(sprintf("E 요약 = 판정+갈린 처치 (%d자 ≤ 520)", nchar(gsub("</?b>", "", sh$short)))) else ng("E 요약 구성", substr(sh$short, 1, 80))
if (grepl("▸ 경계까지", sh$full)) ok("E 전체판엔 뒤 절이 남는다") else ng("E 전체판")
tight <- rf_block_insights_render(p1, max_chars = 300L)
if (nchar(gsub("</?b>", "", tight)) <= 300L || sum(grepl("▸", strsplit(tight, "\n")[[1]])) == 1L) ok("E 예산 초과 시 뒤 절부터 뺀다") else ng("E 예산 미적용", sprintf("%d자", nchar(tight)))
if (identical(rf_block_insights_render(list()), "")) ok("E 절이 없으면 빈 문자열(호출자 폴백)") else ng("E 빈 입력")

cat("\n=== G. B5 스택 — 칸의 정체는 자기 층 · 상주 칸은 다른 칸 (2026-09-17 WP-Z) ===\n")
## 승계 스택(ts_mom_sign) 위에 서로 다른 층을 얹은 세 칸 + 상주 B5_31. 서술 4번째 축은 "승계 × 자기" 로 온다.
CY <- "오버레이 총노출/추세 (ts_mom_sign)"
DESC_G <- DESC   # ★c(DESC, list(B5_16=…)) 는 같은 이름을 두 번 두고 [[ 가 앞 것을 준다 — 대입으로 **교체**한다
DESC_G$B5_16 <- sprintf("S01_Size+V14_EBIT_EV | 동일가중 1/25 | K200 합집합 KQ150 | %s × 종목별/낙폭 (dbeta_tilt_rank)", CY)
DESC_G$B5_17 <- sprintf("S01_Size+V14_EBIT_EV | 동일가중 1/25 | K200 합집합 KQ150 | %s × 종목별/분산 (csd_idio_tilt)", CY)
DESC_G$B5_31 <- sprintf("S01_Size+V14_EBIT_EV | 동일가중 1/25 | K200 합집합 KQ150 | %s × 총노출/다변량 (pg2_risk_overlay_v1)", CY)
rf_cell_desc <- function(base_id = NULL) DESC_G
tabG <- rbind(tab[code != "B5_16"],
              data.table(n = 10:12, code = c("B5_16", "B5_17", "B5_31"), grade = c("C", "C", "B"),
                         port_t = c(1.137, 1.9, 2.2), inherited = FALSE, sr = 0.8, cagr = c(.15, .19, .21),
                         mdd = c(.459, .50, .40), calmar = c(.327, .38, .525), oos = -0.2))
SG <- list(entry = list(base_id = "TEST_BI", attempts = list(), parent = NULL,
                        carry = list(overlay = list(kind = "ts_mom_gate", arm_id = "ts_mom_sign"))), tab = tabG, used = 12L, maxa = 25L)
pg <- rf_block_insights(SG, "B5", ROOT)
gl <- paste(pg[["무엇이 갈랐나"]] %||% "", collapse = " / ")
if (grepl("dbeta_tilt_rank", gl, fixed = TRUE) && grepl("pg2_risk_overlay_v1", gl, fixed = TRUE) && !grepl("ts_mom_sign", gl, fixed = TRUE))
  ok("G 갈린 처치 = 자기 층끼리(dbeta_tilt_rank → pg2_risk_overlay_v1) · 승계 층 ts_mom_sign 은 안 적는다") else ng("G 갈린 처치", gl)
if (!grepl("두 칸이 같다", gl, fixed = TRUE)) ok("G 상주 B5_31 과 설계 B5_16 을 '같다' 로 읽지 않는다") else ng("G 같은 바닥 = 같은 칸 오판", gl)
cl <- paste(pg[["군집·단조"]] %||% "", collapse = " / ")
if (!nzchar(cl) || !grepl("처치의 효과는 하나", cl, fixed = TRUE) || grepl("라벨은 3개", cl, fixed = TRUE)) ok("G 군집 절이 세 칸을 한 처치로 접지 않는다") else ng("G 군집 처치 수", cl)
## carry 없이도(블록 공통 접두) 자기 층이 남는다
SG2 <- SG; SG2$entry$carry <- NULL
gl2 <- paste(rf_block_insights(SG2, "B5", ROOT)[["무엇이 갈랐나"]] %||% "", collapse = " / ")
if (grepl("dbeta_tilt_rank", gl2, fixed = TRUE) && !grepl("ts_mom_sign", gl2, fixed = TRUE)) ok("G carry 없음 → 블록 공통 접두(ts_mom_sign)를 빼고 자기 층으로 가른다") else ng("G 공통 접두", gl2)
## 돌연변이 통제 — 자기 층을 안 빼면 승계 층이 두 칸 서술에 모두 실린다(구분에 기여 0)
if (grepl("ts_mom_sign", DESC_G$B5_16, fixed = TRUE) && grepl("ts_mom_sign", DESC_G$B5_31, fixed = TRUE)) ok("G 돌연변이 통제 — 원 서술은 두 칸 다 승계 층을 품는다(픽스처가 결함을 가른다)") else ng("G 판별력")
rf_cell_desc <- function(base_id = NULL) DESC

cat("\n=== F. 블록이 바뀌면 내용이 바뀐다 (획일화 검사) ===\n")
r1 <- gsub("[0-9.]+", "#", rf_block_insights_render(p1)); r2 <- gsub("[0-9.]+", "#", rf_block_insights_render(p2))
if (!identical(r1, r2) && !identical(p1[["판정"]][1], p2[["판정"]][1])) ok("F B1 과 B2 의 서술이 다르다 (수치 제거 후에도)") else ng("F 두 블록 서술 동일")

cat(sprintf("\n== test_rf_block_insights: %d pass · %d fail ==\n", P, F))
cat(sprintf('{"test":"rf_block_insights","pass":%d,"fail":%d,"total":%d}\n', P, F, P + F))
if (F > 0L) quit(status = 1L)
