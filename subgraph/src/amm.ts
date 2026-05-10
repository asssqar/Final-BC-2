import {Swap as SwapEvent} from "../generated/ResourceAMM/ResourceAMM";
import {Swap} from "../generated/schema";

export function handleSwap(event: SwapEvent): void {
    const id = event.transaction.hash.concatI32(event.logIndex.toI32());
    const s = new Swap(id);
    s.sender = event.params.sender;
    s.to = event.params.to;
    s.tokenIn = event.params.tokenIn;
    s.amountIn = event.params.amountIn;
    s.amountOut = event.params.amountOut;
    s.timestamp = event.block.timestamp;
    s.txHash = event.transaction.hash;
    s.save();
}
