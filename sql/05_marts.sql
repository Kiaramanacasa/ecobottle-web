-- =====================================================================
-- 05_marts.sql — Data marts agregados para la visualización web
-- =====================================================================
-- Leen SOLO del modelo estrella (dim_ y fact_), nunca de raw.
-- Cada mart trae las medidas YA CALCULADAS: totales, porcentajes,
-- rankings, promedios y hasta el "nivel" (0 a 1) con el que se llena
-- cada botella del gráfico. La página web (carpeta web/) no calcula
-- nada: lee estos CSV de dw/mart/ y los muestra.
--
-- Criterios (los mismos del resto del trabajo):
--   * Venta = pedido con estado PAID o FULFILLED.
--   * Ventas = total del pedido (con IVA y envío).
--   * Venta neta = ventas - IVA.
--   * NPS = % promotores (9-10) - % detractores (0-6).
-- =====================================================================


-- ---------------------------------------------------------------------
-- MART_KPIS: una sola fila con los indicadores generales del período.
-- ---------------------------------------------------------------------
CREATE TABLE mart_kpis AS
WITH pedidos AS (
    SELECT
        COUNT(*) AS pedidos_totales,
        SUM(CASE WHEN status IN ('PAID', 'FULFILLED') THEN 1 ELSE 0 END) AS pedidos_cobrados,
        SUM(CASE WHEN status IN ('PAID', 'FULFILLED') THEN total_amount END) AS ventas_totales,
        SUM(CASE WHEN status IN ('PAID', 'FULFILLED') THEN tax_amount END) AS impuestos,
        SUM(CASE WHEN status IN ('CANCELLED', 'REFUNDED') THEN total_amount END) AS monto_perdido
    FROM fact_sales_order
),
online AS (
    SELECT SUM(f.total_amount) AS ventas_online
    FROM fact_sales_order AS f
    JOIN dim_channel AS ch
        ON ch.channel_key = f.channel_key
    WHERE f.status IN ('PAID', 'FULFILLED')
      AND ch.code = 'ONLINE'
),
usuarios AS (
    -- Usuario = cliente identificado, o la sesión si es anónima
    SELECT
        COUNT(*) AS sesiones,
        COUNT(DISTINCT CASE
            WHEN customer_key IS NOT NULL THEN 'C-' || customer_key
            ELSE 'S-' || session_id
        END) AS usuarios_activos
    FROM fact_web_session
),
nps AS (
    SELECT
        COUNT(*) AS respuestas_nps,
        SUM(CASE WHEN score >= 9 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)
          - SUM(CASE WHEN score <= 6 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS nps
    FROM fact_nps
),
recurrencia AS (
    SELECT
        SUM(CASE WHEN pedidos >= 2 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS pct_recurrentes
    FROM (
        SELECT customer_key, COUNT(*) AS pedidos
        FROM fact_sales_order
        WHERE status IN ('PAID', 'FULFILLED')
        GROUP BY customer_key
    )
),
fechas AS (
    SELECT MIN(d.fecha) AS desde, MAX(d.fecha) AS hasta
    FROM fact_sales_order AS f
    JOIN dim_date AS d
        ON d.date_key = f.date_key
)
SELECT
    ROUND(p.ventas_totales, 2)                                  AS ventas_totales,
    p.pedidos_cobrados,
    ROUND(p.ventas_totales / p.pedidos_cobrados, 2)             AS ticket_promedio,
    u.usuarios_activos,
    u.sesiones,
    ROUND(n.nps, 1)                                             AS nps,
    n.respuestas_nps,
    ROUND(p.ventas_totales - p.impuestos, 2)                    AS venta_neta,
    ROUND(p.impuestos, 2)                                       AS impuestos,
    ROUND(p.impuestos * 100.0 / p.ventas_totales, 1)            AS iva_cada_100,
    ROUND(p.pedidos_cobrados * 100.0 / p.pedidos_totales, 1)    AS pct_pedidos_concretados,
    ROUND(p.monto_perdido, 2)                                   AS monto_perdido,
    ROUND(o.ventas_online * 100.0 / p.ventas_totales, 1)        AS pct_ventas_online,
    ROUND(r.pct_recurrentes, 1)                                 AS pct_clientes_recurrentes,
    f.desde,
    f.hasta
FROM pedidos AS p, online AS o, usuarios AS u, nps AS n, recurrencia AS r, fechas AS f;


-- ---------------------------------------------------------------------
-- MART_VENTAS_MENSUAL: una fila por mes.
-- nivel = ventas del mes / ventas del mejor mes (llena la botella).
-- ---------------------------------------------------------------------
CREATE TABLE mart_ventas_mensual AS
WITH por_mes AS (
    SELECT
        d.year AS anio,
        d.month AS mes,
        SUM(f.total_amount) AS ventas,
        SUM(CASE WHEN ch.code = 'ONLINE' THEN f.total_amount ELSE 0 END) AS ventas_online,
        SUM(CASE WHEN ch.code = 'OFFLINE' THEN f.total_amount ELSE 0 END) AS ventas_tiendas,
        COUNT(*) AS pedidos
    FROM fact_sales_order AS f
    JOIN dim_date AS d
        ON d.date_key = f.date_key
    JOIN dim_channel AS ch
        ON ch.channel_key = f.channel_key
    WHERE f.status IN ('PAID', 'FULFILLED')
    GROUP BY d.year, d.month
)
SELECT
    anio,
    mes,
    printf('%04d-%02d', anio, mes)                                          AS periodo,
    ['Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic'][mes] AS mes_corto,
    ['Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic'][mes] || ' ' || anio AS etiqueta,
    ROUND(ventas, 2)                                                        AS ventas,
    ROUND(ventas_online, 2)                                                 AS ventas_online,
    ROUND(ventas_tiendas, 2)                                                AS ventas_tiendas,
    pedidos,
    ROUND(ventas / pedidos, 2)                                              AS ticket_promedio,
    ROUND(ventas / MAX(ventas) OVER (), 4)                                  AS nivel,
    ROUND(ventas_online / MAX(ventas) OVER (), 4)                           AS nivel_online,
    ROUND(AVG(ventas) OVER (), 2)                                           AS promedio_mensual,
    ROUND(AVG(ventas) OVER () / MAX(ventas) OVER (), 4)                     AS nivel_promedio,
    ROUND((ventas / AVG(ventas) OVER () - 1) * 100, 1)                      AS pct_vs_promedio,
    CASE WHEN ventas = MAX(ventas) OVER () THEN 1 ELSE 0 END                AS es_mejor_mes
FROM por_mes
ORDER BY anio, mes;


-- ---------------------------------------------------------------------
-- MART_VENTAS_CANAL: una fila por canal de venta.
-- ---------------------------------------------------------------------
CREATE TABLE mart_ventas_canal AS
SELECT
    ch.name                                                     AS canal,
    ROUND(SUM(f.total_amount), 2)                               AS ventas,
    COUNT(*)                                                    AS pedidos,
    ROUND(SUM(f.total_amount) / COUNT(*), 2)                    AS ticket_promedio,
    ROUND(SUM(f.total_amount) * 100.0 / SUM(SUM(f.total_amount)) OVER (), 1) AS pct_ventas
FROM fact_sales_order AS f
JOIN dim_channel AS ch
    ON ch.channel_key = f.channel_key
WHERE f.status IN ('PAID', 'FULFILLED')
GROUP BY ch.name
ORDER BY ventas DESC;


-- ---------------------------------------------------------------------
-- MART_VENTAS_PROVINCIA: una fila por provincia, con su ranking.
-- ---------------------------------------------------------------------
CREATE TABLE mart_ventas_provincia AS
SELECT
    p.name                                                      AS provincia,
    ROUND(SUM(f.total_amount), 2)                               AS ventas,
    COUNT(*)                                                    AS pedidos,
    ROUND(SUM(f.total_amount) * 100.0 / SUM(SUM(f.total_amount)) OVER (), 1) AS pct_ventas,
    RANK() OVER (ORDER BY SUM(f.total_amount) DESC)             AS ranking,
    ROUND(SUM(f.total_amount) / MAX(SUM(f.total_amount)) OVER (), 4) AS nivel
FROM fact_sales_order AS f
JOIN dim_province AS p
    ON p.province_key = f.province_key
WHERE f.status IN ('PAID', 'FULFILLED')
GROUP BY p.name
ORDER BY ranking;


-- ---------------------------------------------------------------------
-- MART_PRODUCTOS_MENSUAL: una fila por producto y mes, con su ranking.
-- Las ventas de cada línea se prorratean al total del pedido (igual que
-- en tablero_ventas) para que la suma coincida con las ventas totales.
-- ---------------------------------------------------------------------
CREATE TABLE mart_productos_mensual AS
WITH por_mes AS (
    SELECT
        d.year AS anio,
        d.month AS mes,
        p.name AS producto,
        SUM(i.quantity) AS unidades,
        SUM(CAST(i.line_total AS DOUBLE) * o.total_amount / o.subtotal) AS ventas
    FROM fact_sales_order_item AS i
    JOIN fact_sales_order AS o
        ON o.order_id = i.order_id
    JOIN dim_date AS d
        ON d.date_key = i.date_key
    JOIN dim_product AS p
        ON p.product_key = i.product_key
    WHERE o.status IN ('PAID', 'FULFILLED')
    GROUP BY d.year, d.month, p.name
)
SELECT
    anio,
    mes,
    printf('%04d-%02d', anio, mes)                                          AS periodo,
    ['Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic'][mes] || ' ' || anio AS etiqueta,
    producto,
    unidades,
    ROUND(ventas, 2)                                                        AS ventas,
    RANK() OVER (PARTITION BY anio, mes ORDER BY ventas DESC)               AS ranking,
    ROUND(ventas * 100.0 / SUM(ventas) OVER (PARTITION BY anio, mes), 1)    AS pct_del_mes,
    ROUND(ventas / MAX(ventas) OVER (), 4)                                  AS nivel
FROM por_mes
ORDER BY anio, mes, ranking;


-- ---------------------------------------------------------------------
-- MART_NPS_MENSUAL: una fila por mes con el NPS y su composición.
-- ---------------------------------------------------------------------
CREATE TABLE mart_nps_mensual AS
WITH por_mes AS (
    SELECT
        d.year AS anio,
        d.month AS mes,
        COUNT(*) AS respuestas,
        SUM(CASE WHEN n.score >= 9 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS pct_promotores,
        SUM(CASE WHEN n.score BETWEEN 7 AND 8 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS pct_pasivos,
        SUM(CASE WHEN n.score <= 6 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS pct_detractores
    FROM fact_nps AS n
    JOIN dim_date AS d
        ON d.date_key = n.date_key
    GROUP BY d.year, d.month
)
SELECT
    anio,
    mes,
    printf('%04d-%02d', anio, mes)                                          AS periodo,
    ['Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic'][mes] || ' ' || anio AS etiqueta,
    respuestas,
    ROUND(pct_promotores - pct_detractores, 1)                              AS nps,
    ROUND(pct_promotores, 1)                                                AS pct_promotores,
    ROUND(pct_pasivos, 1)                                                   AS pct_pasivos,
    ROUND(pct_detractores, 1)                                               AS pct_detractores,
    ROUND(AVG(pct_promotores - pct_detractores) OVER (), 1)                 AS nps_promedio_mensual,
    CASE WHEN pct_promotores - pct_detractores
              = MIN(pct_promotores - pct_detractores) OVER () THEN 1 ELSE 0 END AS es_minimo
FROM por_mes
ORDER BY anio, mes;


-- ---------------------------------------------------------------------
-- MART_PAGOS_METODO: una fila por medio de pago, con su tasa de fallos.
-- ---------------------------------------------------------------------
CREATE TABLE mart_pagos_metodo AS
SELECT
    pm.nombre                                                   AS metodo,
    pm.tipo                                                     AS tipo,
    COUNT(*)                                                    AS pagos,
    SUM(CASE WHEN p.status = 'FAILED' THEN 1 ELSE 0 END)        AS fallidos,
    ROUND(SUM(CASE WHEN p.status = 'FAILED' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS tasa_fallos,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1)          AS pct_pagos
FROM fact_payment AS p
JOIN dim_payment_method AS pm
    ON pm.payment_method_key = p.payment_method_key
GROUP BY pm.nombre, pm.tipo
ORDER BY tasa_fallos DESC;


-- ---------------------------------------------------------------------
-- MART_TRAFICO: una fila por origen del tráfico y dispositivo.
-- pct_del_origen = qué parte de las sesiones de ese origen llega desde
-- cada dispositivo.
-- ---------------------------------------------------------------------
CREATE TABLE mart_trafico AS
SELECT
    ts.nombre                                                   AS origen,
    ts.campania                                                 AS campania,
    dv.nombre                                                   AS dispositivo,
    COUNT(*)                                                    AS sesiones,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY ts.nombre), 1) AS pct_del_origen,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1)          AS pct_total,
    SUM(COUNT(*)) OVER (PARTITION BY ts.nombre)                 AS sesiones_origen
FROM fact_web_session AS w
JOIN dim_traffic_source AS ts
    ON ts.source_key = w.source_key
JOIN dim_device AS dv
    ON dv.device_key = w.device_key
GROUP BY ts.nombre, ts.campania, dv.nombre
ORDER BY sesiones_origen DESC, origen, sesiones DESC;


-- ---------------------------------------------------------------------
-- MART_ENTREGAS: una fila por provincia y año, con los días promedio
-- entre el pedido y la entrega (solo envíos entregados).
-- ---------------------------------------------------------------------
CREATE TABLE mart_entregas AS
SELECT
    p.name                                                      AS provincia,
    d.year                                                      AS anio,
    COUNT(*)                                                    AS envios_entregados,
    ROUND(AVG(s.delivery_days), 1)                              AS dias_promedio,
    CASE WHEN AVG(s.delivery_days)
              = MAX(AVG(s.delivery_days)) OVER (PARTITION BY d.year) THEN 1 ELSE 0 END AS es_mas_lenta
FROM fact_shipment AS s
JOIN dim_date AS d
    ON d.date_key = s.date_key
JOIN dim_province AS p
    ON p.province_key = s.province_key
WHERE s.status = 'DELIVERED'
GROUP BY p.name, d.year
UNION ALL
SELECT
    'Todas'                                                     AS provincia,
    d.year                                                      AS anio,
    COUNT(*)                                                    AS envios_entregados,
    ROUND(AVG(s.delivery_days), 1)                              AS dias_promedio,
    0                                                           AS es_mas_lenta
FROM fact_shipment AS s
JOIN dim_date AS d
    ON d.date_key = s.date_key
WHERE s.status = 'DELIVERED'
GROUP BY d.year
ORDER BY provincia, anio;


-- ---------------------------------------------------------------------
-- MART_ESTADOS_PEDIDO: una fila por estado del pedido.
-- ---------------------------------------------------------------------
CREATE TABLE mart_estados_pedido AS
SELECT
    CASE status
        WHEN 'FULFILLED' THEN 'Entregado'
        WHEN 'PAID'      THEN 'Pagado'
        WHEN 'CANCELLED' THEN 'Cancelado'
        WHEN 'REFUNDED'  THEN 'Reembolsado'
        WHEN 'CREATED'   THEN 'Creado'
        ELSE status
    END                                                         AS estado,
    CASE WHEN status IN ('PAID', 'FULFILLED') THEN 1 ELSE 0 END AS es_venta,
    COUNT(*)                                                    AS pedidos,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1)          AS pct_pedidos,
    ROUND(SUM(total_amount), 2)                                 AS monto
FROM fact_sales_order
GROUP BY status
ORDER BY pedidos DESC;


-- ---------------------------------------------------------------------
-- MART_CLIENTES: cómo se reparten clientes y ventas según tres miradas
-- (grupo): frecuencia de compra, valor del cliente y tipo de compra.
--   cantidad   = clientes (o pedidos, en "Tipo de compra")
--   pct_cantidad / pct_ventas = su peso dentro del grupo
-- ---------------------------------------------------------------------
CREATE TABLE mart_clientes AS
WITH ventas AS (
    SELECT customer_key, order_id, date_key, total_amount
    FROM fact_sales_order
    WHERE status IN ('PAID', 'FULFILLED')
),
por_cliente AS (
    SELECT
        customer_key,
        COUNT(*) AS pedidos,
        SUM(total_amount) AS ventas
    FROM ventas
    GROUP BY customer_key
),
clasificados AS (
    SELECT
        customer_key,
        pedidos,
        ventas,
        CASE
            WHEN pedidos = 1 THEN '1 compra'
            WHEN pedidos <= 3 THEN '2 a 3 compras'
            ELSE '4 o más compras'
        END AS frecuencia,
        CASE
            WHEN NTILE(5) OVER (ORDER BY ventas DESC, customer_key) = 1 THEN 'Top 20 % de clientes'
            ELSE 'Resto de clientes'
        END AS segmento
    FROM por_cliente
),
compras AS (
    SELECT
        total_amount,
        CASE
            WHEN ROW_NUMBER() OVER (PARTITION BY customer_key ORDER BY date_key, order_id) = 1
            THEN 'Primera compra' ELSE 'Recompra'
        END AS tipo
    FROM ventas
),
grupos AS (
    SELECT 'Frecuencia' AS grupo, frecuencia AS categoria,
           CASE frecuencia WHEN '1 compra' THEN 1 WHEN '2 a 3 compras' THEN 2 ELSE 3 END AS orden,
           COUNT(*) AS cantidad, SUM(ventas) AS ventas
    FROM clasificados
    GROUP BY frecuencia
    UNION ALL
    SELECT 'Valor', segmento,
           CASE WHEN segmento LIKE 'Top%' THEN 1 ELSE 2 END,
           COUNT(*), SUM(ventas)
    FROM clasificados
    GROUP BY segmento
    UNION ALL
    SELECT 'Tipo de compra', tipo,
           CASE WHEN tipo = 'Primera compra' THEN 1 ELSE 2 END,
           COUNT(*), SUM(total_amount)
    FROM compras
    GROUP BY tipo
)
SELECT
    grupo,
    categoria,
    orden,
    cantidad,
    ROUND(cantidad * 100.0 / SUM(cantidad) OVER (PARTITION BY grupo), 1) AS pct_cantidad,
    ROUND(ventas, 2)                                                     AS ventas,
    ROUND(ventas * 100.0 / SUM(ventas) OVER (PARTITION BY grupo), 1)     AS pct_ventas
FROM grupos
ORDER BY grupo, orden;
