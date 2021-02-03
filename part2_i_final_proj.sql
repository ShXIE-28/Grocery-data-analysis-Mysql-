-- ----------Part a-----------------------------------------------------------------
-- a. How many:
-- Q1. Store shopping trips are recorded in your database? # 7596145
SELECT COUNT(DISTINCT TC_id) FROM trips;

-- Q2. Households appear in your database? # 39577
SELECT COUNT(*) FROM households;

-- Q3. Stores of different retailers appear in our data base? # 863
SELECT TC_retailer_code, COUNT(DISTINCT TC_retailer_code_store_code) FROM trips WHERE TC_retailer_code_store_code <> 0 GROUP BY TC_retailer_code;

-- Q4. Different products are recorded?
-- i. Products per category and products per module
SELECT COUNT(DISTINCT prod_id), group_at_prod_id FROM products GROUP BY group_at_prod_id; # 119
SELECT COUNT(DISTINCT prod_id), module_at_prod_id FROM products GROUP BY module_at_prod_id; # 1225

-- ii. Plot the distribution of products per module and products per category(python code)
# results saved as file a_prod_module_per_dept.csv

-- Q5. Total transactions # 38587942
SELECT COUNT(*) FROM purchases;

-- transactions realized under some kind of promotion # 2603946
SELECT COUNT(*) FROM purchases WHERE coupon_value_at_TC_prod_id <> 0.00;

-- ------------PART B----------- --------------------------------------------------------------------
-- b. Aggregate the data at the household‐monthly level to answer the following questions:
-- Q1. How many households do not shop at least once on a 3 month periods. # 32 (90 days as 3 months period)
-- correct the format of date
CREATE TABLE monthly(
	SELECT hh_id, STR_TO_DATE(TC_DATE, '%Y-%m-%d') AS correct_date, YEAR(STR_TO_DATE(TC_DATE, '%Y-%m-%d')) AS year, MONTH(STR_TO_DATE(TC_DATE, '%Y-%m-%d')) AS month
	FROM trips
	WHERE TC_total_spent <> 0
	ORDER BY hh_id, year, month
);
ALTER TABLE monthly ORDER BY hh_id, correct_date;

-- date + id
CREATE TABLE date(
	SELECT hh_id, correct_date, ROW_NUMBER() OVER (ORDER BY hh_id, correct_date) AS num
    from monthly
    ORDER BY hh_id, correct_date
);
ALTER TABLE date ADD INDEX (num);

-- date + id2
CREATE TABLE date2(
	SELECT *, 1+num AS num2 FROM date  
);
ALTER TABLE date2 ADD INDEX (num2);

-- combine tables
SELECT COUNT(DISTINCT C.hh_id)
FROM
(SELECT A.hh_id, DATEDIFF(A.correct_date, B.correct_date) AS TIME_WINDOW_SIZE
FROM date AS A INNER JOIN date2 AS B
ON A.num = B.num2
WHERE A.hh_id = B.hh_id) AS C
WHERE C.TIME_WINDOW_SIZE > 90; # get the result: 32

-- Q2. Among the households who shop at least once a month, which % of them concentrate at least 80% of their grocery expenditure (on average) on single retailer? And among 2 retailers?
-- create temporary table of adding month+year
DROP TABLE IF EXISTS trip_yearmonth;
CREATE TEMPORARY TABLE trip_yearmonth
    SELECT * , STR_TO_DATE(TC_date,'%Y-%m-%d') as date_correct,  EXTRACT( YEAR_MONTH from STR_TO_DATE(TC_date,'%Y-%m-%d')) as yearmonth
    from trips
    order by hh_id ASC, date_correct ASC;
 
-- add index 1 
DROP TABLE IF EXISTS trip_yearmonth1;
CREATE TEMPORARY TABLE trip_yearmonth1
select  hh_id, yearmonth, ROW_NUMBER() OVER (ORDER BY hh_id ASC,yearmonth ASC) as ID1
from trip_yearmonth 
group by hh_id,yearmonth 
order by hh_id ;
-- add index 2
DROP TABLE IF EXISTS trip_yearmonth2;
CREATE TEMPORARY TABLE trip_yearmonth2
   SELECT *, 1 + ID1 AS ID2 FROM trip_yearmonth1 order by  hh_id ASC;

-- add right table index
       ALTER TABLE trip_yearmonth2 ADD INDEX y (ID2); 
-- differencing + select households
DROP TABLE IF EXISTS trip_households;
CREATE TEMPORARY TABLE trip_households
 select * from (select a.hh_id as hh_id1 , a.yearmonth as date_0, b.yearmonth as date_1, datediff(a.yearmonth,b.yearmonth) as time_window_size
   from trip_yearmonth1 as a inner join trip_yearmonth2 as b on a.ID1=b.ID2) as aa 
   where time_window_size > 1 and time_window_size < 20 ;

  -- add right table index
       ALTER TABLE trip_households ADD INDEX y (hh_id1); 
       -- combine--->get households
DROP TABLE IF EXISTS trip_households1;
CREATE TEMPORARY TABLE trip_households1
  select * from trips a left join trip_households b on a.hh_id=b.hh_id1 where b.hh_id1 is NULL order by a.hh_id ;
create temporary table temp1
select sum(TC_total_spent)as total_spend,hh_id from trip_households1 group by hh_id order by hh_id ;
create temporary table temp2
select sum(TC_total_spent)as spend_per_retailer,hh_id, TC_retailer_code from trip_households1 group by hh_id,TC_retailer_code ;
-- add right table index
       ALTER TABLE temp2 ADD INDEX y (hh_id); 
      -- at least 1 household has 1 retailers >80% (total number is 888)
create temporary table 1_retailer
select round(b.spend_per_retailer/a.total_spend,3)*100 as "percentage(%)", a.hh_id,b.TC_retailer_code 
from temp1 as a 
inner join  temp2 as b on a.hh_id= b.hh_id
 where round(b.spend_per_retailer/a.total_spend,3)*100 >=80
order by a.hh_id;

 -- at least 1 household has 2 retailers >80%
SELECT @@sql_mode;
set sql_mode ="STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION";
-- get total households sum_percentage(intermidate)
select percentage,hh_id,TC_retailer_code
from(
SELECT
    @r:= case when @type=aa.hh_id
               then @r+1 
               else 1  
               end as rowNum,

    @type:=aa.hh_id as household_id,
    aa.* 
from 
    (select round(b.spend_per_retailer/a.total_spend,3)*100 as percentage, a.hh_id,b.TC_retailer_code 
from temp1 as a 
inner join  temp2 as b on a.hh_id= b.hh_id
order by a.hh_id,round(b.spend_per_retailer/a.total_spend,3)*100 desc)as aa ,(select @r:=0,@type:='') bb) as aaa
where aaa.rowNum between 1 and 2 
group by aaa.hh_id,aaa.TC_retailer_code;
-- get the targeted percentage( total is 3418)
create temporary table 2_retailers
select sum(bbb.percentage)as sum_percentage,bbb.hh_id
from(select percentage,hh_id,TC_retailer_code
from(
SELECT
    @r:= case when @type=aa.hh_id
               then @r+1 
               else 1  
               end as rowNum,

    @type:=aa.hh_id as household_id,
    aa.* 
    from 
    (select round(b.spend_per_retailer/a.total_spend,3)*100 as percentage, a.hh_id,b.TC_retailer_code 
from temp1 as a 
inner join  temp2 as b on a.hh_id= b.hh_id
order by a.hh_id,round(b.spend_per_retailer/a.total_spend,3)*100 desc)as aa ,(select @r:=0,@type:='') bb) as aaa
where aaa.rowNum between 1 and 2 
group by aaa.hh_id,aaa.TC_retailer_code ) as bbb group by bbb.hh_id 
having sum(bbb.percentage) > 80;

-- Q2 i Are their demographics remarkably different? Are these people richer? Poorer?
    -- ---- for demographics
select count(*) as targeted_household, aa.hh_race from (select b.* from part2 a inner join households b on a.hh_id=b.hh_id) aa group by aa.hh_race;
select count(*) as total_household, hh_race from households group by hh_race;
select count(*) from households;
select aa.targeted_household,bb.total_household as total_household_in_race ,(aa.targeted_household/bb.total_household)*100 as 'per_in_household%',(aa.targeted_household/39577)*100 as 'per_in_total_household%',aa.hh_race 
from (select count(*) as targeted_household, aa.hh_race from (select b.* from part2 a inner join households b on a.hh_id=b.hh_id) aa group by aa.hh_race)aa
inner join 
(select count(*) as total_household, hh_race from households group by hh_race) bb on aa.hh_race=bb.hh_race;
    -- ---- for richer or poorer
  select avg(hh_income) from households; -- 18.7170
  select avg(a.hh_income) from households a inner join 1_retailer b on a.hh_id=b.hh_id; -- 17.3468
  select avg(a.hh_income) from households a inner join 2_retailers b on a.hh_id=b.hh_id; -- 17.3089
  
  -- Q2 ii. What is the retailer that has more loyalists? (retail number:6920)
select count(a.hh_id) as total_number, b.TC_retailer_code from households a inner join 1_retailer b on a.hh_id=b.hh_id group by b.TC_retailer_code order by count(a.hh_id) DESC ;

select count(m.hh_id) as total_number,m.TC_retailer_code  from(
select percentage,hh_id,TC_retailer_code
from(
SELECT
    @r:= case when @type=aa.hh_id
               then @r+1 
               else 1  
               end as rowNum,

    @type:=aa.hh_id as household_id,
    aa.* 
from 
    (select round(b.spend_per_retailer/a.total_spend,3)*100 as percentage, a.hh_id,b.TC_retailer_code 
from temp1 as a 
inner join  temp2 as b on a.hh_id= b.hh_id
order by a.hh_id,round(b.spend_per_retailer/a.total_spend,3)*100 desc)as aa ,(select @r:=0,@type:='') bb) as aaa
where aaa.rowNum between 1 and 2 
group by aaa.hh_id,aaa.TC_retailer_code )as m inner join 2_retailers n on m.hh_id=n.hh_id 
group by m.TC_retailer_code
order by count(m.hh_id) DESC ;

-- iii. Where do they live? Plot the distribution by state.(python code)

-- 	Q3. Plot with the distribution:
-- i. Average number of items purchased on a given month.
# results saved as b_q3_i.csv
CREATE TABLE monthly_prod(
	SELECT trips.hh_id, STR_TO_DATE(TC_DATE, '%Y-%m-%d') AS correct_date, YEAR(STR_TO_DATE(TC_DATE, '%Y-%m-%d')) AS year, MONTH(STR_TO_DATE(TC_DATE, '%Y-%m-%d')) AS month, purchases.prod_id, quantity_at_TC_prod_id
	FROM trips RIGHT JOIN purchases
	ON trips.TC_id = purchases.TC_id);

SELECT month, AVG(num_items) FROM 
(SELECT month, hh_id, SUM(quantity_at_TC_prod_id) AS num_items 
FROM monthly_prod GROUP BY month, hh_id) AS A 
GROUP BY month 
ORDER BY month;

-- ii. Average number of shopping trips per month.
# results saved as b_q3_ii.csv
SELECT month, AVG(num_trips) FROM
(SELECT month, hh_id, COUNT(correct_date) AS num_trips
FROM monthly_prod GROUP BY month, hh_id) AS A
GROUP BY month
ORDER BY month;

-- iii. Average number of days between 2 consecutive shopping trips.
# results saved as b_q3_iii.csv
SELECT month, AVG(AVG_TIME_WINDOW_SIZE) FROM
(SELECT A.hh_id, MONTH(A.correct_date) AS month, AVG(DATEDIFF(A.correct_date, B.correct_date)) AS AVG_TIME_WINDOW_SIZE
FROM date AS A INNER JOIN date2 AS B
ON A.num = B.num2
WHERE A.hh_id = B.hh_id
GROUP BY MONTH(A.correct_date), A.hh_id) AS C
GROUP BY month
ORDER BY month;

-- -----------Part c----------------------------------------------------------------------------------------------
-- c. Answer and reason the following questions: (Make informative visualizations)
-- Is the number of shopping trips per month correlated with the average number of items purchased?
# resutls saved as c_q1.csv
SELECT C.month, AVG(num_items), AVG(num_trips)
FROM
(SELECT month, AVG(num_items) FROM 
(SELECT month, hh_id, SUM(quantity_at_TC_prod_id) AS num_items 
FROM monthly_prod GROUP BY month, hh_id) AS A 
GROUP BY month 
ORDER BY month) AS C
JOIN
(SELECT month, AVG(num_trips) FROM
(SELECT month, hh_id, COUNT(correct_date) AS num_trips
FROM monthly_prod GROUP BY month, hh_id) AS B
GROUP BY month
ORDER BY month) AS D
ON C.month = D.month;

-- Is the average price paid per item correlated with the number of items purchased?
# results saved as c_q2.csv
SELECT prod_id, FORMAT(SUM(total_price_paid_at_TC_prod_id) / SUM(quantity_at_TC_prod_id),2), SUM(quantity_at_TC_prod_id) 
FROM purchases 
GROUP BY TC_id;

-- Private Labeled products are the products with the same brand as the supermarket. In the data set they appear labeled as ‘CTL BR’
-- i What are the product categories that have proven to be more “Private labelled”
# results saved as file PC_3_i.csv
 select count(prod_id)as total_number_CTL_BR,group_at_prod_id as category 
   from CTL_BR_Product
   group by group_at_prod_id
   order by count(prod_id) DESC;
 
 select a.*,b.* , round(b.total_number_CTL_BR/a.total_number,3)*100 as percentage from (  select count(prod_id)as total_number,group_at_prod_id as category 
   from products 
   group by group_at_prod_id) a inner join ( select count(prod_id)as total_number_CTL_BR,group_at_prod_id as category 
   from CTL_BR_Product
   group by group_at_prod_id)b on a.category=b.category order by round(b.total_number_CTL_BR/a.total_number,3)*100 DESC;

-- ii Is the expenditure share in Private Labeled products constant across months?
# results saved as Pc_3_ii.csv
 -- step 1 : join table products with purchase table 
   drop table if exists CTL_BR_Purchase; 
   create temporary table CTL_BR_Purchase;
        select a.TC_id,a.quantity_at_TC_prod_id,a.total_price_paid_at_TC_prod_id,a.coupon_value_at_TC_prod_id,a.deal_flag_at_TC_prod_id,
               b.brand_at_prod_id,b.department_at_prod_id,b.prod_id,b.group_at_prod_id,b.module_at_prod_id,b.amount_at_prod_id
        from purchases a inner join CTL_BR_Product b on a.prod_id= b.prod_id limit 10 ;
 
  select count(total_price_paid_at_TC_prod_id) from CTL_BR_Purchase;
  select a.TC_id,a.quantity_at_TC_prod_id,a.total_price_paid_at_TC_prod_id,a.coupon_value_at_TC_prod_id,a.deal_flag_at_TC_prod_id,
               b.brand_at_prod_id,b.department_at_prod_id,b.prod_id,b.group_at_prod_id,b.module_at_prod_id,b.amount_at_prod_id
               ,c.TC_date
        from purchases a inner join CTL_BR_Product b on a.prod_id= b.prod_id inner join trips c on a.TC_id=c.TC_id;
-- step 2 : use python to do the calculation (see details in file c_q3_ii.html)

-- iii the distribution of monthly expenduture on grocery of three income groups
-- divide the household
--  step 1 adjust the income by household size 
       -- Adjusted household income = Household income / (Household size)N(where N= 0.5)

drop table if exists household_adjust_income;
create temporary table household_adjust_income
select row_number() over (order by round(hh_income/sqrt(hh_size),3)) as adjust_income_rank,
       round(hh_income/sqrt(hh_size),3) as adjusted_income,hh_income,
       hh_id 
from households ;
--  step 2 calcualte the median
select count(*) from households; -- 39577 
  select * from (select row_number() over (order by round(hh_income/sqrt(hh_size),3)) as adjust_income_rank,
       round(hh_income/sqrt(hh_size),3) as adjusted_income,hh_income,
       hh_id 
from households) as a 
where a.adjust_income_rank= (39577+1)/2; -- so the median adjust_income is 13.000
-- step 3 the range for median is :(8.6667,26)
-- step 4 select each part of households
-- Assumption: low income: adjusted_income < 10; medium income: adjusted_income between 10 and 18; high income: adjusted_income > 18
# results see file adjusted_hh_income.csv
 select count(*) 
 from household_adjust_income 
 where adjusted_income < 10; -- 9243 (23.35%)
 select count(*) 
 from household_adjust_income 
 where adjusted_income
 between 10 and 18; -- 23703 (59.89%)
 select count(*) 
 from household_adjust_income 
 where adjusted_income > 18; -- 6631 (16.75%)
# results of three income groups are saved seperately.

-- use high income as an example 
    -- step 1 comnine household with trips
	select b.hh_id, a.TC_id, EXTRACT( YEAR_MONTH from STR_TO_DATE(a.TC_date,'%Y-%m-%d')) as yearmonth
    from trips a
     inner join 
     ( select hh_id from household_adjust_income where adjusted_income > 18) b on a.hh_id=b.hh_id ;
     
     -- low income
	select b.hh_id, a.TC_id, EXTRACT( YEAR_MONTH from STR_TO_DATE(a.TC_date,'%Y-%m-%d')) as yearmonth
    from trips a
     inner join 
     ( select  hh_id 
 from household_adjust_income 
 where adjusted_income < 10) b on a.hh_id=b.hh_id ;
 
 -- medium income
 select b.hh_id, a.TC_id, EXTRACT( YEAR_MONTH from STR_TO_DATE(a.TC_date,'%Y-%m-%d')) as yearmonth
    from trips a
     inner join 
     ( select  hh_id 
 from household_adjust_income 
 where adjusted_income between 10 and 18) b on a.hh_id=b.hh_id ;
# step 5 all results are calculated by python(see details in file c_q3_iii.html)

# for all graph codes, please turn to see file project_graph_code.html

