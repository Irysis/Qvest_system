#==============================================================================
# factor_stubs.R — FQ-064/065 팩터 선언 스텁 (add_factor 인터페이스 준비)
#
#   ★스텁 목적: 키 랜딩 前 팩터 metadata·방향·category·PIT 규약을 확정 선언.
#   ★왜 실제 add_factor()를 지금 호출하지 않는가(정직 라벨):
#     02_Infrastructure/factor_db/add_factor.R 의 template 엔진(momentum/ratio/trailing_agg…)은
#     RAWDATA 컬럼(Close/Vol/Size/Ret…)에서 계산하는 rawdata-native 팩터 전용이다.
#     FQ-064(국민연금 헤드카운트)·FQ-065(정부조달 수주)는 **외부 패널(data.go.kr)** 을
#     firm_crosswalk로 종목 귀속한 뒤 계산하는 external-source 팩터라, 표준 template로
#     compute 불가 → custom compute 경로(러너 run_fq064/065.R)로 온보딩한다.
#     따라서 여기서는 (a) 선언 메타를 확정하고 (b) 랜딩 시 실행할 add_factor 호출을
#     주석 형태로 사전등록한다(registry 오염·미완 compute 등록 방지).
#
#   실행: bash 02_Infrastructure/ops/safe_run.sh Rscript factor_stubs.R
#         → factor_declarations.json 저장(선언 확정본). add_factor 실호출은 랜딩 후 결정.
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT  <- file.path(ROOT, "stage_artifacts/method_frontier/firm_level_scaffold")

declarations <- list(
  list(
    id            = "NPS_Headcount_Mom_3M",
    fq            = "FQ-064",
    name          = "National Pension headcount momentum 3M",
    category      = "employment_growth",
    direction     = "higher_better",       # 고용 순증 = 확장 → long-side (가설부호; 실측서 검증)
    source        = "data.go.kr:국민연금 사업장 가입자수 (3046071/15071659) + 대안 고용보험 15002150",
    join_key      = "bizr_no (10자리) ↔ firm_crosswalk.parquet ↔ Ticker",
    pit_usable_date = "M+1월 15일 (자격취득 신고마감; 자격취득=익월 15일까지 신고) — C4 유사 lag",
    definition    = "delta_ln( plan-level 가입자수 합산, firm-aggregated ), 3M momentum. 대기업 다-사업장 법인합산 필수. 정규직 편향 정규화(sector/size-residualize).",
    compute_path  = "external: run_fq064_headcount.R (crosswalk join → firm headcount panel → 3M/6M Δln momentum → z-score)",
    evidence_tier = "D",
    landing_call  = "add_factor(id='NPS_Headcount_Mom_3M', name='NPS headcount mom 3M', category='employment_growth', template=NA_external, direction='higher_better', source='data.go.kr_nps', evidence_tier='D', note='external panel; compute via run_fq064_headcount.R'); # ★template 엔진 미적용 — sync_registry=FALSE로 메타만, compute는 러너"
  ),
  list(
    id            = "GovProc_Award_MagYoY",
    fq            = "FQ-065",
    name          = "Government procurement award magnitude YoY",
    category      = "revenue_lead_event",
    direction     = "higher_better",       # 수주 magnitude↑ = 매출 선행 → long-side
    source        = "data.go.kr:나라장터 낙찰/계약 (15129397/15129427/15129466)",
    join_key      = "bizno(낙찰기업 사업자번호) ↔ firm_crosswalk.parquet ↔ Ticker (비상장 자회사→상장모기업 계열매핑 별도)",
    pit_usable_date = "최초 낙찰일(공표시차≈0) — 계약변경분은 최초일 스냅샷 vintage 고정(변경금액 소급 반영 금지)",
    definition    = "TTM 수주금액(낙찰금액 합산, firm+계열 귀속) / 시총, 및 YoY 증가율. 신규 대형계약 magnitude. 건설·방산·IT/SI·의료기기 sector 편중 정규화.",
    compute_path  = "external: run_fq065_procurement.R (crosswalk+계열 join → firm award panel → TTM/시총 + YoY → z-score)",
    evidence_tier = "D",
    landing_call  = "add_factor(id='GovProc_Award_MagYoY', name='Gov procurement award mag YoY', category='revenue_lead_event', template=NA_external, direction='higher_better', source='data.go.kr_g2b', evidence_tier='D', note='external panel; compute via run_fq065_procurement.R; FQ-002 파서 통합'); # ★수주 magnitude=directional long-side, occurrence-only(FQ-002 t=0.59 null)와 구분"
  )
)

write_json(declarations, file.path(OUT, "factor_declarations.json"), pretty = TRUE, auto_unbox = TRUE)
cat("[factor_stubs] 선언 확정:", length(declarations), "팩터 → factor_declarations.json\n")
for (d in declarations) cat(sprintf("  - %s (%s) dir=%s pit=%s\n", d$id, d$fq, d$direction, d$pit_usable_date))
cat("\n★랜딩 후: 러너로 external 패널 검증(canonical PORT_t) → 신호 실재 확인 시에만 add_factor 실호출(메타-only, sync_registry 판단).\n")
