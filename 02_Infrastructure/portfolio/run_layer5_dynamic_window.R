## ============================================================================
## run_layer5_dynamic_window.R — base 오버레이 패널 생성 (측정 윈도 종료월 동적화)
##
## 왜 이 래퍼가 필요한가:
##   원본 05_Production/.../2-1.../01_reproducible_code/run_layer5_rerun_extended.R 은
##   측정 패널 종료월을 **하드코딩**한다:
##       panel_267m_full  <- panel[realized_ym >= "2004-02" & realized_ym <= "2026-06"]
##       panel_255m_admit <- panel[realized_ym >= "2005-02" & realized_ym <= "2026-06"]
##   주석 "[rerun] May/June 포함"이 단서 — 리밸 때마다 사람이 손으로 늘려야 했고,
##   2026-07 리밸에서 아무도 안 고쳐 **7월이 통째로 잘렸다**.
##   실측 피해(2026-08-01): PR 271행 / panel 273행을 정상 산출해놓고 이 필터가 269행으로
##   깎아 period_returns_layer5.csv → live_book_series → 페이퍼 NAV → 차트가 2개월 뒤처졌다.
##   ★그런데 모니터는 "신규 실현월 없음 = 설정 정상"으로 보고했다(침묵 실패).
##
## 왜 사본이 아니라 런타임 치환인가:
##   05_Production 은 수정 금지다. 사본을 만들면 원본과 갈라져 "어느 쪽이 정본인가"가 또
##   생긴다(오늘 D3 미러에서 sha1 대조가 필요했던 이유와 같은 계통). 그래서 원본을 읽어
##   **딱 그 두 줄만** 치환해 실행하고, 치환 대상이 없으면 중단한다 — 원본이 바뀌면
##   조용히 다른 동작을 하는 대신 여기서 멈춘다.
##
## 종료월 = 패널의 ret_orig 유한값이 있는 마지막 realized_ym (실측 종점).
## ============================================================================
suppressPackageStartupMessages({library(data.table)})
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT",
          "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
SRC <- file.path(ROOT, "05_Production/2.Factor_Model",
                 "2-1.STR_1715_AR_on_M4_R05_overlay_PG2/01_reproducible_code",
                 "run_layer5_rerun_extended.R")
if (!file.exists(SRC)) stop("[dynwindow] 원본 부재: ", SRC)

txt <- readLines(SRC, warn = FALSE)

## ── 치환 대상 검증 (없으면 중단 — 원본 변경 시 조용한 오동작 차단) ──────────
pat_full  <- 'panel_267m_full <- panel[realized_ym >= "2004-02" & realized_ym <= "2026-06"]'
pat_admit <- 'panel_255m_admit <- panel[realized_ym >= "2005-02" & realized_ym <= "2026-06"]'
i_full  <- grep(pat_full,  txt, fixed = TRUE)
i_admit <- grep(pat_admit, txt, fixed = TRUE)
if (length(i_full) != 1L || length(i_admit) != 1L)
  stop(sprintf("[dynwindow] 치환 대상 불일치 (full %d건 / admit %d건, 각 1건이어야) — 원본이 바뀌었다. 패치 재확인 필요.",
               length(i_full), length(i_admit)))

## 종료월을 패널 실측 종점에서 파생 + 로그
txt[i_full] <- paste0(
  'PANEL_END_YM <- max(panel$realized_ym, na.rm = TRUE); ',
  'cat(sprintf("  [panel window] 종료월 = %s (동적 — 패널 실측 종점)\\n", PANEL_END_YM)); ',
  'panel_267m_full <- panel[realized_ym >= "2004-02" & realized_ym <= PANEL_END_YM]')
txt[i_admit] <- 'panel_255m_admit <- panel[realized_ym >= "2005-02" & realized_ym <= PANEL_END_YM]'

cat(sprintf("[dynwindow] 원본 %d줄 중 2줄 치환 (L%d, L%d) — 종료월 하드코딩 제거\n",
            length(txt), i_full, i_admit))

## 원본과 동일한 작업 디렉토리·환경에서 실행 (source() 의미론 보존)
old_wd <- getwd(); on.exit(setwd(old_wd), add = TRUE)
setwd(dirname(SRC))
eval(parse(text = paste(txt, collapse = "\n")), envir = globalenv())
cat("[dynwindow] DONE\n")
