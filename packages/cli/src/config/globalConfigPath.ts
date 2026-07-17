import { join } from "node:path";

export function globalConfigPath(homeDirectory: string): string {
  return join(homeDirectory, ".config", "macwlt", "config.json");
}
