-- =====================================================================
-- 01_dimensiones.sql — Tablas de DIMENSIONES del modelo estrella
-- =====================================================================
-- Cada dimensión tiene:
--   * una clave SUBROGADA (<nombre>_key): número propio del data warehouse
--   * la clave NATURAL (<nombre>_id): el ID que viene de raw/
-- =====================================================================


-- ---------------------------------------------------------------------
-- DIM_PRODUCT: un producto por fila, con su categoría y familia aplanadas
-- ---------------------------------------------------------------------
CREATE TABLE dim_product (
    product_key INTEGER PRIMARY KEY,
    product_id  INTEGER NOT NULL,
    sku         VARCHAR NOT NULL,
    name        VARCHAR NOT NULL,
    category    VARCHAR,             -- Classic / Sport
    family      VARCHAR,             -- Bottles
    list_price  DECIMAL(12, 2)
);

INSERT INTO dim_product
SELECT
    ROW_NUMBER() OVER (ORDER BY p.product_id) AS product_key,
    p.product_id,
    p.sku,
    p.name,
    c.name AS category,
    f.name AS family,
    p.list_price
FROM raw.product AS p
LEFT JOIN raw.product_category AS c
    ON c.category_id = p.category_id
LEFT JOIN raw.product_category AS f
    ON f.category_id = c.parent_id;


-- ---------------------------------------------------------------------
-- DIM_DATE: un día por fila, del 2024-01-01 al 2025-09-30
-- ---------------------------------------------------------------------
CREATE TABLE dim_date (
    date_key   INTEGER PRIMARY KEY,  -- formato AAAAMMDD, ej. 20240131
    fecha      DATE NOT NULL,
    year       INTEGER,
    month      INTEGER,
    month_name VARCHAR,
    day        INTEGER,
    day_name   VARCHAR
);

INSERT INTO dim_date
SELECT
    CAST(strftime(fecha, '%Y%m%d') AS INTEGER) AS date_key,
    fecha,
    year(fecha)      AS year,
    month(fecha)     AS month,
    monthname(fecha) AS month_name,
    day(fecha)       AS day,
    dayname(fecha)   AS day_name
FROM (
    SELECT CAST(range AS DATE) AS fecha
    FROM range(
        DATE '2024-01-01',
        DATE '2025-10-01',
        INTERVAL 1 DAY
    )
);


-- ---------------------------------------------------------------------
-- DIM_CHANNEL: canal de venta (online / tienda)
-- ---------------------------------------------------------------------
CREATE TABLE dim_channel (
    channel_key INTEGER PRIMARY KEY,
    channel_id  INTEGER NOT NULL,
    code        VARCHAR NOT NULL,
    name        VARCHAR NOT NULL
);

INSERT INTO dim_channel
SELECT
    ROW_NUMBER() OVER (ORDER BY channel_id) AS channel_key,
    channel_id,
    code,
    name
FROM raw.channel;


-- ---------------------------------------------------------------------
-- DIM_PROVINCE: provincias
-- ---------------------------------------------------------------------
CREATE TABLE dim_province (
    province_key INTEGER PRIMARY KEY,
    province_id  INTEGER NOT NULL,
    name         VARCHAR NOT NULL,
    code         VARCHAR
);

INSERT INTO dim_province
SELECT
    ROW_NUMBER() OVER (ORDER BY province_id) AS province_key,
    province_id,
    name,
    code
FROM raw.province;


-- ---------------------------------------------------------------------
-- DIM_CUSTOMER: clientes
-- ---------------------------------------------------------------------
CREATE TABLE dim_customer (
    customer_key INTEGER PRIMARY KEY,
    customer_id  INTEGER NOT NULL,
    email        VARCHAR,
    first_name   VARCHAR,
    last_name    VARCHAR,
    phone        VARCHAR,
    status       VARCHAR,
    created_at   TIMESTAMP
);

INSERT INTO dim_customer
SELECT
    ROW_NUMBER() OVER (ORDER BY customer_id) AS customer_key,
    customer_id,
    email,
    first_name,
    last_name,
    phone,
    status,
    created_at
FROM raw.customer;


-- ---------------------------------------------------------------------
-- DIM_STORE: tiendas físicas
-- ---------------------------------------------------------------------
CREATE TABLE dim_store (
    store_key  INTEGER PRIMARY KEY,
    store_id   INTEGER NOT NULL,
    name       VARCHAR NOT NULL,
    address_id INTEGER
);

INSERT INTO dim_store
SELECT
    ROW_NUMBER() OVER (ORDER BY store_id) AS store_key,
    store_id,
    name,
    address_id
FROM raw.store;


-- ---------------------------------------------------------------------
-- DIM_TRAFFIC_SOURCE: origen de la visita web
-- "campania" sigue el caso: las campañas en redes generan tráfico "ads"
-- y el email genera tráfico "direct" y "referral".
-- ---------------------------------------------------------------------
CREATE TABLE dim_traffic_source (
    source_key INTEGER PRIMARY KEY,
    source     VARCHAR NOT NULL,     -- código original: ads, direct, ...
    nombre     VARCHAR,
    campania   VARCHAR
);

INSERT INTO dim_traffic_source
SELECT
    ROW_NUMBER() OVER (ORDER BY source) AS source_key,
    source,
    CASE source
        WHEN 'ads'      THEN 'Anuncios'
        WHEN 'direct'   THEN 'Directo'
        WHEN 'organic'  THEN 'Orgánico'
        WHEN 'referral' THEN 'Referido'
        ELSE source
    END AS nombre,
    CASE source
        WHEN 'ads'      THEN 'Redes sociales'
        WHEN 'direct'   THEN 'Email'
        WHEN 'referral' THEN 'Email'
        ELSE 'Sin campaña'
    END AS campania
FROM (SELECT DISTINCT source FROM raw.web_session WHERE source IS NOT NULL);


-- ---------------------------------------------------------------------
-- DIM_DEVICE: dispositivo desde el que se navegó
-- ---------------------------------------------------------------------
CREATE TABLE dim_device (
    device_key INTEGER PRIMARY KEY,
    device     VARCHAR NOT NULL,     -- código original: mobile, desktop, tablet
    nombre     VARCHAR,
    tipo       VARCHAR               -- Móvil / Escritorio
);

INSERT INTO dim_device
SELECT
    ROW_NUMBER() OVER (ORDER BY device) AS device_key,
    device,
    CASE device
        WHEN 'mobile'  THEN 'Celular'
        WHEN 'desktop' THEN 'Computadora'
        WHEN 'tablet'  THEN 'Tablet'
        ELSE device
    END AS nombre,
    CASE WHEN device = 'desktop' THEN 'Escritorio' ELSE 'Móvil' END AS tipo
FROM (SELECT DISTINCT device FROM raw.web_session WHERE device IS NOT NULL);


-- ---------------------------------------------------------------------
-- DIM_PAYMENT_METHOD: medio de pago (GATEWAY = Mercado Pago)
-- ---------------------------------------------------------------------
CREATE TABLE dim_payment_method (
    payment_method_key INTEGER PRIMARY KEY,
    method             VARCHAR NOT NULL,   -- código original: CARD, GATEWAY, ...
    nombre             VARCHAR,
    tipo               VARCHAR             -- Electrónico / Efectivo
);

INSERT INTO dim_payment_method
SELECT
    ROW_NUMBER() OVER (ORDER BY method) AS payment_method_key,
    method,
    CASE method
        WHEN 'CARD'     THEN 'Tarjeta'
        WHEN 'GATEWAY'  THEN 'Mercado Pago'
        WHEN 'CASH'     THEN 'Efectivo'
        WHEN 'TRANSFER' THEN 'Transferencia'
        ELSE method
    END AS nombre,
    CASE WHEN method = 'CASH' THEN 'Efectivo' ELSE 'Electrónico' END AS tipo
FROM (SELECT DISTINCT method FROM raw.payment WHERE method IS NOT NULL);
