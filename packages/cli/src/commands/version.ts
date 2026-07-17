import { ok, type Result } from "../result";
import { cliVersion, type Command, type CommandContext } from "../command";

export type VersionArgs = { readonly kind: "version" };

export const versionCommand: Command<VersionArgs> = {
  name: "version",
  aliases: ["--version", "-v"],
  needsClient: false,
  describe(): string {
    return "  macwlt version";
  },
  parse(_args: readonly string[]): Result<VersionArgs, string> {
    return ok({ kind: "version" });
  },
  async run(_ctx: CommandContext, _args: VersionArgs): Promise<Result<string, string>> {
    return ok(`macwlt ${cliVersion}`);
  },
};