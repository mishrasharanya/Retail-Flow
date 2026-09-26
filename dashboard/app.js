const money = new Intl.NumberFormat("en-US", {
  style: "currency",
  currency: "BRL",
  maximumFractionDigits: 0,
});
const integer = new Intl.NumberFormat("en-US", { maximumFractionDigits: 0 });
const decimal = new Intl.NumberFormat("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const percent = new Intl.NumberFormat("en-US", { style: "percent", minimumFractionDigits: 1, maximumFractionDigits: 1 });

async function loadJson(name) {
  const response = await fetch(`data/${name}.json`);
  if (!response.ok) throw new Error(`Unable to load ${name}.json`);
  return response.json();
}

function renderKpis(summary) {
  const cards = [
    ["Delivered orders", integer.format(summary.delivered_orders)],
    ["Customers", integer.format(summary.customers)],
    ["Revenue", money.format(summary.revenue)],
    ["Average order", money.format(summary.average_order_value)],
    ["Review score", `${decimal.format(summary.average_review_score)} / 5`],
    ["Late deliveries", percent.format(summary.late_delivery_rate)],
    ["Delivery time", `${decimal.format(summary.average_delivery_days)} days`],
  ];
  document.querySelector("#kpi-grid").innerHTML = cards.map(([label, value]) => `
    <article class="kpi"><span class="kpi-label">${label}</span><strong class="kpi-value">${value}</strong></article>
  `).join("");
}

function renderInsights(summary, monthly, categories, states) {
  const meaningfulMonths = monthly.filter(row => Number(row.order_count) >= 100);
  const peakMonth = meaningfulMonths.reduce((best, row) => Number(row.revenue) > Number(best.revenue) ? row : best);
  const worstDeliveryMonth = meaningfulMonths.reduce((worst, row) => Number(row.late_delivery_rate) > Number(worst.late_delivery_rate) ? row : worst);
  const topCategory = categories[0];
  const topState = states[0];
  const stateRevenue = states.reduce((sum, row) => sum + Number(row.revenue), 0);
  const topStateShare = Number(topState.revenue) / stateRevenue;
  const monthName = value => new Date(value).toLocaleDateString("en-US", { month: "long", year: "numeric", timeZone: "UTC" });
  const cards = [
    {
      number: money.format(peakMonth.revenue),
      title: `${monthName(peakMonth.order_month)} was the revenue peak`,
      body: `${integer.format(peakMonth.order_count)} delivered orders drove the high point. Its ${percent.format(peakMonth.late_delivery_rate)} late rate was above the overall ${percent.format(summary.late_delivery_rate)} rate.`,
    },
    {
      number: percent.format(worstDeliveryMonth.late_delivery_rate),
      title: `${monthName(worstDeliveryMonth.order_month)} had the most delivery pressure`,
      body: `More than one in five delivered orders arrived after the estimate, compared with about one in twelve overall.`,
    },
    {
      number: percent.format(topStateShare),
      title: `${topState.customer_state} leads delivered revenue`,
      body: `${integer.format(topState.order_count)} orders produced ${money.format(topState.revenue)}, while its ${percent.format(topState.late_delivery_rate)} late rate remained below the national result.`,
    },
    {
      number: money.format(topCategory.product_revenue),
      title: `${topCategory.product_category_name.replaceAll("_", " ")} is the leading category`,
      body: `${integer.format(topCategory.items_sold)} items generated the highest product value, with an average order review of ${decimal.format(topCategory.average_review_score)}.`,
    },
  ];
  document.querySelector("#insight-grid").innerHTML = cards.map(card => `
    <article class="insight-card"><strong class="insight-number">${card.number}</strong><h3>${card.title}</h3><p>${card.body}</p></article>
  `).join("");
}

function renderMonthlyChart(rows) {
  const width = 1200, height = 330;
  const margin = { top: 18, right: 25, bottom: 42, left: 72 };
  const innerWidth = width - margin.left - margin.right;
  const innerHeight = height - margin.top - margin.bottom;
  const values = rows.map(row => Number(row.revenue));
  const max = Math.max(...values) * 1.08;
  const x = index => margin.left + (index / (rows.length - 1)) * innerWidth;
  const y = value => margin.top + innerHeight - (value / max) * innerHeight;
  const points = rows.map((row, index) => `${x(index)},${y(Number(row.revenue))}`).join(" ");
  const area = `${margin.left},${margin.top + innerHeight} ${points} ${margin.left + innerWidth},${margin.top + innerHeight}`;
  const grid = [0, .25, .5, .75, 1].map(ratio => {
    const yy = margin.top + innerHeight * (1 - ratio);
    return `<line class="grid-line" x1="${margin.left}" x2="${width - margin.right}" y1="${yy}" y2="${yy}" />
      <text class="axis-label" x="${margin.left - 12}" y="${yy + 4}" text-anchor="end">${money.format(max * ratio)}</text>`;
  }).join("");
  const xLabels = rows.map((row, index) => index % 3 === 0
    ? `<text class="axis-label" x="${x(index)}" y="${height - 12}" text-anchor="middle">${new Date(row.order_month).toLocaleDateString("en-US", { month: "short", year: "2-digit", timeZone: "UTC" })}</text>`
    : "").join("");
  const dots = rows.map((row, index) => `<circle class="data-point" cx="${x(index)}" cy="${y(Number(row.revenue))}" r="4"><title>${row.order_month.slice(0, 7)}: ${money.format(row.revenue)}</title></circle>`).join("");

  document.querySelector("#monthly-chart").innerHTML = `<svg viewBox="0 0 ${width} ${height}" preserveAspectRatio="none">
    <defs><linearGradient id="areaGradient" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#087f72" stop-opacity=".22"/><stop offset="1" stop-color="#087f72" stop-opacity="0"/></linearGradient></defs>
    ${grid}<polygon class="revenue-area" points="${area}"/><polyline class="revenue-line" points="${points}"/>${dots}${xLabels}
  </svg>`;
}

function renderCategories(rows) {
  const max = Math.max(...rows.map(row => Number(row.product_revenue)));
  document.querySelector("#category-chart").innerHTML = rows.slice(0, 10).map(row => `
    <div class="bar-row" title="${row.items_sold} items sold">
      <span class="bar-label">${row.product_category_name.replaceAll("_", " ")}</span>
      <span class="bar-track"><span class="bar-fill" style="width:${Number(row.product_revenue) / max * 100}%"></span></span>
      <strong class="bar-value">${money.format(row.product_revenue)}</strong>
    </div>
  `).join("");
}

function renderStates(rows) {
  document.querySelector("#state-table").innerHTML = rows.slice(0, 10).map(row => `
    <tr><td><strong>${row.customer_state}</strong></td><td>${integer.format(row.order_count)}</td><td>${money.format(row.revenue)}</td><td>${percent.format(row.late_delivery_rate)}</td></tr>
  `).join("");
}

function renderSellers(rows) {
  document.querySelector("#seller-table").innerHTML = rows.map(row => `
    <tr><td class="seller-id" title="${row.seller_id}">${row.seller_id}</td><td>${row.seller_city}, ${row.seller_state}</td><td>${integer.format(row.order_count)}</td><td>${integer.format(row.items_sold)}</td><td>${money.format(row.product_revenue)}</td><td>${row.average_review_score == null ? "—" : decimal.format(row.average_review_score)}</td></tr>
  `).join("");
}

async function initialize() {
  try {
    const [summaryRows, monthly, categories, states, sellers, metadata] = await Promise.all([
      loadJson("dashboard_summary"), loadJson("monthly_sales"), loadJson("category_performance"),
      loadJson("state_performance"), loadJson("seller_performance"), loadJson("metadata"),
    ]);
    renderKpis(summaryRows[0]);
    renderInsights(summaryRows[0], monthly, categories, states);
    renderMonthlyChart(monthly);
    renderCategories(categories);
    renderStates(states);
    renderSellers(sellers);
    document.querySelector("#generated-at").textContent = `Exported ${new Date(metadata.generated_at).toLocaleString()}`;
  } catch (error) {
    const message = document.querySelector("#error-message");
    message.hidden = false;
    message.textContent = `${error.message}. Serve this folder with python -m http.server; do not open index.html directly.`;
  }
}

initialize();
