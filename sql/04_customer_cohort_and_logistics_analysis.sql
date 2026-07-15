-- ============================================================
-- Olist Customer Cohort and Logistics Analysis
-- ============================================================
/*
目的：
1. 建構成熟客戶分析群組
2. 驗證物流、運費、評論及地理位置數據
3. 產生用於 Power BI 的最終分析表
*/

-- ============================================================
-- Step 1. 建立有效已送達訂單資料 step1_effective_orders
-- ============================================================
CREATE TABLE step1_effective_orders AS
SELECT 
    o.order_id,
    o.customer_id,
    c.customer_unique_id,
    c.customer_state,
    o.order_purchase_timestamp::TIMESTAMP AS order_purchase_timestamp
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'; 


-- ============================================================
-- Step 2. 彙整至不重複顧客層級 step2_unique_customers
-- ============================================================
CREATE TABLE step2_unique_customers AS
WITH unique_orders_per_customer AS (
    -- 先把每個買家「重複的訂單列」收攏，確保一筆訂單就是一列
    SELECT 
        customer_unique_id,
        customer_state,
        order_id,
        order_purchase_timestamp
    FROM step1_effective_orders
    GROUP BY customer_unique_id, customer_state, order_id, order_purchase_timestamp
),
ranked_customers AS (
    SELECT 
        customer_unique_id,
        customer_state,
        -- 精確計算這個買家這輩子到底下了幾筆「不重複的訂單」
        COUNT(order_id) OVER(PARTITION BY customer_unique_id) AS total_orders,
        -- 找出這個買家最早的下單時間
        MIN(order_purchase_timestamp) OVER(PARTITION BY customer_unique_id) AS first_purchase_time,
        -- 依據訂單時間排序，找出最新的一筆訂單，用來抓取他最新的主州別
        ROW_NUMBER() OVER(PARTITION BY customer_unique_id ORDER BY order_purchase_timestamp DESC, order_id DESC) AS rn
    FROM unique_orders_per_customer
)
SELECT 
    customer_unique_id,
    customer_state, -- 買家最新落腳的主州別
    total_orders,
    first_purchase_time
FROM ranked_customers
WHERE rn = 1;

-- 檢查總筆數
SELECT 
    total_orders AS "單一買家總訂單數(次)",
    COUNT(*) AS "買家數量(人)",
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS "佔比(%)"
FROM step2_unique_customers
GROUP BY total_orders
ORDER BY total_orders DESC;

-- Step 3: 將天數差進行區間分層，統計各區間的客群分佈
SELECT 
    CASE 
        WHEN days_to_next_order <= 7 THEN '01. Within 1 Week'
        WHEN days_to_next_order <= 14 THEN '02. 1-2 Weeks'
        WHEN days_to_next_order <= 30 THEN '03. 2 Weeks - 1 Month'
        WHEN days_to_next_order <= 60 THEN '04. 1-2 Months'
        WHEN days_to_next_order <= 90 THEN '05. 2-3 Months'
        WHEN days_to_next_order <= 180 THEN '06. 3-6 Months'
        ELSE '07. Over 6 Months'
    END AS repurchase_interval_tier,
    COUNT(*) AS repurchase_count,
    ROUND(AVG(days_to_next_order)::NUMERIC, 1) AS avg_days_within_tier,
    ROUND((COUNT(*)::NUMERIC / SUM(COUNT(*)) OVER() * 100), 2) AS pct_of_total_repurchases
FROM repurchase_intervals
GROUP BY 1
ORDER BY 1 ASC;


--===============--
-- Step 3. 6-Month Maturity Filter (篩選滿 6 個月的成熟客戶)
--===============--
CREATE TABLE step3_mature_customers AS
SELECT 
    customer_unique_id,
    customer_state,
    total_orders
FROM step2_unique_customers
WHERE first_purchase_time <= '2018-03-07'; -- 基準日前 6 個月

-- 檢查
SELECT 
    total_orders AS "單一買家總訂單數(次)",
    COUNT(*) AS "買家數量(人)",
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS "佔比(%)"
FROM step3_mature_customers
GROUP BY total_orders
ORDER BY total_orders DESC;

--===============--
-- 找出定義跨州訂單依據
--===============--

-- 檢查同一客戶多筆訂單情況 --
SELECT
    COUNT(DISTINCT m.customer_unique_id) AS unique_customers, -- 真正不重複的成熟買家數 (預期為 56,949)
    COUNT(DISTINCT c.customer_id) AS customer_records,        -- 這些成熟買家對應的每次訂單買家紀錄
    COUNT(DISTINCT o.order_id) AS total_orders,               -- 這些成熟買家貢獻的 delivered 總訂單數 (預期為 59,496)
    COUNT(*) AS joined_rows                                   -- 這些訂單在商品明細或後續關聯中的總行數
FROM step3_mature_customers m
JOIN customers c 
    ON m.customer_unique_id = c.customer_unique_id
JOIN orders o 
    ON c.customer_id = o.customer_id
WHERE o.order_status = 'delivered';
-- 由於同一 customer_unique_id 可能對應多筆 customer_id 與多張訂單，因此老客回購率應以 customer_unique_id 為單位計算。

--===============--
-- 訂單運送時間 資料探勘
--===============--
-- 檢查純卡車運送時間分佈異常
WITH mature_order_shipping_calc AS (
    SELECT 
        o.order_id,
        -- 🎯 核心物流：只計算純卡車在途運送天數 (Shipping Duration)
        EXTRACT(EPOCH FROM (
            o.order_delivered_customer_date::TIMESTAMP 
            - o.order_delivered_carrier_date::TIMESTAMP
        )) / 86400 AS shipping_days
    FROM step3_mature_customers m
    JOIN customers c ON m.customer_unique_id = c.customer_unique_id
    JOIN orders o ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
      -- 🎯 簡化清洗：只排除跟「運輸天數」直接相關的空值
      -- AND o.order_delivered_carrier_date IS NOT NULL
      -- AND o.order_delivered_customer_date IS NOT NULL
)
SELECT
    COUNT(*) AS total_valid_shipping_orders, -- 完好活下來的純淨運送單量
    ROUND(MIN(shipping_days)::NUMERIC, 2) AS min_days,
    ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY shipping_days)::NUMERIC, 2) AS q1_days,
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY shipping_days)::NUMERIC, 2) AS median_days, -- 全局運輸天數中位數
    ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY shipping_days)::NUMERIC, 2) AS q3_days,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY shipping_days)::NUMERIC, 2) AS p95_days,
    ROUND(PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY shipping_days)::NUMERIC, 2) AS p99_days,
    ROUND(MAX(shipping_days)::NUMERIC, 2) AS max_days,
    
    -- 異常值與極端值偵測（對齊新規則）
    COUNT(*) FILTER (WHERE shipping_days < 0) AS negative_shipping_orders, -- 檢查是否有發貨時間大於簽收時間的單
    COUNT(*) FILTER (WHERE shipping_days > 90) AS over_90_days_orders     -- 檢查運輸在途超過 60 天的極端慢單
FROM mature_order_shipping_calc;


-- 確認是否有該州總單量很少，卻有很高比例的訂單超過 90 天 
WITH mature_delivery_days_calc AS (
    -- Step 1: 鎖定 step3 成熟客戶，算出他們所有成功訂單的配送天數與州別
    SELECT 
        o.order_id,
        m.customer_state AS buyer_state, -- 統一使用 step3 定義的主州別
        EXTRACT(EPOCH FROM (
            o.order_delivered_customer_date::TIMESTAMP 
            - o.order_purchase_timestamp::TIMESTAMP
        )) / 86400 AS delivery_days
    FROM step3_mature_customers m
    JOIN customers c ON m.customer_unique_id = c.customer_unique_id
    JOIN orders o ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp IS NOT NULL
      AND o.order_delivered_customer_date IS NOT NULL
),
state_total_orders AS (
    -- Step 2: 統計成熟客在各州原本的「總訂單數」
    SELECT 
        buyer_state,
        COUNT(*) AS total_state_orders
    FROM mature_delivery_days_calc
    GROUP BY buyer_state
),
outlier_by_state AS (
    -- Step 3: 統計成熟客中，大於 90 天的極端單在各州的分布
    SELECT 
        buyer_state,
        COUNT(*) AS outlier_orders_count
    FROM mature_delivery_days_calc
    WHERE delivery_days > 90
    GROUP BY buyer_state
)
-- Step 4: 將總訂單與極端單對接，計算在成熟客群體下的佔比
SELECT 
    t.buyer_state,
    COALESCE(o.outlier_orders_count, 0) AS orders_over_90_days,
    t.total_state_orders,
    -- 指標 1：這群壞單佔該州成熟客整體訂單的百分比
    ROUND(
        (COALESCE(o.outlier_orders_count, 0)::NUMERIC / t.total_state_orders * 100), 
        4
    ) AS pct_within_state,
    -- 指標 2：這群壞單佔「全站成熟客總極端單」的比例
    ROUND(
        (COALESCE(o.outlier_orders_count, 0)::NUMERIC / NULLIF(SUM(COALESCE(o.outlier_orders_count, 0)) OVER(), 0) * 100), 
        2
    ) AS pct_of_total_outliers
FROM state_total_orders t
LEFT JOIN outlier_by_state o ON t.buyer_state = o.buyer_state
ORDER BY orders_over_90_days DESC, total_state_orders DESC;
--===============--
-- 訂單運送費用 資料探勘
--===============--

-- 找出 delivered 狀態下，完全沒有商品與運費紀錄的異常訂單明細
SELECT 
    o.order_id,
    m.customer_unique_id,
    o.order_purchase_timestamp,
    o.order_status
FROM step3_mature_customers m
JOIN customers c ON m.customer_unique_id = c.customer_unique_id
JOIN orders o ON c.customer_id = o.customer_id
LEFT JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
  AND oi.order_id IS NULL; -- 鎖定成熟客中完全沒有串到明細的孤兒訂單
  
-- 檢查運費分佈異常
WITH mature_order_freight_calc AS (
    SELECT 
        o.order_id,
        SUM(oi.freight_value) AS total_order_freight
    FROM step3_mature_customers m
    JOIN customers c ON m.customer_unique_id = c.customer_unique_id
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY o.order_id
)
SELECT
    COUNT(*) AS total_valid_freight_orders,
    ROUND(MIN(total_order_freight)::NUMERIC, 2) AS min_freight,
    ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY total_order_freight)::NUMERIC, 2) AS q1_freight,
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY total_order_freight)::NUMERIC, 2) AS median_freight,
    ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY total_order_freight)::NUMERIC, 2) AS q3_freight,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY total_order_freight)::NUMERIC, 2) AS p95_freight,
    ROUND(PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY total_order_freight)::NUMERIC, 2) AS p99_freight,
    ROUND(MAX(total_order_freight)::NUMERIC, 2) AS max_freight,
    COUNT(*) FILTER (WHERE total_order_freight < 0) AS negative_freight_orders,
    COUNT(*) FILTER (WHERE total_order_freight > 150) AS over_150_freight_orders
FROM mature_order_freight_calc;

-- 運費分佈顯示，少數訂單存在極端運送費用。

-- 確認是否有該州總單量很少，卻有很高比例的訂單運費過高（確認排除高運費樣本，不會遺失掉重要地域訊息）
WITH mature_order_freight_calc AS (
    -- Step 1: 先算出每筆成熟客成功訂單的總運費與買家主州別
    SELECT 
        o.order_id,
        m.customer_state AS buyer_state, -- 採用 step3 主州別
        SUM(oi.freight_value) AS total_order_freight
    FROM step3_mature_customers m
    JOIN customers c ON m.customer_unique_id = c.customer_unique_id
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY o.order_id, m.customer_state
),
state_total_orders AS (
    -- Step 2: 統計各州成熟客原本的「總訂單數」
    SELECT 
        buyer_state,
        COUNT(*) AS total_state_orders
    FROM mature_order_freight_calc
    GROUP BY buyer_state
),
outlier_by_state AS (
    -- Step 3: 統計大於 150 BRL 的極端高運費單在各州的分布
    SELECT 
        buyer_state,
        COUNT(*) AS outlier_orders_count
    FROM mature_order_freight_calc
    WHERE total_order_freight > 150
    GROUP BY buyer_state
)
-- Step 4: 將總訂單與極端運費單對接，並加算相關比例指標
SELECT 
    t.buyer_state,
    COALESCE(o.outlier_orders_count, 0) AS orders_over_150_freight,
    t.total_state_orders,
    -- 指標 1：高運費單佔該州成熟客整體訂單的百分比
    ROUND(
        (COALESCE(o.outlier_orders_count, 0)::NUMERIC / t.total_state_orders * 100), 
        4
    ) AS pct_within_state,
    -- 指標 2：動態算出這群高運費單佔「全站成熟客總極端高運費單」的比例
    ROUND(
        (COALESCE(o.outlier_orders_count, 0)::NUMERIC / NULLIF(SUM(COALESCE(o.outlier_orders_count, 0)) OVER(), 0) * 100), 
        2
    ) AS pct_of_total_outliers
FROM state_total_orders t
LEFT JOIN outlier_by_state o ON t.buyer_state = o.buyer_state
ORDER BY orders_over_150_freight DESC, total_state_orders DESC;


--===============--
-- 評分 資料探勘
--===============--

-- 發現單筆訂但有多評論問題
SELECT order_id, COUNT(*) 
FROM order_reviews 
GROUP BY order_id 
HAVING COUNT(*) > 1;


WITH unique_order_reviews AS (
    -- 先在評論表進行聚合，確保每個 order_id 只有唯一的一筆評分（解決 1 對多膨脹問題）
    SELECT 
        order_id,
        MAX(review_score) AS review_score
    FROM order_reviews
    GROUP BY order_id
),
mature_order_reviews_calculated AS (
    -- Step 1: 鎖定 step3 成熟客戶，撈出他們的所有已送達訂單，並串接壓平後的評論表
    SELECT 
        o.order_id,
        COALESCE(r.review_score, 0) AS adjusted_review_score
    FROM step3_mature_customers m
    JOIN customers c ON m.customer_unique_id = c.customer_unique_id
    JOIN orders o ON c.customer_id = o.customer_id
    LEFT JOIN unique_order_reviews r ON o.order_id = r.order_id
    WHERE o.order_status = 'delivered'
)
-- Step 2: 統計成熟客的各評分分佈筆數與佔比
SELECT 
    CASE 
        WHEN adjusted_review_score = 5 THEN '5 Stars'
        WHEN adjusted_review_score = 4 THEN '4 Stars'
        WHEN adjusted_review_score = 3 THEN '3 Stars'
        WHEN adjusted_review_score = 2 THEN '2 Stars'
        WHEN adjusted_review_score = 1 THEN '1 Star'
        ELSE '0 (No Review)'
    END AS review_score_tier,
    COUNT(*) AS order_count,
    ROUND(
        (COUNT(*)::NUMERIC / SUM(COUNT(*)) OVER() * 100), 
        2
    ) AS pct_of_total_orders
FROM mature_order_reviews_calculated
GROUP BY adjusted_review_score
ORDER BY adjusted_review_score DESC; 



--===============--
-- 探勘買家是否有跨州紀錄
--===============--
WITH mature_customer_state_count AS (
    SELECT
        m.customer_unique_id,
        -- 統計該成熟客在所有已送達訂單中，總共出現過幾種不同的收件州別
        COUNT(DISTINCT c.customer_state) AS state_count,
        COUNT(DISTINCT o.order_id) AS order_count
    FROM step3_mature_customers m
    JOIN customers c ON m.customer_unique_id = c.customer_unique_id
    JOIN orders o ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY m.customer_unique_id
)
SELECT
    COUNT(*) AS total_mature_customers,
    COUNT(*) FILTER (WHERE state_count > 1) AS mature_customers_with_multiple_states,
    ROUND(
        (COUNT(*) FILTER (WHERE state_count > 1)::NUMERIC 
        / COUNT(*)::NUMERIC * 100),
        2
    ) AS multiple_state_customer_percentage
FROM mature_customer_state_count;
-- 雖然多數買家僅出現在單一州別，但仍有少數 customer_unique_id 橫跨多個 customer_state。為避免回購率因州別拆分而被低估，本分析以買家最新一次下單州別作為其主州別。



-- 跨州訂單比例
WITH mature_order_cross_state AS (
    SELECT 
        o.order_id,
        m.customer_state AS buyer_state, -- 統一採用 step3 的買家主州別
        COUNT(*) AS total_items,
        -- 統計單筆訂單中，有多少件商品的賣家與買家主州別不同
        COUNT(*) FILTER (
            WHERE m.customer_state <> s.seller_state
        ) AS cross_state_items,
        -- 統計單筆訂單中，有多少件商品的賣家與買家主州別相同
        COUNT(*) FILTER (
            WHERE m.customer_state = s.seller_state
        ) AS intra_state_items
    FROM step3_mature_customers m
    JOIN customers c ON m.customer_unique_id = c.customer_unique_id
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN order_items i ON o.order_id = i.order_id
    JOIN sellers s ON i.seller_id = s.seller_id
    WHERE o.order_status = 'delivered'
    GROUP BY o.order_id, m.customer_state
)
SELECT 
    buyer_state,
    COUNT(*) AS total_orders,

    -- 指標 1：該州成熟客的訂單中，只要包含一件跨州商品，就定義為跨州訂單的比例 (%)
    ROUND(
        COUNT(*) FILTER (
            WHERE cross_state_items > 0
        )::NUMERIC / COUNT(*)::NUMERIC * 100,
        2
    ) AS any_item_cross_state_order_ratio,

    -- 指標 2：純商品層級（Item-level）的跨州商品總數佔比 (%)
    ROUND(
        SUM(cross_state_items)::NUMERIC 
        / NULLIF(SUM(total_items), 0)::NUMERIC * 100,
        2
    ) AS item_level_cross_state_ratio,

    -- 指標 3：混合型訂單比例（同一筆訂單裡，既買了同州的商品，也買了跨州的商品）(%)
    ROUND(
        COUNT(*) FILTER (
            WHERE cross_state_items > 0 
              AND intra_state_items > 0
        )::NUMERIC / COUNT(*)::NUMERIC * 100,
        2
    ) AS mixed_order_ratio
FROM mature_order_cross_state
GROUP BY buyer_state
ORDER BY any_item_cross_state_order_ratio DESC;
-- 本研究進一步檢查訂單中賣家與買家州別是否一致。由於一張訂單可能包含多個商品與多個賣家，因此本分析將「至少一項商品由不同州賣家寄送」定義為跨州訂單，以反映消費者在該筆訂單中可能承受的跨州物流影響。


-- ============================================================
-- 建立州別層級物流與回購分析資料表
-- dm_state_logistics_retention_summary
-- ============================================================

CREATE TABLE dm_state_logistics_retention_summary AS
WITH mature_order_base AS (
    -- Step 1: 專注在出庫與簽收兩個節點，精確鎖定核心成熟客的所有有效運送明細
    SELECT 
        o.order_id,
        m.customer_unique_id,
        m.customer_state AS buyer_state, 
        SUM(i.price) AS total_order_price,
        SUM(i.freight_value) AS total_order_freight,
        MAX(CASE WHEN m.customer_state <> s.seller_state THEN 1 ELSE 0 END) AS is_cross_state,
        
        -- 🎯 核心物流：只計算純卡車在途運送天數（Shipping Duration）
        MAX(EXTRACT(EPOCH FROM (o.order_delivered_customer_date::TIMESTAMP - o.order_delivered_carrier_date::TIMESTAMP)) / 86400) AS shipping_days
    FROM step3_mature_customers m
    JOIN customers c ON m.customer_unique_id = c.customer_unique_id
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN order_items i ON o.order_id = i.order_id
    JOIN sellers s ON i.seller_id = s.seller_id
    WHERE o.order_status = 'delivered' 
      -- 🎯 簡化清洗：只抓取跟「實際運輸」直接關聯的非空欄位（精確移除了缺失值）
      AND o.order_delivered_carrier_date IS NOT NULL
      AND o.order_delivered_customer_date IS NOT NULL
    GROUP BY o.order_id, m.customer_unique_id, m.customer_state
    -- 🎯 只排除卡車運輸天數相減為負數（時間倒錯）的異常髒資料
    HAVING MAX(EXTRACT(EPOCH FROM (o.order_delivered_customer_date::TIMESTAMP - o.order_delivered_carrier_date::TIMESTAMP)) / 86400) >= 0
),
state_retention_metrics AS (
    -- Step 2: 買家總人數與回購率依舊以 step3 的 56,949 人為黃金基準分母
    SELECT 
        customer_state AS buyer_state,
        COUNT(*) AS total_customers_mature,
        ROUND((COUNT(CASE WHEN total_orders > 1 THEN 1 END)::NUMERIC / COUNT(*)::NUMERIC * 100), 2) AS retention_rate_percentage
    FROM step3_mature_customers
    GROUP BY customer_state
),
state_order_counts AS (
    -- Step 3: 🎯 動態統計通過此核心物流過濾後活下來的真實運送不重複單量
    SELECT 
        buyer_state,
        COUNT(DISTINCT order_id) AS total_orders_mature
    FROM mature_order_base
    GROUP BY buyer_state
),
state_logistics_and_financial AS (
    -- Step 4: 各州運費財務指標與運輸天數統計聚合
    SELECT 
        buyer_state,
        ROUND(AVG(total_order_price)::NUMERIC, 2) AS avg_order_price,
        ROUND(AVG(total_order_freight)::NUMERIC, 2) AS avg_freight_value,
        ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY total_order_freight)::NUMERIC, 2) AS median_freight_value,
        ROUND((COUNT(CASE WHEN is_cross_state = 1 THEN 1 END)::NUMERIC / COUNT(*)::NUMERIC * 100), 2) AS cross_state_ratio_percentage,
        ROUND(AVG(total_order_freight / NULLIF(total_order_price + total_order_freight, 0) * 100)::NUMERIC, 2) AS avg_order_freight_ratio_percentage,
        ROUND((COUNT(CASE WHEN total_order_freight > total_order_price THEN 1 END)::NUMERIC / COUNT(*)::NUMERIC * 100), 2) AS freight_inverse_order_ratio_percentage,

        -- 同州 vs 跨州運費中位數
        ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY CASE WHEN is_cross_state = 0 THEN total_order_freight END)::NUMERIC, 2) AS intra_median_freight,
        ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY CASE WHEN is_cross_state = 1 THEN total_order_freight END)::NUMERIC, 2) AS cross_median_freight,

        -- 🎯 運輸天數分佈統計（此處皆改為計算純卡車在途運送時長）
        ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY shipping_days)::NUMERIC, 1) AS total_q1_days,
        ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY shipping_days)::NUMERIC, 1) AS total_median_days,
        ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY shipping_days)::NUMERIC, 1) AS total_q3_days,
        
        -- 同州 vs 跨州純運送天數細節
        ROUND(AVG(CASE WHEN is_cross_state = 0 THEN shipping_days END)::NUMERIC, 1) AS intra_avg_days,
        ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY CASE WHEN is_cross_state = 0 THEN shipping_days END)::NUMERIC, 1) AS intra_median_days,
        ROUND(AVG(CASE WHEN is_cross_state = 1 THEN shipping_days END)::NUMERIC, 1) AS cross_avg_days,
        ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY CASE WHEN is_cross_state = 1 THEN shipping_days END)::NUMERIC, 1) AS cross_median_days
    FROM mature_order_base
    GROUP BY buyer_state
)
-- Step 5: 完美融合輸出最終大表
SELECT 
    r.buyer_state,
    r.total_customers_mature,
    COALESCE(o.total_orders_mature, 0) AS total_orders_mature, -- 🎯 動態對齊純淨運送單量
    lc.avg_order_price,
    lc.avg_freight_value,
    lc.median_freight_value,
    lc.avg_order_freight_ratio_percentage,
    lc.freight_inverse_order_ratio_percentage,
    lc.cross_state_ratio_percentage,
    lc.intra_median_freight,
    lc.cross_median_freight,
    ROUND((lc.cross_median_freight - lc.intra_median_freight)::NUMERIC, 2) AS cross_state_freight_diff,
    ROUND((lc.cross_median_freight / NULLIF(lc.intra_median_freight, 0))::NUMERIC, 2) AS cross_state_freight_premium_ratio,
    lc.total_q1_days,
    lc.total_median_days,
    lc.total_q3_days,
    lc.intra_avg_days,
    lc.intra_median_days,
    lc.cross_avg_days,
    lc.cross_median_days,
    ROUND((lc.cross_median_days - lc.intra_median_days)::NUMERIC, 1) AS cross_state_delivery_diff_median,
    ROUND((lc.cross_avg_days - lc.intra_avg_days)::NUMERIC, 1) AS cross_state_delivery_diff_avg,
    r.retention_rate_percentage
FROM state_retention_metrics r
LEFT JOIN state_order_counts o ON r.buyer_state = o.buyer_state -- 串接動態計數表
LEFT JOIN state_logistics_and_financial lc ON r.buyer_state = lc.buyer_state
ORDER BY r.retention_rate_percentage DESC;



-- ============================================================
-- 建立含評分指標的州別層級延伸分析資料表
-- dm_state_logistics_retention_summary_with_reviews
-- ============================================================
CREATE TABLE dm_state_logistics_retention_summary_with_reviews AS
WITH mature_order_base AS (
    -- Step 1: 專注在出庫與簽收兩個節點，計算精確在途運送時間
    SELECT 
        o.order_id,
        m.customer_unique_id,
        m.customer_state AS buyer_state, 
        SUM(i.price) AS total_order_price,
        SUM(i.freight_value) AS total_order_freight,
        MAX(CASE WHEN m.customer_state <> s.seller_state THEN 1 ELSE 0 END) AS is_cross_state,
        
        -- 🎯 核心物流：只算純卡車在途運送天數（Shipping Duration）
        MAX(EXTRACT(EPOCH FROM (o.order_delivered_customer_date::TIMESTAMP - o.order_delivered_carrier_date::TIMESTAMP)) / 86400) AS shipping_days,
        MAX(r.review_score) AS order_review_score
    FROM step3_mature_customers m
    JOIN customers c ON m.customer_unique_id = c.customer_unique_id
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN order_items i ON o.order_id = i.order_id
    JOIN sellers s ON i.seller_id = s.seller_id
    LEFT JOIN order_reviews r ON o.order_id = r.order_id
    WHERE o.order_status = 'delivered'
      -- 🎯 拋棄複雜定義！只抓跟「運送時間」直接相關的非空條件
      AND o.order_delivered_carrier_date IS NOT NULL
      AND o.order_delivered_customer_date IS NOT NULL
    GROUP BY o.order_id, m.customer_unique_id, m.customer_state
    -- 🎯 只排除卡車運輸時間倒錯的異常值
    HAVING MAX(EXTRACT(EPOCH FROM (o.order_delivered_customer_date::TIMESTAMP - o.order_delivered_carrier_date::TIMESTAMP)) / 86400) >= 0
),
state_retention_metrics AS (
    SELECT 
        customer_state AS buyer_state,
        COUNT(*) AS total_customers_mature,
        ROUND((COUNT(CASE WHEN total_orders > 1 THEN 1 END)::NUMERIC / COUNT(*)::NUMERIC * 100), 2) AS retention_rate_percentage
    FROM step3_mature_customers
    GROUP BY customer_state
),
state_order_counts AS (
    -- 🎯 動態計算通過此核心過濾後活下來的真實運送單量
    SELECT 
        buyer_state,
        COUNT(DISTINCT order_id) AS total_orders_mature
    FROM mature_order_base
    GROUP BY buyer_state
),
state_logistics_percentiles AS (
    SELECT 
        buyer_state,
        ROUND((COUNT(CASE WHEN is_cross_state = 1 THEN 1 END)::NUMERIC / COUNT(*)::NUMERIC * 100), 2) AS cross_state_ratio_percentage,
        ROUND((COUNT(CASE WHEN total_order_freight > total_order_price THEN 1 END)::NUMERIC / COUNT(*)::NUMERIC * 100), 2) AS freight_inverse_order_ratio_percentage,
        ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY CASE WHEN is_cross_state = 0 THEN total_order_freight END)::NUMERIC, 2) AS intra_median_freight,
        ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY CASE WHEN is_cross_state = 1 THEN total_order_freight END)::NUMERIC, 2) AS cross_median_freight,
        
        -- 🎯 統計指標同步簡化：只保留同州與跨州的運費與卡車運輸天數中位數
        ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY CASE WHEN is_cross_state = 0 THEN shipping_days END)::NUMERIC, 1) AS intra_median_days,
        ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY CASE WHEN is_cross_state = 1 THEN shipping_days END)::NUMERIC, 1) AS cross_median_days,
        
        ROUND(AVG(order_review_score)::NUMERIC, 2) AS avg_review_score,
        ROUND(
            (COUNT(CASE WHEN is_cross_state = 0 AND order_review_score <= 2 THEN 1 END)::NUMERIC / 
            NULLIF(COUNT(CASE WHEN is_cross_state = 0 AND order_review_score IS NOT NULL THEN 1 END), 0)::NUMERIC * 100), 2
        ) AS intra_low_review_ratio,
        ROUND(
            (COUNT(CASE WHEN is_cross_state = 1 AND order_review_score <= 2 THEN 1 END)::NUMERIC / 
            NULLIF(COUNT(CASE WHEN is_cross_state = 1 AND order_review_score IS NOT NULL THEN 1 END), 0)::NUMERIC * 100), 2
        ) AS cross_low_review_ratio
    FROM mature_order_base
    GROUP BY buyer_state
)
SELECT 
    r.buyer_state,
    r.total_customers_mature,
    COALESCE(o.total_orders_mature, 0) AS total_orders_mature, 
    lc.cross_state_ratio_percentage,
    lc.freight_inverse_order_ratio_percentage,
    lc.intra_median_freight,
    lc.cross_median_freight,
    lc.intra_median_days, -- 此時這裡的中位數天數，代表純卡車運送天數了
    lc.cross_median_days, -- 同上
    lc.avg_review_score,
    lc.intra_low_review_ratio,
    lc.cross_low_review_ratio,
    ROUND((lc.cross_low_review_ratio / NULLIF(lc.intra_low_review_ratio, 0))::NUMERIC, 2) AS cross_low_review_ratio_multiplier,
    r.retention_rate_percentage
FROM state_retention_metrics r
LEFT JOIN state_order_counts o ON r.buyer_state = o.buyer_state 
LEFT JOIN state_logistics_percentiles lc ON r.buyer_state = lc.buyer_state
ORDER BY r.retention_rate_percentage DESC;



-- 最終分析資料表一致性檢查
SELECT 
    'step3_mature_customers' AS table_name,
    COUNT(*) AS total_unique_customers,
    SUM(total_orders) AS total_orders_contributed
FROM step3_mature_customers

UNION ALL

SELECT 
    'dm_state_logistics_retention_summary' AS table_name,
    SUM(total_customers_mature) AS total_unique_customers,
    SUM(total_orders_mature) AS total_orders_contributed
FROM dm_state_logistics_retention_summary

UNION ALL

SELECT 
    'dm_state_logistics_retention_summary_with_reviews' AS table_name,
    SUM(total_customers_mature) AS total_unique_customers,
    SUM(total_orders_mature) AS total_orders_contributed
FROM dm_state_logistics_retention_summary_with_reviews;



-- 物流分析樣本保留與排除原因檢查
WITH base_orders AS (
    -- 抓出所有屬於 step3 成熟客的 delivered 訂單基礎資料 (59,496筆)
    SELECT 
        o.order_id,
        o.order_status,
        o.order_delivered_carrier_date,
        o.order_delivered_customer_date
    FROM step3_mature_customers m
    JOIN customers c ON m.customer_unique_id = c.customer_unique_id
    JOIN orders o ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
),
reason_diagnose AS (
    SELECT 
        order_id,
        -- 🎯 核心簡化修改：只檢查與「實際在途運輸」相關的空值與負數
        CASE 
            -- 1. 檢查出庫或簽收時間是否有缺失
            WHEN order_delivered_carrier_date IS NULL 
              OR order_delivered_customer_date IS NULL 
            THEN '1. Missing Carrier/Customer Date'
            
            -- 2. 檢查卡車運輸時間是否小於 0 (簽收時間早於發貨時間)
            WHEN (EXTRACT(EPOCH FROM (order_delivered_customer_date::TIMESTAMP - order_delivered_carrier_date::TIMESTAMP)) < 0)
            THEN '2. Negative Shipping Duration'
            
            -- 3. 通過簡化後的物流過濾，屬於我們定義的真實運送訂單
            ELSE '3. 完好活下來的純淨運送訂單'
        END AS filter_reason
    FROM base_orders
)
SELECT 
    filter_reason AS "評估狀態/剔除原因",
    COUNT(*) AS "訂單筆數",
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS "佔比(%)"
FROM reason_diagnose
GROUP BY filter_reason
ORDER BY "評估狀態/剔除原因";


-- ============================================================
-- 建立顧客層級 Power BI 訂單次數事實資料表
-- fact_customer_order_totals
-- ============================================================
CREATE TABLE fact_customer_order_totals AS
SELECT 
    m.customer_unique_id,
    m.customer_state AS buyer_state, -- 🌟 聯動的關鍵：必須保留州別維度
    COUNT(DISTINCT o.order_id) AS total_orders
FROM step3_mature_customers m  
JOIN customers c ON m.customer_unique_id = c.customer_unique_id
JOIN orders o ON c.customer_id = o.customer_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_carrier_date IS NOT NULL
  AND o.order_delivered_customer_date IS NOT NULL
  AND (o.order_delivered_customer_date::TIMESTAMP - o.order_delivered_carrier_date::TIMESTAMP) >= '0 second'::INTERVAL
GROUP BY m.customer_unique_id, m.customer_state;
-- 檢查建立結果
SELECT * FROM fact_customer_order_totals;



-- 目標州別商品類別深入分析 ('MT')
SELECT 
    c.customer_state AS state,
    t.product_category_name_english AS product_category,
    COUNT(oi.product_id) AS total_purchased
FROM customers c
-- 1. 連結訂單
JOIN orders o 
    ON c.customer_id = o.customer_id
-- 2. 連結訂單明細
JOIN order_items oi 
    ON o.order_id = oi.order_id
-- 3. 連結商品資訊
JOIN products p 
    ON oi.product_id = p.product_id
-- 4. 連結英文翻譯表
JOIN product_category_name_translation t 
    ON p.product_category_name = t.product_category_name
-- 5. 篩選'MT' 
WHERE c.customer_state = 'MT'
GROUP BY c.customer_state, t.product_category_name_english
-- 6. 依照購買數量由高到低排序
ORDER BY total_purchased DESC
-- 限制只顯示前 10 名
LIMIT 10;

