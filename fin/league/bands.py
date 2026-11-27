# Band edges shared by the league test and the live paper executor, so a rule means the same thing in both.
import numpy as np, pandas as pd
FUNDS = {'SPY', 'QQQ', 'IWM', 'DIA', 'TQQQ', 'SQQQ', 'ARKK', 'GLD', 'TLT', 'USO'}
M7 = ['down a full day range or more', 'down half to one range', 'down a little', 'flat', 'up a little', 'up half to one range', 'up a full day range or more']
BANDS = {
    'move': ([-1, -0.5, -0.15, 0.15, 0.5, 1], M7),
    'gap': ([-0.5, -0.15, 0.15, 0.5], ['big gap down', 'gap down', 'no gap', 'gap up', 'big gap up']),
    'prev': ([-0.7, -0.2, 0.2, 0.7], ['big down day', 'down day', 'flat day', 'up day', 'big up day']),
    'f5': ([0.12, 0.25, 0.4], ['tiny', 'normal', 'wide', 'very wide']),
    'pos': ([0.2, 0.8], ['near the low', 'in the middle', 'near the high']),
    'rv': ([0.6, 1.5, 3.0], ['quiet', 'normal', 'busy', 'very busy']),
    'mkt': ([-1.0, -0.3, 0.3, 1.0], ['market down 1% or more', 'market down', 'market flat', 'market up', 'market up 1% or more']),
    'rel': ([-0.5, -0.15, 0.15, 0.5], ['much weaker than the market', 'weaker', 'in line', 'stronger', 'much stronger than the market']),
    'l30': ([-0.3, -0.1, 0.1, 0.3], ['fell hard', 'fell', 'flat', 'rose', 'rose hard']),
    'h1': ([-0.3, -0.1, 0.1, 0.3], ['fell hard', 'fell', 'flat', 'rose', 'rose hard']),
    'h4': ([-0.5, -0.15, 0.15, 0.5], ['fell hard', 'fell', 'flat', 'rose', 'rose hard']),
    'h24': ([-1, -0.3, 0.3, 1], ['fell a full day range or more', 'fell', 'flat', 'rose', 'rose a full day range or more']),
}
def band(name, s):
    edges, names = BANDS[name]
    return pd.cut(pd.Series(np.asarray(s, dtype=float)), [-np.inf] + edges + [np.inf], labels=names).astype(object).values
def band1(name, x):
    """one value -> its band label (live executor)"""
    if x is None or x != x: return None
    edges, names = BANDS[name]
    for e, n in zip(edges, names):
        if x <= e: return n
    return names[-1]
