export interface ConfigStorage {
  read(path: string): Promise<string | undefined>;
  write(path: string, contents: string): Promise<void>;
}
