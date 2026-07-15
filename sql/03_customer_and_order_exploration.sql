-- ============================================================
-- 第一部分：資料範圍與有效訂單定義
-- ============================================================
-- 所有訂單的消費時間範圍
SELECT
    MIN(order_purchase_timestamp) AS earliest_purchase_time,
    MAX(order_purchase_timestamp) AS latest_purchase_time,
    COUNT(*) AS total_orders
FROM orders
WHERE order_purchase_timestamp IS NOT NULL;

-- 查看 「交易成功」訂單的消費時間範圍
SELECT
    MIN(order_purchase_timestamp) AS earliest_delivered_purchase_time,
    MAX(order_purchase_timestamp) AS latest_delivered_purchase_time,
    COUNT(*) AS delivered_orders
FROM orders
WHERE order_status = 'delivered'
  AND order_purchase_timestamp IS NOT NULL;
-- 查看 「交易成功」訂單比例
SELECT 
    COUNT(*) AS "全站總訂單數(大盤)",
    COUNT(CASE WHEN order_status = 'delivered' THEN 1 END) AS "交易成功訂單數",
    ROUND(
        (COUNT(CASE WHEN order_status = 'delivered' THEN 1 END)::NUMERIC / COUNT(*)::NUMERIC * 100), 
        2
    ) AS "交易成功比例(%)"
FROM orders
WHERE order_purchase_timestamp IS NOT NULL;

SELECT order_status, COUNT(*) 
FROM orders 
GROUP BY order_status;

-- ============================================================
--第二部分：初步顧客與回購分析
-- ============================================================
--===============--
-- 計算每個月新客人數:侷限於交易成功且已送達
--===============--
-- 每個月帶來了多少新客
-- Monthly acquisition shifted to quarterly new customer acquisition analysis
WITH customer_first_purchase AS (
    -- Step 1: Identify the first purchase timestamp for each unique customer
    SELECT 
        c.customer_unique_id,
        MIN(o.order_purchase_timestamp::TIMESTAMP) AS first_purchase_time
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered' -- Ensure only valid, completed purchases are counted
    GROUP BY c.customer_unique_id
)
-- Step 2: Group by quarter and calculate the count and percentage of total new customers
SELECT 
    TO_CHAR(first_purchase_time, 'YYYY-"Q"Q') AS first_purchase_quarter,
    COUNT(*) AS new_customers_count,
    -- Use a window function to get total unique customers as denominator for percentage
    ROUND(
        (COUNT(*)::NUMERIC / SUM(COUNT(*)) OVER() * 100), 
        2
    ) AS pct_of_total_new_customers
FROM customer_first_purchase
GROUP BY TO_CHAR(first_purchase_time, 'YYYY-"Q"Q')
ORDER BY first_purchase_quarter ASC;

--===============--
-- 計算回頭客相關訊息:侷限於交易成功且已送達
--===============--
-- 整體單次消費與回頭客比例
WITH customer_orders AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS total_orders
    FROM orders o
    JOIN customers c 
        ON o.customer_id = c.customer_id
    -- 關鍵修正：僅鎖定交易成功且已送達之訂單
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp IS NOT NULL
    GROUP BY c.customer_unique_id
)
SELECT
    COUNT(*) AS total_unique_customers,
    COUNT(*) FILTER (WHERE total_orders = 1) AS one_time_customers,
    COUNT(*) FILTER (WHERE total_orders > 1) AS repeat_customers,
    ROUND(
        COUNT(*) FILTER (WHERE total_orders = 1)::NUMERIC 
        / COUNT(*)::NUMERIC * 100,
        2
    ) AS one_time_customer_ratio_percentage,
    ROUND(
        COUNT(*) FILTER (WHERE total_orders > 1)::NUMERIC 
        / COUNT(*)::NUMERIC * 100,
        2
    ) AS repeat_customer_ratio_percentage,
    SUM(total_orders) AS total_orders,
    ROUND(AVG(total_orders)::NUMERIC, 2) AS avg_orders_per_customer
FROM customer_orders;




-- 依「買家最新主州別」計算單次消費與回頭客比例
WITH customer_summary AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS total_orders,
        (ARRAY_AGG(
            c.customer_state 
            ORDER BY o.order_purchase_timestamp DESC
        ))[1] AS latest_main_state
    FROM orders o
    JOIN customers c 
        ON o.customer_id = c.customer_id
    -- 鎖定交易成功且已送達之訂單
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp IS NOT NULL
    GROUP BY c.customer_unique_id
)
SELECT
    latest_main_state AS buyer_state,
    COUNT(*) AS total_unique_customers,
    COUNT(*) FILTER (WHERE total_orders = 1) AS one_time_customers,
    COUNT(*) FILTER (WHERE total_orders > 1) AS repeat_customers,
    ROUND(
        COUNT(*) FILTER (WHERE total_orders = 1)::NUMERIC 
        / NULLIF(COUNT(*), 0)::NUMERIC * 100,
        2
    ) AS one_time_customer_ratio_percentage,
    ROUND(
        COUNT(*) FILTER (WHERE total_orders > 1)::NUMERIC 
        / NULLIF(COUNT(*), 0)::NUMERIC * 100,
        2
    ) AS repeat_customer_ratio_percentage
FROM customer_summary
GROUP BY latest_main_state
ORDER BY repeat_customer_ratio_percentage DESC;


--
WITH customer_summary AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS total_orders,
        (ARRAY_AGG(
            c.customer_state 
            ORDER BY o.order_purchase_timestamp DESC
        ))[1] AS latest_main_state
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp IS NOT NULL
    GROUP BY c.customer_unique_id
),
state_metrics AS (
    -- 先計算出各州原本的基礎數據（總人數、單次人數、回購人數、回購率）
    SELECT
        latest_main_state AS buyer_state,
        COUNT(*) AS total_unique_customers,
        COUNT(*) FILTER (WHERE total_orders = 1) AS one_time_customers,
        COUNT(*) FILTER (WHERE total_orders > 1) AS repeat_customers,
        ROUND(
            COUNT(*) FILTER (WHERE total_orders > 1)::NUMERIC 
            / NULLIF(COUNT(*), 0)::NUMERIC * 100,
            2
        ) AS repeat_customer_ratio_percentage
    FROM customer_summary
    GROUP BY latest_main_state
),
tiered_data AS (
    SELECT
        *,
        CASE 
            WHEN repeat_customer_ratio_percentage >= 4.0 THEN '>= 4%'
            WHEN repeat_customer_ratio_percentage >= 3.0 AND repeat_customer_ratio_percentage < 4.0 THEN '3%-4%'
            WHEN repeat_customer_ratio_percentage >= 2.0 AND repeat_customer_ratio_percentage < 3.0 THEN '2%-3%'
            ELSE '< 2%'
        END AS retention_tier,
        -- 為了讓最後的排序符合邏輯（從大到小排序區間），加上一個隱藏的排序權重
        CASE 
            WHEN repeat_customer_ratio_percentage >= 4.0 THEN 1
            WHEN repeat_customer_ratio_percentage >= 3.0 AND repeat_customer_ratio_percentage < 4.0 THEN 2
            WHEN repeat_customer_ratio_percentage >= 2.0 AND repeat_customer_ratio_percentage < 3.0 THEN 3
            ELSE 4
        END AS tier_sort_order
    FROM state_metrics
)
-- 最後聚合：統計各區間的總量，並把州別黏起來
SELECT
    retention_tier,
    COUNT(*) AS number_of_states,
    -- 用 STRING_AGG 把同區間的州別黏起來，並在裡面做字母排序 (A-Z)
    STRING_AGG(buyer_state, ', ' ORDER BY buyer_state) AS included_states,
    SUM(total_unique_customers) AS total_customers,
    SUM(one_time_customers) AS one_time_customers,
    SUM(repeat_customers) AS repeat_customers,
    -- 精準計算區間加權回購率 (區間總回購人數 / 區間總人數 * 100)
    ROUND((SUM(repeat_customers)::NUMERIC / NULLIF(SUM(total_unique_customers), 0)::NUMERIC * 100), 2) AS weighted_retention_rate_percentage,
    -- 計算該區間內，各州回購率的算術平均數
    ROUND(AVG(repeat_customer_ratio_percentage), 2) AS avg_state_retention_rate_percentage
FROM tiered_data
GROUP BY retention_tier, tier_sort_order
ORDER BY tier_sort_order;

-- 統計回購間隔時長
WITH customer_order_sequences AS (
    -- Step 1: 撈出所有已送達訂單，並用視窗函數找出同一個人的「下一筆訂單時間」
    SELECT 
        c.customer_unique_id,
        o.order_purchase_timestamp::TIMESTAMP AS current_order_time,
        LEAD(o.order_purchase_timestamp::TIMESTAMP) OVER(
            PARTITION BY c.customer_unique_id 
            ORDER BY o.order_purchase_timestamp ASC
        ) AS next_order_time
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
),
repurchase_intervals AS (
    -- Step 2: 篩選出「真的有下下一單」的數據，並計算前後兩單的天數差
    SELECT 
        customer_unique_id,
        current_order_time,
        next_order_time,
        EXTRACT(EPOCH FROM (next_order_time - current_order_time)) / 86400 AS days_to_next_order
    FROM customer_order_sequences
    WHERE next_order_time IS NOT NULL -- 排除最後一單（因為沒有下一單了）
)
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

-- 列出回購間隔時長區間最長的25筆：確認具體天數
WITH customer_order_sequences AS (
    -- Step 1: 找出同一個人的下一筆訂單時間
    SELECT 
        c.customer_unique_id,
        o.order_id AS current_order_id,
        o.order_purchase_timestamp::TIMESTAMP AS current_order_time,
        LEAD(o.order_purchase_timestamp::TIMESTAMP) OVER(
            PARTITION BY c.customer_unique_id 
            ORDER BY o.order_purchase_timestamp ASC
        ) AS next_order_time,
        LEAD(o.order_id) OVER(
            PARTITION BY c.customer_unique_id 
            ORDER BY o.order_purchase_timestamp ASC
        ) AS next_order_id
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
),
repurchase_details AS (
    -- Step 2: 計算間隔天數，並關聯商品品類表看他們「第一單」買了什麼
    SELECT 
        s.customer_unique_id AS "買家ID",
        s.current_order_id AS "第一單ID",
        s.current_order_time AS "第一單購買時間",
        s.next_order_id AS "第二單ID",
        s.next_order_time AS "第二單購買時間",
        -- 精確計算具體天數，保留 1 位小數
        ROUND((EXTRACT(EPOCH FROM (s.next_order_time - s.current_order_time)) / 86400)::NUMERIC, 1) AS "具體間隔天數",
        t.product_category_name_english AS "第一單商品品類"
    FROM customer_order_sequences s
    -- 透過 LEFT JOIN 一路串到英文品類名稱表
    LEFT JOIN order_items i ON s.current_order_id = i.order_id AND i.order_item_id = 1
    LEFT JOIN products p ON i.product_id = p.product_id
    LEFT JOIN product_category_name_translation t ON p.product_category_name = t.product_category_name
    WHERE s.next_order_time IS NOT NULL
)
-- Step 3: 排序並取出最長的 25 筆
SELECT * FROM repurchase_details
ORDER BY "具體間隔天數" DESC
LIMIT 200;

-- ============================================================
-- 「訂單明細層級」與「賣家維度層級」確認
-- ============================================================

-- 一張訂單包含的商品件數
SELECT 
    item_count AS "一張訂單包含的商品件數",
    COUNT(*) AS "訂單筆數",
    ROUND((COUNT(*)::NUMERIC / SUM(COUNT(*)) OVER() * 100), 2) AS "佔總訂單比例(%)"
FROM (
    SELECT order_id, COUNT(*) AS item_count
    FROM order_items
    GROUP BY order_id
) t
GROUP BY item_count
ORDER BY item_count ASC;
--由於部分訂單包含多個商品項目，若直接在 order_items 層級計算平均運費或配送天數，會使多商品訂單被重複加權。因此後續分析先將商品項目彙整至訂單層級，再依州別計算指標。

-- 統計「一筆訂單包含幾個賣家」
WITH order_seller_counts AS (
    -- 統計每筆交易成功訂單中，到底包含了幾個獨立的賣家
    SELECT 
        o.order_id,
        COUNT(DISTINCT i.seller_id) AS unique_sellers_per_order
    FROM orders o
    JOIN order_items i ON o.order_id = i.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY o.order_id
)
SELECT 
    CASE 
        WHEN unique_sellers_per_order = 1 THEN '1. Single Seller Order'
        WHEN unique_sellers_per_order = 2 THEN '2. Cross 2 Sellers'
        WHEN unique_sellers_per_order = 3 THEN '3. Cross 3 Sellers'
        ELSE '4. Cross 4 or More Sellers'
    END AS order_composition_type,
    COUNT(*) AS order_count,
    ROUND((COUNT(*)::NUMERIC / SUM(COUNT(*)) OVER() * 100), 2) AS pct_of_total_delivered_orders
FROM order_seller_counts
-- 依照第一個欄位 ( CASE WHEN 的分類結果)分組
GROUP BY 1
-- 依據第一個欄位的文字排序
ORDER BY 1 ASC;

-- 「一筆訂單包含多個賣家」的跨洲情況
WITH multi_seller_orders AS (
    -- Step 1: 撈出跨店訂單（賣家數 >= 2），並找出買家州別，以及賣家州別的數量與範圍
    SELECT 
        o.order_id,
        c.customer_state AS buyer_state,
        COUNT(DISTINCT i.seller_id) AS total_unique_sellers,
        COUNT(DISTINCT s.seller_state) AS total_unique_seller_states,
        -- 用 MIN/MAX 來判斷當賣家都在同一個州時，那個州是不是跟買家一樣
        MIN(s.seller_state) AS min_seller_state,
        MAX(s.seller_state) AS max_seller_state,
        -- 用來判斷買家州別是否有包含在賣家州別的清單中（利用 bool_or 聚合函數）
        BOOL_OR(s.seller_state = c.customer_state) AS is_buyer_state_matched_with_any_seller
    FROM orders o
    JOIN order_items i ON o.order_id = i.order_id
    JOIN sellers s ON i.seller_id = s.seller_id
    JOIN customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY o.order_id, c.customer_state
    -- 關鍵過濾：只看跨店訂單（賣家數 >= 2）
    HAVING COUNT(DISTINCT i.seller_id) >= 2
)
-- Step 2: 交叉比對「買賣地理關係」與「賣家間地理關係」，切分為四組
SELECT 
    CASE 
        -- 情況 1：所有賣家都在同一個州，且該州剛好就是買家的州
        WHEN total_unique_seller_states = 1 AND min_seller_state = buyer_state 
            THEN '1. Same State (Buyer & All Sellers in Same State)'
        
        -- 情況 2：賣家們分散在不同州，但其中至少有一個賣家跟買家同州
        WHEN total_unique_seller_states > 1 AND is_buyer_state_matched_with_any_seller = TRUE 
            THEN '2. Mixed States (Sellers Across States, Part Match with Buyer)'
        
        -- 情況 3：所有賣家都在同一個州，但該州與買家不同州
        WHEN total_unique_seller_states = 1 AND min_seller_state != buyer_state 
            THEN '3. Cross States (All Sellers in Same State, But Different from Buyer)'
        
        -- 情況 4：賣家們分散在不同州，且沒有任何一個賣家跟買家同州
        ELSE '4. Full Cross States (Buyer & All Sellers in Different States)'
    END AS geographic_distribution_type,
    COUNT(*) AS order_count,
    ROUND((COUNT(*)::NUMERIC / SUM(COUNT(*)) OVER() * 100), 2) AS pct_of_multi_seller_orders
FROM multi_seller_orders
GROUP BY 1
ORDER BY 1 ASC;

