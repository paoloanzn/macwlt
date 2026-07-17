import { ok, type Result } from "../result";
import { helpText, type Command, type CommandContext } from "../command";

export type HelpArgs = { readonly kind: "help" };

export const helpCommand: Command<HelpArgs> = {
  name: "help",
  aliases: ["--help", "-h"],
  needsClient: false,
  describe(): string {
    return "";
  },
  parse(_args: readonly string[]): Result<HelpArgs, string> {
    return ok({ kind: "help" });
  },
  async run(ctx: CommandContext, _args: HelpArgs): Promise<Result<string, string>> {
    return ok(helpText(ctx.registry));
  },
};