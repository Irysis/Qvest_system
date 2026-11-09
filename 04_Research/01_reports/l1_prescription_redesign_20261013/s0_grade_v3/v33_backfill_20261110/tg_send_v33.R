#!/usr/bin/env Rscript
# 등급 v3.3 재채점 정정 통지 1통(푸시) — qvest-telegram SKILL §0(1단위 1통 · 판정 먼저 · 정정 = 푸시 · 숫자 안 자름)
#   수치 출처 = 같은 폴더 transitions.json · env_parity_r452_vs_r462.json(재채점 산출 · 손계산 없음)
#   사용: Rscript tg_send_v33.R [--send]   (기본 = 미리보기 · QVEST_TG_DRY_RUN=1)
suppressPackageStartupMessages(library(jsonlite))
args <- commandArgs(trailingOnly = TRUE)
SEND <- "--send" %in% args
ROOT <- gsub("\\\\", "/", Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "")))
HERE <- file.path(ROOT, "04_Research/01_reports/l1_prescription_redesign_20261013/s0_grade_v3/v33_backfill_20261110")
tr <- fromJSON(file.path(HERE, "transitions.json"), simplifyVector = FALSE)
par <- fromJSON(file.path(HERE, "env_parity_r452_vs_r462.json"), simplifyVector = FALSE)
source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

ch <- tr$changed
pick <- function(sid) Filter(function(x) identical(x$strategy_id, sid), ch)[[1]]
t2 <- function(x) sprintf("%.2f", as.numeric(x))
a1 <- pick("RP_20261018_062857_26492"); a2 <- pick("RP_20261018_064319_28512"); a3 <- pick("RP_20261018_153141_29448")
fs <- pick("RP_20261109_105545_37508"); o1 <- pick("RP_20261016_224702_30212"); o2 <- pick("RP_20260921_100007_6876")

secs <- list(
  list(heading = "현재 리서치 상황", type = "text",
       body = paste0("단계: 등급 체계 개정 발효(v3.2 → v3.3 · 도훈 11-09 '1안' · '대안')\n",
                     "대상: 저장된 권위 등급 ", format(tr$n_ok, big.mark = ","), "기록 재채점\n",
                     "위치: FF 요인 파일 교체(11-10 01:58 · 국제판 FF · 상한 가치가중 · CD91) 직후\n",
                     "직전 판정: v3.2(팩터 알파 노치 없음 · A 의 OOS 관문 = 롤링 36개월 통과율)")),
  list(heading = "판정", type = "text",
       body = paste0("현 측정 축(전 종목 + 위생 · 2000~)에서 팩터 조정 알파 노치로 B → A 3건 · C → B 1건. ",
                     "A 3건은 모두 재무 v1(결함) 위에서 잰 값이라 재무 v2 팩터 DB 로 재측정하기 전에는 A 자격 관문 · Judge 로 보내지 않는다(보류).")),
  list(heading = "바뀐 등급 — 현 측정 축", type = "bullet", items = c(
    sprintf("P2R03 기준 칸(2002.06975 DNN 계보 엔진 · 엔트로피 비중) B → A — 네 모형 알파 최소 t %s(%s) · 시험 창 Calmar %s vs KOSPI200 %s · 재무 v1 → 보류",
            t2(a1$fa_t_min), a1$fa_model, t2(a1$calmar_tw), t2(a1$bench_calmar_tw)),
    sprintf("P2R03 같은 엔진 + 조건부 오버레이 L2 B → A — 최소 t %s(%s) · 시험 창 Calmar %s vs %s · 재무 v1 → 보류",
            t2(a2$fa_t_min), a2$fa_model, t2(a2$calmar_tw), t2(a2$bench_calmar_tw)),
    sprintf("P2R04 기준 칸(P2R03 기준 칸과 같은 셀 · 같은 값) B → A — 최소 t %s(%s) · 재무 v1 → 보류", t2(a3$fa_t_min), a3$fa_model),
    sprintf("F-Score(Piotroski 2000 · 재무 v2 직접) C → B — 최소 t %s(%s) · A 는 PORT_t · CAGR · Sharpe 하한 미달", t2(fs$fa_t_min), fs$fa_model))),
  list(heading = "바뀐 등급 — 구 측정 축(현 축과 비교 금지)", type = "bullet", items = c(
    sprintf("1801.01777(구 축 = 전 종목 + 위생 · 동전주 바닥 전 · 재구현 진행 중) A → B — 새 OOS 관문: 시험 창 Calmar %s < KOSPI200 %s",
            t2(o1$calmar_tw), t2(o1$bench_calmar_tw)),
    sprintf("구 강화 칸(유동성 · 가격 지연 신호 · 구 축 K200∪KQ150 · 2005~) B → A — 시험 창 Calmar %s vs %s · 구 축이라 BOOK 후보 아님",
            t2(o2$calmar_tw), t2(o2$bench_calmar_tw)))),
  list(heading = "핵심 수치", type = "kv", kv = list(
    "재채점" = sprintf("%s기록 · 바뀜 6전략(8기록 — 사본 · 폐기 측정 포함)", format(tr$n_ok, big.mark = ",")),
    "현 축 A" = "3(전부 보류 · 재측정 대기)",
    "두 R 판 대조" = sprintf("4.5.2 vs 4.6.2 — 등급 차이 %d · S 차이 최대 %s",
                            as.integer(par$result$grade_differs), format(par$result$max_abs_dS)))),
  list(heading = "다음", type = "text",
       body = paste0("① A 3건(P2R03 기준 칸 · L2 · P2R04 기준 칸)을 재무 v2 팩터 DB 로 재측정 → A 자격 관문 → Judge(PIT). ",
                     "② F-Score 재측정(논문식 bhr 결합 · 결정 REPLICATION-LS-PAPER-BHR). ",
                     "③ FF 요인은 오늘 밤부터 일일 체인 [5c] 가 매일 갱신."))
)
title <- "[1계층·등급 v3.3] 저장 등급 재채점 정정 — 현 축 A 3(보류) · B 1"
footer <- paste0("산출물: 04_Research/01_reports/l1_prescription_redesign_20261013/s0_grade_v3/v33_backfill_20261110/transitions.md")
if (!SEND) Sys.setenv(QVEST_TG_DRY_RUN = "1")
r <- tg_agent_brief(agent = "AlphaSearch", title = title, sections = secs, footer = footer,
                    relaxed = TRUE, force = TRUE, decode_jargon = FALSE, glossary = FALSE, mute = FALSE,
                    smart_break = FALSE,   # 'B → A' 화살표 앞에서 문장을 끊지 않게
                    dry_run = !SEND)
cat(if (SEND) "[tg_v33] 발송 완료\n" else "[tg_v33] 미리보기(발송 없음)\n")
if (!SEND && is.character(r)) cat(r, sep = "\n") else if (!SEND && is.list(r) && !is.null(r$text)) cat(r$text, "\n")
