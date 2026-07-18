import type { CommandHook } from "../command";
import { err, ok } from "../result";
import {
  terminalConfirmationPrompt,
  type ConfirmationPrompt,
} from "../terminalConfirmationPrompt";

export function createConfirmationHook(
  prompt: ConfirmationPrompt = terminalConfirmationPrompt,
): CommandHook {
  return async () => {
    const confirmed = await prompt("Continue? [y/N] ");
    return confirmed ? ok(undefined) : err("command cancelled");
  };
}
