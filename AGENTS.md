# Macwlt Agent Guide
> Essential Guide for AI agents working on macwlt.

## Package Instructions

Before working in a subpackage, find and follow the `AGENTS.md` file in that
subpackage. Read every applicable guide when a change spans multiple subpackages.
Changes to the root native test suite follow the core subpackage guide.

## Commits
- Use this commit message format when the user explicitly asks for a commit:
  `(<commit type>) (<ai model>, <human reviewed T|F>, <tested T|F>) <commit text>`.
- Examples: `(feat) (GPT-5.5, F, T) add new logging system`,
  `(fix) (GPT-5.5, T, T) preserve dyld cache environment`.
- Before creating a commit, ask the user whether a human reviewed the changes so
  the second metadata field can be set to `T` or `F` accurately.
- Set the tested field to `T` only when relevant tests or verification commands
  were run successfully for the committed changes. Otherwise set it to `F`.
- Keep commit text concise and focused on user-visible impact or the regression
  shield being added.
