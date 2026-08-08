## FQ 등재 — M26 증분 라운드 결과 + 후속 프로브
## 규약: ① ID 는 파일 실측 max +1 (병행 세션 충돌 방지) ② toJSON digits=NA (남의 항목 반올림 훼손 금지)
##      ③ 쓴 뒤 git diff --numstat 로 순수추가 확인 (호출자 책임)
suppressPackageStartupMessages({ library(jsonlite) })
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(fmt,...) cat(sprintf(paste0("[fq] ",fmt,"\n"),...))
QP <- "06_Registry/alpha_frontier_queue.json"
q <- fromJSON(QP, simplifyVector = FALSE)
ids <- vapply(q$entries, function(e) as.character(e$id %||% ""), character(1))
`%||%` <- function(a,b) if (is.null(a)||length(a)==0L) b else a
ids <- vapply(q$entries, function(e) if (is.null(e$id)) "" else as.character(e$id), character(1))
nums <- suppressWarnings(as.integer(sub("^FQ-", "", ids)))
mx <- max(nums, na.rm = TRUE)
say("★현행 entries %d · max FQ id 실측 = FQ-%03d", length(q$entries), mx)

RES <- fromJSON("stage_artifacts/WT_D20260808_002/alpha_validation.json", simplifyVector = TRUE)
pt_raw   <- RES$transition$canonical_port_t_raw
pt_res   <- RES$transition$canonical_port_t_resid
fmb_t    <- RES$primary$fmb_nw3_t
sp_max   <- RES$primary$max_spearman_vs_incumbent

new <- list()
mk <- function(n, lane, title, hyp, ev, wall, gate, nxt, refs, extra=NULL) {
  e <- list(id = sprintf("FQ-%03d", n), lane = lane, title = title, hypothesis = hyp,
            ev_rationale = ev, wall_check = wall, data_gate = gate,
            owner = "미배정", status = "open", next_action = nxt,
            source_refs = refs, registered = "2026-08-08",
            registered_by = "alpha-research WT-D20260808_002")
  if (!is.null(extra)) e <- c(e, extra)
  e
}

new[[1]] <- mk(mx+1, "material_qualification",
  sprintf("M26_Revenue_Mom 증분 재료 자격 확립 (FMB NW3 t=%+.3f) — 전이는 cap-w PORT_t %+.3f 로 HARD 미달", fmb_t, pt_raw),
  paste0("이익-컨센서스 3종(C01_SUE·C02_EPS_Chg_1m·C04_ESBR) 통제 후 매출 전망 63일 개정(M26)이 ",
         "1M forward 수익에 횡단면 증분 정보를 준다. 283개월 전표본 Fama-MacBeth NW(lag3) t=", sprintf("%+.3f", fmb_t),
         " · 기존 3종과 최대 spearman ", sprintf("%.4f", sp_max), " (문턱 0.9) ⇒ 재탕 아님. placebo p=",
         sprintf("%.4f", RES$robustness$placebo_p), "."),
  "재료 자격은 확립됐으나 top-25 EW 전이에서 HARD 2.95 미달 — 소비면이 랭킹 슬롯이 아닐 수 있다(2026-08-02 MAX5 선례: 랭킹 사망·필터로는 ΔIR +0.169).",
  sprintf("cap-w PORT_t %+.3f (원신호) / %+.3f (3종 잔차) — 둘 다 HARD 2.95 미달. IC t_NW3 %+.2f 와 괴리 = 전이 벽.",
          pt_raw, pt_res, RES$secondary$rank_ic_t_nw3),
  "없음 (factor_db M26 산출 중, 318/442월)",
  "소비면 7종 순회: ①팩터 랭킹(측정완료·미달) ②유니버스 필터 ③오버레이/국면 입력 ④위험모델 ⑤monitoring ⑥선별 라벨 ⑦타 모드. 미측정 6면 중 ②⑥ 우선(랭킹 사망·필터 생존 선례).",
  c("stage_artifacts/WT_D20260808_002/alpha_validation.json",
    "qepm/mailbox/worktask/WT-D20260808_002/alpha_package.json"))

new[[2]] <- mk(mx+2, "pit_integrity",
  "컨센서스 계열 same-day vintage(Date <= sig_d) — T-1 선언과 비대칭, M26 lag1 유지율 0.23 의 대안 설명",
  paste0("registry 가 스스로 known_discrepancy 로 자인: 선언 lag_rule 은 T-1 인데 코드 강제점은 Date <= sig_d ",
         "(factor_db_builder.R:441 .pit_consensus · compute_consensus.R:33). 월말 당일 갱신된 컨센서스가 ",
         "종가 이전에 알 수 있었는지 미검증. 본 라운드 M26 은 lag1 스트레스에서 t 2.56→0.60(유지율 0.23)으로 ",
         "급락했는데, 이는 (a) 개정 최신분만 정보인 짧은 수명 (b) 월말 당일 vintage 로 구분되지 않는다."),
  "T-1 strict 재빌드 A/B 가 (a)/(b) 를 가른다. (b)로 판명되면 컨센서스 4종 전부(북 incumbent 포함) 재판정 필요 — 영향 범위가 본 라운드보다 크다.",
  "구조적으로는 신호창 종점(월말)과 수익창((월말, +1M])이 겹치지 않아 look-ahead 아님. 남은 위험은 월말 당일 종가-전 가용성 sub-daily 축뿐.",
  "필요 — 컨센서스 원천 vintage 재빌드(Date <= sig_d - 1)",
  "M26·C01·C02·C04 를 T-1 strict 로 재산출해 FMB t A/B. 인플레 >5% 면 strict 값으로 재판정(pit.md 오버레이 규약 준용).",
  c("02_Infrastructure/factor_db/factor_registry.json",
    "stage_artifacts/WT_D20260808_002/run_log.txt"))

new[[3]] <- mk(mx+3, "infra_repair",
  "compute_consensus.R 침묵 스킵 7종 — registry 등재 19 vs 실산출 12, 442개월 전 구간 0행",
  paste0("names(cons) 로 게이트된 블록 7개(C10·C11·C13·C14·C15·C17·C18)가 cons 슬림 리팩터(58-60행) 이후 ",
         "영구 거짓이 되어 442개 월 파일 전 구간 0행. 3종은 M2x 에 살아있는 쌍둥이가 있고(C14≡M26·C17≡M28·C11≈M25), ",
         "4종(C10·C13·C15·C18)은 등가물 없이 미시험 재료로 남아 있다."),
  "C18_Earnings_CAR_3d 는 이벤트-CAR 성격으로 M2x 에 등가물이 없다 — 비-return 인접 신규 재료 후보. 나머지 3종도 미시험.",
  "해당 없음(빌더 결함). 단 알파 차단 실증 — 'registry 19종을 다 시험했다'는 읽기가 실제로는 12종.",
  "없음 (수리는 코드 배선)",
  "제안서 stage_artifacts/WT_D20260808_002/duplicate_registration_proposal.json §proposal_B 배선 → 수리 후 C10/C13/C15/C18 재료 자격 라운드.",
  c("stage_artifacts/WT_D20260808_002/duplicate_registration_proposal.json",
    "stage_artifacts/WT_D20260808_002/consensus_silent_skip_census.csv"))

q$entries <- c(q$entries, new)
q$updated <- "2026-08-08"
write(toJSON(q, auto_unbox = TRUE, pretty = TRUE, digits = NA, null = "null"), QP)
say("등재 완료: %s", paste(vapply(new, function(e) e$id, character(1)), collapse=" "))
say("★쓴 뒤 확인 필요: git diff --numstat %s (순수추가여야 함)", QP)
