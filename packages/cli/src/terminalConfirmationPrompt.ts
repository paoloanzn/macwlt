import { createInterface } from "node:readline/promises";

export type ConfirmationPrompt = (question: string) => Promise<boolean>;

export async function terminalConfirmationPrompt(
  question: string,
): Promise<boolean> {
  const readline = createInterface({
    input: process.stdin,
    output: process.stderr,
  });
  try {
    return isAffirmativeConfirmation(await readline.question(question));
  } catch {
    return false;
  } finally {
    readline.close();
  }
}

function isAffirmativeConfirmation(answer: string): boolean {
  const normalized = answer.trim().toLowerCase();
  return normalized === "y" || normalized === "yes";
}
