## test_overlay_precheck.R — 오버레이 착수 전 판정 계약 (위반 주입 포함)
## 대상: 02_Infrastructure/contracts/overlay_precheck.R + 06_Registry/overlay_base_q1_share_20260810.json
## 왜: 2026-08-10 세 경로가 같은 원리에 도달하고 실제 PORT_t 4점이 확인했다 —
##     **선별 오버레이는 base 의 선호를 되돌린다**(q1 높을수록 Δ 나쁨).
##     PG2 0.308 → Δ **-0.846** vs FAM_L 0.148 → **+0.736**. 이 판정이 결정 지점에서 살아 있는지 잰다.
## ★검사 축: ①실측 4점이 올바른 판정을 받는가(양성 대조) ②미측정이 **NA** 로 남는가(0 위장 금지)
##          ③경계 동작 ④위반 주입(범위 밖·NULL·문자) ⑤표↔계약 배선(호출부 0 방지)
##          ⑥돌연변이(문턱을 없애면 PG2 가 GO 로 뒤집힘)
suppressPackageStartupMessages({ library(jsonlite) })
.args <- commandArgs(trailingOnly = FALSE)
.fa <- grep("^--file=", .args, value = TRUE)
.here <- if (length(.fa)) dirname(normalizePath(sub("^--file=", "", .fa[1]), winslash="/", mustWork=FALSE)) else getwd()
.root <- normalizePath(file.path(.here, "..", ".."), winslash = "/", mustWork = FALSE)
SRC <- file.path(.root, "02_Infrastructure/contracts/overlay_precheck.R")
if (!file.exists(SRC)) { cand <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT",""))
  if (nzchar(cand)) { .root <- cand; SRC <- file.path(cand, "02_Infrastructure/contracts/overlay_precheck.R") } }
if (!file.exists(SRC)) stop(sprintf("계약 미발견: %s (러너 위치 문제이지 계약 실패 아님)", SRC))
suppressMessages(source(SRC))
TBL <- file.path(.root, "06_Registry/overlay_base_q1_share_20260810.json")

PASS <- 0L; FAIL <- 0L
.m1 <- function(x){x<-as.character(x); if(!length(x)) "" else x[1]}
ok  <- function(n,m=""){PASS<<-PASS+1L; cat(sprintf("  PASS: %s%s\n", n, if(nzchar(.m1(m))) paste0(" — ",.m1(m)) else ""))}
bad <- function(n,m=""){FAIL<<-FAIL+1L; cat(sprintf("  FAIL: %s%s\n", n, if(nzchar(.m1(m))) paste0(" — ",.m1(m)) else ""))}
chk <- function(n,c,m="") if (isTRUE(c)) ok(n,m) else bad(n,m)

cat("\n[A] 실측 4점이 올바른 판정을 받는가 (양성 대조)\n")
chk("A1_pg2_no_go", overlay_q1_precheck(0.308)$verdict == "NO_GO",
    "PG2 q1 0.308(Δ -0.846) → NO_GO")
chk("A2_faml_go", overlay_q1_precheck(0.148)$verdict == "GO", "FAM_L 0.148(Δ +0.736) → GO")
chk("A3_famcr_go", overlay_q1_precheck(0.150)$verdict == "GO", "FAM_CR 0.150(Δ +0.210) → GO")
chk("A4_fams_go", overlay_q1_precheck(0.195)$verdict == "GO", "FAM_S 0.195(Δ +0.116) → GO")
chk("A5_sign_separates", overlay_q1_precheck(0.308)$verdict != overlay_q1_precheck(0.195)$verdict,
    "Δ 부호가 갈린 두 점이 **다른 판정**을 받는다 — 계약이 실제로 구분한다")

cat("\n[B] 경계\n")
chk("B1_caution_band", overlay_q1_precheck(0.26)$verdict == "CAUTION", "0.25~0.28 은 CAUTION")
chk("B2_boundary_025", overlay_q1_precheck(0.250)$verdict == "CAUTION", "0.250 정확히 = CAUTION(균등)")
chk("B3_boundary_028", overlay_q1_precheck(0.280)$verdict == "NO_GO", "0.280 정확히 = NO_GO")

cat("\n[C] 위반 주입 — 잘못된 입력이 발화하는가\n")
chk("C1_negative", overlay_q1_precheck(-0.1)$verdict == "INVALID", "음수 = INVALID")
chk("C2_over_one", overlay_q1_precheck(1.5)$verdict == "INVALID", "1 초과 = INVALID")
chk("C3_na", overlay_q1_precheck(NA)$verdict == "INVALID", "NA = INVALID")
chk("C4_char", overlay_q1_precheck("높음")$verdict == "INVALID", "문자 = INVALID")
chk("C5_null", overlay_q1_precheck(NULL)$verdict == "INVALID", "NULL = INVALID")
chk("C6_invalid_msg", grepl("0 으로 대체하지", overlay_q1_precheck(NA)$message),
    "INVALID 메시지가 **'미측정을 0 으로 대체하지 말 것'** 을 명시")

cat("\n[D] 표 ↔ 계약 배선 (호출부 0 방지)\n")
if (file.exists(TBL)) {
  chk("D1_lookup_pg2", isTRUE(abs(overlay_q1_lookup("PG2", TBL) - 0.308) < 0.02),
      sprintf("표에서 PG2 조회 = %.3f", overlay_q1_lookup("PG2", TBL)))
  chk("D2_lookup_missing_na", is.na(overlay_q1_lookup("__no_such_base__", TBL)),
      "미등록 base 는 **NA** — 0 으로 위장하지 않는다")
  tb <- fromJSON(TBL)
  chk("D3_table_has_caveats", length(tb$caveats) >= 3 &&
        any(grepl("자본 후보 아님", tb$caveats)),
      "표가 **자본 후보 아님** 경고를 담는다(수치만 옮겨가는 것 방지)")
  chk("D4_table_size", nrow(tb$bases) >= 20, sprintf("base %d종 등재", nrow(tb$bases)))
} else {
  chk("D0_table_missing", FALSE, sprintf("표 미발견: %s — 배선 끊김", TBL))
}
chk("D5_no_file_no_zero", is.na(overlay_q1_lookup("PG2", "__nope__.json")),
    "표 파일이 없으면 **NA** (조용한 0 금지)")

cat("\n[E] 돌연변이 — 문턱을 없애면 판정이 무너지는가 (검사 사망 통제)\n")
mut <- function(q) "GO"          # 문턱 무시 구현
chk("E1_mutation_flips", mut(0.308) == "GO" && overlay_q1_precheck(0.308)$verdict != "GO",
    "문턱을 없애면 PG2 가 GO 로 뒤집힌다 — A1 의 PASS 가 문턱에서 온 것임을 실증")

cat("\n[F] 처리 범위 — P20(2026-08-10) 이 일반화 미달을 실측했으므로 계약이 **거부**하는가\n")
## 왜 이 축이 있나: P20 에서 D03 밴드는 Q2_PARTIAL 이었다(상위3 Δ +0.712 vs 하위3 +0.922,
## 유일 음수 Δ 의 CORE4_EW 가 band_share 20 중 10위). 원리는 서지만 **예측자가 처리마다 다르다**.
## 주석 경고는 dead 가 되므로 계약이 스스로 범위를 지켜야 한다.
chk("F1_default_in_scope", overlay_q1_precheck(0.148)$verdict == "GO",
    "기본값(reversal)은 그대로 판정 — 기존 소비자 무파손")
chk("F2_band_out_of_scope",
    overlay_q1_precheck(0.148, treatment = "d03_band_q34_fill")$verdict == "OUT_OF_SCOPE",
    "D03 밴드 = **OUT_OF_SCOPE** (P20 Q2_PARTIAL)")
chk("F3_out_of_scope_beats_value",
    overlay_q1_precheck(0.35, treatment = "vol_target")$verdict == "OUT_OF_SCOPE",
    "범위 밖이면 q1 값과 무관하게 OUT_OF_SCOPE — 값이 판정을 앞지르지 않는다")
chk("F4_scope_msg_cites_p20",
    grepl("CORE4_EW", overlay_q1_precheck(0.2, treatment = "d03_band")$message) &&
      grepl("예측자가 처리마다 다르다", overlay_q1_precheck(0.2, treatment = "d03_band")$message),
    "메시지가 P20 의 **강한 검정점(CORE4_EW)** 과 처리별 예측자 원칙을 명시")
chk("F5_na_treatment", overlay_q1_precheck(0.148, treatment = NA)$verdict == "OUT_OF_SCOPE",
    "처리 미표기 = OUT_OF_SCOPE (조용히 reversal 로 가정하지 않는다)")
chk("F6_scope_note_present", nzchar(overlay_q1_precheck(0.148)$scope_note),
    "정상 판정도 **scope_note 를 동봉** — 수치만 옮겨가는 인용 차단")
mut2 <- function(q, tr) overlay_q1_precheck(q)$verdict     # 처리 무시 구현
chk("F7_mutation_scope",
    mut2(0.148, "d03_band") == "GO" &&
      overlay_q1_precheck(0.148, treatment = "d03_band")$verdict == "OUT_OF_SCOPE",
    "처리 인자를 무시하면 밴드가 GO 로 통과한다 — F2 의 PASS 출처 실증")
chk("F8_table_treatment_field", file.exists(TBL) &&
      grepl("reversal", fromJSON(TBL)$treatment, fixed = TRUE),
    "표도 `treatment` 를 선언한다 — 계약·표가 같은 범위를 말한다")

cat("\n[G] 죽은 예측자 원장 — 같은 곳을 세 번째로 파는 것을 막는가 (P17a·P23b 2회 실패)\n")
chk("G1_band_dead_predictor", !is.na(overlay_dead_predictor("d03_band_q34_fill")),
    "밴드 처리는 **이미 죽은 예측자(rel14)** 기록을 갖는다")
chk("G2_cites_nonpersistence", grepl("Jaccard", overlay_dead_predictor("d03_band")),
    "사유가 검정력이 아니라 **비지속성(Jaccard 0.182)** 임을 명시 — 재시도 유인 차단")
chk("G3_warns_shared_term", grepl("공유항", overlay_dead_predictor("d03_band")) &&
      grepl("0.632", overlay_dead_predictor("d03_band")),
    "**공유항 오염판이 확증처럼 보인다**(rho -0.632)는 경고를 동봉 — 오염 수치 인용 차단")
chk("G4_unknown_is_na", is.na(overlay_dead_predictor("vol_target")),
    "기록 없는 처리는 **NA** — '죽은 예측자 없음'이 아니라 '미기록'")
chk("G5_empty_is_na", is.na(overlay_dead_predictor(character(0))),
    "빈 입력도 NA (조용한 매칭 금지)")
chk("G6_surfaced_in_verdict",
    !is.na(overlay_q1_precheck(0.2, treatment = "d03_band")$dead_predictor),
    "OUT_OF_SCOPE 판정이 죽은 예측자를 **함께 반환** — 조회를 따로 해야 알 수 있으면 dead 배관")

cat("\n[H] 지속성 — 문턱이 **실현-표본 서술**이 아님을 계약이 스스로 들고 있는가 (P24)\n")
## 왜: P23b 는 rel14 를 비지속성(Jaccard 0.182)으로 죽였다. 같은 칼을 q1 에도 대야 공정하다.
## 이 축이 없으면 계약은 '내 예측자만 안 재는' 이중잣대가 된다.
chk("H1_persistence_declared", is.list(CP_OVERLAY_Q1_PERSISTENCE) &&
      identical(CP_OVERLAY_Q1_PERSISTENCE$verdict, "J1_PERSISTENT"),
    "q1 의 지속성 판정이 계약에 **선언**되어 있다")
chk("H2_beats_dead_predictor",
    CP_OVERLAY_Q1_PERSISTENCE$group_jaccard > 4 * CP_OVERLAY_Q1_PERSISTENCE$rel14_jaccard_reference,
    sprintf("q1 Jaccard %.3f vs 죽은 rel14 %.3f — **같은 척도로 대조**",
            CP_OVERLAY_Q1_PERSISTENCE$group_jaccard, CP_OVERLAY_Q1_PERSISTENCE$rel14_jaccard_reference))
chk("H3_caveat_admits_weak_test", grepl("약한 지속성 시험", CP_OVERLAY_Q1_PERSISTENCE$caveat) &&
      grepl("미검", CP_OVERLAY_Q1_PERSISTENCE$caveat),
    "★한정을 **계약이 스스로 말한다** — 홀/짝은 약한 시험이고 시대-분할은 미검")
chk("H4_flips_are_in_caution", grepl("CAUTION", CP_OVERLAY_Q1_PERSISTENCE$verdict_flips) &&
      grepl("횡단 0건", CP_OVERLAY_Q1_PERSISTENCE$verdict_flips),
    "판정 흔들림 3/22 가 **전부 CAUTION 밴드** · GO↔NO_GO 횡단 0 — 밴드가 근거를 얻었다")
chk("H5_surfaced_in_verdict", is.list(overlay_q1_precheck(0.148)$persistence),
    "정상 판정이 지속성 근거를 **함께 반환** — 따로 조회해야 알면 dead 배관")
chk("H6_lesson_transferable", grepl("평균", CP_OVERLAY_Q1_PERSISTENCE$lesson) &&
      grepl("argmax|위치", CP_OVERLAY_Q1_PERSISTENCE$lesson),
    "**평균-비중은 지속적·argmax/위치는 아님** — 새 예측자 설계에 이월되는 교훈")

cat(sprintf("\nTOTAL: %d pass / %d fail\n", PASS, FAIL))
cat(sprintf('{"test":"overlay_precheck","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS+FAIL))
if (FAIL > 0L) quit(status = 1L)
