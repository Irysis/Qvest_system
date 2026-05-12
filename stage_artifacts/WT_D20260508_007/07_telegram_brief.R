#==============================================================================
# WT-D20260508_007 — Step 7: Telegram brief (v6.2 SOT)
#==============================================================================
suppressPackageStartupMessages({
  library(jsonlite)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
source(file.path(PROJ, "02_Infrastructure", "telegram", "telegram_notify.R"))

# Build sections
sections <- list(
  list(emoji = "📌",
       heading = "12개월 horizon 단일 거시 알파 검증",
       type = "summary",
       body = "WT_005 12M 부분 신호 정식 검증 — Harvey-NW HAC 미달, 비졸업 연구 증거"),

  list(emoji = "📊",
       heading = "12M 핵심 지표",
       type = "kv",
       kv = list(
         "정보계수 ICIR" = "0.317 (>0.20 PASS)",
         "Harvey 단순 t" = "3.88 (PASS)",
         "Harvey HAC t lag12" = "1.66 (FAIL <3.0)",
         "부기간 사인" = "3/3 (+ unanimous)",
         "엄격 ICIR p2" = "0.125 fail / p1 p3 PASS",
         "DSR N=30 z" = "1.85 PASS",
         "DSR N=50 z" = "1.64 (p=0.05 경계)",
         "블록 부트스트랩 p" = "0.027 PASS",
         "직교성 LS" = "0.149 PASS / LO20 0.58 fail"
       )),

  list(emoji = "🚩",
       heading = "Challenge Flags 핵심",
       type = "bullet",
       items = c(
         "RF Harvey-NW HAC lag4-18 1.66~1.96 (균일 fail)",
         "RF-A3 active: p3 0.610 / overall 0.317 = 1.92",
         "직교성 LO_top20 0.581 (AX-007 break)",
         "C13 literal Z_Score_Aligned 미충족 (inherited)",
         "C14/C15 documented exception inherited"
       )),

  list(emoji = "➡️",
       heading = "다음 단계",
       type = "bullet",
       items = c(
         "Risk Agent 미spawn (Q-Lead 결정 대기)",
         "후속 path: WT_006 IPCA / multi-feature ML / LS sleeve / multi-sleeve",
         "Forward 2026-05 Top-20 LO 보존 (건강관리/SW/IT-HW cluster)"
       ))
)

result <- tg_agent_brief(
  agent = "Alpha",
  title = "WT-D20260508_007 ALPHA_DONE — 12M long-horizon non-graduating evidence",
  as_of = "2026-05-08",
  sections = sections,
  footer = "Codex REVISE / 6 ACCEPT + 2 PARTIAL + 1 REBUTTAL / escalate 미발동"
)

cat(sprintf("[07] Telegram dispatch: ok=%s, bytes=%s\n",
            result$ok, ifelse(is.null(result$bytes), "NULL", result$bytes)))
if (!result$ok) cat(sprintf("[07] error: %s\n", result$error))
