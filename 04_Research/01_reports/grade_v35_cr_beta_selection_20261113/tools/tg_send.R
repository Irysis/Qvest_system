## 등급 v3.5 출시 · 재채점 보고 — 텔레그램 1통(요약 + 차트 3장) · 수치 = build_report.R 의 요약(data/report_summary_<RUN>.json · 계약 산출 집계)
## 실행: 저장소 루트에서 Rscript …/tools/tg_send.R   (미리보기 · 발송 없음) / … tg_send.R send   (발송)
##   환경변수 V35_RUN(요약 꼬리표 · 기본 d1)
suppressPackageStartupMessages(library(jsonlite))
ROOT <- sub("/+$", "", gsub("\\\\", "/", Sys.getenv("QM_ROOT", getwd()))); setwd(ROOT)
suppressMessages(source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R")))
SEND <- "send" %in% commandArgs(trailingOnly = TRUE)
if (!SEND) Sys.setenv(QVEST_TG_DRY_RUN = "1")
D <- file.path(ROOT, "04_Research/01_reports/grade_v35_cr_beta_selection_20261113")
RUN <- Sys.getenv("V35_RUN", "d1")
OD <- sub("/+$", "", gsub("\\\\", "/", Sys.getenv("V35_OUT_DIR", D)))   # 리허설 미리보기 = 스크래치 산출(발송은 보고서 폴더 산출만)
if (SEND && !identical(OD, D)) stop("[v35 tg] 발송은 보고서 폴더 산출로만 한다(V35_OUT_DIR 지정 불가)")
S <- fromJSON(file.path(OD, "data", sprintf("report_summary_%s.json", RUN)), simplifyVector = TRUE)
pre_ok <- !SEND && identical(Sys.getenv("V35_TG_ALLOW_PRE"), "1")              # 쓰기 전 미리보기(발송 불가)
if ((is.null(S$census_post) || is.na(S$census_post)) && !pre_ok) stop("[v35 tg] 쓰기 뒤 전수가 없는 요약이다 — 재채점 쓰기 뒤에만 보낸다")
if (!isTRUE(S$vintage_ok) || S$errors != 0L || S$t4_same != S$n_t4 || S$rule_up != 0L || S$rule_outside != 0L)
  stop("[v35 tg] 출시 조건 위반(데이터 시점 · 오류 · 음성 대조 · 상향 · 범위 밖 규칙 효과) — 보내지 않는다")
figs <- c("① 권위 등급 분포 — 재채점 전 vs 뒤" = file.path(OD, "charts/01_grade_distribution.png"),
          "② 위기 방어 '강함' 기록 — 시가총액·노출 일치 대조 vs 시가총액·β 일치 대조를 이긴 위기 비율" = file.path(OD, "charts/02_cr_strong_attribution.png"),
          "③ 재채점 등급 이동 — 규칙 효과 vs 데이터 갱신 효과" = file.path(OD, "charts/03_transition_by_cause.png"))
stopifnot(all(file.exists(figs)))
fmt <- function(x) format(x, big.mark = ",", trim = TRUE)
mv <- S$rule_moves; n_down <- if (is.null(mv[["내림"]])) 0L else mv[["내림"]]; n_same <- if (is.null(mv[["그대로"]])) 0L else mv[["그대로"]]
dl <- S$rule_down_list
cur <- if (length(dl) && NROW(dl)) dl[!dl$superseded & !dl$aborted, , drop = FALSE] else NULL   # 현행 기록만 이름으로 · 대체 · 중단 기록은 건수로
n_old <- if (length(dl) && NROW(dl)) sum(dl$superseded | dl$aborted) else 0L
down_txt <- if (!is.null(cur) && NROW(cur)) paste(sprintf("%s %s→%s(보유 β %.2f · 동일 β 대조 %.0f%%)", cur$strategy, cur$from, cur$to, cur$beta_leg,
                                                          100 * cur$share_sb), collapse = " · ") else "없음"
if (n_old > 0L) down_txt <- sprintf("%s · 그 밖에 대체되거나 중단된 측정 기록 %d건도 같은 방향(인용 대상 아님)", down_txt, n_old)
dist <- S$dist; dist_txt <- paste(sprintf("%s %s → %s", dist$g, fmt(dist$before), fmt(dist$after)), collapse = " · ")
sb <- S$rule_sb_range; bt <- S$rule_beta_range
summ <- sprintf("위기 방어 가점 = 시가총액·β 일치 대조까지 · 범위 %d건 중 %d건 하향 · 상향 0", S$n_rule, n_down)
stopifnot(nchar(summ) >= 20, nchar(summ) <= 100)
r <- tg_agent_brief(
  agent = "Q-Lead",
  title = "[1계층·등급 규칙] v3.5 출시 — 위기 방어 가점에 시가총액·β 일치 대조 추가",
  sections = list(
    list(type = "summary", emoji = "\U0001F4CC", body = summ),
    list(type = "bullet", heading = "무엇이 바뀌었나", emoji = "\U0001F527",
         items = c("기존: 같은 시가총액 분위에서 무작위로 고른 대조 포트폴리오(characteristic-matched random portfolios · 200개)의 위기 낙폭 5% 분위보다 덜 빠지면 '선택 방어' 가점. β 를 맞추지 않아 분위 안 저β 종목만 담아도 통과했다.",
                   "v3.5: 각 대조 포트폴리오를 현금 혼합으로 전략 β 까지 낮춘 동일 β 대조군(월간 OLS β · 차입 없음)도 위기 과반에서 이겨야 가점. 노출을 시변 조절하면 노출 경로까지 맞춘 대조도 이겨야 '선택'.",
                   "근거: 헌장 빈칸 14(선택 방어 = 시가총액 × β 동시 일치 대조까지 넘을 때) · 도훈 결정 GRADE-CR-NOTCH-BETA-SELECTION-20261113 · 발효 11-14 16:03.",
                   "종합점수 S · 하한 · 팩터 조정 알파 노치 · OOS 관문은 그대로 — 가점 조건만 더했으므로 같은 입력이면 등급이 오르지 않는다.")),
    list(type = "bullet", heading = "검증 — 합성 자료 양성·음성 대조 · 돌연변이", emoji = "\U0001F9EA",
         items = c("음성: 분위 안 저β(0.4) 대칭 종목 → 기존 대조 100% 통과 · 동일 β 대조 0% → 가점 해제",
                   "양성: 평상 β 1.0 · 위기 β 0.3(비대칭) → 둘 다 100% → 가점 유지 / 평상 0.6 · 위기 0.2 → 유지(저β 자체를 벌하지 않는다)",
                   "저β + 위기 달 노출 축소 → 노출 경로 동일 β 대조 0% → '선택' 아님(타이밍 · 증거 없으면 가점 없음)",
                   "합성 검사 37건 · 검사 무력화 돌연변이 6종 검출 · 가점 경우의 수 240개에서 등급 상승 0 · 운영 회귀 7종 통과")),
    list(type = "bullet", heading = "재채점 — 측정 전 고정한 범위 · 같은 입력 v3.4 vs v3.5", emoji = "\U0001F4CA",
         items = c(sprintf("범위: 위기 방어 가점이 유지된 기록 %d건(사전등록 시점 %d + 그 뒤 측정 %d) · 규칙 효과 = 하향 %d · 유지 %d · 상향 0", S$n_rule, S$n_rule_snap, S$n_rule_new, n_down, n_same),
                   sprintf("하향: %s", down_txt),
                   if (length(sb) == 2L) sprintf("범위 기록의 동일 β 대조 통과율 %.0f~%.0f%%(과반 미달) · 보유 β %.2f~%.2f — v3.5 가점 유지 기록 %d건", 100 * sb[1], 100 * sb[2], bt[1], bt[2], S$keep_notch) else
                     sprintf("v3.5 가점 유지 기록 %d건", S$keep_notch),
                   sprintf("실데이터 음성 대조: 가점이 이미 없던 강함 기록 + 무작위 기록 %d건 → 등급 동일 %d/%d", S$n_t4, S$t4_same, S$n_t4),
                   sprintf("팩터 수익률 갱신(규칙 무관 · %s) 재채점 %d건 → 등급 이동 %d건", Sys.getenv("V35_FA_NOTE", "원천 수익률 정정(가격 연속성 · 내부 단절 채움) 반영 — 팩터 조정 알파 노치만 다시 계산"), S$n_fa, S$fa_total_moved),
                   sprintf("전체 %s건 분포: %s", fmt(S$n_records), dist_txt),
                   sprintf("상향 수혜 표식 %s건 · A 하향 %d건 · Judge 요청 회수 %d건", as.character(S$benefit_new), S$a_down, S$judge_withdraw))),
    list(type = "bullet", heading = "다음", emoji = "\U000027A1\UFE0F",
         items = c("1계층 라운드는 이미 새 계약 위에서 돈다 — P1R04(닫힘) · P1S03(판정) · P4C01 · P1S04(등록) 모두 v3.5 계약 고정값",
                   "재채점 범위의 P1R03 기록은 원천 수익률 정정 전 측정(대체됨 · 인용 대상 아님) — 15개 엔진은 정정 뒤 v3.5 로 다시 측정됐다 · 정정 구간을 보유한 다른 기록의 저장 수익률은 측정 때 값이라 재측정 몫",
                   sprintf("교체 뒤 v3.5 로 측정된 기록 %d건은 팩터 수익률 갱신만 다시 채점(등급 저장 그대로 %d/%d)", S$n_post_release %||% 0L, S$post_release_same %||% 0L, S$n_post_release %||% 0L),
                   "위기 무렵 보유 회전(노출 1 · 보유를 저β 로 교체): 도훈 결정 (나) — 위기 전 보유 동결 대조를 진단 기록으로 쌓는다(등급 반영 v3.6 은 따로) · 후속: 행동 카드 보고 문구를 동일 β 대조 결과와 맞추기"))),
  charts = figs, relaxed = TRUE, glossary = FALSE)
cat("ok:", isTRUE(r$ok %||% TRUE), "\n")
