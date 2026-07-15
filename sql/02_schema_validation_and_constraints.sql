-- ============================================================
-- 1. Primary key validation and creation
-- ============================================================
-- 先檢查 orders.order_id 是否重複 --
SELECT 
    order_id,
    COUNT(*) AS count_num
FROM orders
GROUP BY order_id
HAVING COUNT(*) > 1;
-- 先檢查 orders.order_id 是否有 NULL --
SELECT *
FROM orders
WHERE order_id IS NULL;
-- 建立 orders 主鍵 --
ALTER TABLE orders
ADD CONSTRAINT orders_pkey
PRIMARY KEY (order_id);

-- 檢查 (order_id, order_item_id) 是否重複 --
SELECT 
    order_id,
    order_item_id,
    COUNT(*) AS count_num
FROM order_items
GROUP BY 
    order_id,
    order_item_id
HAVING COUNT(*) > 1;
-- 檢查是否有 NULL --
SELECT *
FROM order_items
WHERE order_id IS NULL
   OR order_item_id IS NULL;
-- 建立 order_items 主鍵 --
ALTER TABLE order_items
ADD CONSTRAINT order_items_pkey
PRIMARY KEY (order_id, order_item_id);

-- 先檢查 seller_id 是否重複 --
SELECT 
    seller_id,
    COUNT(*) AS count_num
FROM sellers
GROUP BY seller_id
HAVING COUNT(*) > 1;
-- 先檢查 sellers.seller_id 是否有 NULL --
SELECT *
FROM sellers
WHERE seller_id IS NULL;
-- 建立 sellers 主鍵 --
ALTER TABLE sellers
ADD CONSTRAINT sellers_pkey
PRIMARY KEY (seller_id);

-- 先檢查customers.customer_id 是否重複 --
SELECT
     customer_id,COUNT(*)
FROM customers
GROUP BY customer_id
HAVING COUNT(*)>1;
-- 先檢查是否有 NULL --
SELECT *
FROM customers
WHERE customer_id IS NULL;
-- 建立 customers 主鍵 --
ALTER TABLE customers
ADD CONSTRAINT customers_pkey
PRIMARY KEY (customer_id);

-- 檢查 mql_id是否重複 --
SELECT 
    mql_id,
    COUNT(*) AS count_num
FROM leads_closed
GROUP BY mql_id
HAVING COUNT(*) > 1;
-- 檢查是否有 NULL --
SELECT *
FROM leads_closed
WHERE mql_id IS NULL;
-- 建立 leads_closed 主鍵 --
ALTER TABLE leads_closed
ADD CONSTRAINT leads_closed_pkey
PRIMARY KEY (mql_id);


-- 檢查  (order_id, payment_sequential) 是否重複 --
SELECT 
    order_id,
    payment_sequential,
    COUNT(*) AS count_num
FROM order_payments
GROUP BY order_id,payment_sequential
HAVING COUNT(*) > 1;
-- 檢查是否有 NULL --
SELECT *
FROM order_payments
WHERE order_id IS NULL
   OR payment_sequential IS NULL;

-- 建立 order_payments 主鍵 --
ALTER TABLE order_payments
ADD CONSTRAINT order_payments_pkey
PRIMARY KEY (order_id,payment_sequential);



-- 檢查 product_id是否重複 --
SELECT 
    product_id,
    COUNT(*) AS count_num
FROM products
GROUP BY product_id
HAVING COUNT(*) > 1;
-- 檢查是否有 NULL --
SELECT *
FROM products
WHERE product_id IS NULL;

-- 建立 products 主鍵 --
ALTER TABLE products
ADD CONSTRAINT products_pkey
PRIMARY KEY (product_id);

-- 檢查 (review_id, order_id) 是否重複 --
SELECT 
    product_category_name,
    COUNT(*) AS count_num
FROM product_category_name_translation
GROUP BY product_category_name
HAVING COUNT(*) > 1;
-- 檢查是否有 NULL --
SELECT *
FROM product_category_name_translation
WHERE product_category_name IS NULL;

-- 建立 product_category_name_translation 主鍵 --
ALTER TABLE product_category_name_translation
ADD CONSTRAINT product_category_name_translation_pkey
PRIMARY KEY (product_category_name);

-- 檢查 product_category_name是否重複 --
SELECT 
    review_id,order_id,
    COUNT(*) AS count_num
FROM order_reviews
GROUP BY review_id,order_id
HAVING COUNT(*) > 1;
-- 檢查是否有 NULL --
SELECT *
FROM order_reviews
WHERE review_id IS NULL
   OR order_id IS NULL;

-- 建立 order_reviews 主鍵 --
ALTER TABLE order_reviews
ADD CONSTRAINT order_reviews_pkey
PRIMARY KEY (review_id,order_id);

-- 先檢查 orders.order_id 是否重複 --
SELECT 
    geolocation_id,
    COUNT(*) AS count_num
FROM geolocation
GROUP BY geolocation_id
HAVING COUNT(*) > 1;
-- 先檢查 orders.order_id 是否有 NULL --
SELECT *
FROM geolocation
WHERE geolocation_id IS NULL;
-- 建立 geolocation 主鍵 --
ALTER TABLE geolocation
ADD CONSTRAINT geolocation_pkey
PRIMARY KEY (geolocation_id);

-- 先檢查 orders.order_id 是否重複 --
SELECT 
    mql_id,
    COUNT(*) AS count_num
FROM leads_qualified
GROUP BY mql_id
HAVING COUNT(*) > 1;
-- 先檢查 orders.order_id 是否有 NULL --
SELECT *
FROM leads_qualified
WHERE mql_id IS NULL;
-- 建立 leads_qualified 主鍵 --
ALTER TABLE leads_qualified
ADD CONSTRAINT leads_qualified_pkey
PRIMARY KEY (mql_id);
-- ============================================================ 
-- 2. Foreign key validation and creation -- 
-- ============================================================
-- orders.customer_id 外來鍵 先檢查外來鍵是否有對不到的資料
SELECT o.customer_id
FROM orders o
LEFT JOIN customers c
ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL;
-- ------------------------------------------------------------
-- orders.customer_id -> customers.customer_id
-- ------------------------------------------------------------
ALTER TABLE orders
ADD CONSTRAINT orders_customer_id_fkey
FOREIGN KEY (customer_id)
REFERENCES customers(customer_id);

-- order_payments.order_id 外來鍵 先檢查外來鍵是否有對不到的資料
SELECT op.order_id
FROM order_payments op
LEFT JOIN orders o
ON op.order_id = o.order_id
WHERE o.order_id IS NULL;
-- order_payments.order_id → orders.order_id
ALTER TABLE order_payments
ADD CONSTRAINT order_payments_order_id_fkey
FOREIGN KEY (order_id)
REFERENCES orders(order_id);

-- products.product_category_name 外來鍵 先檢查外來鍵是否有對不到的資料
SELECT DISTINCT p.product_category_name
FROM products p
LEFT JOIN product_category_name_translation pct
ON p.product_category_name = pct.product_category_name
WHERE pct.product_category_name IS NULL
  AND p.product_category_name IS NOT NULL;
-- 有兩筆對不到，把這兩筆補進 product_category_name_translation
INSERT INTO product_category_name_translation (
    product_category_name,
    product_category_name_english
)
VALUES
    ('portateis_cozinha_e_preparadores_de_alimentos', 'portable_kitchen_and_food_preparers'),
    ('pc_gamer', 'pc_gamer');
-- products.product_category_name → product_category_name_translation.product_category_name
ALTER TABLE products
ADD CONSTRAINT products_product_category_name_fkey
FOREIGN KEY (product_category_name)
REFERENCES product_category_name_translation(product_category_name);

-- order_reviews.order_id  外來鍵 先檢查外來鍵是否有對不到的資料
SELECT DISTINCT r.order_id
FROM order_reviews r
LEFT JOIN orders o
ON r.order_id = o.order_id
WHERE o.order_id IS NULL
  AND r.order_id IS NOT NULL;
-- order_reviews.order_id → orders.order_id
ALTER TABLE order_reviews
ADD CONSTRAINT order_reviews_order_id_fkey
FOREIGN KEY (order_id)
REFERENCES orders(order_id);

-- ------------------------------------------------------------
-- order_reviews.order_id -> orders.order_id
-- ------------------------------------------------------------
SELECT DISTINCT oi.order_id
FROM order_items oi
LEFT JOIN orders o
ON oi.order_id = o.order_id
WHERE o.order_id IS NULL
  AND oi.order_id IS NOT NULL;
  
ALTER TABLE order_items
ADD CONSTRAINT order_items_order_id_fkey
FOREIGN KEY (order_id)
REFERENCES orders(order_id);
  
-- ------------------------------------------------------------
-- order_items.order_id -> orders.order_id
-- ------------------------------------------------------------
SELECT DISTINCT oi.product_id
FROM order_items oi
LEFT JOIN products p
ON oi.product_id = p.product_id
WHERE p.product_id IS NULL
  AND oi.product_id IS NOT NULL;
  
ALTER TABLE order_items
ADD CONSTRAINT order_items_product_id_fkey
FOREIGN KEY (product_id)
REFERENCES products(product_id);
-- ------------------------------------------------------------
-- order_items.seller_id -> sellers.seller_id
-- ------------------------------------------------------------
SELECT DISTINCT oi.seller_id
FROM order_items oi
LEFT JOIN sellers s
ON oi.seller_id = s.seller_id
WHERE s.seller_id IS NULL
  AND oi.seller_id IS NOT NULL;

ALTER TABLE order_items
ADD CONSTRAINT order_items_seller_id_fkey
FOREIGN KEY (seller_id)
REFERENCES sellers(seller_id);

-- ------------------------------------------------------------
-- leads_closed.mql_id -> leads_qualified.mql_id
-- ------------------------------------------------------------
SELECT DISTINCT lc.mql_id
FROM leads_closed lc
LEFT JOIN leads_qualified lq
ON lc.mql_id = lq.mql_id
WHERE lq.mql_id IS NULL
  AND lc.mql_id IS NOT NULL;
  
ALTER TABLE leads_closed
ADD CONSTRAINT leads_closed_mql_id_fkey
FOREIGN KEY (mql_id)
REFERENCES leads_qualified(mql_id);
-- ------------------------------------------------------------
-- leads_closed.seller_id -> sellers.seller_id
-- Constraint not applied
-- ------------------------------------------------------------
SELECT DISTINCT lc.seller_id
FROM leads_closed lc
LEFT JOIN sellers s
ON lc.seller_id = s.seller_id
WHERE s.seller_id IS NULL
  AND lc.seller_id IS NOT NULL;
-- leads_closed 裡有 462 筆 seller_id，在 sellers 表中找不到對應資料，不要建立 seller_id 外來鍵
SELECT 
    COUNT(*) AS unmatched_rows,
    COUNT(DISTINCT lc.seller_id) AS unmatched_seller_count
FROM leads_closed lc
LEFT JOIN sellers s
ON lc.seller_id = s.seller_id
WHERE s.seller_id IS NULL
  AND lc.seller_id IS NOT NULL;