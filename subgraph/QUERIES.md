# Documented GraphQL Queries (≥ 5)

The following queries are exposed by the production subgraph and are exercised
from the frontend at `frontend/src/lib/queries.ts`.

## 1. Top crafters (leaderboard)

```graphql
query TopCrafters {
    players(orderBy: totalCrafted, orderDirection: desc, first: 10) {
        id
        address
        totalCrafted
        totalLootBoxes
    }
}
```

## 2. Active proposals with vote tally

```graphql
query ActiveProposals {
    proposals(where: {state: "Pending"}) {
        id
        description
        forVotes
        againstVotes
        abstainVotes
        startTime
        endTime
    }
}
```

## 3. Recent swaps on the resource AMM

```graphql
query RecentSwaps($limit: Int = 25) {
    swaps(orderBy: timestamp, orderDirection: desc, first: $limit) {
        id
        sender
        to
        tokenIn
        amountIn
        amountOut
        timestamp
        txHash
    }
}
```

## 4. Player inventory + recent crafts

```graphql
query PlayerProfile($id: ID!) {
    player(id: $id) {
        id
        totalCrafted
        totalLootBoxes
        holdings(first: 50) {
            itemId
            balance
            lastUpdated
        }
    }
    craftEvents(where: {player: $id}, orderBy: timestamp, orderDirection: desc, first: 10) {
        outputId
        outputAmount
        timestamp
        txHash
    }
}
```

## 5. Loot-box fulfilment status for a request

```graphql
query LootBoxStatus($requestId: ID!) {
    lootBoxOpen(id: $requestId) {
        id
        fulfilled
        rewardItemId
        rewardAmount
        openedAt
        fulfilledAt
    }
}
```

## 6. Recipe usage (governance analytics)

```graphql
query RecipeUsage {
    recipes(where: {active: true}, orderBy: timesCrafted, orderDirection: desc) {
        id
        outputId
        outputAmount
        craftFee
        timesCrafted
    }
}
```
