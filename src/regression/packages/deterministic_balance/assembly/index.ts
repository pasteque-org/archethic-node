import {
    ActionResult,
    ContextWithTransaction,
    TriggerType,
    TransactionBuilder,
    Address,
    ContextWithInherit,
    getBurnAddress
} from "@archethicjs/ae-contract-as";

const UCO_SCALING_FACTOR: u64 = 100_000_000;
const FIVE_UCO: u64 = 5;
const FIVE_UCO_SCALED: u64 = FIVE_UCO * UCO_SCALING_FACTOR;

class State {
}


export function onInherit(context: ContextWithInherit<State>): void {
    let diff = context.balance.uco - context.nextBalance.uco;
    if (Math.abs(diff as f64) != FIVE_UCO_SCALED as f64) {
        throw new Error("Invalid balance");
    }
    if (context.nextTransaction.data.ledger.uco.transfers[0].to.toString() != getBurnAddress().toString()) {
        throw new Error("Invalid transfer");
    }
    if (context.nextTransaction.data.ledger.uco.transfers[0].amount != FIVE_UCO_SCALED) {
        throw new Error("Invalid amount");
    }
}

// @ts-ignore
@action(TriggerType.Transaction)
export function processTransaction(context: ContextWithTransaction<State>): ActionResult<State> {

    let newContent = (context.balance.uco - FIVE_UCO_SCALED) / UCO_SCALING_FACTOR;
    return new ActionResult<State>().setTransaction(
        new TransactionBuilder()

            .addUCOTransfer(getBurnAddress(), FIVE_UCO_SCALED)
            .setContent(newContent.toString())
    );
}
