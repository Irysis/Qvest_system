## P2R04 종료 기록 — 등록부 결과(판정 · 철학 P2 · 판단 T2 · 보고 경로) — writer 경유(program_registry.R::pr_record_round)
##   철학 · T2 리뷰 id 는 환경변수로 받는다(P2R04_P2_ID · P2R04_T2_ID) — 리뷰 등록 뒤 Q 가 넘긴다. P2R03 close_round.R 과 같은 틀.
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; Sys.setenv(QM_ROOT = ROOT); setwd(ROOT)
suppressMessages(source(file.path(ROOT, "02_Infrastructure/programs/program_registry.R")))
library(jsonlite)
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
SA  <- "stage_artifacts/programs/P2_DEFENSE/P2R04_defensive_holdings"
pre <- fromJSON(file.path(ROOT, SA, "prereg.json"), simplifyVector = FALSE)
ev  <- fromJSON(file.path(ROOT, "04_Research/programs/P2_DEFENSE/P2R04_defensive_holdings/results/evaluation_visible.json"), simplifyVector = FALSE)
codes <- grep("_H[1-4]$", vapply(pre$cells, function(z) z$code, character(1)), value = TRUE)   # 판정 칸 = 장치 H1~H4 × 두 엔진(진단 C · W · N0 · RX0 제외)
stopifnot(length(codes) == 8L)
pr_record_round("P2_DEFENSE", list(
  round_id = "P2R04_defensive_holdings", prereg = file.path(SA, "prereg.json"),
  prereg_md5 = unname(tools::md5sum(file.path(ROOT, SA, "prereg.json"))), status = "complete", n_variants = 8L,
  variants = as.list(codes),
  verdict = list(label = as.character(ev$verdict_label %||% ev$verdict), pass_both = list(), pass_one = list(), selected = list(),
                 note = paste0("β 짝(같은 β 현금 사본) 깊은 위기 과반 0/8(최대 2/4 = E3 H2) — 판정 칸 노출(β) 방어 4 · 결정적 미달 4 · 방어 이름 없음 · ",
                               "깊은 위기별 β 짝 승 2008-05~10 0/8 · 2020-01~03 1/8 · 2011-05~09 5/8 · 2021-06~ 2/8: 늘 켜진 50% 틸트는 전면 급락 둘에서 엔진 β 사본을 못 넘고 분산 위기에선 저변동이 넘음(결과 뒤 기술 · 판정 아님 · 조건부 하방β P2R03 D1 은 2020 승 — '늘 켜짐 대 조건부' · T2 C-037) · ",
                               "용량 — 전부 통과 0(등록 판독) · 단 W2(저변동 12.5% · 진단 칸) 두 구성 ③ 3/4 · ④ 3/4(P2 첫 β 짝 깊은 위기 과반 · 2008-05 여유 0.006) · ⑤ 수준 역행 · ⑭ 미달 → 방어 주장 불가 · 결과로 발견 · 후보로 올리지 않는다(T2 C-036) · ",
                               "희석(① 위기 수 겹침 H1 3/5 · H2 4/6 · H3 3/3 · H4 4/5)은 비깊은 위기 한정 · 깊은 위기 N0 1/4(T2 C-038) · 결측 패턴 방어 0 · ",
                               "⑤ Δ<0 = H1 두 구성 · H4 E2 · 악화 = H2 · H3 두 구성 · H4 E3 · ",
                               "결론 범위 4: P2R02 C4 '검증' 대체 = E2 H2 노출 방어 · E3 W2 ③ ④ 통과 · ⑤ ⑭ 미달 · C5 = 결정적 미달 · P4 골격(E2 × C4) 같은 사양 = 노출 방어(③ 1/4 · S 0.606 < 0.623 · 골격 변경 제안 없음) · ",
                               "분산 위기 저변동 승은 하락/상승 β 비 악화(두 구성) 동반 — 빈칸 3 · 8 상 방어 주장 불가(철학 C-047) · 보류: 저변동 틸트 류 P4 · A 승격 전 도훈 확인(철학 C-046) · ",
                               "H4 = PIT 경계 기록(정정 공시 판본 없음 · 결론 범위 9) · 다음 = 원천 ① 분포 표적(P2R05 · 결론 범위 5 · 깊은 위기별 기대 · 저용량 저변동 기준 칸 · 합집합 결합 금지)")),
  philosophy_p2 = Sys.getenv("P2R04_P2_ID", "(대기)"),
  superfan_t2 = Sys.getenv("P2R04_T2_ID", "(대기)"),
  r7 = list(label = ev$noise_reading$label %||% NA, judged = ev$noise_reading$judged_devices %||% NA, max_dS = ev$noise_reading$max_dS %||% NA,
            p2r03_reread = "잡음 이내(판정 장치 7/7 · 검증 0 · ③ 두 구성 > 0.5 장치 0 · S 증분 평균 최대 −0.0225 < 0.02 — 판단 T2 R-20261018-005 재도출)",
            counter = "등록 판독(S 포함): P2R03 이내 → P2R04 밖 → 계수 0",
            defense_component = "방어 성분(체계 §4 병목 = 깊은 위기 방어): 판정 칸 ③ 최대 2/4 — P2R03 · P2R04 연속 2회 잡음 → P2R05 는 사유(등록된 다음 단계 · 원천 ① 첫 측정)를 적고 P2 로 열되 방어 성분 잡음이면 P2 정지 · 도훈 보고(철학 C-045 수용)",
            note = "P2R04 '잡음 밖'은 H4 단독(S 증분 E2 +0.146 · E3 −0.019 · 수익 쪽 · PIT 경계 장치) — P1 재료로 기록"),
  measurement = list(epoch = "all_hyg_px1000_2000_v1", ok = "23/23", vintage_groups = "E2 · E3 지문 동일 · 평가 지문 = 측정 지문 · RX0 = P2R03 RX0(보유 · 수익 215개월 동일)",
                     attempts = "1회 기동(10-18 15:14 measure_now_vram.sh · 병렬 2) · 평가 15:59"),
  report = file.path(SA, "ROUND_REPORT.md"), failure_map = file.path(SA, "failure_map.md")), root = ROOT)
pr_set_status("P2_DEFENSE", "active", reason = paste0("P2R04 falsified(β 짝 깊은 위기 0/8 · 늘 켜진 틸트는 전면 급락 둘에서 β 사본에 짐) · ",
              "P2R05 원천 ① 분포 표적 설계 · 구현 중 · P2R02 C4 '검증'은 이 축에서 대체(P2R04 결론 범위 4)"), root = ROOT)
cat("P2R04 recorded complete · P2_DEFENSE status active\n")
