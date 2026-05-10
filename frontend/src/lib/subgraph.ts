import {Client, cacheExchange, fetchExchange} from "@urql/core";

export const subgraphUrl =
    process.env.NEXT_PUBLIC_SUBGRAPH_URL ?? "https://api.thegraph.com/subgraphs/name/aetheria";

export const subgraphClient = new Client({
    url: subgraphUrl,
    exchanges: [cacheExchange, fetchExchange],
});
