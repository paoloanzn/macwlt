export type GlobalConfigValidationError = {
  readonly kind: "invalid-config";
  readonly message: string;
};
