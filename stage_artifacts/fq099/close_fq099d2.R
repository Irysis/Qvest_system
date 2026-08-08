source("02_Infrastructure/contracts/close_round.R")
r <- close_round(
  round_id = "FQ099D2_20260808_REJECTIONS_ON_NON_TTM_PANEL",
  verdict_type = "revival_conditional",
  layer = "1_재료",
  mechanism_diagnosis = paste(
    "★언급 11건의 판정 실태를 확인했다 — 대부분이 기각이며 전부 비-TTM 패널 위에서 내려졌다.",
    "module_catalog 2026-06-06 등재 `STR_<코드>_LO_top25` 단일팩터 롱온리 **grade F** 5건 이상: V10_FCF_Yield · IN01_CapEx_to_Assets · IN02_CapEx_to_Revenue · V15_NetDebt_Adj_EP · V17_Payout_Ratio. judge_gate hard fail 1건: Q10_Gross_Margin(L-780 — MDD 51.01% hard fail, SR 0.503, CAGR 12.4%). alpha_search batch_434 콤보 증류 C/F: V03_CFP · Q01_GPA. defense family 실패: Q24_Altman_Z(L-144).",
    "★내 직전 프레이밍 정밀화 — 오염은 2016+ 에만 있지 않다. **두 시대가 서로 다른 방식으로 왜곡된다**: ①2015 이전 = 전 종목 분기값이라 스케일 혼합은 없으나 **단일 분기값의 계절성 노이즈**가 그대로 신호에 들어간다(기업마다 분기 비중이 달라 횡단면 서열을 교란). TTM 이 존재하는 이유가 정확히 이것이다. ②2016 이후 = 여기에 **스케일 혼합**(연간 vs 동결 분기)이 추가된다. ⇒ **전 역사가 비-TTM 기준으로 측정됐다.**",
    "★주장하지 않는 것(명시): 이 기각들이 뒤집힌다고 말하지 않는다. 확립된 것은 **입력이 비-TTM 이었다**는 사실이고 그로부터 따라오는 것은 **재심이 정당하다**는 처분뿐이다. 결과는 교정 후 측정해야 안다. 단일팩터 롱온리 top25 는 이미 16/16 FAIL posterior 가 있는 형태이므로(CLAUDE.md Project Goals 최후순위) 교정만으로 F 가 A 로 바뀔 것을 기대할 근거는 없다 — 재심의 값은 '이 재료를 버려도 되는가' 의 판단 근거를 오염 없는 것으로 교체하는 데 있다.",
    "★재심 우선순위는 형태로 갈린다: module_catalog 5건은 **단일팩터 standalone** 형태라 사전 확률이 낮다. 반면 Q10_Gross_Margin 은 judge_gate 까지 올라갔고 사유가 **MDD 51.01% 단일**(신호력이 아니라 구조)이므로 screening tier 규약상 `screen_route` 대상이었어야 한다 — 여기가 재심 값이 가장 높다."),
  next_probes = c(
    "FQ-099d2a — Q10_Gross_Margin 재심 최우선. 기각 사유가 MDD 51.01% 단일이면 measurement-graduation §3 의 screening tier 규약상 신호력은 별도 판정이고 overlay 경유 소비면이 열려 있다. 교정 패널로 rank IC 를 재측정해 신호가 실재하는지부터 확인한다.",
    "FQ-099d2b — module_catalog 5건은 단일팩터 standalone 형태이므로 개별 재심보다 **묶어서 한 번** 교정 패널 위 rank IC 스크린. 개별 F 를 뒤집는 게 목적이 아니라 '비-TTM 이 이 계열을 체계적으로 눌렀는가' 를 보는 것이다. 눌렀다면 26건 미평가 코호트의 사전 확률도 함께 올라간다.",
    "FQ-099b(실행 중) 와의 연결 — 099b 가 IC 개선을 보이면 본 재심의 기대값이 직접 상승한다. 두 라운드는 같은 질문의 다른 각도이며 결과를 교차 대조해야 한다."),
  consumer_surfaces = c("팩터랭킹", "선별라벨", "타모드이식"),
  frontier_update = "FQ-099d2 확정: 언급 11건 중 기각 9건+ 이 비-TTM 패널 위 판정 · 오염이 전 역사(2015 이전=계절성, 이후=스케일혼합) · 재심 정당하나 결과 미지 · Q10_Gross_Margin 최우선(구조 사유 기각) · FQ-099d2a/b 신규",
  live_trigger = "수리 완료 시 Q10_Gross_Margin 부터 교정 패널 rank IC 재측정 — 신호 실재 시 overlay 소비면으로 라우팅",
  evidence_refs = c("stage_artifacts/fq099/fq099d2.R",
                    "stage_artifacts/fq099/fq099d_mentioned.txt",
                    "06_Registry/knowledge_index.json")
)
cat("[close_fq099d2] RC_OK\n")
