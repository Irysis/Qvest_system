# -*- coding: utf-8 -*-
"""quantiwise_fetch.py — QuantiWise 정본 xlsx 수급 진입점 (2026-09-18)

★왜 (도훈 2026-09-18): 벤치마크 정본은 `03_Universe/Benchmark_price.xlsx` 다.
  그 파일이 2026-07-01 이후 안 들어오는 사이, 일일 배관은 **조용히 Naver 로 때우며**
  옛 리베이스 체인 위에 매일 값을 얹었다. `.cache/indices.parquet` 이 06-30 에 멈춘 것도
  같은 원인이다. 정본이 멈춘 것을 아무도 못 본 것 — 그것이 모든 재발의 온상이었다.
  ⇒ 수급을 **하나의 진입점**으로 만들고, 성공/실패/전제부재를 전부 상태 JSON 에 남긴다.
    daily_refresh 는 이것을 먼저 부르고, 실패하면 조용히 넘어가지 않고 stale 로 신고한다.

★수급 방식 — **인터넷이 아니라 이 PC 안**이다 (도훈: "퀀티 자동 로그인 가능하잖아").
  초판(09-18 오전)은 "로그인 절차 미구현" 으로 남겨 뒀지만, 실물을 찾아보니 배관이 이미
  전부 깔려 있었다. 새로 만들 것이 없다 — 있는 길을 부르기만 하면 된다:

    (1) 단말       C:\\WISEfn\\Quantiwise\\Quantiwise.exe  (FnGuide Quantiwise 7G)
    (2) 자동로그인  C:\\WISEfn\\Common\\Data\\maincfg.ini  [LOGIN] SAVEID=1·SAVEUSERPW=1·LOGINCOMPLETE=1
                   ★코드는 **플래그만** 본다. ID/PW 값은 읽지도, 로그·상태 JSON 에 남기지도 않는다.
                   (그래서 QW_USER/QW_PASS 같은 환경변수 계약은 폐기됐다 — 자격은 단말이 갖는다)
    (3) 엑셀 애드인 "Quantiwise For Excel" (VSTO · LoadBehavior=3)
    (4) 질의 시트  Benchmark_price.xlsx 자체가 퀀티 질의서다 — A1 이 하이퍼링크("Refresh"),
                   B5 Period(From)=19900103, **B6 Period(To)=CPD-1TD(직전 영업일)**.
                   상대 토큰이라 날짜를 박을 필요가 없다: 누를 때마다 어제까지 채워진다.

  실행 경로 = `qw_excel_refresh.ps1` (엑셀 COM + 애드인 이벤트). 이 파일은 그 드라이버를
  부르고, 받은 작업본을 **검증한 뒤에만** 정본 자리에 원자적으로 올린다.

사용:
  python 02_Infrastructure/data/quantiwise_fetch.py [--dest PATH] [--status-only]
                                                    [--timeout-sec N] [--visible]
종료코드:
  0 = 새 정본을 받아 교체했다
  2 = 받을 것이 없다(원격이 이미 우리 것과 같음) — 실패 아님
  3 = **전제 부재**(단말·애드인·자동로그인 미설정) — 호출부는 'stale 신고' 로 처리할 것
  1 = 수급 실패(세션·검증 실패). 기존 파일은 손대지 않았다.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

PROJECT_ROOT = Path(
    os.environ.get('CLAUDE_PROJECT_DIR') or os.environ.get('QM_ROOT')
    or Path(__file__).resolve().parents[2]
)
DEST = PROJECT_ROOT / '03_Universe' / 'Benchmark_price.xlsx'
STATUS_PATH = PROJECT_ROOT / '.cache' / 'quantiwise_fetch_status.json'
PS_DRIVER = Path(__file__).resolve().with_name('qw_excel_refresh.ps1')

# 드라이버 종료코드 → 의미 (qw_excel_refresh.ps1 헤더와 같은 표)
RC_UPDATED, RC_FAILED, RC_NO_CHANGE, RC_NO_PRECONDITION = 0, 1, 2, 3


def _write_status(payload: dict) -> None:
    """상태 사이드카 — 로그는 흘러가지만 파일은 남는다(게이트 축 D 가 읽을 수 있다)."""
    try:
        STATUS_PATH.parent.mkdir(parents=True, exist_ok=True)
        tmp = str(STATUS_PATH) + f'.tmp{os.getpid()}'
        with open(tmp, 'w', encoding='utf-8') as fh:
            json.dump(payload, fh, ensure_ascii=False, indent=2)
        os.replace(tmp, str(STATUS_PATH))
    except Exception:
        pass


def _describe_generic(path: Path) -> dict:
    """벤치 외 퀀티 질의서(예: 03_Universe/Update_File/*_update.xlsx)의 지문.

    ★이 파일들도 **같은 질의서**다 — A1 이 'Refresh' 하이퍼링크이고 B5/B6 이 Period(From/To).
      다만 시트가 여럿이라 갱신 범위가 Book 이고, 지수 파서로는 못 읽는다.
      그래서 여기서는 **첫 시트 A열의 마지막 날짜**만 본다(교체 판정에 필요한 최소량).
    """
    d = {'path': str(path), 'exists': path.exists(), 'kind': 'generic'}
    if not path.exists():
        return d
    st = path.stat()
    d['size_bytes'] = int(st.st_size)
    d['mtime'] = datetime.fromtimestamp(st.st_mtime).isoformat(timespec='seconds')
    try:
        import openpyxl
        wb = openpyxl.load_workbook(path, read_only=True, data_only=True)
        try:
            ws = wb.worksheets[0]
            last, n = None, 0
            for (v,) in ws.iter_rows(min_col=1, max_col=1, values_only=True):
                if v is None:
                    continue
                try:
                    dt = datetime.fromisoformat(str(v)[:19])
                except ValueError:
                    continue
                n += 1
                if last is None or dt > last:
                    last = dt
        finally:
            wb.close()
        d['rows'] = n
        if last is not None:
            d['date_max'] = last.strftime('%Y-%m-%d')
    except Exception as e:
        d['read_error'] = f'{e.__class__.__name__}: {e}'
    return d


def _describe(path: Path) -> dict:
    """정본 파일의 소비면 지문 — mtime · 크기 · (읽을 수 있으면) 행수·최신일."""
    if Path(path).resolve() != DEST.resolve():
        return _describe_generic(Path(path))     # 벤치가 아니면 지수 파서를 쓰지 않는다
    d = {'path': str(path), 'exists': path.exists()}
    if not path.exists():
        return d
    st = path.stat()
    d['size_bytes'] = int(st.st_size)
    d['mtime'] = datetime.fromtimestamp(st.st_mtime).isoformat(timespec='seconds')
    try:
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        import benchmark_axis as BA
        ref = BA.load_quantiwise_kospi200(path)
        d['rows'] = int(len(ref))
        if len(ref):
            d['date_min'] = ref['Date'].min().strftime('%Y-%m-%d')
            d['date_max'] = ref['Date'].max().strftime('%Y-%m-%d')
    except Exception as e:
        d['read_error'] = f'{e.__class__.__name__}: {e}'
    return d


def _fetch_impl(workdir: Path, timeout_sec: int, visible: bool,
                target: Path = DEST, scope: str = 'sheet') -> Path | None:
    """실제 수급 — 퀀티 단말 + 엑셀 애드인으로 정본 시트를 다시 받아온다.

    계약:
      · 자격증명은 **단말이** 갖는다. 이 코드는 플래그조차 드라이버에게 맡기고 값을 모른다.
      · 내려받기는 `workdir` 안에서 끝낸다 — 정본 경로에 직접 쓰지 않는다.
        교체는 호출자(main)가 검증 후 원자적으로 한다.
      · 받을 것이 없으면 None 을 돌려준다(= 종료코드 2).
      · 전제(단말·애드인·자동로그인)가 없으면 NotImplementedError — 호출부가 stale 로 신고한다.
    """
    if not PS_DRIVER.exists():
        raise RuntimeError(f'드라이버 부재: {PS_DRIVER}')
    if os.name != 'nt':
        raise NotImplementedError('퀀티 단말 경로는 Windows 전용이다(이 호스트는 아니다)')

    out = workdir / (target.stem + '.new' + target.suffix)
    jout = workdir / 'refresh_result.json'
    for p in (out, jout):
        try:
            p.unlink()
        except FileNotFoundError:
            pass

    cmd = ['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(PS_DRIVER),
           '-Source', str(target), '-Out', str(out), '-TimeoutSec', str(int(timeout_sec)),
           '-Scope', scope.capitalize(), '-JsonOut', str(jout)]
    if visible:
        cmd.append('-Visible')

    print(f'  드라이버 실행: {PS_DRIVER.name} (timeout {timeout_sec}s)')
    proc = subprocess.run(cmd, capture_output=True, text=True,
                          encoding='utf-8', errors='replace',
                          timeout=timeout_sec + 300)
    for line in (proc.stdout or '').splitlines():
        if line.strip():
            print(f'    {line.rstrip()}')
    detail = {}
    if jout.exists():
        try:
            detail = json.loads(jout.read_text(encoding='utf-8-sig'))
        except Exception:
            pass
    _fetch_impl.last_detail = detail          # main 이 상태 JSON 에 싣는다

    rc = proc.returncode
    msg = str(detail.get('message') or (proc.stderr or '').strip() or f'rc={rc}')
    if rc == RC_NO_PRECONDITION:
        raise NotImplementedError(f'{detail.get("result", "no_precondition")} — {msg}')
    if rc == RC_NO_CHANGE:
        return None
    if rc != RC_UPDATED:
        raise RuntimeError(f'{detail.get("result", "failed")} — {msg}')
    if not out.exists():
        raise RuntimeError('드라이버가 성공을 보고했는데 결과 파일이 없다')
    return out


_fetch_impl.last_detail = {}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--dest', default=str(DEST))
    ap.add_argument('--status-only', action='store_true',
                    help='수급하지 않고 현재 정본의 지문만 기록·출력한다')
    ap.add_argument('--timeout-sec', type=int, default=1800,
                    help='시트 Refresh 완료 대기 상한(기본 1800초)')
    ap.add_argument('--scope', choices=['sheet', 'book'], default='sheet',
                    help="갱신 범위. 질의 시트가 여럿인 통합문서(Update_File 계열)는 book")
    ap.add_argument('--visible', action='store_true',
                    help='엑셀 창을 띄운 채 돌린다(사람이 지켜볼 때·진단용)')
    args = ap.parse_args()
    dest = Path(args.dest)

    before = _describe(dest)
    print(f'[quantiwise_fetch] 정본 = {dest}')
    print(f'  현재: rows={before.get("rows", "?")} '
          f'date_max={before.get("date_max", "?")} mtime={before.get("mtime", "?")}')

    if args.status_only:
        _write_status({'schema': 'quantiwise_fetch_status_v1', 'result': 'status_only',
                       'at': datetime.now().isoformat(timespec='seconds'), 'before': before})
        return 0

    workdir = PROJECT_ROOT / '.cache' / '_qw_fetch'
    workdir.mkdir(parents=True, exist_ok=True)
    try:
        got = _fetch_impl(workdir, args.timeout_sec, args.visible, dest, args.scope)
    except NotImplementedError as e:
        print(f'  ★전제 부재 — {e}')
        _write_status({'schema': 'quantiwise_fetch_status_v1', 'result': 'no_precondition',
                       'at': datetime.now().isoformat(timespec='seconds'),
                       'message': str(e), 'before': before,
                       'driver': _fetch_impl.last_detail,
                       '_note': ('호출부는 이것을 stale 신고로 처리한다 — '
                                 '조용히 Naver 로 때우지 않는다')})
        return 3
    except Exception as e:
        print(f'  ★수급 실패({e.__class__.__name__}: {e}) — 기존 정본 미변경')
        _write_status({'schema': 'quantiwise_fetch_status_v1', 'result': 'failed',
                       'at': datetime.now().isoformat(timespec='seconds'),
                       'message': f'{e.__class__.__name__}: {e}', 'before': before,
                       'driver': _fetch_impl.last_detail})
        return 1

    if got is None:
        print('  받을 것이 없음(원격이 우리 것과 같음) — 미변경')
        _write_status({'schema': 'quantiwise_fetch_status_v1', 'result': 'no_change',
                       'at': datetime.now().isoformat(timespec='seconds'), 'before': before,
                       'driver': _fetch_impl.last_detail})
        return 2

    # ── 교체 전 검증: 읽히는가 · 행이 줄지 않았는가 · 더 최신인가 ──────────────
    cand = _describe(Path(got))
    if 'rows' not in cand or not cand['rows']:
        print('  ★받은 파일에서 IKS200 을 읽지 못함 — 교체하지 않음')
        _write_status({'schema': 'quantiwise_fetch_status_v1', 'result': 'rejected_unreadable',
                       'at': datetime.now().isoformat(timespec='seconds'),
                       'before': before, 'candidate': cand,
                       'driver': _fetch_impl.last_detail})
        return 1
    if before.get('rows') and cand['rows'] < before['rows']:
        print(f'  ★행 축소 ({before["rows"]}→{cand["rows"]}) — 교체하지 않음')
        _write_status({'schema': 'quantiwise_fetch_status_v1', 'result': 'rejected_shrink',
                       'at': datetime.now().isoformat(timespec='seconds'),
                       'before': before, 'candidate': cand,
                       'driver': _fetch_impl.last_detail})
        return 1
    # 드라이버가 '갱신됨' 이라 해도 지평선이 안 늘었으면 교체하지 않는다(무의미한 mtime 갱신 금지).
    if (before.get('date_max') and cand.get('date_max')
            and cand['date_max'] <= before['date_max'] and cand['rows'] <= before.get('rows', 0)):
        print(f'  지평선 불변({before["date_max"]}) — 교체하지 않음')
        _write_status({'schema': 'quantiwise_fetch_status_v1', 'result': 'no_change',
                       'at': datetime.now().isoformat(timespec='seconds'),
                       'before': before, 'candidate': cand,
                       'driver': _fetch_impl.last_detail})
        return 2

    # 원자적 교체 (대상을 열지 않는다 — Windows 매핑 거부/절단 회피)
    tmp = dest.with_name(dest.name + f'.tmp{os.getpid()}')
    shutil.copy(got, tmp)
    os.replace(str(tmp), str(dest))
    after = _describe(dest)
    print(f'  교체 완료: rows={after.get("rows")} date_max={after.get("date_max")}')
    _write_status({'schema': 'quantiwise_fetch_status_v1', 'result': 'updated',
                   'at': datetime.now().isoformat(timespec='seconds'),
                   'before': before, 'after': after,
                   'driver': _fetch_impl.last_detail})
    return 0


if __name__ == '__main__':
    sys.exit(main())
