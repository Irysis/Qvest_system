## 원천 이음매(2026-03-30) 수리 · P1R03 재측정 — 텔레그램 1통(prep_send · qvest-telegram SKILL §0 · 정정 = 푸시)
##   실행: 저장소 루트에서 Rscript 04_Research/01_reports/rawdata_seam_20260330_repair_20261113/tools/send_report.R [--dry]
##   입력: ../p1r03_before_after.csv(차트 스크립트가 권위 산출물에서 옮겨 적은 값) · ../charts/*.png
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- sub("/+$", "", gsub("\\\\", "/", Sys.getenv("QM_ROOT", getwd()))); setwd(ROOT)
REP <- file.path(ROOT, "04_Research/01_reports/rawdata_seam_20260330_repair_20261113")
if ("--dry" %in% commandArgs(trailingOnly = TRUE)) Sys.setenv(QVEST_TG_DRY_RUN = "1")
source(file.path(ROOT, "02_Infrastructure/programs/program_report.R"))
M <- fread(file.path(REP, "p1r03_before_after.csv"))
pct <- function(x, d = 1) ifelse(is.finite(x), sprintf("%+.*f%%", d, 100 * x), "–")
f2 <- function(x) ifelse(is.finite(x), sprintf("%.2f", x), "–")
row <- function(c) M[code == c]
key5 <- c("FGROW", "FREGI", "FTECH", "FLIQU", "FRISK")
lines_day <- vapply(key5, function(c) { r <- row(c); sprintf("%s: %s → %s", r$name, pct(r$d_old), pct(r$d_new)) }, "")
lines_cal <- vapply(key5, function(c) { r <- row(c)
  sprintf("%s: 전기간 Calmar %s → %s · OOS Calmar %s → %s · 등급 %s → %s", r$name, f2(r$calmar_old), f2(r$calmar_new),
          f2(r$tw_old), f2(r$tw_new), r$g_old, r$g_new) }, "")
chg <- M[g_old != g_new]
grade_line <- if (nrow(chg)) paste(sprintf("%s %s→%s", chg$name, chg$g_old, chg$g_new), collapse = " · ") else "등급 변화 없음(15엔진)"
bench_tw <- M$btw[is.finite(M$btw)][1]

ch <- c("RAWDATA 단면 — 하루 |수익|>35% 종목 수(수리 전 vs 후)" = file.path(REP, "charts/c1_rawdata_cross_section.png"),
        "P1R03 엔진 15 — 2026-03-30 하루 순수익(수리 전 vs 후)" = file.path(REP, "charts/c2_p1r03_seam_day.png"),
        "핵심 5엔진 순자산(2022-07=1 · OOS 음영)" = file.path(REP, "charts/c3_p1r03_nav_key5.png"),
        "P1R03 엔진 15 — 전기간 · OOS Calmar 와 등급(수리 전 vs 후)" = file.path(REP, "charts/c4_p1r03_calmar_grade.png"))
ch <- ch[file.exists(ch)]

extra <- list(
  list(heading = "원인", type = "bullet", items = c(
    "2026-03-30 = 퀀티 base 수출본(~03-27) → 증분 수출본(03-30~) 이음매. 두 수출본의 수정주가 조정 기준 시점이 달라, 그 사이 액면분할 · 병합 종목은 비율 k(×5 · ×2 · ×10 · ×0.2 …)만큼 뛴다 — 그날 351종목 |수익|>35%(2000년 이후 정상일 최댓값 14종목) · 동일가중 +66.1% vs KOSPI200 −3.09%.",
    "09-07 부터 적재 단계의 이음매 보정이 매 적재 이 날을 고쳐 왔다(분할 배율 정정 280종목 · 미측정 처리 82종목). 11-11 신규 상장 보충 요청이 증분 수급 구간을 03-28~ 에서 11-10~ 로 좁혔고, 적재 단계는 수익률을 전 기간 다시 계산하면서 보정은 새 구간 첫날에만 적용해 03-30 보정이 지워졌다(오염 기간 11-11 11:28 ~ 11-13 09:07).")),
  list(heading = "수리 · 검증", type = "bullet", items = c(
    "적재 단계: 수익률 재계산 = 새로 받은 구간만 · 모든 원천 전환일을 매 적재 재판정 · 저장 전 전 기간 감사(발행주식수 · 시가총액 패턴으로 새 단절을 찾아 미측정 처리 + 경보). 가격 수준은 건드리지 않는다(PIT).",
    "RAWDATA 소급 정정: 바뀐 값 = 수익률 352행뿐(전 열 대조) · 03-30 |수익|>35% 351 → 0 · 동일가중 −1.84%. 파생 데이터: FF 요인 재빌드(2026-03 SMB +17.8% → +5.6% · RMW −12.7% → −2.0% — 오염 전 판본과 동일) · 당월 팩터 DB · IC 원장 · 결합용 팩터 뷰.",
    "양성 대조: 감사기가 오염본에서 352행 · 경보일 03-30 을 잡고 정정본에서 0 · 구판 복원 돌연변이가 03-30 +393% 를 재현(시험 34건 + 기존 111건 통과).")),
  list(heading = "03-30 하루 순수익 — 핵심 5엔진(수리 전 → 후)", type = "bullet", items = unname(lines_day)),
  list(heading = "재측정 — 같은 사양 · 정본 측정 계약(수리 전 → 후)", type = "bullet", items = c(unname(lines_cal),
    sprintf("밸류(반대 방향 — 액면분할 종목 보유로 그날 −80%%가 잡혔던 엔진): OOS Calmar %s → %s vs KOSPI200 %s — 등급 v3.4 OOS 관문 통과로 바뀜 · A 미달 사유 = 스윕 선택 현실 점검 하나 · 종합점수 S %s → %s(< 1) 라 B 유지",
            f2(row("FVALU")$tw_old), f2(row("FVALU")$tw_new), f2(bench_tw), f2(row("FVALU")$S_old), f2(row("FVALU")$S_new)))),
  list(heading = "영향 범위", type = "bullet", items = c(
    sprintf("P1R03 15엔진 재측정 — 수익 노출 11 · 15개 모두 오염된 FF 요인 판본으로 채점됐었다. IS(≤ 2022-12-31) 일간 수익은 15엔진 모두 비트 단위로 같다 → 자격 판정 8/15 불변. 등급: %s.", grade_line),
    "충실구현 3편(11-11 ~ 11-12): 2편은 03-30 수익 무노출 · FF 요인 판본만 오염(팩터 알파 재채점 대상) · 1편은 PIT 격리 대상(원래 인용 불가). 진행 중 1편(08:53 적재)은 끝나면 재측정 — A 자격은 자동 보류.",
    "BOOK_0001 라이브 트래킹(07-02~) 무영향 · 상설 자격 평가 · 강화 사슬 측정 없음 · 2계층 모듈 풀 4건(P1R03 B)은 재측정 전 자격 보류.",
    "09-07 이전 구 측정 축 산출물(보정 도입 전)은 노출이 있었으나 구 축은 현 등급 비교에 쓰지 않는다.")),
  list(heading = "결정 대기", type = "bullet", items = c(
    "가격 수준 기반 팩터(52주 고 · 저점 대비 · 로그가격 기울기 · 이평 교차 · MACD)는 수준이 03-30 에서 끊겨 2026-03 ~ 2027-03 값이 틀린다 — 수익률 연쇄 가격 지수(그날까지의 수익만 · PIT)로 다시 계산할지.",
    "원천 내부 단절 101행(2000년 이후 89 · 09-07 수익률 무처치) · 10-15 새 단절 1건(지금 미측정 처리 · 실수익 −30%)을 시총 기준 실수익으로 정정할지 — IS 값이 바뀌어 전 측정 재측정 파급.")))

prep_send(program = "P1_RETURN",
          target = "P1R03 정정 — RAWDATA 2026-03-30 원천 이음매 수리 · 15엔진 재측정",
          status = list(stage = "데이터 결함 수리 · 재측정(측정 신뢰 훼손 — 도훈 11-13 지시)",
                        position = "적재기 3층 수리 · RAWDATA 소급 정정 · 파생 재빌드 · P1R03 15엔진 재측정 끝",
                        previous = "P1R03 자격 8/15(IS) — OOS · 전기간 값 인용 보류(‡)"),
          verdict_line = sprintf("IS 판정 불변 · OOS · 전기간 값 정정 — 성장 엔진 03-30 하루 %s → %s · %s",
                                 pct(row("FGROW")$d_old), pct(row("FGROW")$d_new), grade_line),
          next_step = "P1R04 측정 재개(정정 데이터) · 결정 대기 2건 · 진행 중 레인 측정 1건 판정",
          artifact = REP, charts = ch, push = TRUE, extra = extra)
