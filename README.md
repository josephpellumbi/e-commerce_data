##  E-Commerce Sales Analysis

---

## Overview

This project explores transactional data from a UK-based online retail company using SQL. The dataset — sourced from the [UCI Machine Learning Repository via Kaggle](https://www.kaggle.com/datasets/carrie1/ecommerce-data) — contains real transactions spanning December 2010 through December 2011. The retailer primarily sells unique, all-occasion gifts, with a significant portion of its customer base consisting of wholesalers.

---

## Purpose

The goal of this project was to use SQL to answer meaningful business questions about revenue performance, customer behavior, and geographic sales patterns. Specific areas of focus included:

- **Revenue & sales trends** - How did monthly revenue change over the year, and when did notable spikes occur?
- **Geographic breakdown** - Which countries drove the most revenue, and which had the highest average order value?
- **Order segmentation** - How do orders distribute across small, medium, and large spend tiers?
- **Data quality assessment** - What anomalies exist in the raw data, and how should they be handled before analysis?

---

## Dataset

| Field | Description |
|---|---|
| `InvoiceNo` | Unique transaction ID; prefix `C` indicates a cancellation |
| `StockCode` | Unique product code |
| `Description` | Product name |
| `Quantity` | Units per transaction |
| `InvoiceDate` | Date and time of the transaction |
| `UnitPrice` | Price per unit (GBP £) |
| `CustomerID` | Unique customer identifier |
| `Country` | Country of the customer |

**Source:** [Kaggle - E-Commerce Data](https://www.kaggle.com/datasets/carrie1/ecommerce-data)  
**Original source:** UCI Machine Learning Repository, contributed by Dr. Daqing Chen

---

## Data Cleaning

Before analysis, a consistent cleaning CTE was applied across queries to filter out unreliable records:

- Removed **9,288 cancelled orders** (InvoiceNo starting with `'C'`)
- Removed **10,624 rows** where `Quantity <= 0`
- Removed **2,517 rows** where `UnitPrice <= 0`
- Excluded **135,080 rows** with a null `CustomerID`

These issues represent a meaningful portion of the raw dataset and would significantly skew revenue figures if left unaddressed.

---

## Key Findings

### 1. Revenue Spiked Sharply in Fall 2011
Monthly revenue climbed from a range of roughly **£450K–£680K** earlier in 2011 to a range of **£950K–£1.16M** between September and November 2011. This ~70% increase likely reflects holiday seasonal demand driving elevated purchasing activity in Q4.

### 2. Singapore, Netherlands & Australia Led in Average Order Value
Despite not having the highest transaction volumes, these three countries posted the highest average order values:

| Country | Avg. Order Value (£) |
|---|---|
| Singapore | 3,039.90 |
| Netherlands | 3,036.66 |
| Australia | 2,430.20 |

This suggests these markets skewed toward larger, potentially wholesale-style purchases.

### 3. The UK Dominated Total Revenue
The UK accounted for approximately **£7.3M** in total revenue — far ahead of all other countries — reflecting both the retailer's home market concentration and its domestic customer base. Saudi Arabia ranked lowest at **£145.92**.

### 4. Medium-Sized Orders Made Up ~60% of All Transactions
Orders were segmented into three tiers by total invoice value:

| Tier | Invoice Value | Order Count | % of Total |
|---|---|---|---|
| Small | < £200 | ~6,100 | ~7% |
| Medium | £200 - £999 | ~11,000 | ~60% |
| Large | ≥ £1,000 | ~1,300 | ~33% |

Medium-tier orders were the clear majority, suggesting the typical customer — likely a small wholesaler — placed moderate-sized bulk purchases rather than very large or very small ones.

---

## SQL Concepts Used

- Common Table Expressions (CTEs)
- Window functions (`LAG`, `SUM OVER`)
- `DATE_TRUNC` for time-series aggregation
- `CASE WHEN` for custom bucketing
- Aggregate functions with `GROUP BY`
- Data quality validation with `COUNT` + filter conditions

---

## Tools Used

- **SQL** - DuckDB (through DBeaver)
- **Tableau**
