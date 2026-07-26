# -*- coding: utf-8 -*-
"""pull_nps_files.py — FQ-064 국민연금 사업장 패널 백필 (무인증 파일데이터 경로)
#
#  ★2026-07-25 실측으로 확정된 경로. odcloud API(15083277)는 401 미승인이나 **불필요** —
#    data.go.kr 파일데이터는 로그인·인증키 없이 월별 CSV 전량 다운로드 가능(실측 HTTP 200).
#
#  경로 3단:
#    (1) nps_endpoint_manifest.json 의 uddi (odcloud 경로에서 추출된 것과 동일 식별자)
#    (2) POST /tcs/dss/selectDpkDetailInfo.do (publicDataDetailPk=uddi) → atchFileId 추출
#    (3) GET  /cmm/cmm/fileDownload.do?atchFileId=...&fileDetailSn=1 → CSV (CP949, ~100MB/월)
#
#  디스크 절약: 월별 CSV는 임시 다운로드 → 상장사 매칭분만 남기고 즉시 삭제.
#    전량 보존 시 127월 x ~110MB = 약 14GB이나, 매칭 필터 후 parquet은 수 MB 수준.
#
#  ★식별자 규약(2026-07-25 실측): 사업자등록번호는 **앞 6자리 마스킹**이다.
#    (구 manifest의 'BZOWR_RGST_NO 10자리 비마스킹'은 CSV 헤더의 타입선언 VARCHAR(10)을
#     자릿수로 오독한 것 — 실데이터는 6자리. PIT_plan §3의 마스킹 분기가 실현됨.)
#    따라서 조인 = bizno6 prefix로 후보 축소 후 사업장명 정규화 매칭(startswith 우선).
#    census 실측(2026-06): 474사 중 prefix 존재 474 / 사업장명 매칭 436.
#
#  실행: <venv python> stage_artifacts/method_frontier/firm_level_scaffold/data_pull/pull_nps_files.py
"""
import os, re, io, sys, json, time, urllib.parse, urllib.request, urllib.error
import pandas as pd

ROOT = os.environ.get("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
SCAF = os.path.join(ROOT, "stage_artifacts/method_frontier/firm_level_scaffold")
PULL = os.path.join(SCAF, "data_pull")
MAN  = os.path.join(PULL, "nps_endpoint_manifest.json")
TMP  = os.path.join(ROOT, ".cache/nps_probe")
OUTP = os.path.join(PULL, "nps_headcount_raw.parquet")
os.makedirs(TMP, exist_ok=True)

BASE = "https://www.data.go.kr"
UA = {"User-Agent": "Mozilla/5.0", "Referer": f"{BASE}/data/15083277/fileData.do"}

# ★헤더 스키마가 vintage마다 다르다 (2026-07-25 실측):
#   최신월  : `자료생성년월,사업장명,사업자등록번호,…`            (깨끗한 한글)
#   과거월  : `자료생성년월 DATA_CRT_YM VARCHAR(6),"사업장명 WKPL_NM\tVARCHAR(100)",…`
#             (한글명 + 영문코드 + 타입선언이 한 셀에 뭉쳐 있고 탭·따옴표까지 섞임)
#   → 고정 usecols 이름매칭은 과거월 전량 실패한다. **영문코드를 1순위 키**로 해석하고
#     (영문코드는 전 vintage 불변) 없으면 한글명으로 폴백한다.
#   ※ 구 manifest의 'BZOWR_RGST_NO 10자리'는 이 헤더의 VARCHAR(10)을 자릿수로 오독한 것.
FIELDS = [
    ("data_ym",   "DATA_CRT_YM",    "자료생성년월"),
    ("wkpl_nm",   "WKPL_NM",        "사업장명"),
    ("bizno6",    "BZOWR_RGST_NO",  "사업자등록번호"),
    ("corp_type", "WKPL_STYL_DVCD", "사업장형태구분코드"),
    ("induty",    "WKPL_INTP_CD",   "사업장업종코드"),
    ("hc",        "JNNGP_CNT",      "가입자수"),
    ("amt",       "CRRMM_NTC_AMT",  "당월고지금액"),
    ("acq",       "NW_ACQZR_CNT",   "신규취득자수"),
    ("lss",       "LSS_JNNGP_CNT",  "상실가입자수"),
]
COLS = [f[0] for f in FIELDS]


def resolve_cols(path):
    """헤더 1행만 읽어 (표준명 → 컬럼 위치) 해석. vintage 무관."""
    hdr = pd.read_csv(path, encoding="cp949", nrows=0, low_memory=False)
    raw = list(hdr.columns)
    idx = {}
    for std, eng, kor in FIELDS:
        hit = next((i for i, c in enumerate(raw) if eng in str(c)), None)
        if hit is None:   # 폴백: 한글명 접두 일치(타입선언 없는 최신 vintage)
            hit = next((i for i, c in enumerate(raw) if str(c).strip().startswith(kor)), None)
        if hit is None:
            raise ValueError(f"컬럼 미해석: {std} ({eng}/{kor}) — 헤더 샘플 {raw[:4]}")
        idx[std] = hit
    return idx


def norm(s):
    s = str(s)
    s = re.sub(r"\(주\)|㈜|주식회사|\(유\)|주 식 회 사", "", s)
    return re.sub(r"[\s\-\.,]", "", s)


def post(url, data):
    body = urllib.parse.urlencode(data, encoding="utf-8").encode()
    req = urllib.request.Request(url, data=body, headers=UA)
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read().decode("utf-8", "replace")


def atch_id_for(uddi):
    """uddi → atchFileId (3단 경로 2번째 단계)"""
    html = post(f"{BASE}/tcs/dss/selectDpkDetailInfo.do",
                {"publicDataPk": "15083277", "publicDataDetailPk": uddi})
    # ★실제 마크업은 쉼표 뒤 공백 포함: fn_fileDataDown('15083277', 'uddi:…', 'FILE_…', '1', 'csv')
    #   공백 불허 패턴으로 짰다가 전 월 미검출 → \s* 허용 (2026-07-25 실측 수리)
    m = re.search(r"fn_fileDataDown\(\s*'15083277'\s*,\s*'[^']*'\s*,\s*'(FILE_\d+)'\s*,\s*'(\d+)'", html)
    return (m.group(1), m.group(2)) if m else (None, None)


def download(atch, sn, dst):
    url = f"{BASE}/cmm/cmm/fileDownload.do?atchFileId={atch}&fileDetailSn={sn}&insertDataPrcus=N"
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=600) as r, open(dst, "wb") as f:
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            f.write(chunk)
    return os.path.getsize(dst)


def main():
    xw = pd.read_parquet(os.path.join(SCAF, "firm_crosswalk.parquet"))
    xw["bizno6"] = xw["bizr_no"].astype(str).str.strip().str[:6]
    xw["corp_norm"] = xw["corp_name"].map(norm)
    prefixes = set(xw.bizno6)
    print(f"[pull] crosswalk {len(xw)}사 / prefix {len(prefixes)}", flush=True)

    man = json.load(open(MAN, encoding="utf-8"))
    eps = man["endpoints"]
    # first-release vintage: 같은 data_ym이면 datamonth-label(원 아카이브) 우선
    by_ym = {}
    for e in eps:
        ym, pref = e["data_ym"], (0 if e["label_kind"].startswith("datamonth") else 1)
        if ym not in by_ym or pref < by_ym[ym][0]:
            by_ym[ym] = (pref, e["path"])
    plan = sorted((ym, p) for ym, (_, p) in by_ym.items())
    print(f"[pull] {len(plan)} distinct data_ym (first-release vintage)", flush=True)

    done = set()
    if os.path.exists(OUTP):
        done = set(pd.read_parquet(OUTP, columns=["data_ym"]).data_ym.unique())
        print(f"[pull] 기존 산출 {len(done)}월 — 이어받기", flush=True)

    frames = []
    if done:
        frames.append(pd.read_parquet(OUTP))

    for i, (ym, path) in enumerate(plan, 1):
        if ym in done:  # data_ym 기준 아님(파일 라벨 기준 진행관리)
            continue
        uddi = path.split("/")[-1]          # 'uddi:xxxx'
        try:
            atch, sn = atch_id_for(uddi)
            if not atch:
                print(f"[{i}/{len(plan)}] {ym} SKIP — atchFileId 미검출", flush=True)
                continue
            dst = os.path.join(TMP, f"_tmp_{ym}.csv")
            sz = download(atch, sn, dst)
            idx = resolve_cols(dst)
            df = pd.read_csv(dst, encoding="cp949", usecols=list(idx.values()),
                             dtype=str, low_memory=False)
            df = df.iloc[:, [sorted(idx.values()).index(v) for v in idx.values()]]
            df.columns = COLS
            df["bizno6"] = df.bizno6.astype(str).str.strip().str.zfill(6)
            df = df[df.bizno6.isin(prefixes)].copy()      # prefix 후보만 (디스크 절약)
            for c in ("hc", "amt", "acq", "lss"):
                df[c] = pd.to_numeric(df[c], errors="coerce")
            # ★★data_ym은 **파일 내부 자료생성년월이 유일 권위** — 파일 제목/manifest 라벨로
            #   덮어쓰면 안 된다. 실측(2026-07-25): 제목 '…2015년 12월.csv'의 내부 자료생성년월은
            #   **2015-11**로 한 달 이르다(manifest label_kind의 'extraction-label(prior-month)'과
            #   정합). 계획 ym으로 덮어쓰면 신호가 1개월 미래로 라벨링돼 look-ahead가 된다.
            #   러너 STEP 3의 sig_ym = data_ym + 1 이 내부값 위에서만 PIT 정합.
            df["file_label_ym"] = ym                      # 진단용(라벨 vs 실제 괴리 추적)
            df["wkpl_norm"] = df.wkpl_nm.map(norm)
            frames.append(df)
            print(f"[{i}/{len(plan)}] {ym} OK — {sz/1e6:.0f}MB → 후보 {len(df)}행", flush=True)
        except Exception as ex:
            print(f"[{i}/{len(plan)}] {ym} ERR {type(ex).__name__}: {str(ex)[:140]}", flush=True)
            continue
        finally:
            # 파싱 성공·실패 무관 임시 CSV 제거 (구판은 실패 시 잔존 → 3.5GB 누적 실사고)
            try:
                if os.path.exists(dst):
                    os.remove(dst)
            except Exception:
                pass
        if i % 10 == 0:
            pd.concat(frames, ignore_index=True).to_parquet(OUTP, index=False)
            print(f"[pull] 중간 저장 {OUTP}", flush=True)

    if not frames:
        sys.exit("[pull] 수집 0행 — 경로/네트워크 확인")
    out = pd.concat(frames, ignore_index=True)
    out.to_parquet(OUTP, index=False)
    print(f"[pull] 완료 — {len(out)}행 / {out.data_ym.nunique()}월 → {OUTP}", flush=True)


if __name__ == "__main__":
    main()
