# Avante.nvim

## ACP

We are mostly working on the ACP integration here, and want it to work as closely as possible to how zed does it. Zed is
an editor that allows users to run claude from their editor.

When we are adding features/functionality, we want to use the ACP protocol, and have this isolated and testable.

## Features

### Modes

We want to implement modes like the agents have, using the ACP protocol.

### Side Bar View

Currently, the sidebar view is osmething that isn't working very well. It is a bit buggy and clunky, and we want to
support different modes and views.

1. we should have a single full-page prompt with everything in it (no tabs)
1. it should support having diffs that then get applied (like today)
1. better ui options.

### Adding Context

Right now, managing context for the agent is really important. We have the "add files" option, but it should use
telescope. We want the add file viewer to be a telescope viewer that lets you select from the current directory, go up a
directory, or share a full path, or homedir (using a ~) path.

## Approach

### Configuration First

Everything should be in the avante config file.

### Backwards compatible

Let's make things backwards compatible and then opt-in where possible.

### Reference Zed

You can find the zed code in ~/clones/zed and please reference how they use ACP.

### Agent vs ACP mode

Most thing we're iterating on are in ACP mode here.

### Atuin for prompts

I want to take every prompt that we write in here, and turn it into a history, that I can then search through.

### Managing Context

Instead of a context box, let's make it so that typing @ in the prompt will let you manage the context. It should be a
popup item.

### Profile Mode

I want to define profiles that I can use. This should let me define  that I want to use model claude-code, add in
additioanl context automatically (files or directories) and have a base prompt / agent I'm using with each one.

### Plan Mode

We need to make sure that the plan mode is actually working. I want to build a "review" mode where I can review the plan
before submitting it.
