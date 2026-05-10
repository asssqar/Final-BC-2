import {BigInt, Bytes, store} from "@graphprotocol/graph-ts";
import {
    TransferSingle as TransferSingleEvent,
    TransferBatch as TransferBatchEvent,
    RecipeSet as RecipeSetEvent,
    RecipeRemoved as RecipeRemovedEvent,
    Crafted as CraftedEvent
} from "../generated/GameItems/GameItems";
import {Player, Holding, Recipe, CraftEvent} from "../generated/schema";

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

function loadOrCreateHolding(playerId: string, itemId: BigInt, ts: BigInt): Holding {
    const id = playerId + "-" + itemId.toString();
    let h = Holding.load(id);
    if (h == null) {
        h = new Holding(id);
        h.player = playerId;
        h.itemId = itemId;
        h.balance = ZERO;
        h.lastUpdated = ts;
    }
    return h as Holding;
}

export function handleTransferSingle(event: TransferSingleEvent): void {
    if (event.params.from.notEqual(Bytes.fromHexString("0x0000000000000000000000000000000000000000"))) {
        const sender = loadOrCreatePlayer(event.params.from);
        const h = loadOrCreateHolding(sender.id, event.params.id, event.block.timestamp);
        h.balance = h.balance.minus(event.params.value);
        h.lastUpdated = event.block.timestamp;
        h.save();
    }
    if (event.params.to.notEqual(Bytes.fromHexString("0x0000000000000000000000000000000000000000"))) {
        const recv = loadOrCreatePlayer(event.params.to);
        const h = loadOrCreateHolding(recv.id, event.params.id, event.block.timestamp);
        h.balance = h.balance.plus(event.params.value);
        h.lastUpdated = event.block.timestamp;
        h.save();
    }
}

export function handleTransferBatch(event: TransferBatchEvent): void {
    const ids = event.params.ids;
    const values = event.params.values;
    for (let i = 0; i < ids.length; i++) {
        if (event.params.from.notEqual(Bytes.fromHexString("0x0000000000000000000000000000000000000000"))) {
            const sender = loadOrCreatePlayer(event.params.from);
            const h = loadOrCreateHolding(sender.id, ids[i], event.block.timestamp);
            h.balance = h.balance.minus(values[i]);
            h.lastUpdated = event.block.timestamp;
            h.save();
        }
        if (event.params.to.notEqual(Bytes.fromHexString("0x0000000000000000000000000000000000000000"))) {
            const recv = loadOrCreatePlayer(event.params.to);
            const h = loadOrCreateHolding(recv.id, ids[i], event.block.timestamp);
            h.balance = h.balance.plus(values[i]);
            h.lastUpdated = event.block.timestamp;
            h.save();
        }
    }
}

export function handleRecipeSet(event: RecipeSetEvent): void {
    const id = event.params.recipeId.toString();
    let r = Recipe.load(id);
    if (r == null) r = new Recipe(id);
    r.outputId = event.params.outputId;
    r.outputAmount = event.params.outputAmount;
    r.craftFee = event.params.craftFee;
    r.active = true;
    if (r.timesCrafted === null) r.timesCrafted = ZERO;
    r.lastUpdated = event.block.timestamp;
    r.save();
}

export function handleRecipeRemoved(event: RecipeRemovedEvent): void {
    const id = event.params.recipeId.toString();
    const r = Recipe.load(id);
    if (r == null) return;
    r.active = false;
    r.lastUpdated = event.block.timestamp;
    r.save();
}

export function handleCrafted(event: CraftedEvent): void {
    const player = loadOrCreatePlayer(event.params.crafter);
    player.totalCrafted = player.totalCrafted.plus(ONE);
    player.save();

    const recipeId = event.params.recipeId.toString();
    let recipe = Recipe.load(recipeId);
    if (recipe == null) {
        recipe = new Recipe(recipeId);
        recipe.outputId = event.params.outputId;
        recipe.outputAmount = event.params.outputAmount;
        recipe.craftFee = ZERO;
        recipe.active = true;
        recipe.timesCrafted = ZERO;
        recipe.lastUpdated = event.block.timestamp;
    }
    recipe.timesCrafted = recipe.timesCrafted.plus(ONE);
    recipe.save();

    const ev = new CraftEvent(event.transaction.hash.concatI32(event.logIndex.toI32()));
    ev.player = player.id;
    ev.recipe = recipe.id;
    ev.outputId = event.params.outputId;
    ev.outputAmount = event.params.outputAmount;
    ev.timestamp = event.block.timestamp;
    ev.txHash = event.transaction.hash;
    ev.save();
}
