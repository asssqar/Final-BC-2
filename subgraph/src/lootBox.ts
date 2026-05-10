import {BigInt, Bytes} from "@graphprotocol/graph-ts";
import {
    LootBoxOpened as OpenedEvent,
    LootBoxFulfilled as FulfilledEvent
} from "../generated/LootBox/LootBox";
import {LootBoxOpen, Player} from "../generated/schema";

const ZERO = BigInt.fromI32(0);
const ONE = BigInt.fromI32(1);

function loadOrCreatePlayer(addr: Bytes): Player {
    const id = addr.toHexString();
    let p = Player.load(id);
    if (p == null) {
        p = new Player(id);
        p.address = addr;
        p.totalCrafted = ZERO;
        p.totalLootBoxes = ZERO;
        p.totalRented = ZERO;
        p.rentalsListed = ZERO;
        p.save();
    }
    return p as Player;
}

export function handleOpened(event: OpenedEvent): void {
    const player = loadOrCreatePlayer(event.params.player);
    player.totalLootBoxes = player.totalLootBoxes.plus(ONE);
    player.save();

    const id = event.params.requestId.toString();
    const o = new LootBoxOpen(id);
    o.player = player.id;
    o.requestId = event.params.requestId;
    o.fulfilled = false;
    o.openedAt = event.block.timestamp;
    o.save();
}

export function handleFulfilled(event: FulfilledEvent): void {
    const id = event.params.requestId.toString();
    const o = LootBoxOpen.load(id);
    if (o == null) return;
    o.fulfilled = true;
    o.rewardItemId = event.params.itemId;
    o.rewardAmount = event.params.amount;
    o.fulfilledAt = event.block.timestamp;
    o.save();
}
