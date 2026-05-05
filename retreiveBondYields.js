// Bond yields in basis points (1e4 precision)

const series = ["DGS2", "DGS5", "DGS10", "DGS30"];

const responses = await Promise.all(
  series.map((id) =>
    Functions.makeHttpRequest({
      url:
        `https://api.stlouisfed.org/fred/series/observations` +
        `?series_id=${id}` +
        `&api_key=${secrets.FRED_API_KEY}` +
        `&file_type=json` +
        `&sort_order=desc` +
        `&limit=1`,
    })
  )
);

const values = [];
const timestamps = [];

for (let i = 0; i < responses.length; i++) {
  const res = responses[i];

  if (res.error) {
    throw Error(`Request failed for ${series[i]}`);
  }

  const obs = res.data.observations[0];

  if (!obs || obs.value === ".") {
    throw Error(`Missing data for ${series[i]}`);
  }

  // Convert % string → BPS (1e4 precision)
  // e.g. "4.52" → 45200
  const yieldBps = Math.round(parseFloat(obs.value) * 10000);

  values.push(yieldBps);

  timestamps.push(Math.floor(new Date(obs.date).getTime() / 1000));
}

// deterministic timestamp (oldest to avoid future bias)
const timestamp = Math.min(...timestamps);

// optional debug
console.log("bond yields timestamp:", timestamp);

return Functions.encodeAbiParameters(
  ["uint256[]", "uint256"],
  [values, timestamp]
);