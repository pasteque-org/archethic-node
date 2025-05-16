/// <reference types="assemblyscript/std/portable" />
import {
    ActionResult,
    Context,
    ContextWithParams,
    TriggerType,
} from "@archethicjs/ae-contract-as";

// Define the contract state
class State {
    counter: i32 = 0;
}

// Initialize the contract during creation
export function onInit(_context: Context<State>): State {
    return new State();
}

class IncArgs {
    value!: u32;
}

// Define an action triggered by a transaction
// @ts-ignore
@action(TriggerType.Transaction)
export function inc(context: ContextWithParams<State, IncArgs>): ActionResult<State> {
    const state = context.state;

    // Validate the input
    if (context.arguments.value == 0)
        throw new Error("increment value must be greater than 0")

    // Update the state
    state.counter += context.arguments.value;

    // Return the updated state
    return new ActionResult<State>().setState(state)
}
