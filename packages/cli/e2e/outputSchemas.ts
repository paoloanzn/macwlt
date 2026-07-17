import { z } from "zod";

export const createOutputSchema = z.object({
  jointPublicKey: z.string().regex(/^(02|03)[0-9a-f]{64}$/),
});

export const pubkeyOutputSchema = z.object({
  publicKey: z.string().regex(/^(02|03)[0-9a-f]{64}$/),
});

export const addressOutputSchema = z.object({
  address: z.string().min(1),
  derivationPath: z.string(),
  type: z.enum([
    "bitcoin",
    "bitcoin-testnet",
    "bitcoin-taproot",
    "bitcoin-taproot-testnet",
    "ethereum",
  ]),
});

export const ethSignatureOutputSchema = z.object({
  signature: z.string().regex(/^[0-9a-f]{130}$/),
});
