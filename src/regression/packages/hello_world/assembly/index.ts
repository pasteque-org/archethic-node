import {
    ActionResult,
    ContextWithParams,
    TriggerType,
    TransactionBuilder
} from "@archethicjs/ae-contract-as";

class State {
}

class ActionParams {
    param!: string;
}

// @ts-ignore
@action(TriggerType.Transaction)
export function processTransaction(context: ContextWithParams<State, ActionParams>): ActionResult<State> {
    const receivedParam = context.arguments.param;

    if (receivedParam != "Hello") {
        throw new Error("Invalid parameter for transaction. Expected \"Hello\", but received: \"" + receivedParam + "\".");
    }

    return new ActionResult<State>().setTransaction(
        new TransactionBuilder()
            .setContent("World")
    );
}

// @ts-ignore
@publicFunction()
export function getPublicValue(context: ContextWithParams<State, ActionParams>): string {
    const receivedParam = context.arguments.param;

    if (receivedParam == "Hello") {
        return "World";
    } else {
        throw new Error("Invalid parameter for public query. Expected \"Hello\", but received: \"" + receivedParam + "\".");
    }
}
