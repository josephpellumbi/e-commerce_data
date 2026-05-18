-- -------------------------------------
-- Creating the table
-- -------------------------------------
drop table if exists online_retail;

create table if not exists online_retail as 
select * 
from read_csv_auto('/Users/josephpellumbi/Downloads/ecommerce_data.csv', encoding='ISO_8859_1');





-- -------------------------------------
-- Phase 1 - Initial Exploration
-- -------------------------------------
select *
from ecommerce_data.main.online_retail t
limit 10;

-- count total rows
select count(*)
from online_retail;

-- count total unique invoice numbers
select count(distinct InvoiceNo)
from online_retail;

-- find date range of transactions
select min(InvoiceDate) as first_date, max(InvoiceDate) as last_date
from online_retail;

-- identify any null customer ids
select * from online_retail
where CustomerID is null;
-- 135,080 rows where customer id is null

-- total revenue by country
with cte_revenue as (
	select *, (quantity * unitprice) as revenue
	from online_retail
)
select country, 
round(sum(revenue), 2) as total_revenue
from cte_revenue
group by country
order by total_revenue desc;

-- top 10 best selling products
select stockcode, description, quantity, unitprice,
(quantity * unitprice) as revenue
from online_retail
where unitprice != 0
group by stockcode, description, quantity, unitprice, revenue
order by quantity desc
limit 10;

-- ISSUE: Total revenue by country
-- Query above includes cancelled orders (invoices starting with 'C'),
-- which have negative quantities and will undercount revenue
-- explore this in the data

select *
from online_retail
where invoiceno like 'C%';

select *
from online_retail
where quantity <= 0;

--check for negative or zero unit prices beyond filtering them out
select count(*)
from online_retail
where unitprice <= 0;
-- 2517 rows where this happens

-- we need to add a filter to our total revenue by country
with cte_revenue as (
	select *, (quantity * unitprice) as revenue
	from online_retail
	where quantity > 0
)
select country, sum(revenue) as total_revenue
from cte_revenue
group by country
order by total_revenue desc;

-- ISSUE: Top 10 Best Selling Products
-- Query above is grouping by quantity, unitprice, and revenue,
-- which means each individual row is treated as its own group.
-- We are not aggregating anything, just sorting raw rows by quantity
-- rather than summing quantity per product.


-- Fix it by grouping only on product identifiers and using sum()
select stockcode, description, 
sum(quantity) as total_quantity_sold, 
round(sum(quantity * unitprice), 2) as total_revenue
from online_retail
where unitprice != 0 and quantity > 0
group by stockcode, description
order by total_quantity_sold desc
limit 10;





-- -------------------------------------
-- Phase 2 - Intermediate Analysis
-- -------------------------------------

-- 1. Clean the dataset, filtering out cancelled orders,
-- 	  rows where quantity or unitprice are 0 or negative,
--    and rows where customer id is null.
with clean_ecommerce as (
	select *
	from online_retail
	where invoiceno not like 'C%'
	and quantity > 0
	and unitprice > 0
	and customerid is not null
)
-- checking to see if the cte works properly
select count(invoiceno)
from clean_ecommerce
where invoiceno like 'C%';
--where quantity < 0
-- where unitprice < 0



-- 2. Monthly revenue trend
-- What does total revenue look like month by month?
-- We need to extract the month and year from invoicedate to group by.
-- (look into DuckDB's date_trunc or strftime functions)

select strptime(invoicedate, '%m/%d/%Y %H:%M')
from online_retail
limit 5;

-- since the above query returns clean timestamps,
-- wrap date_trunc around it

select date_trunc('month', strptime(invoicedate, '%m/%d/%Y %H:%M'))
from online_retail
limit 5;

-- update the column type in the table permanently
alter table online_retail
alter column invoicedate type timestamp
using strptime(invoicedate, '%m/%d/%Y %H:%M');

-- solution
with clean_ecommerce as (
	select *
	from online_retail
	where invoiceno not like 'C%'
	and quantity > 0
	and unitprice > 0
	and customerid is not null
)
select date_trunc('month', invoicedate) as month,
round(sum(quantity * unitprice), 2) as total_revenue
from clean_ecommerce
group by month
order by month;

-- 3. Best and worst performing months
-- Which month had the highest revenue and which had the lowest?
-- This can build on the previous query.

-- since it can build on the previous query, chain the CTEs
-- however we need to make sure the month is in the result set

with clean_ecommerce as (
	select *
	from online_retail
	where invoiceno not like 'C%'
	and quantity > 0
	and unitprice > 0
	and customerid is not null
),

monthly_trend as (
	select date_trunc('month', invoicedate) as month,
	round(sum(quantity * unitprice), 2) as total_revenue
	from clean_ecommerce
	group by month
	order by month
)

-- use union all to combine 2 queries: 1 for max, 1 for min
select * from (
select month, total_revenue from monthly_trend
order by total_revenue desc
limit 1
)

union all

select * from (
select month, total_revenue from monthly_trend
order by total_revenue asc
limit 1
);

-- 4. Average order value by country
-- An order is defined at the invoice level (one invoiceno = one order).
-- Average order value = total revenue / number of distinct invoices,
-- grouped by country.

-- chain CTEs once again
with clean_ecommerce as (
	select *
	from online_retail
	where invoiceno not like 'C%'
	and quantity > 0
	and unitprice > 0
	and customerid is not null
),


-- grab the columns we need from the prompt info
-- this includes 2 aggregate functions
-- RULE: aggregation and GROUP BY need to live together in the same query block
order_value as (
	select country,
	count(distinct invoiceno) as unique_invoice_total,
	round(sum(quantity * unitprice), 2) as total_revenue
	from clean_ecommerce
	group by country
)

-- now we have what we need, solve for avg_order_value
select country, 
round(total_revenue / unique_invoice_total, 2) as avg_order_value
from order_value
order by avg_order_value desc;


-- Looking at the results, does a country with a high avg_order_value
-- necessarily mean it's the highest revenue country? Why or why not?

-- The above result set does not return the full picture.
-- The country might not have a lot of orders, but the ones it
-- does have might have a higher total revenue.

-- A country with 2 massive orders will look different from a country
-- with 2000 consistent mid-sized orders, even if their avg_order_value
-- is similar.

-- Include unique_invoice_total from the order_value CTE.
-- This will give the context needed to tell the story properly.

with clean_ecommerce as (
	select *
	from online_retail
	where invoiceno not like 'C%'
	and quantity > 0
	and unitprice > 0
	and customerid is not null
),

order_value as (
	select country,
	count(distinct invoiceno) as unique_invoice_total,
	round(sum(quantity * unitprice), 2) as total_revenue
	from clean_ecommerce
	group by country
)

select country, 
round(total_revenue / unique_invoice_total, 2) as avg_order_value,
unique_invoice_total
from order_value
order by avg_order_value desc;



-- 5. Revenue buckets with CASE WHEN
-- Categorize each invoice into Small (under 200 pounds),
-- Medium (200-1000), or Large (over 1000) based on total invoice value.
-- How many invoices fall into each bucket?

-- chain CTEs again

with clean_ecommerce as (
	select *
	from online_retail
	where invoiceno not like 'C%'
	and quantity > 0
	and unitprice > 0
	and customerid is not null
),

-- create the case logic for categorization of total_invoice_value
invoice_revenue as (
select invoiceno, 
round(sum(quantity * unitprice), 2) as total_invoice_value,

case
	when total_invoice_value < 200
	then 'Small'
	when total_invoice_value >= 200 and total_invoice_value < 1000
	then 'Medium'
	when total_invoice_value >= 1000
	then 'Large'
end as revenue_buckets

from clean_ecommerce
group by invoiceno
),

-- pull the case logic into another CTE
categories as (
select invoiceno, total_invoice_value, revenue_buckets
from invoice_revenue
)

-- find how many invoices that fall into each bucket
select revenue_buckets, count(revenue_buckets) as bucket_count
from categories
group by revenue_buckets;



-- ISSUE: alias reference in CASE WHEN

-- DuckDB might allow this to work, but in standard SQL,
-- you can't reference an alias (total_invoice_value) in a
-- CASE WHEN within the same SELECT block where it's defined.

-- Not reliable in BigQuery for example

-- Safer to do this:
case
    when round(sum(quantity * unitprice), 2) < 200 then 'Small'
    when round(sum(quantity * unitprice), 2) >= 200 
        and round(sum(quantity * unitprice), 2) < 1000 then 'Medium'
    when round(sum(quantity * unitprice), 2) >= 1000 then 'Large'
end as revenue_buckets

-- or move the CASE WHEN into the next CTE where total_invoice_value is
-- already defined and accessible

-- Minor issue: categories CTE is unnecessary
-- we can query invoice_revenue directly



-- FINAL QUERY

-- using clean data
with clean_ecommerce as (
	select *
	from online_retail
	where invoiceno not like 'C%'
	and quantity > 0
	and unitprice > 0
	and customerid is not null
),

-- create the case logic for categorization of total_invoice_value
invoice_revenue as (
select invoiceno, 
round(sum(quantity * unitprice), 2) as total_invoice_value,

case
    when round(sum(quantity * unitprice), 2) < 200 then 'Small'
    when round(sum(quantity * unitprice), 2) >= 200 
        and round(sum(quantity * unitprice), 2) < 1000 then 'Medium'
    when round(sum(quantity * unitprice), 2) >= 1000 then 'Large'
end as revenue_buckets


from clean_ecommerce
group by invoiceno
)

-- find how many invoices that fall into each bucket
select revenue_buckets, count(*) as bucket_count,
-- include a percentage of whole to show a better picture of bucket count
round(bucket_count / sum(bucket_count) over () * 100, 2) as pct_of_total
from invoice_revenue
group by revenue_buckets;





-- -------------------------------------
-- Phase 3 - Advanced Queries
-- -------------------------------------

-- 1. Rank top products within each country
-- Which products are the best sellers in each country?
-- Use RANK() with PARTITION BY to rank products by
-- total quantity sold within each country.
-- Return only the top 3 products per country.

with clean_ecommerce as (
	select *, (quantity * unitprice) as revenue
	from __online_retail__
	where invoiceno not like 'C%'
	and quantity > 0
	and unitprice > 0
	and customerid is not null
),

ranked_data as (
select stockcode, description, quantity, country,
	rank() over (
		partition by country
		order by quantity desc)
	as ranking
from clean_ecommerce
group by stockcode, description, quantity, country
)

select *
from ranked_data
where ranking <= 3;

-- ISSUE: quantity is a raw row level value, not an aggregated one
-- are you actually summing up the total quantity sold
-- per product per country, or are you just grouping
-- individual row quantities?

-- think back to the same mistake in Phase 1 top 10 products query
-- this is the same pattern

with clean_ecommerce as (
	select *, (quantity * unitprice) as revenue
	from online_retail
	where invoiceno not like 'C%'
	and quantity > 0
	and unitprice > 0
	and customerid is not null
),

ranked_data as (
select stockcode, description,
-- sum(quantity) properly aggregates total quantity per product per country
sum(quantity) as total_quantity, country,
	rank() over (
		partition by country
		order by total_quantity desc)
	as ranking
from clean_ecommerce
group by stockcode, description, country
)

select *
from ranked_data
where ranking <= 3;

-- One thing about RANK()
-- if 2 products have the same total_quantity within a country,
-- they'll both get the same rank and the next rank will be skipped
-- ex. (1, 2, 2, 4)

-- To get consecutive ranking without gaps, use DENSE_RANK()
-- neither is wrong, they just behave differently on ties

-- try it
with clean_ecommerce as (
	select *, (quantity * unitprice) as revenue
	from online_retail
	where invoiceno not like 'C%'
	and quantity > 0
	and unitprice > 0
	and customerid is not null
),

ranked_data as (
select stockcode, description,
-- sum(quantity) properly aggregates total quantity per product per country
sum(quantity) as total_quantity, country,
	dense_rank() over (
		partition by country
		order by total_quantity desc)
	as ranking
from clean_ecommerce
group by stockcode, description, country
)

select *
from ranked_data
where ranking <= 3;



-- 2. Running total revenue over time
-- Using your monthly revenue results from Phase 2,
-- calculate a cumulative running total of 
-- revenue month by month. Look into sum() over (order by month).

-- phase 2 monthly revenue results
with clean_ecommerce as (
	select *
	from online_retail
	where invoiceno not like 'C%'
	and quantity > 0
	and unitprice > 0
	and customerid is not null
)
select date_trunc('month', invoicedate) as month,
round(sum(quantity * unitprice), 2) as total_revenue
from clean_ecommerce
group by month
order by month;

-- let's turn the bottom select query into a CTE we can select from
with clean_ecommerce as (
	select *
	from online_retail
	where invoiceno not like 'C%'
	and quantity > 0
	and unitprice > 0
	and customerid is not null
),

total_revenue_over_time as (
-- make sure invoicedate is not still a varchar
-- if you need to, go back to the phase 2 question 
-- and update the column type
	select date_trunc('month', invoicedate) as month,
	-- select date_trunc('month', strptime(invoicedate, '%m/%d/%Y %H:%M')) as month,
	round(sum(quantity * unitprice), 2) as total_revenue
	from clean_ecommerce
	group by month
	order by month
)

select month, total_revenue, round(sum(total_revenue) over (order by month), 2) as running_total
from total_revenue_over_time;



-- 3. Month-over-month revenue change
-- How much did revenue grow or shrink compared to 
-- the previous month? Look into the LAG() function - it lets
-- you reference the value from a previous row.

with clean_ecommerce as (
	select *
	from online_retail
	where invoiceno not like 'C%'
	and quantity > 0
	and unitprice > 0
	and customerid is not null
),

total_revenue_over_time as (
	select date_trunc('month', strptime(invoicedate, '%m/%d/%Y %H:%M')) as month,
	round(sum(quantity * unitprice), 2) as total_revenue
	from clean_ecommerce
	group by month
	order by month
),

monthly_revenue as (
	select month, total_revenue, round(sum(total_revenue) over (order by month), 2) as running_total
	from total_revenue_over_time
)

select month, total_revenue,
round(lag(total_revenue, 1, 0) over (order by month), 2) as previous_month,
total_revenue - round(lag(total_revenue, 1, 0) over (order by month), 2) as revenue_change
from monthly_revenue;

-- Minor issue: revenue_change is not being rounded
-- you are rounding the lag part in the final select query, but
-- the overall subtraction expression itself isn't wrapped in ROUND()
-- the ROUND() only applies to what's inside the parentheses

with clean_ecommerce as (
	select *
	from online_retail
	where invoiceno not like 'C%'
	and quantity > 0
	and unitprice > 0
	and customerid is not null
),

total_revenue_over_time as (
	select date_trunc('month', strptime(invoicedate, '%m/%d/%Y %H:%M')) as month,
	round(sum(quantity * unitprice), 2) as total_revenue
	from clean_ecommerce
	group by month
	order by month
),

monthly_revenue as (
	select month, total_revenue, round(sum(total_revenue) over (order by month), 2) as running_total
	from total_revenue_over_time
)

select month, total_revenue,
round(lag(total_revenue, 1, 0) over (order by month), 2) as previous_month,
round(total_revenue - lag(total_revenue, 1, 0) over (order by month), 2) as revenue_change
from monthly_revenue;

-- The running_total in monthly_revenue is unused and the final
-- SELECT statement doesn't reference it, so that whole CTE
-- is doing extra work for nothing.

-- You could query total_revenue_over_time directly in your final SELECT
-- and remove monthly_revenue entirely, which keeps the query leaner.

with clean_ecommerce as (
	select *
	from online_retail
	where invoiceno not like 'C%'
	and quantity > 0
	and unitprice > 0
	and customerid is not null
),

total_revenue_over_time as (
	select date_trunc('month', strptime(invoicedate, '%m/%d/%Y %H:%M')) as month,
	round(sum(quantity * unitprice), 2) as total_revenue
	from clean_ecommerce
	group by month
	order by month
)
-- removed monthly_revenue CTE
select month, total_revenue,
round(lag(total_revenue, 1, 0) over (order by month), 2) as previous_month,
round(total_revenue - lag(total_revenue, 1, 0) over (order by month), 2) as revenue_change
from total_revenue_over_time;

-- You're also calling LAG() twice. You calculate the same LAG()
-- expression for previous month and again for revenue_change. 
-- It works, but it's repetitive. A cleaner approach is to
-- wrap the LAG() result in another CTE first, then reference it
-- by alias in the final SELECT.

with clean_ecommerce as (
	select *
	from online_retail
	where invoiceno not like 'C%'
	and quantity > 0
	and unitprice > 0
	and customerid is not null
),

total_revenue_over_time as (
	select date_trunc('month', strptime(invoicedate, '%m/%d/%Y %H:%M')) as month,
	round(sum(quantity * unitprice), 2) as total_revenue
	from clean_ecommerce
	group by month
	order by month
),
-- wrapping the LAG() in another CTE first
revenue_change as (
	select month, total_revenue,
	round(lag(total_revenue, 1, 0) over (order by month), 2) as previous_month
	from total_revenue_over_time
)
-- now reference it by alias
select month, total_revenue, previous_month,
round(total_revenue - previous_month, 2) as revenue_change
from revenue_change;



-- FINAL SOLUTION
with clean_ecommerce as (
	select *
	from online_retail
	where invoiceno not like 'C%'
	and quantity > 0
	and unitprice > 0
	and customerid is not null
),

total_revenue_over_time as (
	select date_trunc('month', invoicedate) as month,	
	-- only use below line if the column type of invoicedate hasn't been updated
	--select date_trunc('month', strptime(invoicedate, '%m/%d/%Y %H:%M')) as month,
	round(sum(quantity * unitprice), 2) as total_revenue
	from clean_ecommerce
	group by month
	order by month
),

revenue_change as (
	select month, total_revenue,
	round(lag(total_revenue, 1, 0) over (order by month), 2) as previous_month
	from total_revenue_over_time
)

select month, total_revenue, previous_month,
round(total_revenue - previous_month, 2) as revenue_change
from revenue_change;



-- 4. Most valuable customers by total spend
-- Who are the top 20 customers by total revenue?
-- Remember that ~135,000 rows have no CustomerID, so your
-- clean data filter will handle that naturally.

with clean_ecommerce as (
	select *
	from online_retail
	where invoiceno not like 'C%'
	and quantity > 0
	and unitprice > 0
	and customerid is not null
)
select customerid, country, 
round(sum(quantity * unitprice), 2) as total_revenue
from clean_ecommerce
group by customerid, country
order by total_revenue desc
limit 20;

-- note: grouping by country may split customers
-- with transactions across multiple countries

-- Wrap complex logic in CTEs
-- By this point you should be naturally doing this already -
-- but make sure each of your Phase 3 queries uses CTEs to keep
-- the logic readable and well-commented.



-- BONUS QUESTION - Segment customers into quartiles by spend
-- Use NTILE() to accomplish this

with clean_ecommerce as (
	select *
	from online_retail
	where invoiceno not like 'C%'
	and quantity > 0
	and unitprice > 0
	and customerid is not null
),

customer_revenue as (
	select customerid,
	round(sum(quantity * unitprice), 2) as total_revenue
	from clean_ecommerce
	group by customerid
)

select customerid, total_revenue,
ntile(4) over (order by total_revenue desc) as rev_quartiles
from customer_revenue
order by total_revenue desc;

-- NTILE() is about dividing rows evenly by count, not value
-- There are 4338 rows in this result set, so each quartile
-- will contain roughly 1084 or 1085 customerids.

-- Interesting finding - the top 25% of customers are responsible
-- for a disproportionately large share of the total revenue.

-- This is a classic pattern in retail known as the 
-- Pareto principle or 80/20 rule, where roughly 80% of 
-- revenue comes from 20% of customers.

-- Let's quantify that by extending the above query further.

with clean_ecommerce as (
	select *
	from online_retail
	where invoiceno not like 'C%'
	and quantity > 0
	and unitprice > 0
	and customerid is not null
),

customer_revenue as (
	select customerid,
	round(sum(quantity * unitprice), 2) as total_revenue
	from clean_ecommerce
	group by customerid
),

revenue_segments as (
	select customerid, total_revenue,
	ntile(4) over (order by total_revenue desc) as rev_quartiles
	from customer_revenue
	order by total_revenue desc
)

select rev_quartiles, count(customerid) as customer_count,
round(sum(total_revenue), 2) as quartile_revenue
from revenue_segments
group by rev_quartiles
order by rev_quartiles;

-- Percentages would tell a better story here. Find the 
-- combined total revenue and divide quartile_revenue by that.

with clean_ecommerce as (
	select *
	from online_retail
	where invoiceno not like 'C%'
	and quantity > 0
	and unitprice > 0
	and customerid is not null
),

customer_revenue as (
	select customerid,
	round(sum(quantity * unitprice), 2) as total_revenue
	from clean_ecommerce
	group by customerid
),

revenue_segments as (
	select customerid, total_revenue,
	ntile(4) over (order by total_revenue desc) as rev_quartiles
	from customer_revenue
	order by total_revenue desc
),

quart_rev as (
	select rev_quartiles, count(customerid) as customer_count,
	round(sum(total_revenue), 2) as quartile_revenue
	from revenue_segments
	group by rev_quartiles
	order by rev_quartiles
)

select rev_quartiles, quartile_revenue,
round(quartile_revenue / sum(quartile_revenue) over () * 100, 2) as pct_of_total
from quart_rev;

-- The Pareto principle strikes true here. Revenue quartile 1
-- is responsible for 79% of the combined total revenue.





-- -------------------------------------
-- Phase 4 - Findings
-- -------------------------------------

-- Write a short summary of 3–5 key findings from your analysis
-- Connect DBeaver to Tableau and build a simple dashboard 
-- visualizing your top findings

-- 1. Total revenue spiked during the 2011 fall season 
-- (Sep 2011 - Nov 2011), rising from the ~450k to ~680k range 
-- to a ~950k to ~1.16m range during that period.

-- Holiday seasonal demand could be the cause of this.

with clean_ecommerce as (
	select *
	from online_retail
	where invoiceno not like 'C%'
	and quantity > 0
	and unitprice > 0
	and customerid is not null
),

total_revenue_over_time as (
	select date_trunc('month', invoicedate) as month,	
	-- only use below line if the column type of invoicedate hasn't been updated
	--select date_trunc('month', strptime(invoicedate, '%m/%d/%Y %H:%M')) as month,
	round(sum(quantity * unitprice), 2) as total_revenue
	from clean_ecommerce
	group by month
	order by month
),

revenue_change as (
	select month, total_revenue,
	round(lag(total_revenue, 1, 0) over (order by month), 2) as previous_month
	from total_revenue_over_time
)

select month, total_revenue, previous_month,
round(total_revenue - previous_month, 2) as revenue_change
from revenue_change;


-- 2. Singapore (3039.9), Netherlands (3036.66), and Australia (2430.2) 
-- rounded out the top 3 in highest average order value, 
-- although they did not have the highest unique invoice totals.

with clean_ecommerce as (
	select *
	from online_retail
	where invoiceno not like 'C%'
	and quantity > 0
	and unitprice > 0
	and customerid is not null
),

order_value as (
	select country,
	count(distinct invoiceno) as unique_invoice_total,
	round(sum(quantity * unitprice), 2) as total_revenue
	from clean_ecommerce
	group by country
)

select country, 
round(total_revenue / unique_invoice_total, 2) as avg_order_value,
unique_invoice_total
from order_value
order by avg_order_value desc;

-- 3. The UK dominated the total revenue with nearly 7.3m,
-- while Saudi Arabia ranked lowest in total revenue at 145.9.

with clean_ecommerce as (
	select *, (quantity * unitprice) as revenue
	from online_retail
	where invoiceno not like 'C%'
	and quantity > 0
	and unitprice > 0
	and customerid is not null
)
select country, 
round(sum(revenue), 2) as total_revenue
from clean_ecommerce
group by country
order by total_revenue desc;


-- 4. Medium sized orders, which are defined as the
-- total invoice value being anywhere from £200 - £1000,
-- made up ~11k (~60%) of all total orders.

with clean_ecommerce as (
	select *
	from online_retail
	where invoiceno not like 'C%'
	and quantity > 0
	and unitprice > 0
	and customerid is not null
),

invoice_revenue as (
	select invoiceno, 
	round(sum(quantity * unitprice), 2) as total_invoice_value,
	
	case
	    when round(sum(quantity * unitprice), 2) < 200 then 'Small'
	    when round(sum(quantity * unitprice), 2) >= 200 
	        and round(sum(quantity * unitprice), 2) < 1000 then 'Medium'
	    when round(sum(quantity * unitprice), 2) >= 1000 then 'Large'
	end as revenue_buckets
	
	from clean_ecommerce
	group by invoiceno
)

select revenue_buckets, count(*) as bucket_count,
round(bucket_count / sum(bucket_count) over () * 100, 2) as pct_of_total
from invoice_revenue
group by revenue_buckets;

-- 5. Data issues - 
-- I was surprised to discover there were over 9k cancelled orders,
-- over 10k rows where quantity was less than or equal to 0,
-- over 2.5k rows where unitprice was less than or equal to 0,
-- and ~135k rows where customerid is null.

select count(*)
from online_retail
where invoiceno like 'C%';
-- 9288 cancelled orders

select count(*)
from online_retail
where quantity <= 0;
-- 10,624 rows where quantity was less than 0

select count(*)
from online_retail
where unitprice <= 0;
-- 2517 rows where unitprice is less than or equal to 0

select count(*) 
from online_retail
where CustomerID is null;
-- 135,080 rows where customer id is null





-- -------------------------------------
-- Phase 5 - Exporting to Tableau
-- -------------------------------------

-- I'd suggest exporting the following result sets 
-- since they'll give you the most visually interesting charts:

-- 1. Monthly revenue trend

with clean_ecommerce as (
	select *
	from online_retail
	where invoiceno not like 'C%'
	and quantity > 0
	and unitprice > 0
	and customerid is not null
),

total_revenue_over_time as (
	select date_trunc('month', invoicedate) as month,	
	-- only use below line if the column type of invoicedate hasn't been updated
	--select date_trunc('month', strptime(invoicedate, '%m/%d/%Y %H:%M')) as month,
	round(sum(quantity * unitprice), 2) as total_revenue
	from clean_ecommerce
	group by month
	order by month
),

revenue_change as (
	select month, total_revenue,
	round(lag(total_revenue, 1, 0) over (order by month), 2) as previous_month
	from total_revenue_over_time
)

select month, total_revenue, previous_month,
round(total_revenue - previous_month, 2) as revenue_change
from revenue_change;

-- 2. Total revenue by country

with clean_ecommerce as (
	select *, (quantity * unitprice) as revenue
	from online_retail
	where invoiceno not like 'C%'
	and quantity > 0
	and unitprice > 0
	and customerid is not null
)
select country, 
round(sum(revenue), 2) as total_revenue
from clean_ecommerce
group by country
order by total_revenue desc;

-- 3. Revenue bucket counts

with clean_ecommerce as (
	select *
	from online_retail
	where invoiceno not like 'C%'
	and quantity > 0
	and unitprice > 0
	and customerid is not null
),

invoice_revenue as (
	select invoiceno, 
	round(sum(quantity * unitprice), 2) as total_invoice_value,
	
	case
	    when round(sum(quantity * unitprice), 2) < 200 then 'Small'
	    when round(sum(quantity * unitprice), 2) >= 200 
	        and round(sum(quantity * unitprice), 2) < 1000 then 'Medium'
	    when round(sum(quantity * unitprice), 2) >= 1000 then 'Large'
	end as revenue_buckets
	
	from clean_ecommerce
	group by invoiceno
)

select revenue_buckets, count(*) as bucket_count,
round(bucket_count / sum(bucket_count) over () * 100, 2) as pct_of_total
from invoice_revenue
group by revenue_buckets;

-- 4. Customer quartile breakdown

with clean_ecommerce as (
	select *
	from online_retail
	where invoiceno not like 'C%'
	and quantity > 0
	and unitprice > 0
	and customerid is not null
),

customer_revenue as (
	select customerid,
	round(sum(quantity * unitprice), 2) as total_revenue
	from clean_ecommerce
	group by customerid
),

revenue_segments as (
	select customerid, total_revenue,
	ntile(4) over (order by total_revenue desc) as rev_quartiles
	from customer_revenue
	order by total_revenue desc
),

quart_rev as (
	select rev_quartiles, count(customerid) as customer_count,
	round(sum(total_revenue), 2) as quartile_revenue
	from revenue_segments
	group by rev_quartiles
	order by rev_quartiles
)

select rev_quartiles, quartile_revenue,
round(quartile_revenue / sum(quartile_revenue) over () * 100, 2) as pct_of_total
from quart_rev;

