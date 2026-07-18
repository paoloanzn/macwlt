import defaultConfigInput from "../../config.default.json";
import { parseGlobalConfigData } from "./parseGlobalConfigData";

const parsedDefaultConfig = parseGlobalConfigData(defaultConfigInput);
if (!parsedDefaultConfig.ok) {
  throw new Error(
    `invalid config.default.json: ${parsedDefaultConfig.error.message}`,
  );
}

const contents = `${JSON.stringify(parsedDefaultConfig.value, null, 2)}\n`;

export function defaultGlobalConfigContents(): string {
  return contents;
}
