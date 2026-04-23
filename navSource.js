const url = "https://your-spv.vercel.app/api/nav";

const response = await Functions.makeHttpRequest({ url });

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
      data.nav_by_bucket["2Y"],
      data.nav_by_bucket["5Y"],
      data.nav_by_bucket["10Y"],
      data.nav_by_bucket["30Y"]
    ],
    data.timestamp,
    signature,
    hash
  ]
);