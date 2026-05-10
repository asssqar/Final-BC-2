/**
 * GraphQL queries used by the frontend. Every page that talks to the subgraph imports
 * from this file — keeps the documented query surface (≥ 5) stable.
 */
export const TOP_CRAFTERS = `
query TopCrafters {
    players(orderBy: totalCrafted, orderDirection: desc, first: 10) {
        id
        address
        totalCrafted
        totalLootBoxes
    }
}
`;

export const ACTIVE_PROPOSALS = `
query ActiveProposals {
    proposals(first: 25, orderBy: createdAt, orderDirection: desc) {
        id
        description
        state
        forVotes
        againstVotes
        abstainVotes
        startTime
        endTime
    }
}
`;

export const RECENT_SWAPS = `
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
`;

export const PLAYER_PROFILE = `
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
}
`;

export const LOOTBOX_STATUS = `
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
`;
