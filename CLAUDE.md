## Code Best Practices

- Optimize for local readability before abstraction. Small helper functions are useful when they remove duplication or isolate a meaningful concept, but unnecessary layers of tiny nested functions make code harder to follow.
- If you get stuck, ask for help. It's better to ask me to look at something in the debugger than to flail around for a long time.
- If your changes introduce compiler warnings, fix them.
- You should treat warnings as errors.
- Don't change defaults silently.
- Avoid duplicate expressions; hoist shared computations into a named `const` before branching.
- Don't include AI-generated markdown files (summaries, plans, etc.) in commits — only ship code.
- Don't create dependency cycles. Use delegates or closures instead.




