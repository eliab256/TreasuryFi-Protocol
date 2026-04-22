// Bond yield series
const series = ["DGS1", "DGS2", "DGS5", "DGS10"];

// Fetch data in parallel
const responses = await Promise.all(
  series.map((id) =>
    Functions.makeHttpRequest({
      url: `https://api.stlouisfed.org/fred/series/observations` + `?series_id=${id}` + `&api_key=${secrets.FRED_API_KEY}` + `&file_type=json` + `&sort_order=desc` + `&limit=1`,
    }),
  ),
);

// Single loop: extract both values + timestamps (optimized)
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

  // Parse yield (scaled for Solidity)
  values.push(Math.round(parseFloat(obs.value) * 100));

  // Parse timestamp
  timestamps.push(Math.floor(new Date(obs.date).getTime() / 1000));
}

// Use conservative timestamp
const timestamp = Math.min(...timestamps);

console.log("timestamp: ", timestamp);
// Encode result for Solidity
return Functions.encodeAbiParameters(["uint256[]", "uint256"], [values, timestamp]);
