# -*- coding: utf-8 -*-
# pull_nps.py — FQ-064 국민연금 가입 사업장 내역(data.go.kr 15083277) 월별 패널 pull
#
#   ★KEY-GATED: DATA_GO_API_KEY가 odcloud 데이터셋 15083277에 활용신청(활성화)되어야 동작.
#     현재 상태(2026-07-25 실측): -401 "유효하지 않은 인증키" → 도훈 활용신청 대기(access_gate).
#     nara jangteo(apis.data.go.kr/1230000)엔 유효하나 odcloud/15083277 미승인.
#
#   엔드포인트: https://api.odcloud.kr/api/15083277/v1/uddi:...?page&perPage&serviceKey
#   backfill 실측: 128 endpoint / 124 distinct data_ym / 2015-12 ~ 2026-05 (결측 2020-04, 2022-10)
#   행 스키마: DATA_CRT_YM, WKPL_NM, BZOWR_RGST_NO(10자리), JNNGP_CNT(가입자수),
#             NW_ACQZR_CNT, LSS_JNNGP_CNT, WKPL_STYL_DVCD(1법인2개인), WKPL_JNNG_STCD(1등록2탈퇴), WKPL_INTP_CD
#   PIT vintage(PIT_plan §2): 중복 data_ym은 first-release(가장 이른 추출본) 보존. 개정 소급 금지.
#
#   실행: <venv python> stage_artifacts/method_frontier/firm_level_scaffold/data_pull/pull_nps.py
import os, re, sys, json, time, urllib.parse, urllib.request
import pyarrow as pa, pyarrow.parquet as pq

ROOT = os.environ.get("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
SCAF = os.path.join(ROOT, "stage_artifacts/method_frontier/firm_level_scaffold")
PULL = os.path.join(SCAF, "data_pull")
MAN  = os.path.join(PULL, "nps_endpoint_manifest.json")
OUTP = os.path.join(PULL, "nps_headcount_raw.parquet")

# --- key from .env (하드코딩·재노출 금지) ---
key = None
for line in open(os.path.join(ROOT, ".env"), encoding="utf-8"):
    if line.startswith("DATA_GO_API_KEY="):
        key = line.split("=", 1)[1].strip()
if not key:
    sys.exit("[pull_nps] DATA_GO_API_KEY .env 부재")

man = json.load(open(MAN, encoding="utf-8"))
eps = man["endpoints"]

# first-release vintage: 중복 data_ym이면 datamonth-label(구 아카이브)·이른 추출본 우선
by_ym = {}
for e in eps:
    ym = e["data_ym"]
    pref = 0 if e["label_kind"].startswith("datamonth") else 1
    if ym not in by_ym or pref < by_ym[ym][0]:
        by_ym[ym] = (pref, e["path"])
plan = sorted((ym, p) for ym, (_, p) in by_ym.items())
print(f"[pull_nps] {len(plan)} distinct data_ym to pull (first-release vintage)")

def fetch(path, page, per=10000):
    url = f"https://api.odcloud.kr/api{path}?page={page}&perPage={per}&serviceKey={urllib.parse.quote(key, safe='')}&returnType=JSON"
    with urllib.request.urlopen(url, timeout=90) as r:
        return json.loads(r.read().decode("utf-8"))

rows = []
for ym, path in plan:
    page = 1
    while True:
        try:
            d = fetch(path, page)
        except urllib.error.HTTPError as ex:
            if ex.code == 401:
                sys.exit("[pull_nps] ★401 Unauthorized — DATA_GO_API_KEY가 odcloud 데이터셋 "
                         "15083277에 미승인. 도훈 활용신청 필요(access_gate=dohoon_apply_datagokr_15083277). "
                         "엔드포인트·backfill(2015-12~2026-05, 124월)·스키마는 확인됨.")
            sys.exit(f"[pull_nps] HTTP 실패 {ym} p{page}: {ex}")
        except Exception as ex:
            sys.exit(f"[pull_nps] HTTP 실패 {ym} p{page}: {ex}")
        if "code" in d and d.get("code") not in (None, 0):
            sys.exit(f"[pull_nps] ★API 오류 {ym}: {d}  (활용신청/키 승인 확인 — access_gate)")
        data = d.get("data") or []
        for x in data:
            g = lambda pfx: next((v for k, v in x.items() if k.startswith(pfx)), None)
            styl = str(g("사업장형태구분코드") or "")
            rows.append({
                "bizr_no": re.sub(r"\D", "", str(g("사업자등록번호") or "")),
                "data_ym": (str(g("자료생성년월") or ym.replace("-", ""))[:6]),
                "member_cnt": g("가입자수"),
                "new_acq": g("신규취득자수"),
                "lost": g("상실가입자수"),
                "styl": styl,                     # 1:법인 2:개인
                "jnng_stcd": str(g("사업장가입상태코드") or ""),   # 1:등록 2:탈퇴
                "intp_cd": str(g("사업장업종코드") or ""),
            })
        got = d.get("currentCount", len(data))
        if got < 10000:
            break
        page += 1
        time.sleep(0.05)
    print(f"[pull_nps] {ym}: cum rows={len(rows)}")

# 정규화: data_ym YYYYMM -> YYYY-MM, 법인(styl==1) 유지 라벨은 러너에서 결정(여기선 전량 보존)
for r in rows:
    dy = r["data_ym"]
    r["data_ym"] = f"{dy[:4]}-{dy[4:6]}" if len(dy) == 6 else dy
    r["bizr_no"] = r["bizr_no"].zfill(10) if r["bizr_no"] else None

tbl = pa.Table.from_pylist(rows)
pq.write_table(tbl, OUTP)
print(f"[pull_nps] ✅ wrote {OUTP}  rows={len(rows)}  months={len(plan)}")
print("[pull_nps] 다음: bash 02_Infrastructure/ops/safe_run.sh Rscript "
      "stage_artifacts/method_frontier/firm_level_scaffold/run_fq064_headcount.R")
