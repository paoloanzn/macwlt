import { err, ok, type Result } from "./result";

export type ParsedFlags = {
  readonly json: boolean;
  readonly positionals: readonly string[];
  readonly options: ReadonlyMap<string, string>;
  readonly switches: ReadonlySet<string>;
};

export function parseFlags(args: readonly string[]): Result<ParsedFlags, string> {
  let json = false;
  const positionals: string[] = [];
  const options = new Map<string, string>();
  const switches = new Set<string>();

  for (let index = 0; index < args.length; index++) {
    const arg = args[index];
    if (!arg) continue;
    if (arg === "--json") {
      json = true;
      continue;
    }
    if (arg === "--reset" || arg === "--yes") {
      switches.add(arg.slice(2));
      continue;
    }
    if (!arg.startsWith("--")) {
      positionals.push(arg);
      continue;
    }

    const key = arg.slice(2);
    if (key.length === 0) return err("empty option name");
    const value = args[index + 1];
    if (!value || value.startsWith("--")) return err(`missing value for --${key}`);
    options.set(key, value);
    index++;
  }

  return ok({ json, positionals, options, switches });
}