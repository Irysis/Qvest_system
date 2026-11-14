## P1R04 정식 보고 1통(세션 · 판정 해석 · 판단 T2 · 철학 P2 뒤) — prep_send(qvest-telegram SKILL §0 · 1단위 1통 · 차트 = tools/p1r04_charts.R IS + OOS 판)
##   본문 수치는 IS(보는 창 · 2000~2022)만 — 출처 = results/evaluation_visible.json · pair_reading_visible.json · weight_trace_visible.json ·
##   lowrisk_share_visible.json(모두 보는 창 파일 · 손계산 없음 — 중앙값 집계만).
##   OOS 값은 차트(그림 1 · 3 · 4 · 9)로만 전한다 — 보고를 짜는 세션이 정보 경계(τ_D) 대상이라 OOS 값을 읽지 않는다.
##   11-15 판단 T2(R-20261115-001 · C-20261115-002~004 수용) · 철학 P2(R-20261115-002 · C-20261115-009 · 010 수용) 반영:
##   판정 라벨(등록 단측 규칙)과 처분 문장을 나눈다 · 악화 조항 부재 · 헌장 단위 셈 · 가중 추적 기전 · 등록 반대 가설 판독 · 탐침 순서 · 비용.
##   실행(저장소 루트): Rscript 04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw/tools/p1r04_report.R "<철학 P2 1줄>" "<판단 T2 1줄>" [--send]
##   --send 없으면 드라이런.
ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")); setwd(ROOT)
suppressMessages(source("04_Research/programs/_lib/round_core/v3/load.R"))
suppressMessages(source("02_Infrastructure/programs/program_report.R"))
a <- commandArgs(trailingOnly = TRUE)
SEND <- "--send" %in% a; a <- setdiff(a, "--send")
P2 <- if (length(a) >= 1L && nzchar(a[1])) a[1] else stop("[p1r04_report] 철학 P2 1줄 인자 없음")
T2 <- if (length(a) >= 2L && nzchar(a[2])) a[2] else stop("[p1r04_report] 판단 T2 1줄 인자 없음")
RD <- "04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw"; RES <- file.path(RD, "results")
PR <- rc_json_read(file.path(RES, "pair_reading_visible.json"))
V <- rc_json_read(file.path(RES, "evaluation_visible.json"))
WT <- rc_json_read(file.path(RES, "weight_trace_visible.json"))
SC <- rc_json_read(file.path(RES, "lowrisk_share_visible.json"))
if (!identical(PR$verdict, "support")) stop("[p1r04_report] 짝 읽기 판정이 support 가 아니다 — 본문을 다시 쓴다: ", PR$verdict)
TB <- PR$table; row <- function(l) Filter(function(r) identical(r$lineage, l), TB)[[1]]
num <- function(x) suppressWarnings(as.numeric(x))
f2 <- function(x) formatC(num(x), format = "f", digits = 2)
pp <- function(x) sprintf("%+.1f%%p", 100 * num(x))
tq <- function(code) { r <- Filter(function(x) identical(x$code, code), V$table); if (length(r)) num(r[[1]]$t_alpha_vis) else NA_real_ }
q1 <- vapply(TB, function(r) isTRUE(r$t1_qualify), TRUE); q0 <- vapply(TB, function(r) isTRUE(r$t0_ref_qualify), TRUE)
KO <- c(quality = "퀄리티", defense = "방어", liquidity = "유동성", momentum = "모멘텀", accrual = "발생액", value = "밸류", growth = "성장",
        investor_flow = "수급", risk = "위험", crowding = "쏠림", consensus = "컨센서스", technical = "기술적", regime = "국면", leverage = "레버리지", total = "토탈")
ko <- function(l) unname(KO[l])
lin <- vapply(TB, function(r) r$lineage, ""); dt <- vapply(TB, function(r) num(r$d_t_vis), 0)
cnt <- lin[vapply(TB, function(r) isTRUE(r$counted), TRUE)]
neg <- lin[order(dt)][sort(dt) <= -1.95]
n_q0 <- sum(q0); n_q0_neg <- sum(q0 & dt < 0)
dc <- vapply(TB, function(r) num(r$deep_crisis_nonworse_share), 0); bs <- vapply(TB, function(r) num(r$bull_seg_keep_share), 0)
inv <- row("investor_flow"); tec <- row("technical"); gro <- row("growth")
## 가중 추적(IS · 성과 무참조) — 카테고리별 유지 비(n_pos / n) · 유효 구성원 비(effn / n)의 달 중앙값
M <- data.table::rbindlist(lapply(WT$months, function(m) data.table::data.table(f = m$family, n = num(m$n), np = num(m$n_pos), ef = num(m$effn %||% NA))))
M <- M[is.finite(n) & n > 0, .(ret = stats::median(np / n), efr = stats::median(ef / n, na.rm = TRUE)), by = f]
q0f <- setdiff(lin[q0], "total"); Mq <- M[f %in% q0f]
tw <- SC$summary$technical
CH <- jsonlite::fromJSON(readLines(file.path(RD, "report", "charts_list.json"), warn = FALSE), simplifyVector = TRUE)
charts <- stats::setNames(file.path(ROOT, CH$file), CH$caption)
if (!all(file.exists(charts))) stop("[p1r04_report] 차트 파일 없음")

verdict <- paste0(sprintf("지지(기계 · 등록 단측 규칙) — 셈 대상 %d/%d(%s). ", length(cnt), length(TB), paste(ko(cnt), collapse = " · ")),
                  sprintf("단 등록 전 제안된 '악화 0' 조항이 빠져 있었다(있었으면 지지 아님: t ≤ −2 %d 계보 · 동일가중 자격 %d 계보 증분 %d/%d 음) · 셈 대상 둘 다 수익 엔진 아님 · 헌장 단위로는 셈 1. ",
                          sum(dt <= -2), n_q0, n_q0_neg, n_q0),
                  "처분: IC 가중 = 결합기 기본값 후보 아님 · 사슬 1호 = 동일가중(등록 전 고정)")
design <- c("가설: 카테고리 안 구성원을 as-of ICIR⁺ 로 가중하면 동일가중보다 선택 알파↑(Qian · Hua · Sorensen 2007 · Ehsani · Linnainmaa 2022) · 반대 가설 = ICIR 착시",
            sprintf("설계: 15 카테고리 × {IC 가중, 동일가중} 30칸 · 같은 날 측정 · 표준 구성(롱온리 25종 · 월말 · 15bps · 2억) · 판정 = 기준 엔진 대비 증분 알파 t ≥ %s ∧ 표식 없음이 2 계보 이상 또는 토탈", f2(PR$threshold)))
res <- c(sprintf("엔진 자격: IC 가중 %d/15 · 동일가중 %d/15(직전과 같은 집합) · 성장 탈락(알파 t %s → %s)", sum(q1), n_q0, f2(tq(gro$t0_ref)), f2(tq(gro$t1))),
         sprintf("수급: 증분 t %s · 엔진 알파 t %s → %s(여전히 음) / 기술적: %s · %s → %s · HLRange 한 구성원 몫 %s(저위험 쏠림)",
                 f2(inv$d_t_vis), f2(tq(inv$t0_ref)), f2(tq(inv$t1)), f2(tec$d_t_vis), f2(tq(tec$t0_ref)), f2(tq(tec$t1)), f2(tw$twin_share_median)),
         sprintf("음의 쪽: %s · 원천 4 < 5 · 새 원천 없음", paste(sprintf("%s %s", ko(neg), f2(dt[match(neg, lin)])), collapse = " · ")))
mech <- c(sprintf("자격 카테고리는 구성원 %.0f%% 를 남긴 완만한 재가중이 %d/%d 같은 쪽(음) — 잡음보다 체계적 기울기 · 이득은 거르기가 큰 수급 · 기술적(유지 %.0f%%)에서만",
                  100 * stats::median(Mq$ret), n_q0_neg, n_q0, 100 * stats::median(M[f %in% c("investor_flow", "technical")]$ret)),
          "반대 가설: ICIR 착시 = 지지 쪽 · 미결(1/N 분산 상실과는 분해 설계로 가른다) · 경기순응 = 위기 쪽 부분 지지 · 미결 · 방향 불일치 구성원 섞임 작음(그림 7)")
ideas <- c("① 수급 · 기술적 27 구성원 방향 재판정(성과 무참조) — 다음 결합기보다 먼저",
           "② 분해 설계 T1s(부호 거름 + 생존 구성원 동일가중) — 거르기 · 재가중 효과 분리 · 판정 양측(자격 계보 악화 0) · 표식 = 강세 구간 · 깊은 위기 과반",
           "③ T4 상태 조건부 · T5 상위 꼬리 — 깊은 위기 · 빠른 급락 · 대형주 강세 직접 겨냥 · 비용: 한 판 = 계보마다 시행 +1(A 관문 쪽)")
chk <- "측정 30/30 · 같은 배치 · 입력 지문 동일 · 짝 읽기 셸 버그 → 핀 도구 재실행 · 수리 733649080"
oos <- "OOS(2023~ · 보고 전용) = 그림 1 · 3 · 4 · 9 — 이 세션은 τ_D 대상이라 OOS 값을 읽지 않고 그림으로 전한다(판정 무관)."
r <- prep_send(program = "수익 엔진", target = "P1R04 카테고리 결합기 T1(시점별 IC 가중) 자격 심사 — 정식 보고",
               status = list(stage = "판정 · 해석(정식 보고)", position = "P1 결합기 단계 1 · IC 가중 15 + 동일가중 기준 15",
                             previous = "P1R03 동일가중 15 엔진(자격 8 · 원천 5)"),
               verdict_line = verdict,
               next_step = "P1S03 상설 판 판정 → 영수증 → P4C01 사슬 1호 등록 → P1S02 판 3 등록",
               extra = list(list(heading = "가설 · 설계", type = "bullet", items = design),
                            list(heading = "결과(IS)", type = "bullet", items = res),
                            list(heading = "해석", type = "bullet", items = mech),
                            list(heading = "감독", type = "bullet", items = c(paste0("철학 P2: ", P2), paste0("판단 T2: ", T2))),
                            list(heading = "다음 결합기 단계", type = "bullet", items = ideas),
                            list(heading = "OOS · 점검", type = "text", body = paste(oos, chk, sep = "
"))),
               charts = charts, artifact = RES, push = SEND, dry_run = !SEND, root = ROOT)
cat(sprintf("[p1r04_report] %s ok=%s\n", if (SEND) "발송" else "드라이런", isTRUE((r %||% list())$ok)))
