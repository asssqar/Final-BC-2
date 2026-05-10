/**
 * Best-effort decoder for wallet/RPC errors so the user sees a human message instead of
 * raw JSON-RPC noise.
 */
export function readableTxError(err: unknown): string {
    if (!err) return "Unknown error";
    const e = err as {shortMessage?: string; message?: string; cause?: {shortMessage?: string}};
    if (e.cause?.shortMessage) return e.cause.shortMessage;
    if (e.shortMessage) return e.shortMessage;
    if (e.message) {
        if (e.message.includes("user rejected")) return "Transaction rejected by user";
        if (e.message.includes("insufficient funds")) return "Insufficient gas balance";
        if (e.message.includes("ERC20InsufficientAllowance")) return "Approval required first";
        if (e.message.length > 200) return e.message.slice(0, 200) + "…";
        return e.message;
    }
    return JSON.stringify(err);
}
