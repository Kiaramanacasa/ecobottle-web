/* =====================================================================
   EcoBottle AR: visualización
   ---------------------------------------------------------------------
   Esta página NO calcula medidas. Lee los data marts de dw/mart/
   (generados por sql/05_marts.sql) y los dibuja. Lo único que hace JS
   es dar formato a los números y convertir valores en posiciones de
   pantalla (por ejemplo, el "nivel" 0 a 1 en la altura del agua).
   ===================================================================== */

const MARTS = [
  "mart_kpis", "mart_ventas_mensual", "mart_ventas_canal", "mart_ventas_provincia",
  "mart_productos_mensual", "mart_nps_mensual", "mart_pagos_metodo", "mart_trafico",
  "mart_entregas", "mart_estados_pedido", "mart_clientes",
];
const RUTA_MARTS = "../dw/mart/";
const SIN_MOVIMIENTO = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
const MESES_LARGOS = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio",
  "agosto", "septiembre", "octubre", "noviembre", "diciembre"];

/* ---------------------------------------------------------------------
   Lectura de los CSV
   --------------------------------------------------------------------- */
function parseCSV(texto) {
  const filas = [];
  let fila = [], campo = "", comillas = false;
  for (let i = 0; i < texto.length; i++) {
    const c = texto[i];
    if (comillas) {
      if (c === '"' && texto[i + 1] === '"') { campo += '"'; i++; }
      else if (c === '"') comillas = false;
      else campo += c;
    } else if (c === '"') comillas = true;
    else if (c === ",") { fila.push(campo); campo = ""; }
    else if (c === "\n" || c === "\r") {
      if (c === "\r" && texto[i + 1] === "\n") i++;
      fila.push(campo); filas.push(fila); fila = []; campo = "";
    } else campo += c;
  }
  if (campo !== "" || fila.length) { fila.push(campo); filas.push(fila); }
  const [cabecera, ...datos] = filas.filter(f => f.length > 1 || f[0] !== "");
  const esNumero = /^-?\d+(\.\d+)?$/;
  return datos.map(f => Object.fromEntries(
    cabecera.map((col, j) => [col, esNumero.test(f[j]) ? Number(f[j]) : f[j]])
  ));
}

async function cargarMarts() {
  const embebidos = window.__MARTS__;
  const textos = await Promise.all(MARTS.map(async nombre => {
    if (embebidos && embebidos[nombre]) return embebidos[nombre];
    const resp = await fetch(RUTA_MARTS + nombre + ".csv");
    if (!resp.ok) throw new Error(`No se encontró ${RUTA_MARTS}${nombre}.csv (${resp.status})`);
    return resp.text();
  }));
  return Object.fromEntries(MARTS.map((n, i) => [n, parseCSV(textos[i])]));
}

/* ---------------------------------------------------------------------
   Formato
   --------------------------------------------------------------------- */
const fmt1 = new Intl.NumberFormat("es-AR", { minimumFractionDigits: 1, maximumFractionDigits: 1 });
const fmt0 = new Intl.NumberFormat("es-AR", { maximumFractionDigits: 0 });
const millones = v => `$${fmt1.format(v / 1e6)} M`;
const pesos = v => `$${fmt0.format(v)}`;
const pct = v => `${fmt1.format(v)} %`;
const entero = v => fmt0.format(v);
const mesLargo = fila => `${MESES_LARGOS[fila.mes - 1]} de ${fila.anio}`;
const capital = s => s.charAt(0).toUpperCase() + s.slice(1);
function fechaLarga(iso) {
  const [a, m, d] = iso.split("-").map(Number);
  return `${d} de ${MESES_LARGOS[m - 1]} de ${a}`;
}

/* ---------------------------------------------------------------------
   Botella SVG
   Cuerpo en un viewBox de 100 x 260. El agua ocupa de y=256 (fondo)
   a y=64 (hombros), o sea 192 unidades: nivel 1 = botella llena.
   --------------------------------------------------------------------- */
const FONDO = 256, ALTO_UTIL = 192;
const CUERPO = "M38,20 L62,20 L62,40 C62,52 90,56 90,76 L90,238 Q90,256 72,256 L28,256 Q10,256 10,238 L10,76 C10,56 38,52 38,40 Z";
let idBotella = 0;

function ola(yTope, amplitud = 3.5) {
  // Onda periódica (longitud 50) más ancha que la botella, para deslizarla
  let d = `M-100,${yTope}`;
  for (let x = -100; x < 200; x += 50) {
    d += ` q12.5,${-amplitud} 25,0 t25,0`;
  }
  return d + ` L200,262 L-100,262 Z`;
}

/**
 * capas: [{ nivel, color, clase }] de abajo hacia arriba, cada una dibujada
 * desde el fondo hasta su nivel (la de más arriba se dibuja primero).
 */
function botella({ capas, tapa = "var(--tinta)", burbujas = 0, extra = "" }) {
  const id = `b${++idBotella}`;
  const ordenadas = [...capas].sort((a, b) => b.nivel - a.nivel);
  const agua = ordenadas.map((c, i) => {
    const y = FONDO - c.nivel * ALTO_UTIL;
    const dur = 3.2 + i * 1.3;
    return `<path class="ola ${c.clase || ""}" d="${ola(y)}" fill="${c.color}"
      style="animation-duration:${dur}s;animation-delay:-${i * 0.7}s"/>`;
  }).join("");
  let circulos = "";
  for (let i = 0; i < burbujas; i++) {
    const x = 20 + ((i * 37) % 60), r = 1.2 + (i % 4) * 0.8;
    const dur = 4 + (i % 5) * 1.1, delay = (i * 0.83) % 6;
    circulos += `<circle class="burbuja" cx="${x}" cy="250" r="${r}"
      style="animation-duration:${dur}s;animation-delay:-${delay}s"/>`;
  }
  return `
  <svg viewBox="0 -4 100 266" aria-hidden="true" focusable="false">
    <defs><clipPath id="${id}"><path d="${CUERPO}"/></clipPath></defs>
    <rect x="34" y="-2" width="32" height="24" rx="5" fill="${tapa}"/>
    <rect x="34" y="6" width="32" height="2.5" fill="rgba(255,255,255,.25)"/>
    <rect x="34" y="13" width="32" height="2.5" fill="rgba(255,255,255,.25)"/>
    <path d="${CUERPO}" fill="var(--vidrio)"/>
    <g clip-path="url(#${id})">
      <g class="llenado" style="transform:translateY(${SIN_MOVIMIENTO ? 0 : ALTO_UTIL + 10}px)">
        ${agua}
        ${circulos}
      </g>
    </g>
    <path d="${CUERPO}" fill="none" stroke="var(--vidrio-borde)" stroke-width="2.5"/>
    <path d="M20,92 L20,226" stroke="rgba(255,255,255,.45)" stroke-width="5" stroke-linecap="round"/>
    ${extra}
  </svg>`;
}

// Estilos de animación de la botella (se inyectan una vez)
document.head.insertAdjacentHTML("beforeend", `<style>
  .ola { animation: deslizar 3.5s linear infinite; }
  @keyframes deslizar { from { transform: translateX(0); } to { transform: translateX(-50px); } }
  .llenado { transition: transform 2s cubic-bezier(.22,.9,.25,1); }
  .mes-botella:hover .ola, .mes-botella:focus-visible .ola { animation-duration: .9s !important; }
  .burbuja { fill: rgba(255,255,255,.55); animation: subir 5s ease-in infinite; }
  @keyframes subir {
    0% { transform: translateY(0); opacity: 0; }
    15% { opacity: .9; }
    100% { transform: translateY(-190px); opacity: 0; }
  }
</style>`);

function llenar(svgPadre) {
  const g = svgPadre.querySelector(".llenado");
  if (g) g.style.transform = "translateY(0px)";
}

/* Revela un elemento cuando entra en pantalla (una sola vez) */
const observador = "IntersectionObserver" in window
  ? new IntersectionObserver(entradas => {
      entradas.forEach(e => {
        if (e.isIntersecting) { e.target.__revelar?.(); observador.unobserve(e.target); }
      });
    }, { threshold: 0.25 })
  : null;
function alVerse(el, fn) {
  if (SIN_MOVIMIENTO || !observador) { fn(); return; }
  el.__revelar = fn;
  observador.observe(el);
}

/* ---------------------------------------------------------------------
   Tooltip compartido
   --------------------------------------------------------------------- */
const tooltip = document.getElementById("tooltip");
function mostrarTooltip(html, x, y) {
  tooltip.innerHTML = html;
  tooltip.hidden = false;
  const r = tooltip.getBoundingClientRect();
  const left = Math.min(Math.max(8, x - r.width / 2), window.innerWidth - r.width - 8);
  const top = y - r.height - 14 < 8 ? y + 18 : y - r.height - 14;
  tooltip.style.left = `${left}px`;
  tooltip.style.top = `${top}px`;
}
function ocultarTooltip() { tooltip.hidden = true; }
function conTooltip(el, html) {
  el.addEventListener("pointermove", e => mostrarTooltip(html, e.clientX, e.clientY));
  el.addEventListener("pointerleave", ocultarTooltip);
  el.addEventListener("focus", () => {
    const r = el.getBoundingClientRect();
    mostrarTooltip(html, r.left + r.width / 2, r.top);
  });
  el.addEventListener("blur", ocultarTooltip);
}

/* ---------------------------------------------------------------------
   Secciones
   --------------------------------------------------------------------- */
function dibujarHero(k, canales) {
  document.getElementById("bajada-periodo").textContent =
    `Ventas, clientes y operación del ${fechaLarga(k.desde)} al ${fechaLarga(k.hasta)}.`;

  const kpis = [
    [millones(k.ventas_totales), "Ventas totales"],
    [entero(k.usuarios_activos), "Usuarios activos"],
    [pesos(k.ticket_promedio), "Ticket promedio"],
    [fmt1.format(k.nps), "NPS del período"],
  ];
  document.getElementById("kpis").innerHTML = kpis
    .map(([v, t]) => `<div><dt>${t}</dt><dd>${v}</dd></div>`).join("");

  // La botella grande: todo lo vendido; las capas son los canales
  const online = canales.find(c => c.canal === "Tienda Online");
  const tiendas = canales.find(c => c.canal !== "Tienda Online");
  const lleno = 0.94;
  const nivelOnline = lleno * online.pct_ventas / 100;
  const yOnline = FONDO - nivelOnline * ALTO_UTIL;
  const yTope = FONDO - lleno * ALTO_UTIL;
  const extra = `
    <text class="etiqueta-botella grande en-claro" x="50" y="${yTope + 31}" text-anchor="middle" font-size="15">${millones(k.ventas_totales)}</text>
    <text class="capa-texto en-claro" x="50" y="${yTope + 43}" text-anchor="middle" font-size="7">ventas totales</text>
    <text class="capa-texto en-claro" x="50" y="${yOnline - 9}" text-anchor="middle" font-size="6.6">${tiendas.canal} ${pct(tiendas.pct_ventas)}</text>
    <text class="capa-texto" x="50" y="${(FONDO + yOnline) / 2 + 3}" text-anchor="middle" font-size="6.6">${online.canal} ${pct(online.pct_ventas)}</text>`;
  const fig = document.getElementById("hero-botella");
  fig.innerHTML = botella({
    capas: [
      { nivel: nivelOnline, color: "var(--agua-online)" },
      { nivel: lleno, color: "var(--agua-tiendas)" },
    ],
    burbujas: 14,
    extra,
  }) + `<figcaption id="hero-leyenda">Lo vendido en el período, en capas por canal de venta.</figcaption>`;
  requestAnimationFrame(() => setTimeout(() => llenar(fig.querySelector("svg")), 250));
}

function dibujarGondola(meses, k) {
  const cont = document.getElementById("gondola-botellas");
  cont.style.setProperty("--meses", meses.length);
  cont.innerHTML = "";

  meses.forEach((m, i) => {
    const b = document.createElement("button");
    b.type = "button";
    b.className = "mes-botella" + (m.es_mejor_mes ? " mejor" : "");
    b.setAttribute("role", "listitem");
    b.setAttribute("aria-label", `${capital(mesLargo(m))}: ${millones(m.ventas)} vendidos`);
    b.innerHTML = botella({
      capas: [
        { nivel: m.nivel_online, color: "var(--agua-online)" },
        { nivel: m.nivel, color: "var(--agua-tiendas)" },
      ],
      tapa: m.es_mejor_mes ? "var(--sol)" : "var(--tinta)",
    }) + `<span class="mes-nombre">${m.mes_corto}</span>`
       + (m.es_mejor_mes ? `<span class="corona">Récord</span>` : "");
    conTooltip(b, `<strong>${capital(mesLargo(m))}</strong>
      Ventas: ${millones(m.ventas)}<br>
      Online: ${millones(m.ventas_online)}<br>
      Tiendas físicas: ${millones(m.ventas_tiendas)}<br>
      Pedidos: ${entero(m.pedidos)}<br>
      Frente al promedio: ${m.pct_vs_promedio > 0 ? "+" : ""}${pct(m.pct_vs_promedio)}`);
    cont.appendChild(b);
  });

  // Línea del mes promedio
  const linea = document.createElement("div");
  linea.className = "linea-promedio";
  cont.appendChild(linea);
  const ubicarLinea = () => {
    const svg = cont.querySelector(".mes-botella svg");
    if (!svg) return;
    const rc = cont.getBoundingClientRect(), rs = svg.getBoundingClientRect();
    const escala = rs.height / 266;            // alto del viewBox
    const yAgua = (FONDO - meses[0].nivel_promedio * ALTO_UTIL + 4) * escala;
    linea.style.top = `${rs.top - rc.top + yAgua}px`;
  };
  ubicarLinea();
  window.addEventListener("resize", ubicarLinea);

  // Etiquetas de año debajo de la góndola
  const porAnio = {};
  meses.forEach(m => { porAnio[m.anio] = (porAnio[m.anio] || 0) + 1; });
  const anios = document.createElement("div");
  anios.className = "anios";
  anios.style.setProperty("--cols-anios", Object.values(porAnio).map(n => `${n}fr`).join(" "));
  anios.innerHTML = Object.keys(porAnio).map(a => `<span>${a}</span>`).join("");
  cont.parentElement.appendChild(anios);
  cont.parentElement.insertAdjacentHTML("afterend", `<div class="leyenda gondola-leyenda">
    <span><i style="background:var(--agua-online)"></i>Tienda Online</span>
    <span><i style="background:var(--agua-tiendas)"></i>Tiendas Físicas</span>
    <span><i class="raya"></i>Mes promedio: ${millones(meses[0].promedio_mensual)}</span>
  </div>`);

  // Llenado escalonado al verse
  alVerse(cont, () => {
    cont.querySelectorAll(".mes-botella svg").forEach((svg, i) => {
      setTimeout(() => llenar(svg), SIN_MOVIMIENTO ? 0 : i * 70);
    });
  });

  const mejor = meses.find(m => m.es_mejor_mes);
  document.getElementById("hallazgo-gondola").innerHTML =
    `<strong>${capital(mesLargo(mejor))} fue el mejor mes:</strong> ${millones(mejor.ventas)}, un ${pct(mejor.pct_vs_promedio)} más que un mes promedio. `
    + `La tienda online genera el ${pct(k.pct_ventas_online)} de todas las ventas.`;
}

function dibujarProvincias(provincias) {
  const ol = document.getElementById("provincias");
  ol.innerHTML = provincias.map(p => `
    <li class="cano-fila">
      <span class="cano-rank">${p.ranking}</span>
      <div>
        <div class="cano-top"><span>${p.provincia}</span><span>${millones(p.ventas)} (${pct(p.pct_ventas)})</span></div>
        <div class="cano"><div class="cano-agua" data-nivel="${p.nivel}"></div></div>
      </div>
    </li>`).join("");
  alVerse(ol, () => ol.querySelectorAll(".cano-agua").forEach((el, i) =>
    setTimeout(() => { el.style.width = `${el.dataset.nivel * 100}%`; }, i * 150)));
}

function dibujarDuelo(filas) {
  const periodos = [...new Set(filas.map(f => f.periodo))];
  const productos = [...new Set(filas.map(f => f.producto))].sort();
  const duelo = document.getElementById("duelo");
  const colores = ["var(--agua-tiendas)", "var(--agua-online)"];
  duelo.innerHTML = productos.map((p, i) => `
    <div class="duelo-item" data-producto="${p}">
      <span class="puesto"></span>
      ${botella({ capas: [{ nivel: 1, color: colores[i % 2] }] })}
      <div class="duelo-nombre">${p}</div>
      <div class="duelo-dato"></div>
    </div>`).join("");

  const slider = document.getElementById("mes-slider");
  const label = document.getElementById("mes-label");
  slider.max = periodos.length - 1;

  function mostrar(indice) {
    const periodo = periodos[indice];
    const delMes = filas.filter(f => f.periodo === periodo);
    label.textContent = delMes[0].etiqueta;
    slider.setAttribute("aria-valuetext", delMes[0].etiqueta);
    duelo.querySelectorAll(".duelo-item").forEach(item => {
      const f = delMes.find(x => x.producto === item.dataset.producto);
      const g = item.querySelector(".llenado");
      // el agua sube o baja hasta el nivel del mart (0 a 1)
      g.style.transform = `translateY(${(1 - (f ? f.nivel : 0)) * ALTO_UTIL}px)`;
      const puesto = item.querySelector(".puesto");
      puesto.textContent = f ? `Puesto ${f.ranking}` : "Sin ventas";
      puesto.classList.toggle("primero", f && f.ranking === 1);
      item.querySelector(".duelo-dato").innerHTML = f
        ? `<strong>${millones(f.ventas)}</strong><br>${pct(f.pct_del_mes)} del mes, ${entero(f.unidades)} unidades`
        : "";
    });
  }
  slider.addEventListener("input", () => mostrar(Number(slider.value)));

  const play = document.getElementById("play");
  let timer = null;
  const parar = () => { clearInterval(timer); timer = null; play.setAttribute("aria-pressed", "false"); };
  play.setAttribute("aria-pressed", "false");
  play.addEventListener("click", () => {
    if (timer) { parar(); return; }
    if (Number(slider.value) >= periodos.length - 1) slider.value = 0;
    play.setAttribute("aria-pressed", "true");
    mostrar(Number(slider.value));
    timer = setInterval(() => {
      const v = Number(slider.value) + 1;
      if (v > periodos.length - 1) { parar(); return; }
      slider.value = v;
      mostrar(v);
    }, 1100);
  });

  slider.value = periodos.length - 1;
  alVerse(duelo, () => mostrar(Number(slider.value)));
  if (SIN_MOVIMIENTO) mostrar(Number(slider.value));
}

function dibujarNPS(meses, k) {
  const W = 960, H = 330, m = { t: 30, r: 24, b: 46, l: 44 };
  const yMin = 0, yMax = 50;  // eje fijo del gráfico (no es una medida)
  const x = i => m.l + (i * (W - m.l - m.r)) / (meses.length - 1);
  const y = v => m.t + ((yMax - v) * (H - m.t - m.b)) / (yMax - yMin);

  const puntos = meses.map((f, i) => [x(i), y(f.nps)]);
  const linea = puntos.map((p, i) => `${i ? "L" : "M"}${p[0].toFixed(1)},${p[1].toFixed(1)}`).join(" ");
  const area = `${linea} L${x(meses.length - 1)},${y(yMin)} L${x(0)},${y(yMin)} Z`;
  const grilla = [0, 10, 20, 30, 40, 50].map(v =>
    `<line class="nps-grilla" x1="${m.l}" x2="${W - m.r}" y1="${y(v)}" y2="${y(v)}"/>
     <text class="nps-eje" x="${m.l - 10}" y="${y(v) + 4}" text-anchor="end">${v}</text>`).join("");
  const ejeX = meses.map((f, i) =>
    `<text class="nps-eje" x="${x(i)}" y="${H - m.b + 20}" text-anchor="middle">${f.etiqueta.split(" ")[0]}</text>`
    + (f.mes === 1 ? `<text class="nps-eje" x="${x(i)}" y="${H - m.b + 36}" text-anchor="middle" font-weight="700">${f.anio}</text>` : "")
  ).join("");
  const minimo = meses.findIndex(f => f.es_minimo);

  const cont = document.getElementById("nps");
  cont.innerHTML = `<div class="leyenda"><span><i class="raya"></i>NPS del período completo: ${fmt1.format(k.nps)}</span><span><i style="background:var(--alerta);border-radius:50%"></i>Mes más bajo</span></div>`
    + `
    <svg viewBox="0 0 ${W} ${H}" role="img" aria-label="NPS mensual de ${meses[0].etiqueta} a ${meses[meses.length - 1].etiqueta}">
      <defs>
        <linearGradient id="nps-agua" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stop-color="var(--agua-online)" stop-opacity=".55"/>
          <stop offset="1" stop-color="var(--agua-tiendas)" stop-opacity=".08"/>
        </linearGradient>
        <clipPath id="nps-revelar"><rect x="0" y="0" width="${SIN_MOVIMIENTO ? W : 0}" height="${H}"/></clipPath>
      </defs>
      ${grilla}
      <g clip-path="url(#nps-revelar)">
        <path d="${area}" fill="url(#nps-agua)"/>
        <path class="nps-linea" d="${linea}"/>
      </g>
      <line class="nps-promedio" x1="${m.l}" x2="${W - m.r}" y1="${y(k.nps)}" y2="${y(k.nps)}"/>
      ${minimo >= 0 ? `<text class="nps-nota" x="${x(minimo)}" y="${y(meses[minimo].nps) + 26}" text-anchor="middle" fill="var(--alerta)">${meses[minimo].etiqueta}: ${fmt1.format(meses[minimo].nps)}</text>` : ""}
      ${meses.map((f, i) => `<circle class="nps-punto${f.es_minimo ? " minimo" : ""}" cx="${puntos[i][0]}" cy="${puntos[i][1]}" r="5.5" tabindex="0" data-i="${i}" aria-label="${f.etiqueta}: NPS ${fmt1.format(f.nps)}"/>`).join("")}
      ${ejeX}
    </svg>`;

  cont.querySelectorAll(".nps-punto").forEach(c => {
    const f = meses[Number(c.dataset.i)];
    conTooltip(c, `<strong>${capital(mesLargo(f))}</strong>
      NPS: ${fmt1.format(f.nps)}<br>
      Promotores: ${pct(f.pct_promotores)}<br>
      Pasivos: ${pct(f.pct_pasivos)}<br>
      Detractores: ${pct(f.pct_detractores)}<br>
      Respuestas: ${entero(f.respuestas)}`);
  });

  alVerse(cont, () => {
    const rect = cont.querySelector("#nps-revelar rect");
    const inicio = performance.now(), dur = 1800;
    const paso = t => {
      const p = Math.max(0, Math.min(1, (t - inicio) / dur));
      rect.setAttribute("width", W * (1 - Math.pow(1 - p, 3)));
      if (p < 1) requestAnimationFrame(paso);
    };
    requestAnimationFrame(paso);
  });

  const f = meses[minimo];
  document.getElementById("hallazgo-nps").innerHTML =
    `<strong>El NPS se hundió a ${fmt1.format(f.nps)} en ${mesLargo(f)},</strong> cuando el del período completo es ${fmt1.format(k.nps)}. `
    + `Ese mes los detractores llegaron al ${pct(f.pct_detractores)}.`;
}

function dibujarPagos(pagos) {
  const ESCALA = 12; // eje fijo: 0 a 12 % de fallos
  const ul = document.getElementById("pagos");
  ul.innerHTML = pagos.map(p => `
    <li class="${p.fallidos > 0 ? "gotea" : ""}">
      <span>${p.metodo}</span>
      <span class="barra"><i data-ancho="${Math.min(100, (p.tasa_fallos / ESCALA) * 100)}"></i></span>
      <span class="valor">${pct(p.tasa_fallos)}</span>
    </li>`).join("");
  ul.querySelectorAll("li").forEach((li, i) => conTooltip(li,
    `<strong>${pagos[i].metodo}</strong>${entero(pagos[i].fallidos)} fallidos de ${entero(pagos[i].pagos)} pagos`));
  alVerse(ul, () => ul.querySelectorAll(".barra i").forEach(i => { i.style.width = `${i.dataset.ancho}%`; }));
  const [peor, segundo] = pagos;
  document.getElementById("hallazgo-pagos").innerHTML =
    `<strong>${peor.metodo} falla en el ${pct(peor.tasa_fallos)} de los cobros,</strong> frente al ${pct(segundo.tasa_fallos)} de ${segundo.metodo.toLowerCase()}.`;
}

function dibujarTrafico(filas) {
  const colores = { "Celular": "var(--agua-online)", "Computadora": "var(--agua-tiendas)", "Tablet": "var(--sol)" };
  const dispositivos = [...new Set(filas.map(f => f.dispositivo))];
  document.getElementById("leyenda-trafico").innerHTML = dispositivos
    .map(d => `<span><i style="background:${colores[d] || "var(--tinta-suave)"}"></i>${d}</span>`).join("");

  const origenes = [...new Set(filas.map(f => f.origen))];
  const ul = document.getElementById("trafico");
  ul.innerHTML = origenes.map(o => {
    const partes = filas.filter(f => f.origen === o);
    return `<li class="${o === "Anuncios" ? "destacada" : ""}">
      <div class="fila-titulo"><span>${o}</span><span>${entero(partes[0].sesiones_origen)} sesiones</span></div>
      <div class="apilada">${dispositivos.map(d => {
        const p = partes.find(x => x.dispositivo === d);
        return `<span data-crece="${p ? p.pct_del_origen : 0}" style="background:${colores[d]}" title="${d}: ${p ? pct(p.pct_del_origen) : "0 %"}"></span>`;
      }).join("")}</div>
    </li>`;
  }).join("");
  ul.querySelectorAll("li").forEach((li, i) => {
    const partes = filas.filter(f => f.origen === origenes[i]);
    conTooltip(li, `<strong>${origenes[i]}</strong>Campaña: ${partes[0].campania}<br>`
      + partes.map(p => `${p.dispositivo}: ${pct(p.pct_del_origen)}`).join("<br>"));
  });
  alVerse(ul, () => ul.querySelectorAll("[data-crece]").forEach(s => { s.style.flexGrow = s.dataset.crece; }));

  const anuncios = filas.find(f => f.origen === "Anuncios" && f.dispositivo === "Celular");
  if (anuncios) document.getElementById("hallazgo-trafico").innerHTML =
    `<strong>El ${pct(anuncios.pct_del_origen)} del tráfico de anuncios llega desde el celular:</strong> la experiencia mobile define las campañas.`;
}

function dibujarEntregas(filas) {
  const anios = [...new Set(filas.map(f => f.anio))].sort();
  const [a1, a2] = anios;
  const MIN = 3, MAX = 7; // eje fijo en días
  const xp = v => 6 + ((v - MIN) / (MAX - MIN)) * 88;
  document.getElementById("leyenda-entregas").innerHTML =
    `<span><i style="background:var(--superficie);border:2px solid var(--tinta-suave)"></i>${a1}</span>`
    + `<span><i style="background:var(--agua-online)"></i>${a2}</span>`;

  const provincias = [...new Set(filas.map(f => f.provincia))]
    .sort((a, b) => (a === "Todas" ? -1 : b === "Todas" ? 1 : a.localeCompare(b)));
  const ul = document.getElementById("entregas");
  const nombre = p => (p === "Todas" ? "Total" : p);
  ul.innerHTML = provincias.map(p => {
    const v1 = filas.find(f => f.provincia === p && f.anio === a1);
    const v2 = filas.find(f => f.provincia === p && f.anio === a2);
    const izq = Math.min(xp(v1.dias_promedio), xp(v2.dias_promedio));
    const ancho = Math.abs(xp(v1.dias_promedio) - xp(v2.dias_promedio));
    return `<li class="${v2.es_mas_lenta ? "lenta" : ""}">
      <span>${nombre(p)}</span>
      <div class="manc" aria-label="${nombre(p)}: ${fmt1.format(v1.dias_promedio)} días en ${a1}, ${fmt1.format(v2.dias_promedio)} en ${a2}">
        <i class="manc-barra" style="left:${izq}%;width:${ancho}%"></i>
        <i class="manc-punto manc-a1" style="left:${xp(v1.dias_promedio)}%"></i>
        <i class="manc-punto manc-a2" style="left:${xp(v2.dias_promedio)}%"></i>
        <b class="manc-num" style="left:${xp(v1.dias_promedio)}%">${fmt1.format(v1.dias_promedio)}</b>
        <b class="manc-num manc-num-a2" style="left:${xp(v2.dias_promedio)}%">${fmt1.format(v2.dias_promedio)}</b>
      </div>
    </li>`;
  }).join("");
  ul.querySelectorAll("li").forEach((li, i) => {
    const p = provincias[i];
    const v1 = filas.find(f => f.provincia === p && f.anio === a1);
    const v2 = filas.find(f => f.provincia === p && f.anio === a2);
    conTooltip(li, `<strong>${nombre(p)}</strong>${a1}: ${fmt1.format(v1.dias_promedio)} días<br>${a2}: ${fmt1.format(v2.dias_promedio)} días`);
  });

  const todas1 = filas.find(f => f.provincia === "Todas" && f.anio === a1);
  const todas2 = filas.find(f => f.provincia === "Todas" && f.anio === a2);
  const lenta = filas.find(f => f.anio === a2 && f.es_mas_lenta);
  document.getElementById("hallazgo-entregas").innerHTML =
    `<strong>Los envíos bajaron de ${fmt1.format(todas1.dias_promedio)} a ${fmt1.format(todas2.dias_promedio)} días,</strong> pero ${lenta.provincia} sigue siendo la provincia más lenta.`;
}

function dibujarClientes(filas, k) {
  const colores = {
    "Frecuencia": ["var(--agua-tiendas)", "var(--agua-online)", "var(--agua-online-2)"],
    "Valor": ["var(--sol)", "var(--agua-online)"],
    "Tipo de compra": ["var(--agua-tiendas)", "var(--agua-online)"],
  };
  const titulos = {
    "Frecuencia": "Cuántas veces compra cada cliente",
    "Valor": "El 20 % que más compra",
    "Tipo de compra": "Primeras compras y recompras",
  };
  const orden = ["Valor", "Frecuencia", "Tipo de compra"];
  const cont = document.getElementById("comparaciones");
  cont.innerHTML = orden.map(g => {
    const partes = filas.filter(f => f.grupo === g).sort((a, b) => a.orden - b.orden);
    const unidad = g === "Tipo de compra" ? "Pedidos" : "Clientes";
    const barra = campo => partes.map((p, i) =>
      `<span data-crece="${p[campo]}" style="background:${colores[g][i]};color:${colores[g][i].includes("sol") ? "#1b1300" : "#fff"}">${pct(p[campo])}</span>`).join("");
    return `<div class="comparacion">
      <h3>${titulos[g]}</h3>
      <div class="comp-fila"><span>${unidad}</span><div class="comp-barra">${barra("pct_cantidad")}</div></div>
      <div class="comp-fila"><span>Ventas</span><div class="comp-barra">${barra("pct_ventas")}</div></div>
      <div class="comp-leyenda">${partes.map((p, i) => `<span><i style="background:${colores[g][i]}"></i>${p.categoria}</span>`).join("")}</div>
    </div>`;
  }).join("");
  alVerse(cont, () => cont.querySelectorAll("[data-crece]").forEach(s => { s.style.flexGrow = s.dataset.crece; }));

  // De cada $100, cuántos son IVA
  const iva = Math.round(k.iva_cada_100);
  document.getElementById("iva-titulo").textContent = `De cada $100 vendidos, $${iva} son IVA`;
  const gota = `<svg viewBox="0 0 20 26"><path d="M10 1 C10 1 2 11 2 16.5 A8 8 0 0 0 18 16.5 C18 11 10 1 10 1Z"/></svg>`;
  const gotas = document.getElementById("gotas");
  gotas.innerHTML = Array.from({ length: 100 }, () => gota).join("");
  alVerse(gotas, () => [...gotas.children].slice(100 - iva).forEach((g, i) =>
    setTimeout(() => g.classList.add("iva"), SIN_MOVIMIENTO ? 0 : i * 45)));
  document.getElementById("iva-nota").textContent =
    `Venta neta: ${millones(k.venta_neta)} sobre ${millones(k.ventas_totales)} brutos.`;

}

function dibujarEstados(estados, k) {
  const colores = {
    "Entregado": "var(--agua-online)", "Pagado": "var(--agua-tiendas)",
    "Cancelado": "var(--alerta)", "Reembolsado": "var(--sol)", "Creado": "var(--tinta-suave)",
  };
  const cont = document.getElementById("estados");
  cont.innerHTML = estados.map(e =>
    `<span data-crece="${e.pct_pedidos}" style="background:${colores[e.estado] || "var(--tinta-suave)"}"></span>`).join("");
  cont.insertAdjacentHTML("afterend", `<div class="comp-leyenda" style="margin-top:.6rem">${estados
    .filter(e => e.pct_pedidos >= 0.1)
    .map(e => `<span><i style="background:${colores[e.estado]}"></i>${e.estado} ${pct(e.pct_pedidos)}</span>`).join("")}</div>`);
  [...cont.children].forEach((s, i) => conTooltip(s,
    `<strong>${estados[i].estado}</strong>${entero(estados[i].pedidos)} pedidos<br>${millones(estados[i].monto)}`));
  alVerse(cont, () => cont.querySelectorAll("[data-crece]").forEach(s => { s.style.flexGrow = s.dataset.crece; }));
  document.getElementById("hallazgo-estados").innerHTML =
    `<strong>El ${pct(k.pct_pedidos_concretados)} de los pedidos se concreta.</strong> Cancelaciones y reembolsos suman ${millones(k.monto_perdido)} que no se cobraron.`;
}

/* ---------------------------------------------------------------------
   Fondo: burbujas que suben despacio
   --------------------------------------------------------------------- */
function burbujasDeFondo() {
  const canvas = document.getElementById("burbujas");
  if (SIN_MOVIMIENTO || !canvas.getContext) return;
  const ctx = canvas.getContext("2d");
  let W, H, dpr;
  const burbujas = Array.from({ length: 34 }, () => nueva(true));
  function nueva(inicio) {
    return {
      x: Math.random(), y: inicio ? Math.random() : 1.05,
      r: 2 + Math.random() * 9, v: 0.00012 + Math.random() * 0.00035,
      fase: Math.random() * Math.PI * 2,
    };
  }
  function medir() {
    dpr = Math.min(2, window.devicePixelRatio || 1);
    W = canvas.clientWidth; H = canvas.clientHeight;
    canvas.width = W * dpr; canvas.height = H * dpr;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }
  medir();
  window.addEventListener("resize", medir);
  let anterior = performance.now();
  function cuadro(t) {
    const dt = Math.min(50, t - anterior); anterior = t;
    ctx.clearRect(0, 0, W, H);
    const color = getComputedStyle(document.documentElement).getPropertyValue("--agua-online").trim() || "#1677a8";
    burbujas.forEach((b, i) => {
      b.y -= b.v * dt;
      if (b.y < -0.05) burbujas[i] = nueva(false);
      const x = b.x * W + Math.sin(t / 1400 + b.fase) * 12;
      ctx.beginPath();
      ctx.arc(x, b.y * H, b.r, 0, Math.PI * 2);
      ctx.strokeStyle = color;
      ctx.globalAlpha = 0.16;
      ctx.lineWidth = 1.2;
      ctx.stroke();
      ctx.globalAlpha = 0.22;
      ctx.beginPath();
      ctx.arc(x - b.r * 0.35, b.y * H - b.r * 0.35, b.r * 0.25, 0, Math.PI * 2);
      ctx.fillStyle = color;
      ctx.fill();
    });
    ctx.globalAlpha = 1;
    requestAnimationFrame(cuadro);
  }
  requestAnimationFrame(cuadro);
}

/* ---------------------------------------------------------------------
   Inicio
   --------------------------------------------------------------------- */
async function iniciar() {
  burbujasDeFondo();
  try {
    const d = await cargarMarts();
    const k = d.mart_kpis[0];
    dibujarHero(k, d.mart_ventas_canal);
    dibujarGondola(d.mart_ventas_mensual, k);
    dibujarProvincias(d.mart_ventas_provincia);
    dibujarDuelo(d.mart_productos_mensual);
    dibujarNPS(d.mart_nps_mensual, k);
    dibujarPagos(d.mart_pagos_metodo);
    dibujarTrafico(d.mart_trafico);
    dibujarEntregas(d.mart_entregas);
    dibujarClientes(d.mart_clientes, k);
    dibujarEstados(d.mart_estados_pedido, k);
  } catch (err) {
    const caja = document.getElementById("error");
    caja.hidden = false;
    caja.innerHTML = `<strong>No se pudieron leer los datos.</strong> ${err.message}. `
      + `Si abriste el archivo con doble clic, el navegador bloquea la lectura de los CSV: `
      + `usá la página publicada en GitHub Pages o ejecutá <code>python3 -m http.server</code> en la carpeta del proyecto `
      + `y entrá a <code>http://localhost:8000/web/</code>.`;
    console.error(err);
  }
}
iniciar();
