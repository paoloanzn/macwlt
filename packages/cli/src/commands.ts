import type { Command } from "./command";
import { createCommand } from "./commands/create";
import { resetCommand } from "./commands/reset";
import { pubkeyCommand } from "./commands/pubkey";
import { addressCommand } from "./commands/address";
import { signEthCommand } from "./commands/signEth";
import { signPsbtCommand } from "./commands/signPsbt";
import { helpCommand } from "./commands/help";
import { versionCommand } from "./commands/version";
import { sendCommand } from "./commands/send";

export const commands: readonly Command[] = [
  createCommand,
  resetCommand,
  pubkeyCommand,
  addressCommand,
  signEthCommand,
  signPsbtCommand,
  sendCommand,
  helpCommand,
  versionCommand,
];
