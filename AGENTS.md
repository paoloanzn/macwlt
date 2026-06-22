# Macwlt Agent Guide
> Essential Guide for AI agents working on macwlt.

## Critical Rules

**Read `CLAUDE.md` first** - it contains mandatory coding practices.

## Architecture

Pure Objective-C.

## Finding Your Way

- Use Objective-C to write new features.

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