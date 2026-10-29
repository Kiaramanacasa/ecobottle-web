-- =====================================================================
-- 04_tablero.sql — Marts detallados para el tablero de Data Studio
-- =====================================================================
-- Data Studio no relaciona tablas como un modelo estrella, así que
-- desde el DW armamos 7 tablas planas "listas para graficar" (una fila
-- por pedido, sesión, pago, etc.) y las exportamos a dw/mart/ como CSV.
-- No forman parte del modelo estrella: se leen de él.
-- Las columnas que comparten (fecha, canal) tienen el mismo nombre en
-- todas para que los filtros del tablero apliquen a todas.
-- =====================================================================


-- ---------------------------------------------------------------------
-- TABLERO_VENTAS: una fila por producto vendido, solo pedidos PAID o
-- FULFILLED. "ventas" reparte el total del pedido (con IVA y envío)
-- entre sus productos en proporción a cada línea, así la suma da el
-- total de ventas y el filtro de producto aplica a todos los KPIs.
-- ---------------------------------------------------------------------
COPY (
    SELECT
        i.order_item_id,
        i.order_id,
        d.fecha,
        ch.name AS canal,
        pr.name AS provincia,
        COALESCE(st.name, 'Online') AS tienda,
        p.name AS producto,
        CASE WHEN cu.status = 'A' THEN 'Activo' ELSE 'Inactivo' END AS cliente_estado,
        i.quantity AS cantidad,
        i.line_total AS ventas_linea,
        ROUND(CAST(i.line_total AS DOUBLE) * o.total_amount / o.subtotal, 2) AS ventas
    FROM fact_sales_order_item AS i
    JOIN fact_sales_order AS o
        ON o.order_id = i.order_id
    JOIN dim_date AS d
        ON d.date_key = i.date_key
    JOIN dim_channel AS ch
        ON ch.channel_key = i.channel_key
    JOIN dim_product AS p
        ON p.product_key = i.product_key
    LEFT JOIN dim_province AS pr
        ON pr.province_key = o.province_key
    LEFT JOIN dim_store AS st
        ON st.store_key = i.store_key
    LEFT JOIN dim_customer AS cu
        ON cu.customer_key = i.customer_key
    WHERE o.status IN ('PAID', 'FULFILLED')
    ORDER BY i.order_item_id
) TO 'dw/mart/tablero_ventas.csv' (HEADER);


-- ---------------------------------------------------------------------
-- TABLERO_SESIONES: una fila por sesión web (todas son canal online).
-- "usuario" identifica al cliente si inició sesión; si es anónimo,
-- se usa la sesión (como indica la consigna).
-- ---------------------------------------------------------------------
COPY (
    SELECT
        w.session_id,
        d.fecha,
        ch.name AS canal,
        CASE
            WHEN c.customer_id IS NOT NULL THEN 'C-' || c.customer_id
            ELSE 'S-' || w.session_id
        END AS usuario,
        CASE
            WHEN c.customer_id IS NOT NULL THEN 'Identificado'
            ELSE 'Anónimo'
        END AS tipo_usuario,
        CASE WHEN c.customer_id IS NOT NULL THEN 1 ELSE 0 END AS identificada,
        src.source AS origen,
        dv.device AS dispositivo
    FROM fact_web_session AS w
    JOIN dim_date AS d
        ON d.date_key = w.date_key
    LEFT JOIN dim_customer AS c
        ON c.customer_key = w.customer_key
    LEFT JOIN dim_traffic_source AS src
        ON src.source_key = w.source_key
    LEFT JOIN dim_device AS dv
        ON dv.device_key = w.device_key
    CROSS JOIN dim_channel AS ch
    WHERE ch.code = 'ONLINE'
    ORDER BY w.session_id
) TO 'dw/mart/tablero_sesiones.csv' (HEADER);


-- ---------------------------------------------------------------------
-- TABLERO_NPS: una fila por respuesta. NPS = % promotores - % detractores
-- ---------------------------------------------------------------------
COPY (
    SELECT
        n.nps_id,
        d.fecha,
        ch.name AS canal,
        n.score AS puntaje,
        CASE
            WHEN n.score >= 9 THEN 'Promotor'
            WHEN n.score >= 7 THEN 'Pasivo'
            ELSE 'Detractor'
        END AS categoria,
        CASE WHEN n.score >= 9 THEN 1 ELSE 0 END AS promotor,
        CASE WHEN n.score <= 6 THEN 1 ELSE 0 END AS detractor,
        CASE
            WHEN n.score >= 9 THEN 100
            WHEN n.score <= 6 THEN -100
            ELSE 0
        END AS nps_valor
    FROM fact_nps AS n
    JOIN dim_date AS d
        ON d.date_key = n.date_key
    JOIN dim_channel AS ch
        ON ch.channel_key = n.channel_key
    ORDER BY n.nps_id
) TO 'dw/mart/tablero_nps.csv' (HEADER);


-- ---------------------------------------------------------------------
-- TABLERO_PAGOS: una fila por pago (todos los estados).
-- metodo: GATEWAY = Mercado Pago (pasarela de pago online).
-- "fallido" vale 1 si el pago fue rechazado, para calcular la tasa.
-- La fecha es la del pedido, igual que en el resto del tablero.
-- ---------------------------------------------------------------------
COPY (
    SELECT
        p.payment_id,
        p.order_id,
        d.fecha,
        ch.name AS canal,
        pr.name AS provincia,
        pm.nombre AS metodo,
        CASE p.status
            WHEN 'PAID'     THEN 'Pagado'
            WHEN 'FAILED'   THEN 'Fallido'
            WHEN 'REFUNDED' THEN 'Reembolsado'
            WHEN 'PENDING'  THEN 'Pendiente'
            ELSE p.status
        END AS estado,
        p.amount AS monto,
        CASE WHEN p.status = 'FAILED' THEN 1 ELSE 0 END AS fallido
    FROM fact_payment AS p
    JOIN dim_date AS d
        ON d.date_key = p.date_key
    JOIN dim_channel AS ch
        ON ch.channel_key = p.channel_key
    JOIN fact_sales_order AS o
        ON o.order_id = p.order_id
    LEFT JOIN dim_payment_method AS pm
        ON pm.payment_method_key = p.payment_method_key
    LEFT JOIN dim_province AS pr
        ON pr.province_key = o.province_key
    ORDER BY p.payment_id
) TO 'dw/mart/tablero_pagos.csv' (HEADER);


-- ---------------------------------------------------------------------
-- TABLERO_ENVIOS: una fila por envío de Correo Argentino.
-- dias_entrega = días entre el pedido y la entrega (vacío si no se
-- entregó). "entregado" vale 1 si el envío llegó a destino.
-- ---------------------------------------------------------------------
COPY (
    SELECT
        s.shipment_id,
        s.order_id,
        d.fecha,
        ch.name AS canal,
        pr.name AS provincia,
        COALESCE(st.name, 'Online') AS tienda,
        CASE s.status
            WHEN 'DELIVERED' THEN 'Entregado'
            WHEN 'SHIPPED'   THEN 'En camino'
            WHEN 'READY'     THEN 'Listo para despachar'
            WHEN 'CANCELLED' THEN 'Cancelado'
            ELSE s.status
        END AS estado,
        s.delivery_days AS dias_entrega,
        CASE WHEN s.status = 'DELIVERED' THEN 1 ELSE 0 END AS entregado
    FROM fact_shipment AS s
    JOIN dim_date AS d
        ON d.date_key = s.date_key
    JOIN dim_channel AS ch
        ON ch.channel_key = s.channel_key
    LEFT JOIN dim_province AS pr
        ON pr.province_key = s.province_key
    LEFT JOIN dim_store AS st
        ON st.store_key = s.store_key
    ORDER BY s.shipment_id
) TO 'dw/mart/tablero_envios.csv' (HEADER);


-- ---------------------------------------------------------------------
-- TABLERO_PEDIDOS: una fila por pedido, con TODOS los estados.
-- es_venta = 1 si el pedido cuenta como venta (PAID o FULFILLED).
-- Las medidas de venta solo se completan cuando el pedido es venta,
-- así el tablero las suma o promedia sin filtros ni fórmulas.
--   venta_bruta     = total cobrado (productos + IVA + envío)
--   impuestos       = IVA
--   venta_neta      = venta bruta - impuestos
--   venta_productos = productos sin IVA ni envío
--   monto_perdido   = total de pedidos cancelados o reembolsados
-- ---------------------------------------------------------------------
COPY (
    WITH items AS (
        SELECT
            order_id,
            SUM(quantity) AS unidades,
            SUM(discount_amount) AS descuentos
        FROM fact_sales_order_item
        GROUP BY order_id
    ),
    compras AS (
        SELECT
            order_id,
            ROW_NUMBER() OVER (
                PARTITION BY customer_key
                ORDER BY date_key, order_id
            ) AS nro_compra
        FROM fact_sales_order
        WHERE status IN ('PAID', 'FULFILLED')
    )
    SELECT
        o.order_id,
        d.fecha,
        ch.name AS canal,
        pr.name AS provincia,
        COALESCE(st.name, 'Online') AS tienda,
        CASE o.status
            WHEN 'FULFILLED' THEN 'Entregado'
            WHEN 'PAID'      THEN 'Pagado'
            WHEN 'CANCELLED' THEN 'Cancelado'
            WHEN 'REFUNDED'  THEN 'Reembolsado'
            WHEN 'CREATED'   THEN 'Creado'
            ELSE o.status
        END AS estado,
        CASE WHEN o.status IN ('PAID', 'FULFILLED') THEN 1 ELSE 0 END AS es_venta,
        CASE WHEN cu.status = 'A' THEN 'Activo' ELSE 'Inactivo' END AS cliente_estado,
        CASE
            WHEN co.nro_compra = 1 THEN 'Primera compra'
            WHEN co.nro_compra > 1 THEN 'Recompra'
        END AS tipo_compra,
        it.unidades,
        CASE WHEN o.status IN ('PAID', 'FULFILLED') THEN o.total_amount END AS venta_bruta,
        CASE WHEN o.status IN ('PAID', 'FULFILLED') THEN o.tax_amount END AS impuestos,
        CASE WHEN o.status IN ('PAID', 'FULFILLED') THEN o.total_amount - o.tax_amount END AS venta_neta,
        CASE WHEN o.status IN ('PAID', 'FULFILLED') THEN o.subtotal END AS venta_productos,
        CASE WHEN o.status IN ('PAID', 'FULFILLED') THEN o.shipping_fee END AS envio,
        CASE WHEN o.status IN ('PAID', 'FULFILLED') THEN it.descuentos END AS descuentos,
        CASE WHEN o.status IN ('CANCELLED', 'REFUNDED') THEN o.total_amount END AS monto_perdido
    FROM fact_sales_order AS o
    JOIN dim_date AS d
        ON d.date_key = o.date_key
    JOIN dim_channel AS ch
        ON ch.channel_key = o.channel_key
    LEFT JOIN dim_province AS pr
        ON pr.province_key = o.province_key
    LEFT JOIN dim_store AS st
        ON st.store_key = o.store_key
    LEFT JOIN dim_customer AS cu
        ON cu.customer_key = o.customer_key
    LEFT JOIN items AS it
        ON it.order_id = o.order_id
    LEFT JOIN compras AS co
        ON co.order_id = o.order_id
    ORDER BY o.order_id
) TO 'dw/mart/tablero_pedidos.csv' (HEADER);


-- ---------------------------------------------------------------------
-- TABLERO_CLIENTES: una fila por cliente, acumulado del período.
-- canal y provincia son los más frecuentes en sus compras.
-- recurrente = 1 si compró 2 veces o más (vacío si nunca compró).
-- segmento_valor: el 20 % de clientes que más compra vs el resto.
-- ---------------------------------------------------------------------
COPY (
    WITH ventas AS (
        SELECT customer_key, order_id, total_amount, channel_key, province_key
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
    canal_principal AS (
        SELECT
            v.customer_key,
            ch.name AS canal,
            ROW_NUMBER() OVER (
                PARTITION BY v.customer_key
                ORDER BY COUNT(*) DESC, ch.name
            ) AS orden
        FROM ventas AS v
        JOIN dim_channel AS ch
            ON ch.channel_key = v.channel_key
        GROUP BY v.customer_key, ch.name
    ),
    provincia_principal AS (
        SELECT
            v.customer_key,
            pr.name AS provincia,
            ROW_NUMBER() OVER (
                PARTITION BY v.customer_key
                ORDER BY COUNT(*) DESC, pr.name
            ) AS orden
        FROM ventas AS v
        JOIN dim_province AS pr
            ON pr.province_key = v.province_key
        GROUP BY v.customer_key, pr.name
    ),
    quintiles AS (
        SELECT
            customer_key,
            NTILE(5) OVER (ORDER BY ventas DESC) AS quintil
        FROM por_cliente
    )
    SELECT
        cu.customer_id,
        CASE WHEN cu.status = 'A' THEN 'Activo' ELSE 'Inactivo' END AS cliente_estado,
        cp.canal,
        pp.provincia,
        CASE WHEN pc.pedidos IS NULL THEN 0 ELSE 1 END AS comprador,
        pc.pedidos,
        CASE
            WHEN pc.pedidos >= 2 THEN 1
            WHEN pc.pedidos = 1 THEN 0
        END AS recurrente,
        pc.ventas,
        CASE
            WHEN pc.pedidos IS NULL THEN 'Sin compras'
            WHEN pc.pedidos = 1 THEN '1 compra'
            WHEN pc.pedidos <= 3 THEN '2 a 3 compras'
            ELSE '4 o más compras'
        END AS frecuencia,
        CASE
            WHEN q.quintil = 1 THEN 'Top 20 % de clientes'
            WHEN q.quintil IS NOT NULL THEN 'Resto de clientes'
        END AS segmento_valor
    FROM dim_customer AS cu
    LEFT JOIN por_cliente AS pc
        ON pc.customer_key = cu.customer_key
    LEFT JOIN canal_principal AS cp
        ON cp.customer_key = cu.customer_key AND cp.orden = 1
    LEFT JOIN provincia_principal AS pp
        ON pp.customer_key = cu.customer_key AND pp.orden = 1
    LEFT JOIN quintiles AS q
        ON q.customer_key = cu.customer_key
    ORDER BY cu.customer_id
) TO 'dw/mart/tablero_clientes.csv' (HEADER);
