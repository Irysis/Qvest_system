"""test_nps_refresh_append.py — 국민연금(FQ-064) 월 덧붙이기 refresh_nps() 오프라인 시험 (2026-11-10 신설)

왜: 2026-11-10 신선도 CRITICAL(nps_headcount_raw lag 163 > 75) 원인 = 갱신기 결함 3개.
  ① 첫 화면의 현재 파일(pks)이 후보에 없었다 — 이력 목록은 지난 판만 싣는다 → 가장 최근 달이 구조적으로 빠짐
  ② 상세 페이지가 '20NN년 N월'을 더 싣지 않는데(2026-07-23 판부터) 정규식 None 을 기록 없이 건너뜀 → 5개월 새 달 0
  ③ 붙인 뒤 전체에 drop_duplicates → 기존 파일의 같은 키 행(실측 8,038)을 지움(first-release 위반) + pandas 3 의
     large_string 으로 스키마가 바뀜
  + 리뷰 보강: 같은 달 판 2개 = 등록일 이른 판(first-release) · 라벨 달 / 자료 달 공간이 갈리면 넣지 않고 기록
    (2015~2022-09 라벨 = 자료 − 1개월 · 63달 실측).
네트워크를 쓰지 않는다 — 포털 조회(urlopen · _post)와 내려받기(_nps_download)를 가짜로 바꾸고 합성 자료로 잰다.
축: A 새 달 덧붙이기 · B 기존 행 바이트 동일 · C 스키마 동일 · D 해석 캐시(두 번째 실행 noop · 내려받기 0) · E 임시 파일 정리 ·
    F 같은 달 판 2개 · G 공간 불일치 · M1~M5 돌연변이(고친 곳을 되돌리면 해당 축이 걸린다 · 치환 성사 단정).
실행: .venv_qvest_ml/Scripts/python.exe -X utf8 08_Tests/data/test_nps_refresh_append.py   (운영 파일 쓰기 0)
"""
import importlib.util
import json
import os
import sys
import tempfile
import types
from pathlib import Path

# ── 해석기 자기해결 — 시스템 파이썬(QVEST_PY)에는 pandas · pyarrow 가 없다 → venv 로 다시 실행(SKIP 하지 않는다)
try:
    import pandas as _pd_probe  # noqa: F401
    import pyarrow as _pa_probe  # noqa: F401
except ImportError:
    import subprocess as _sp
    _venv = ""
    for _cand in (str(Path(__file__).resolve().parents[2]), os.environ.get("CLAUDE_PROJECT_DIR", ""), os.environ.get("QM_ROOT", "")):
        _p = os.path.join(_cand.replace("\\", "/"), ".venv_qvest_ml", "Scripts", "python.exe") if _cand else ""
        if _p and os.path.exists(_p):
            _venv = _p
            break
    if _venv and os.environ.get("_QVEST_VENV_REEXEC") != "1":
        sys.exit(_sp.call([_venv, "-X", "utf8", os.path.abspath(__file__)] + sys.argv[1:], env=dict(os.environ, _QVEST_VENV_REEXEC="1")))
    raise

import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq

ROOT = Path(__file__).resolve().parents[2]
SUT = ROOT / "02_Infrastructure" / "data" / "refresh_nonreturn_sources.py"
PASS = FAIL = 0


def chk(name, cond, note=""):
    global PASS, FAIL
    if cond:
        PASS += 1; print(f"  PASS  {name}")
    else:
        FAIL += 1; print(f"  ★FAIL {name}  {note}")


U = lambda tag: f"uddi:{tag * 8}-0000-0000-0000-00000000000{tag[0]}"
CUR, OLD1, OLD2, NEW1, NEW2 = U("c"), U("a"), U("d"), U("b"), U("e")
HDR = ["자료생성년월(DATA_CRT_YM)", "사업장명(WKPL_NM)", "사업자등록번호(BZOWR_RGST_NO)", "사업장형태구분코드(WKPL_STYL_DVCD)",
       "사업장업종코드(WKPL_INTP_CD)", "가입자수(JNNGP_CNT)", "당월고지금액(CRRMM_NTC_AMT)", "신규취득자수(NW_ACQZR_CNT)", "상실가입자수(LSS_JNNGP_CNT)"]
# 시나리오 = 첫 화면 현재 파일 · 이력 목록 · uddi 별 등록일(상세 페이지) · uddi 별 파일 내용(자료 달 · 가입자수 표지)
S0 = {"cur": CUR, "hist": [OLD1, NEW1], "reg": {CUR: "2026-09-23", NEW1: "2026-08-25"},
      "files": {CUR: ("2026-07", 12), NEW1: ("2026-06", 12)}}
S1 = {"cur": CUR, "hist": [OLD1, NEW1, NEW2], "reg": {CUR: "2026-09-23", NEW1: "2026-08-25", NEW2: "2026-08-30"},
      "files": {CUR: ("2026-07", 12), NEW1: ("2026-06", 12), NEW2: ("2026-07", 99)}}      # 07 판 2개 — NEW2 가 먼저 등록


def build_root(td, shifted=False):
    scaf = Path(td) / "stage_artifacts/method_frontier/firm_level_scaffold"
    (scaf / "data_pull").mkdir(parents=True)
    pd.DataFrame({"bizr_no": ["1234560000", "6543210000"]}).to_parquet(scaf / "firm_crosswalk.parquet", index=False)
    # 기존 패널 — 같은 키(달 · 앞자리 · 사업장명) 행 2개 포함(서로 다른 사업장 — 구판 전체 중복 제거가 지우던 형태).
    #   shifted = 라벨 2026-05 의 자료 달이 2026-06(2015~2022-09 의 라벨 = 자료 − 1 형태)
    d05 = "2026-06" if shifted else "2026-05"
    old = pd.DataFrame({"data_ym": ["2026-04", "2026-04", "2026-04", d05], "wkpl_nm": ["가나", "가나", "다라", "가나"],
                        "bizno6": ["123456", "123456", "654321", "123456"], "corp_type": ["1", "1", "2", "1"],
                        "induty": ["A", "B", "C", "A"], "hc": [10, 3, 7, 11], "amt": [100, 30, 70, 110], "acq": [1, 0, 1, 2],
                        "lss": [0, 1, 0, 1], "file_label_ym": ["2026-04", "2026-04", "2026-04", "2026-05"],
                        "wkpl_norm": ["가나", "가나", "다라", "가나"]})
    tbl = pa.Table.from_pandas(old, preserve_index=False)
    tbl = tbl.cast(pa.schema([pa.field(f.name, pa.string() if pa.types.is_string(f.type) or pa.types.is_large_string(f.type) else f.type)
                              for f in tbl.schema], metadata=tbl.schema.metadata))   # 운영 파일과 같은 string(구 판)
    pq.write_table(tbl, scaf / "data_pull/nps_headcount_raw.parquet")
    man = {"endpoints": [{"data_ym": "2026-04", "path": f"/15083277/v1/{OLD1}"}, {"data_ym": "2026-05", "path": f"/15083277/v1/{OLD2}"}]}
    (scaf / "data_pull/nps_endpoint_manifest.json").write_text(json.dumps(man), encoding="utf-8")
    return scaf / "data_pull/nps_headcount_raw.parquet"


def load(td, sc, src_text=None):
    os.environ["QM_ROOT"] = td
    if src_text is None:
        spec = importlib.util.spec_from_file_location("rns_test", SUT)
        M = importlib.util.module_from_spec(spec); spec.loader.exec_module(M)
    else:
        M = types.ModuleType("rns_mut"); M.__file__ = str(SUT)
        exec(compile(src_text, str(SUT), "exec"), M.__dict__)
    calls = {"download": 0}

    class _Resp:
        def __init__(self, s): self.s = s.encode("utf-8")
        def read(self, *a): return self.s
        def __enter__(self): return self
        def __exit__(self, *a): return False

    M.urllib.request.urlopen = lambda req, timeout=None: _Resp(f"<a href='x'>{sc['cur']}</a>")

    def _post(url, data):
        u = data.get("publicDataDetailPk")
        if "selectHistAndCsvData" in url:
            return "".join(f"<li>{h}</li>" for h in sc["hist"])
        r = sc["reg"].get(u, "2026-01-01")
        return (f"<div>국민연금공단_국민연금 가입 사업장 내역 등록일 <span>{r}</span> 수정일 {r} 차기 등록 예정일 2026-12-20 "
                f"fn_fileDataDown('15083277', '{u}', 'FILE_1', '1', 'csv')</div>")
    M._post = _post

    def _dl(html, dst):
        calls["download"] += 1
        u = next(k for k in sc["files"] if k in html)
        ym, hc = sc["files"][u]
        rows = [[ym, "가나", "123456", "1", "A", str(hc), "120", "1", "0"], [ym, "가나", "123456", "1", "A", str(hc), "120", "1", "0"],
                [ym, "마바", "999999", "1", "Z", "5", "50", "0", "0"]]           # 중복 1행 · 교차표 밖 1행(실제 열 = 사업자번호 앞 6자리)
        pd.DataFrame(rows, columns=HDR).to_csv(dst, index=False, encoding="cp949")
    M._nps_download = _dl
    return M, calls


def run(sc, src_text=None, shifted=False, twice=False):
    """한 시나리오를 임시 루트에서 돌리고 사실(dict)을 돌려준다."""
    with tempfile.TemporaryDirectory() as td:
        td = td.replace("\\", "/")
        P = build_root(td, shifted)
        before = pq.read_table(P)
        M, calls = load(td, sc, src_text)
        f = {"err": None, "r": None}
        try:
            f["r"] = M.refresh_nps()
        except Exception as ex:
            f["err"] = ex
        after = pq.read_table(P)
        f.update(before=before, after=after, labels=sorted(set(after.column("file_label_ym").to_pylist())),
                 hc={k: sorted(set(after.filter(pa.compute.equal(after.column("file_label_ym"), k)).column("hc").to_pylist()))
                     for k in set(after.column("file_label_ym").to_pylist())})
        cache = Path(td) / ".cache/nps_probe/uddi_month_resolved.json"
        f["cache"] = json.loads(cache.read_text(encoding="utf-8")) if cache.exists() else {}
        if twice and f["err"] is None:
            d0 = calls["download"]
            f["r2"] = M.refresh_nps()
            f["dl2"] = calls["download"] - d0
        f["left"] = sorted(x.name for x in (Path(td) / ".cache/nps_probe").glob("_*.csv"))
    os.environ.pop("QM_ROOT", None)
    return f


def main():
    import pyarrow.compute  # noqa: F401  (run() 의 pa.compute)
    src = SUT.read_text(encoding="utf-8")
    print("── S0 기본 — 현재 파일 + 이력 새 달 1(둘 다 내용 해석)")
    f = run(S0, twice=True)
    b, a = f["before"], f["after"]
    chk("A1 새 달 2개 덧붙임 — 현재 파일(2026-07) · 내용 해석(2026-06)", f["err"] is None and f["r"].get("added_months") == ["2026-06", "2026-07"]
        and f["labels"] == ["2026-04", "2026-05", "2026-06", "2026-07"], f"{f['err']!r} {f['r']}")
    chk("A2 새 달 안 중복 · 교차표 밖 행 제거(달마다 1행)", a.num_rows == b.num_rows + 2, f"{b.num_rows} → {a.num_rows}")
    chk("B1 기존 행 바이트 동일(같은 키 행 2개 포함)", a.slice(0, b.num_rows).equals(b))
    chk("C1 스키마 동일(string — large_string 아님 · 메타데이터 포함)", a.schema.equals(b.schema, check_metadata=True), str(a.schema))
    chk("D1 해석 캐시 = (uddi · 수정일) 키 2건 · 내용 해석 표지", len(f["cache"]) == 2 and all(v["resolved_by"].startswith("content") for v in f["cache"].values())
        and all(k.endswith(("|2026-09-23", "|2026-08-25")) for k in f["cache"]), str(f["cache"]))
    chk("D2 두 번째 실행 = noop · 내려받기 0(캐시 적중)", f.get("r2", {}).get("action") == "noop" and f.get("dl2") == 0, f"{f.get('r2')} · 다운로드 {f.get('dl2')}")
    chk("D3 진단 필드 — 해석 실패 0 · 공간 불일치 없음", f["r"].get("resolve_failed") == 0 and f["r"].get("ambiguous_months") == [], str(f["r"]))
    chk("E1 받은 임시 CSV 정리(남은 것 없음)", not f["left"], str(f["left"]))
    print("── S1 같은 달 판 2개 — 07 = 현재 파일(등록 09-23) · 이력 NEW2(등록 08-30 · 가입자 99)")
    f = run(S1)
    chk("F1 등록일 이른 판(NEW2) 적재 — 07 가입자수 = 99(first-release)", f["err"] is None and f["hc"].get("2026-07") == [99]
        and f["r"].get("added_months") == ["2026-06", "2026-07"], f"{f['err']!r} hc={f['hc']} r={f['r']}")
    chk("F2 늦은 판의 받은 파일도 정리", not f["left"], str(f["left"]))
    print("── S2 공간 불일치 — 기존 라벨 05 의 자료 달 = 06(라벨 = 자료 − 1 형태) · 새 파일 자료 06")
    f = run(S0, shifted=True)
    chk("G1 자료 달 06 = 자료 공간 보유 · 라벨 공간 없음 → 넣지 않고 기록 · 07 은 정상 적재", f["err"] is None
        and f["r"].get("added_months") == ["2026-07"] and f["r"].get("ambiguous_months") == ["2026-06"]
        and f["labels"] == ["2026-04", "2026-05", "2026-07"], f"{f['err']!r} {f['r']} labels={f['labels']}")
    # ── 돌연변이 — 고친 곳을 되돌리면 해당 축이 걸린다(치환 성사 단정)
    GLOBAL_DEDUP = ("        out = pd.concat([old, new_part[list(old.columns)]], ignore_index=True)\n",
                    "        out = pd.concat([old, new_part[list(old.columns)]], ignore_index=True).drop_duplicates(subset=[\"file_label_ym\", \"bizno6\", \"wkpl_nm\"], keep=\"first\")\n")
    NO_GUARD = ("        if tbl.num_rows != len(old) + len(new_part):\n", "        if False:\n")
    muts = [
        ("M1 전체 중복 제거 + 행 수 지킴이 없음(구판) → 기존 행 변경 검출", [GLOBAL_DEDUP, NO_GUARD], S0, False,
         lambda f: f["err"] is None and not f["after"].slice(0, f["before"].num_rows).equals(f["before"])),
        ("M1b 전체 중복 제거만(지킴이 남김) → 행 수 지킴이가 쓰기 전에 멈춘다", [GLOBAL_DEDUP], S0, False,
         lambda f: isinstance(f["err"], RuntimeError) and "행 수 불일치" in str(f["err"]) and f["after"].equals(f["before"])),
        ("M2 현재 파일 빠짐(구판) → 2026-07 빠짐 검출", [("all_uddi = list(dict.fromkeys(pks + hist_uddi))", "all_uddi = list(dict.fromkeys(hist_uddi))")], S0, False,
         lambda f: f["err"] is None and "2026-07" not in f["labels"]),
        ("M3 내용 해석 없음(구판 — 기록 없이 건너뜀) → 2026-06 · 07 빠짐 검출", [("                ym = _nps_content_month(d, dst)\n", "                continue\n")], S0, False,
         lambda f: f["err"] is None and "2026-06" not in f["labels"]),
        ("M4 등록일 정렬 없음 → 07 이 늦은 판(가입자 12)으로 검출", [("    details.sort(key=lambda x: (_stamp(x[1], \"등록일\") or \"9999-99-99\", x[0]))\n", "    pass\n")], S1, False,
         lambda f: f["err"] is None and f["hc"].get("2026-07") == [12]),
        ("M5 자료 공간 무시(라벨만) → 06 이 겹쳐 들어감 검출", [("            in_l, in_d = ym in have_set, ym in have_data\n", "            in_l, in_d = ym in have_set, ym in have_set\n")], S0, True,
         lambda f: f["err"] is None and "2026-06" in f["labels"]),
    ]
    print("── 돌연변이")
    for name, pairs, sc, shifted, caught in muts:
        bad = [a_[:48] for a_, _ in pairs if src.count(a_) != 1]
        if bad:
            chk(f"{name} — 치환 성사", False, f"대상 수 ≠ 1: {bad}"); continue
        msrc = src
        for a_, b_ in pairs:
            msrc = msrc.replace(a_, b_)
        f = run(sc, msrc, shifted=shifted)
        chk(name, caught(f), f"err={type(f['err']).__name__ if f['err'] else None} · labels {f['labels']} · hc {f['hc']}")
    print(f"\n[test_nps_refresh_append] {PASS} passed, {FAIL} failed")
    print(json.dumps({"test": "nps_refresh_append", "pass": PASS, "fail": FAIL, "total": PASS + FAIL}))
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
