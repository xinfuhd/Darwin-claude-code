#!/usr/bin/env python3
# =============================================================
# mag7-report.py — 科技七姐妹 + TSM 财报数据抓取器
#
# 用法：
#   python3 mag7-report.py            # 打印报告到终端
#   python3 mag7-report.py --save     # 同时保存到 ~/.claude/mag7-latest.md
#   python3 mag7-report.py --watch GOOGL NVDA  # 只看指定股票
#
# 依赖：pip install yfinance pandas
# =============================================================

import sys
import argparse
from datetime import datetime

try:
    import yfinance as yf
    import pandas as pd
except ImportError:
    print("缺少依赖，请先运行：pip install yfinance pandas")
    sys.exit(1)

WATCHLIST = {
    "AAPL":  "苹果",
    "MSFT":  "微软",
    "GOOGL": "谷歌",
    "AMZN":  "亚马逊",
    "NVDA":  "英伟达",
    "META":  "Meta",
    "TSLA":  "特斯拉",
    "TSM":   "台积电",
}

# 标普500参考均值（用于对比，定期手动更新）
SP500_REF = {
    "pe":  22.0,
    "pb":  4.0,
    "roe": 0.18,
}

def fmt(val, fmt_str="{:.1f}", fallback="N/A"):
    try:
        if val is None or (isinstance(val, float) and (val != val)):  # NaN check
            return fallback
        return fmt_str.format(val)
    except Exception:
        return fallback

def pct(val, fallback="N/A"):
    try:
        if val is None or (isinstance(val, float) and (val != val)):
            return fallback
        return f"{val*100:.1f}%"
    except Exception:
        return fallback

def billions(val, fallback="N/A"):
    try:
        if val is None or (isinstance(val, float) and (val != val)):
            return fallback
        return f"${val/1e9:.1f}B"
    except Exception:
        return fallback

def fetch_stock(ticker):
    """抓取单只股票的关键财报数据"""
    try:
        t = yf.Ticker(ticker)
        info = t.info

        # 价格数据
        price       = info.get("currentPrice") or info.get("regularMarketPrice")
        week52_low  = info.get("fiftyTwoWeekLow")
        week52_high = info.get("fiftyTwoWeekHigh")

        # 距历史高点回撤
        drawdown = None
        if price and week52_high and week52_high > 0:
            drawdown = (price - week52_high) / week52_high

        # 估值指标
        pe         = info.get("trailingPE")
        forward_pe = info.get("forwardPE")
        pb         = info.get("priceToBook")
        peg        = info.get("pegRatio")
        ps         = info.get("priceToSalesTrailing12Months")

        # 盈利能力
        roe        = info.get("returnOnEquity")
        profit_m   = info.get("profitMargins")
        op_margin  = info.get("operatingMargins")

        # 规模与成长
        mkt_cap    = info.get("marketCap")
        revenue    = info.get("totalRevenue")
        rev_growth = info.get("revenueGrowth")
        eps        = info.get("trailingEps")
        eps_growth = info.get("earningsGrowth")

        # 现金流
        fcf        = info.get("freeCashflow")
        total_cash = info.get("totalCash")
        total_debt = info.get("totalDebt")

        # 分析师目标价
        target     = info.get("targetMeanPrice")
        upside     = None
        if price and target and price > 0:
            upside = (target - price) / price

        return {
            "price": price,
            "week52_low": week52_low,
            "week52_high": week52_high,
            "drawdown": drawdown,
            "pe": pe,
            "forward_pe": forward_pe,
            "pb": pb,
            "peg": peg,
            "ps": ps,
            "roe": roe,
            "profit_margin": profit_m,
            "op_margin": op_margin,
            "mkt_cap": mkt_cap,
            "revenue": revenue,
            "rev_growth": rev_growth,
            "eps": eps,
            "eps_growth": eps_growth,
            "fcf": fcf,
            "total_cash": total_cash,
            "total_debt": total_debt,
            "target": target,
            "upside": upside,
            "error": None,
        }
    except Exception as e:
        return {"error": str(e)}

def valuation_signal(pe, forward_pe, peg):
    """简单估值信号"""
    signals = []
    if pe and pe < 20:
        signals.append("PE偏低")
    elif pe and pe > 40:
        signals.append("PE偏高")
    if peg and peg < 1.5:
        signals.append("PEG合理")
    elif peg and peg > 2.5:
        signals.append("PEG偏贵")
    if forward_pe and pe and forward_pe < pe * 0.85:
        signals.append("盈利预期改善")
    return " | ".join(signals) if signals else "中性"

def render_report(data: dict, tickers: list) -> str:
    lines = []
    now = datetime.now().strftime("%Y-%m-%d %H:%M")

    lines.append(f"# 科技七姐妹 + TSM 财报速览")
    lines.append(f"> 生成时间：{now}  |  数据来源：Yahoo Finance（有15min延迟）")
    lines.append("")

    # ── 价格总览表 ──
    lines.append("## 价格总览")
    lines.append("")
    lines.append("| 股票 | 当前价 | 52周低 | 52周高 | 距高点 | 分析师目标 | 上行空间 |")
    lines.append("|------|--------|--------|--------|--------|------------|----------|")
    for ticker in tickers:
        d = data[ticker]
        if d.get("error"):
            lines.append(f"| {ticker} | ❌ {d['error'][:30]} | - | - | - | - | - |")
            continue
        drawdown_str = f"{d['drawdown']*100:.1f}%" if d['drawdown'] else "N/A"
        upside_str   = f"+{d['upside']*100:.1f}%" if d.get('upside') and d['upside'] > 0 else (f"{d['upside']*100:.1f}%" if d.get('upside') else "N/A")
        lines.append(
            f"| **{ticker}** {WATCHLIST.get(ticker,'')} "
            f"| ${fmt(d['price'], '{:.2f}')} "
            f"| ${fmt(d['week52_low'], '{:.2f}')} "
            f"| ${fmt(d['week52_high'], '{:.2f}')} "
            f"| {drawdown_str} "
            f"| ${fmt(d['target'], '{:.2f}')} "
            f"| {upside_str} |"
        )

    lines.append("")

    # ── 估值指标 ──
    lines.append("## 估值指标")
    lines.append(f"> 标普500参考：PE ≈ {SP500_REF['pe']}x  |  PB ≈ {SP500_REF['pb']}x  |  ROE ≈ {pct(SP500_REF['roe'])}")
    lines.append("")
    lines.append("| 股票 | Trailing PE | Forward PE | PB | PEG | P/S | 信号 |")
    lines.append("|------|-------------|------------|----|-----|-----|------|")
    for ticker in tickers:
        d = data[ticker]
        if d.get("error"):
            continue
        signal = valuation_signal(d['pe'], d['forward_pe'], d['peg'])
        lines.append(
            f"| **{ticker}** "
            f"| {fmt(d['pe'], '{:.1f}x')} "
            f"| {fmt(d['forward_pe'], '{:.1f}x')} "
            f"| {fmt(d['pb'], '{:.1f}x')} "
            f"| {fmt(d['peg'], '{:.2f}')} "
            f"| {fmt(d['ps'], '{:.1f}x')} "
            f"| {signal} |"
        )

    lines.append("")

    # ── 盈利能力 ──
    lines.append("## 盈利能力")
    lines.append("")
    lines.append("| 股票 | ROE | 净利率 | 经营利润率 | EPS | EPS增速 |")
    lines.append("|------|-----|--------|------------|-----|---------|")
    for ticker in tickers:
        d = data[ticker]
        if d.get("error"):
            continue
        roe_flag = " ⭐" if d['roe'] and d['roe'] > 0.30 else ""
        lines.append(
            f"| **{ticker}** "
            f"| {pct(d['roe'])}{roe_flag} "
            f"| {pct(d['profit_margin'])} "
            f"| {pct(d['op_margin'])} "
            f"| ${fmt(d['eps'], '{:.2f}')} "
            f"| {pct(d['eps_growth'])} |"
        )

    lines.append("")

    # ── 规模与成长 ──
    lines.append("## 规模与成长")
    lines.append("")
    lines.append("| 股票 | 市值 | 年营收 | 营收增速 | 自由现金流 | 净现金 |")
    lines.append("|------|------|--------|----------|------------|--------|")
    for ticker in tickers:
        d = data[ticker]
        if d.get("error"):
            continue
        net_cash = None
        if d['total_cash'] and d['total_debt']:
            net_cash = d['total_cash'] - d['total_debt']
        rev_flag = " 🚀" if d['rev_growth'] and d['rev_growth'] > 0.20 else ""
        lines.append(
            f"| **{ticker}** "
            f"| {billions(d['mkt_cap'])} "
            f"| {billions(d['revenue'])} "
            f"| {pct(d['rev_growth'])}{rev_flag} "
            f"| {billions(d['fcf'])} "
            f"| {billions(net_cash)} |"
        )

    lines.append("")
    lines.append("---")
    lines.append("> ⚠️ 本报告仅供学习参考，不构成投资建议。投资有风险，决策需谨慎。")

    return "\n".join(lines)

def main():
    parser = argparse.ArgumentParser(description="科技七姐妹 + TSM 财报速览")
    parser.add_argument("--save", action="store_true", help="保存报告到 ~/.claude/mag7-latest.md")
    parser.add_argument("--watch", nargs="+", metavar="TICKER", help="只查看指定股票")
    args = parser.parse_args()

    tickers = args.watch if args.watch else list(WATCHLIST.keys())
    tickers = [t.upper() for t in tickers]

    print(f"正在抓取 {len(tickers)} 只股票数据：{', '.join(tickers)}")
    print("请稍候...\n")

    data = {}
    for ticker in tickers:
        sys.stdout.write(f"  {ticker}... ")
        sys.stdout.flush()
        data[ticker] = fetch_stock(ticker)
        status = "✅" if not data[ticker].get("error") else "❌"
        print(status)

    print()
    report = render_report(data, tickers)
    print(report)

    if args.save:
        import os
        save_path = os.path.expanduser("~/.claude/mag7-latest.md")
        with open(save_path, "w") as f:
            f.write(report)
        print(f"\n报告已保存到：{save_path}")

if __name__ == "__main__":
    main()
