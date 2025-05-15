import {
    ActionResult,
    ContextWithTransaction,
    TriggerType,
    TransactionBuilder,
    Address,
    log,
    ContextWithInherit
} from "@archethicjs/ae-contract-as";

const UCO_SCALING_FACTOR: u64 = 100_000_000;
const FIVE_UCO_SCALED: u64 = 5 * UCO_SCALING_FACTOR;
const BURN_ADDRESS: Address = new Address("00000000000000000000000000000000000000000000000000000000000000000000");

class State {
}


export function onInherit(context: ContextWithInherit<State>): void {
    log<string>(context.nextBalance.uco.toString());
    log<string>(context.balance.uco.toString());
    let diff = context.balance.uco - context.nextBalance.uco;
    if (Math.abs(diff as f64) != 5) {
        throw new Error("Invalid balance");
    }
    if (context.contract.data.ledger.uco.transfers[0].to != BURN_ADDRESS) {
        throw new Error("Invalid transfer");
    }
    if (context.contract.data.ledger.uco.transfers[0].amount != FIVE_UCO_SCALED) {
        throw new Error("Invalid amount");
    }
}

// @ts-ignore
@action(TriggerType.Transaction)
export function processTransaction(context: ContextWithTransaction<State>): ActionResult<State> {

    return new ActionResult<State>().setTransaction(
        new TransactionBuilder()

            .addUCOTransfer(BURN_ADDRESS, FIVE_UCO_SCALED)
            .setContent((context.balance.uco - FIVE_UCO_SCALED).toString())
    );
}
