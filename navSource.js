const url = "https://your-spv.vercel.app/api/nav";

const response = await Functions.makeHttpRequest({ url });
const decimals = 8;

if (response.error) {
  throw Error("SPV fetch failed");
}

const data = response.data.data;
const signature = response.data.signature;

const encoded = Functions.encodeString(JSON.stringify(data));
const hash = Functions.keccak256(encoded);


return Functions.encodeAbi(
  ["uint256[4]", "uint256", "bytes", "bytes32"],
  [
    [
        Math.round(data.nav_by_bucket["2Y"]  * 10 ** decimals),
        Math.round(data.nav_by_bucket["5Y"]  * 10 ** decimals),
        Math.round(data.nav_by_bucket["10Y"] * 10 ** decimals),
        Math.round(data.nav_by_bucket["30Y"] * 10 ** decimals),
    ],
    Math.floor(data.timestamp / 1000),
    signature,
    hash
  ]
);