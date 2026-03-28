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

# 基本信息
info = stock.info

# 历史价格（1年日线）
hist = stock.history(period="1y")

# 财务数据
financials = stock.financials
balance_sheet = stock.balance_sheet
cashflow = stock.cashflow
```

### 4. 技术面分析

手动计算关键技术指标：

```python
import pandas as pd
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
df['BB_std'] = df['Close'].rolling(20).std()
df['BB_upper'] = df['BB_mid'] + 2 * df['BB_std']
df['BB_lower'] = df['BB_mid'] - 2 * df['BB_std']

# 成交量均线
df['Volume_MA20'] = df['Volume'].rolling(20).mean()

latest = df.iloc[-1]
print(f"收盘价: {latest['Close']:.2f}")
print(f"MA20: {latest['MA20']:.2f}, MA50: {latest['MA50']:.2f}, MA200: {latest['MA200']:.2f}")
print(f"RSI(14): {latest['RSI']:.1f}")
print(f"MACD: {latest['MACD']:.3f}, Signal: {latest['MACD_signal']:.3f}")
print(f"布林带: {latest['BB_lower']:.2f} ~ {latest['BB_upper']:.2f}")
```

**解读标准：**
- RSI > 70：超买，短期回调风险
- RSI < 30：超卖，可能存在机会
- 价格 > MA200：长期上升趋势
- MACD 金叉/死叉：短期趋势转折信号
- 布林带上轨：阻力；下轨：支撑

### 5. 基本面分析

提取关键估值指标：

```python
# 估值指标
pe = info.get('trailingPE', 'N/A')
forward_pe = info.get('forwardPE', 'N/A')
pb = info.get('priceToBook', 'N/A')
peg = info.get('pegRatio', 'N/A')
ps = info.get('priceToSalesTrailing12Months', 'N/A')

# 盈利质量
roe = info.get('returnOnEquity', 'N/A')
roa = info.get('returnOnAssets', 'N/A')
profit_margin = info.get('profitMargins', 'N/A')
gross_margin = info.get('grossMargins', 'N/A')

# 成长性
revenue_growth = info.get('revenueGrowth', 'N/A')
earnings_growth = info.get('earningsGrowth', 'N/A')

# 财务健康
debt_to_equity = info.get('debtToEquity', 'N/A')
current_ratio = info.get('currentRatio', 'N/A')
free_cashflow = info.get('freeCashflow', 'N/A')

# 市值
market_cap = info.get('marketCap', 'N/A')
```

**价值投资评估框架（巴菲特标准）：**
- ROE > 15%：优质盈利能力
- 负债率 < 50%：财务稳健
- 自由现金流为正且增长：真实盈利
- PE vs 行业均值：估值是否合理
- 护城河：品牌/专利/网络效应/转换成本/成本优势

### 6. 估值分析

使用多种估值方法交叉验证：

```python
# --- 格雷厄姆公式 ---
eps = info.get('trailingEps', 0)
growth_rate = info.get('earningsGrowth', 0.10)
if growth_rate and eps and eps > 0:
    graham_value = eps * (8.5 + 2 * growth_rate * 100) * 4.4 / 4.5
    print(f"格雷厄姆内在价值: ${graham_value:.2f}")

# --- PEG 估值 ---
if peg and peg != 'N/A':
    if peg < 1:
        print(f"PEG={peg:.2f}，可能被低估")
    elif peg > 2:
        print(f"PEG={peg:.2f}，估值偏高")
    else:
        print(f"PEG={peg:.2f}，估值合理")

# --- FCF 收益率 ---
if free_cashflow and free_cashflow != 'N/A' and market_cap and market_cap != 'N/A':
    if free_cashflow > 0:
        fcf_yield = free_cashflow / market_cap
        print(f"自由现金流收益率: {fcf_yield*100:.1f}%")
```

### 7. 行业对比（可选）

对比同行业竞争对手：

```python
competitors = ["MSFT", "GOOGL", "META"]  # 根据行业替换

comparison = {}
for comp in competitors:
    c = yf.Ticker(comp)
    ci = c.info
    comparison[comp] = {
        'PE': ci.get('trailingPE'),
        'PB': ci.get('priceToBook'),
        'ROE': ci.get('returnOnEquity'),
        'Margin': ci.get('profitMargins'),
    }

comp_df = pd.DataFrame(comparison).T
print(comp_df.to_string())
```

### 8. 生成分析报告

以结构化方式输出分析结论，必须包含：

```
📊 [股票代码] 综合分析报告

一、基本信息
   公司名称 | 行业 | 市值 | 当前价格

二、技术面信号
   趋势判断（多头/空头/震荡）
   关键支撑位 / 阻力位
   RSI 状态 | MACD 状态

三、基本面评分（5分制）
   盈利能力 ★★★★☆
   成长性   ★★★☆☆
   财务健康 ★★★★★
   估值合理性 ★★★☆☆

四、估值判断
   相对估值（PE/PB 横向对比）
   绝对估值（格雷厄姆/DCF 参考值）
   结论：当前价格 [便宜/合理/偏贵]

五、操作参考
   适合人群（价值投资者/成长投资者/交易者）
   参考买入区间 / 参考止损位
   持有周期建议

六、⚠️ 风险提示
   主要风险因素（至少3条）
   最坏情景假设
   免责声明
```

### 9. 回测验证（策略类问题时执行）

```python
hist_2y = stock.history(period="2y")
df_bt = hist_2y.copy()
df_bt['MA50'] = df_bt['Close'].rolling(50).mean()
df_bt['MA200'] = df_bt['Close'].rolling(200).mean()
df_bt['Signal'] = (df_bt['MA50'] > df_bt['MA200']).astype(int)

df_bt['Returns'] = df_bt['Close'].pct_change()
df_bt['Strategy'] = df_bt['Signal'].shift(1) * df_bt['Returns']

total_return = (1 + df_bt['Strategy'].dropna()).prod() - 1
buy_hold_return = df_bt['Close'].iloc[-1] / df_bt['Close'].iloc[0] - 1

print(f"均线策略收益: {total_return*100:.1f}%")
print(f"买入持有收益: {buy_hold_return*100:.1f}%")
```

## 常见问题处理

### 用户问"XX 股票能买吗？"
1. 先用数据分析技术面 + 基本面
2. 明确说明无法预测涨跌
3. 给出"在什么条件下适合买入"的框架

### 用户问"现在市场贵不贵？"
分析标普500整体估值：
```python
spy = yf.Ticker("SPY")
spy_info = spy.info
print(f"SPY PE: {spy_info.get('trailingPE')}")
print(f"SPY 52周涨跌: {(spy_info.get('currentPrice',0)/spy_info.get('fiftyTwoWeekLow',1)-1)*100:.1f}%")
```

### 用户问"我该怎么配置仓位？"
基于用户风险偏好讨论：
- 核心仓位（宽基ETF：SPY/QQQ/VTI）70%
- 卫星仓位（个股/行业ETF）30%
- 现金储备建议

## 不做的事

- ❌ 不预测具体目标价和时间节点
- ❌ 不保证任何收益
- ❌ 不推荐"必涨""必跌"
- ❌ 不基于小道消息/内幕信息分析
- ❌ 不替用户做决定，只提供分析框架

## 注意事项

- 所有分析基于公开数据，仅供参考
- 过去表现不代表未来
- 每次分析结尾必须附上免责声明
- 如用户提到大额投资，建议咨询持牌财务顾问
