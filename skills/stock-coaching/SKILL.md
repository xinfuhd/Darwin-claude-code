---
name: stock-coaching
description: 美股投资辅导。分析股票技术面+基本面，提供估值判断、操作策略和风险评估，基于巴菲特/芒格价值投资框架。
version: "1.0.0"
author: xinfuhd
tags: ["finance", "investing", "stocks", "analysis", "chinese"]
metadata: { "openclaw": { "emoji": "📈", "requires": { "bins": ["python3"] }, "install": [{"kind": "pip", "packages": ["yfinance", "pandas", "numpy"], "bins": ["python3"]}] } }
---

# 美股投资辅导 Skill

帮助用户进行数据驱动的美股投资分析，结合技术面与基本面，基于巴菲特/芒格价值投资框架。

## 核心原则

- **数据优先**：用真实数据说话，不凭感觉
- **双维分析**：技术面 + 基本面双重验证
- **风险前置**：每个建议必须附风险说明和止损位
- **诚实边界**：不预测点位，不保证收益，不推荐"必涨"

## 工作流程

创建 todo 列表，按需完成以下步骤：

### 1. 理解用户需求

明确用户想要什么：
- 单股分析（技术面/基本面/综合）？
- 估值判断（贵还是便宜）？
- 策略讨论（买入/持有/卖出时机）？
- 行业/ETF 对比？
- 风险评估？

如果股票代码不清楚，询问用户。

### 2. 安装依赖（如未安装）

```bash
pip install yfinance pandas numpy -q 2>&1 | tail -1
```

### 3. 获取基础数据

```python
import yfinance as yf
import pandas as pd

ticker = "AAPL"  # 替换为实际代码
stock = yf.Ticker(ticker)

info = stock.info
hist = stock.history(period="1y")
```

### 4. 技术面分析

```python
import numpy as np

df = hist.copy()

# 移动均线
df['MA20'] = df['Close'].rolling(20).mean()
df['MA50'] = df['Close'].rolling(50).mean()
df['MA200'] = df['Close'].rolling(200).mean()

# RSI
delta = df['Close'].diff()
gain = delta.clip(lower=0).rolling(14).mean()
loss = (-delta.clip(upper=0)).rolling(14).mean()
df['RSI'] = 100 - (100 / (1 + gain / loss))

# MACD
ema12 = df['Close'].ewm(span=12).mean()
ema26 = df['Close'].ewm(span=26).mean()
df['MACD'] = ema12 - ema26
df['MACD_signal'] = df['MACD'].ewm(span=9).mean()

# 布林带
df['BB_mid'] = df['Close'].rolling(20).mean()
std = df['Close'].rolling(20).std()
df['BB_upper'] = df['BB_mid'] + 2 * std
df['BB_lower'] = df['BB_mid'] - 2 * std

latest = df.iloc[-1]
print(f"收盘价: {latest['Close']:.2f}")
print(f"MA20/50/200: {latest['MA20']:.2f} / {latest['MA50']:.2f} / {latest['MA200']:.2f}")
print(f"RSI(14): {latest['RSI']:.1f}")
print(f"MACD: {latest['MACD']:.3f}  Signal: {latest['MACD_signal']:.3f}")
print(f"布林带: {latest['BB_lower']:.2f} ~ {latest['BB_upper']:.2f}")
```

**解读标准：**
- RSI > 70：超买 | RSI < 30：超卖
- 价格 > MA200：长期上升趋势
- MACD 线上穿信号线：金叉做多信号
- 死叉（MA50 下穿 MA200）：中期看空

### 5. 基本面分析

```python
pe = info.get('trailingPE')
forward_pe = info.get('forwardPE')
pb = info.get('priceToBook')
peg = info.get('pegRatio')
roe = info.get('returnOnEquity')
profit_margin = info.get('profitMargins')
gross_margin = info.get('grossMargins')
revenue_growth = info.get('revenueGrowth')
earnings_growth = info.get('earningsGrowth')
debt_to_equity = info.get('debtToEquity')
current_ratio = info.get('currentRatio')
free_cashflow = info.get('freeCashflow')
market_cap = info.get('marketCap')

print(f"PE: {pe:.1f} | Forward PE: {forward_pe:.1f}" if pe and forward_pe else "")
print(f"PB: {pb:.1f} | PEG: {peg:.2f}" if pb and peg else "")
print(f"ROE: {roe*100:.1f}% | 净利润率: {profit_margin*100:.1f}%" if roe and profit_margin else "")
print(f"营收增长: {revenue_growth*100:.1f}% | 盈利增长: {earnings_growth*100:.1f}%" if revenue_growth and earnings_growth else "")
print(f"负债权益比: {debt_to_equity:.1f}% | 流动比率: {current_ratio:.2f}" if debt_to_equity and current_ratio else "")
if free_cashflow and market_cap and free_cashflow > 0:
    print(f"自由现金流: ${free_cashflow/1e9:.1f}B | FCF收益率: {free_cashflow/market_cap*100:.1f}%")
```

**价值投资评估框架（巴菲特标准）：**
- ROE > 15%：优质盈利能力
- 负债率 < 50%：财务稳健
- 自由现金流持续为正：真实盈利
- PE 低于历史均值 + 行业均值：估值合理

### 6. 估值分析

```python
# 格雷厄姆公式：内在价值 = EPS × (8.5 + 2g) × 4.4 / Y
eps = info.get('trailingEps', 0)
g = (info.get('earningsGrowth') or 0.10) * 100  # 增长率转为百分比
Y = 4.5  # 参考无风险利率
if eps and eps > 0:
    graham = eps * (8.5 + 2 * g) * 4.4 / Y
    price = info.get('currentPrice') or info.get('regularMarketPrice', 0)
    print(f"格雷厄姆内在价值: ${graham:.2f} | 当前价: ${price:.2f}")
    if price > 0:
        margin = (graham - price) / graham * 100
        print(f"安全边际: {margin:.1f}%")

# PEG 判断
if peg:
    label = "低估" if peg < 1 else ("合理" if peg < 2 else "偏贵")
    print(f"PEG={peg:.2f} → {label}")
```

### 7. 行业对比（可选）

```python
competitors = ["MSFT", "GOOGL", "META"]  # 根据行业替换

data = {}
for sym in competitors:
    i = yf.Ticker(sym).info
    data[sym] = {
        'PE': i.get('trailingPE'),
        'PB': i.get('priceToBook'),
        'ROE(%)': round((i.get('returnOnEquity') or 0) * 100, 1),
        '净利润率(%)': round((i.get('profitMargins') or 0) * 100, 1),
    }

print(pd.DataFrame(data).T.to_string())
```

### 8. 生成分析报告

输出标准化报告，必须包含：

```
📊 [股票代码] 综合分析报告

一、基本信息
   公司 | 行业 | 市值 | 当前价 | 52周区间

二、技术面信号
   趋势：多头 / 空头 / 震荡
   支撑位 / 阻力位
   RSI 状态 | MACD 状态 | 均线排列

三、基本面评分（5分制）
   盈利能力   ★★★★☆
   成长性     ★★★☆☆
   财务健康   ★★★★★
   估值合理性 ★★★☆☆

四、估值判断
   PE/PB 与历史均值、行业均值对比
   格雷厄姆内在价值 / 安全边际
   结论：便宜 / 合理 / 偏贵

五、操作参考
   适合人群
   参考建仓区间 | 止损位
   持有周期建议

六、⚠️ 风险提示（至少3条）
   + 免责声明
```

### 9. 策略回测（策略类问题时执行）

```python
hist_2y = stock.history(period="2y")
df_bt = hist_2y.copy()
df_bt['MA50'] = df_bt['Close'].rolling(50).mean()
df_bt['MA200'] = df_bt['Close'].rolling(200).mean()
df_bt['Signal'] = (df_bt['MA50'] > df_bt['MA200']).astype(int)

df_bt['Return'] = df_bt['Close'].pct_change()
df_bt['Strategy'] = df_bt['Signal'].shift(1) * df_bt['Return']

strat_ret = (1 + df_bt['Strategy'].dropna()).prod() - 1
bh_ret = df_bt['Close'].iloc[-1] / df_bt['Close'].iloc[0] - 1

print(f"均线策略(2年): {strat_ret*100:.1f}%")
print(f"买入持有(2年): {bh_ret*100:.1f}%")
```

## 常见问题

**"XX 能买吗？"** → 数据分析 + 给出"什么条件下适合买入"框架，不预测涨跌

**"市场贵不贵？"** → 分析 SPY/QQQ 整体 PE、席勒CAPE 概念

**"仓位怎么配？"** → 核心（宽基ETF 70%）+ 卫星（个股 30%）+ 现金储备

## 禁区

- ❌ 不预测具体价格目标或时间节点
- ❌ 不保证收益，不推荐"必涨"股票
- ❌ 不基于内幕消息或小道消息分析
- ❌ 不替用户做决定，只提供分析框架

---

*所有分析基于公开数据，仅供参考，不构成投资建议。过去表现不代表未来。*
