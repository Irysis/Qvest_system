import importlib
for m in ['torch', 'numpy', 'pandas', 'pyarrow', 'cvxpy', 'cvxpylayers', 'scipy']:
    try:
        mod = importlib.import_module(m)
        print('OK', m, getattr(mod, '__version__', '?'))
    except Exception as e:
        print('MISSING', m, str(e)[:60])
try:
    import torch
    print('cuda', torch.cuda.is_available())
except Exception:
    pass
