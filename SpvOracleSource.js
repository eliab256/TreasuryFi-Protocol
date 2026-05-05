// SPV reserves + cash buckets (BPS 1e4 precision)

const url = "https://your-spv.vercel.app/api/usdValues";

const response = await Functions.makeHttpRequest({ url });

if (response.error) {
  throw Error("SPV fetch failed");
}

const data = response.data.data;
const signature = response.data.signature;

// deterministic hash input
const encoded = Functions.encodeString(JSON.stringify(data));
const hash = Functions.keccak256(encoded);

// helper: USD string → cents → BPS-like integer (1e4 precision)
function toBps(value) {
  if (typeof value !== "string") {
    throw Error("Value must be string");
  }

  const parts = value.split(".");
  const integer = parts[0];
  let decimals = parts[1] || "00";

  decimals = (decimals + "00").slice(0, 2);

  // cents
  const cents = BigInt(integer + decimals);

  // convert cents → BPS scale (1e4)
  return Number(cents) * 100;
}

// bond values
const bond = [
  toBps(data.usdValue_by_bucket["2Y"]),
  toBps(data.usdValue_by_bucket["5Y"]),
  toBps(data.usdValue_by_bucket["10Y"]),
  toBps(data.usdValue_by_bucket["30Y"]),
];

// cash values
const cash = [
  toBps(data.cash_usd_by_bucket["2Y"]),
  toBps(data.cash_usd_by_bucket["5Y"]),
  toBps(data.cash_usd_by_bucket["10Y"]),
  toBps(data.cash_usd_by_bucket["30Y"]),
];

// optional sanity timestamp
const timestamp = data.timestamp;

return Functions.encodeAbiParameters(
  ["uint256[4]", "uint256[4]", "uint256", "bytes", "bytes32"],
  [bond, cash, timestamp, signature, hash]
);